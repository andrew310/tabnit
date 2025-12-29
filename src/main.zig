const std = @import("std");
const zdl = @import("zdl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <file_or_dir> ...\n", .{args[0]});
        return;
    }

    for (args[1..]) |path| {
        try processPath(allocator, path);
    }
}

fn processPath(allocator: std.mem.Allocator, path: []const u8) !void {
    const stat = std.fs.cwd().statFile(path) catch |err| {
        if (err == error.FileNotFound) {
            // Might be a directory, statFile fails on dirs on some systems or versions
            // Try opening as directory
            var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
                 std.debug.print("Error: Could not find or open {s}\n", .{path});
                 return;
            };
            defer dir.close();
            try walkDir(allocator, dir, path);
            return;
        }
        return err;
    };

    if (stat.kind == .directory) {
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();
        try walkDir(allocator, dir, path);
    } else {
        try parseFile(allocator, path);
    }
}

fn walkDir(allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8) !void {
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".sql")) {
            const full_path = try std.fs.path.join(allocator, &.{ path, entry.path });
            defer allocator.free(full_path);
            try parseFile(allocator, full_path);
        }
    }
}

fn parseFile(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        std.debug.print("Could not open file {s}: {any}\n", .{file_path, err});
        return;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    var parser = zdl.parser.Parser.init(allocator, buffer, .Postgres);
    var result = parser.parse() catch |err| {
        std.debug.print("Error parsing {s}: {any}\n", .{file_path, err});
        return;
    };
    defer result.deinit(allocator);

    std.debug.print("📜 {s} ({d} statements)\n", .{ file_path, result.statements.items.len });

    for (result.statements.items) |stmt| {
        switch (stmt) {
            .create_type => |t| {
                std.debug.print("TYPE {s}: ", .{t.name});
                for (t.values.items, 0..) |val, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("'{s}'", .{val});
                }
                std.debug.print("\n", .{});
            },
            .create_table => |tbl| {
                std.debug.print("TABLE {s}\n", .{tbl.table});
                for (tbl.columns.items) |col| {
                    std.debug.print("  - {s}: {s}", .{ col.name, col.data_type });
                    if (col.primary_key) std.debug.print(" [PK]", .{});
                    if (!col.nullable) std.debug.print(" [NOT NULL]", .{});
                    if (col.unique) std.debug.print(" [UNIQUE]", .{});
                    if (col.references) |ref| std.debug.print(" -> {s}({?s})", .{ ref.table, ref.column });
                    std.debug.print("\n", .{});
                }
            },
            .create_schema => |s| {
                std.debug.print("SCHEMA {s}", .{s.name});
                if (s.if_not_exists) std.debug.print(" (IF NOT EXISTS)", .{});
                std.debug.print("\n", .{});
            },
            .create_function => |f| {
                std.debug.print("FUNCTION {s}\n", .{f.name});
            },
            .ignored => |i| {
                std.debug.print("IGNORED {s}\n", .{i.name});
            },
        }
    }
    std.debug.print("\n", .{});
}
