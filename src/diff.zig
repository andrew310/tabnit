const std = @import("std");
const ast = @import("ast.zig");

pub const ColumnModification = struct {
    name: []const u8,
    type_changed: ?[]const u8 = null,
    nullable_changed: ?bool = null,
    default_changed: ?[]const u8 = null,
};

pub const TableChange = union(enum) {
    add_column: ast.Column,
    drop_column: []const u8,
    modify_column: ColumnModification,
};

pub const AlterTable = struct {
    name: []const u8,
    changes: std.ArrayList(TableChange),

    pub fn deinit(self: *AlterTable, allocator: std.mem.Allocator) void {
        self.changes.deinit(allocator);
    }
};

pub const Change = union(enum) {
    create_table: ast.CreateTableStmt,
    drop_table: []const u8,
    alter_table: AlterTable,

    pub fn deinit(self: *Change, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .create_table => |*c| c.deinit(allocator),
            .drop_table => {},
            .alter_table => |*c| c.deinit(allocator),
        }
    }
};

pub const DiffResult = struct {
    changes: std.ArrayList(Change),

    pub fn deinit(self: *DiffResult, allocator: std.mem.Allocator) void {
        for (self.changes.items) |*c| {
            c.deinit(allocator);
        }
        self.changes.deinit(allocator);
    }
};

pub fn diff(allocator: std.mem.Allocator, old: []const ast.Statement, new: []const ast.Statement) !DiffResult {
    var changes = std.ArrayList(Change){};
    errdefer {
        for (changes.items) |*c| c.deinit(allocator);
        changes.deinit(allocator);
    }

    var old_tables = std.StringHashMap(ast.CreateTableStmt).init(allocator);
    defer old_tables.deinit();

    // Index old tables
    for (old) |stmt| {
        switch (stmt) {
            .create_table => |t| try old_tables.put(t.table, t),
            else => {},
        }
    }

    // Iterate new tables
    for (new) |stmt| {
        switch (stmt) {
            .create_table => |new_table| {
                if (old_tables.get(new_table.table)) |old_table| {
                    // Table exists in both, compare columns
                    var table_changes = std.ArrayList(TableChange){};
                    errdefer table_changes.deinit(allocator);

                    try diffTableColumns(allocator, old_table, new_table, &table_changes);

                    if (table_changes.items.len > 0) {
                        try changes.append(allocator, Change{
                            .alter_table = .{
                                .name = new_table.table,
                                .changes = table_changes,
                            },
                        });
                    } else {
                        table_changes.deinit(allocator);
                    }
                    
                    _ = old_tables.remove(new_table.table);
                } else {
                    // New table
                    var table_copy = new_table;
                    table_copy.columns = try std.ArrayList(ast.Column).initCapacity(allocator, new_table.columns.items.len);
                    table_copy.columns.appendSliceAssumeCapacity(new_table.columns.items);
                    
                    table_copy.primary_key_columns = try std.ArrayList([]const u8).initCapacity(allocator, new_table.primary_key_columns.items.len);
                    table_copy.primary_key_columns.appendSliceAssumeCapacity(new_table.primary_key_columns.items);

                    table_copy.unique_constraints = std.ArrayList(ast.UniqueConstraint){};

                    try changes.append(allocator, Change{ .create_table = table_copy });
                }
            },
            else => {},
        }
    }

    // Remaining old tables are dropped
    var it = old_tables.iterator();
    while (it.next()) |entry| {
        try changes.append(allocator, Change{ .drop_table = entry.key_ptr.* });
    }

    return DiffResult{ .changes = changes };
}

fn diffTableColumns(
    allocator: std.mem.Allocator, 
    old: ast.CreateTableStmt, 
    new: ast.CreateTableStmt, 
    changes: *std.ArrayList(TableChange)
) !void {
    var old_cols = std.StringHashMap(ast.Column).init(allocator);
    defer old_cols.deinit();

    for (old.columns.items) |col| {
        try old_cols.put(col.name, col);
    }

    for (new.columns.items) |new_col| {
        if (old_cols.get(new_col.name)) |old_col| {
            // Compare
            var mod = ColumnModification{ .name = new_col.name };
            var modified = false;

            if (!std.mem.eql(u8, old_col.data_type, new_col.data_type)) {
                mod.type_changed = new_col.data_type;
                modified = true;
            }
            if (old_col.nullable != new_col.nullable) {
                mod.nullable_changed = new_col.nullable;
                modified = true;
            }
            // Check default... (string comparison for now)
            const old_def = old_col.default orelse "";
            const new_def = new_col.default orelse "";
            if (!std.mem.eql(u8, old_def, new_def)) {
                if (old_col.default == null and new_col.default == null) {
                    // Equal
                } else {
                   mod.default_changed = new_col.default;
                   modified = true;
                }
            }

            if (modified) {
                try changes.append(allocator, TableChange{ .modify_column = mod });
            }

            _ = old_cols.remove(new_col.name);
        } else {
            // Added
            try changes.append(allocator, TableChange{ .add_column = new_col });
        }
    }

    // Dropped
    var it = old_cols.iterator();
    while (it.next()) |entry| {
        try changes.append(allocator, TableChange{ .drop_column = entry.key_ptr.* });
    }
}
