const std = @import("std");
const zdl = @import("zdl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} [--json] [--diff-snapshot <file>] <file_or_dir> ...\n", .{args[0]});
        return;
    }

    var use_json = false;
    var snapshot_path: ?[]const u8 = null;
    var paths = std.ArrayListUnmanaged([]const u8){};
    defer paths.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            use_json = true;
        } else if (std.mem.eql(u8, arg, "--diff-snapshot")) {
            i += 1;
            if (i < args.len) {
                snapshot_path = args[i];
            } else {
                std.debug.print("Error: --diff-snapshot requires a file path\n", .{});
                return;
            }
        } else {
            try paths.append(allocator, arg);
        }
    }

    var buffers = std.ArrayListUnmanaged([]u8){};
    defer {
        for (buffers.items) |b| allocator.free(b);
        buffers.deinit(allocator);
    }

    var current_statements = std.ArrayListUnmanaged(zdl.ast.Statement){};
    defer {
        for (current_statements.items) |*stmt| {
            stmt.deinit(allocator);
        }
        current_statements.deinit(allocator);
    }

    for (paths.items) |path| {
        const silent_mode = use_json or (snapshot_path != null);
        try processPath(allocator, path, &current_statements, &buffers, silent_mode);
    }

    if (snapshot_path) |snap_file| {
        // DIFF MODE
        const snap_content = std.fs.cwd().readFileAlloc(allocator, snap_file, 100 * 1024 * 1024) catch |err| {
             std.debug.print("Error reading snapshot file: {any}\n", .{err});
             return;
        };
        defer allocator.free(snap_content);

        // Parse JSON snapshot
        const parsed = std.json.parseFromSlice([]zdl.ast.Statement, allocator, snap_content, .{}) catch |err| {
            std.debug.print("Error parsing snapshot JSON: {any}\n", .{err});
            return;
        };
        defer parsed.deinit();

        var diff_res = try zdl.diff.diff(allocator, parsed.value, current_statements.items);
        defer diff_res.deinit(allocator);

        std.debug.print("{f}\n", .{std.json.fmt(diff_res.changes.items, .{})});

    } else {
        // NORMAL MODE
        if (use_json) {
            std.debug.print("{f}\n", .{std.json.fmt(current_statements.items, .{})});
        }
    }
}

fn processPath(allocator: std.mem.Allocator, path: []const u8, all_statements: *std.ArrayListUnmanaged(zdl.ast.Statement), buffers: *std.ArrayListUnmanaged([]u8), silent_mode: bool) !void {
    const stat = std.fs.cwd().statFile(path) catch |err| {
        if (err == error.FileNotFound) {
            var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
                 if (!silent_mode) std.debug.print("Error: Could not find or open {s}\n", .{path});
                 return;
            };
            defer dir.close();
            try walkDir(allocator, dir, path, all_statements, buffers, silent_mode);
            return;
        }
        return err;
    };

    if (stat.kind == .directory) {
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();
        try walkDir(allocator, dir, path, all_statements, buffers, silent_mode);
    } else {
        try parseFile(allocator, path, all_statements, buffers, silent_mode);
    }
}

fn walkDir(allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8, all_statements: *std.ArrayListUnmanaged(zdl.ast.Statement), buffers: *std.ArrayListUnmanaged([]u8), silent_mode: bool) !void {
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".sql")) {
            const full_path = try std.fs.path.join(allocator, &.{ path, entry.path });
            defer allocator.free(full_path);
            try parseFile(allocator, full_path, all_statements, buffers, silent_mode);
        }
    }
}

fn parseFile(allocator: std.mem.Allocator, file_path: []const u8, all_statements: *std.ArrayListUnmanaged(zdl.ast.Statement), buffers: *std.ArrayListUnmanaged([]u8), silent_mode: bool) !void {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        if (!silent_mode) std.debug.print("Could not open file {s}: {any}\n", .{ file_path, err });
        return;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);
    try buffers.append(allocator, buffer);

    var parser = zdl.parser.Parser.init(allocator, buffer, .Postgres);
    var result = parser.parse() catch |err| {
        if (!silent_mode) std.debug.print("Error parsing {s}: {any}\n", .{ file_path, err });
        return;
    };
    
    const stmts = try result.statements.toOwnedSlice(allocator);
    defer allocator.free(stmts);
    
    if (!silent_mode) {
        std.debug.print("📜 {s} ({d} statements)\n", .{ file_path, stmts.len });
    }

    for (stmts) |stmt| {
        try all_statements.append(allocator, stmt);
    }
}
