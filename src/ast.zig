const std = @import("std");

pub const Dialect = enum {
    Postgres,

    pub fn identifierQuoteChar(self: Dialect) u8 {
        return switch (self) {
            .Postgres => '"',
        };
    }
};

pub const ForeignKey = struct {
    table: []const u8,
    column: ?[]const u8 = null,
    on_delete: ?[]const u8 = null, // CASCADE, SET NULL, etc.
};

pub const Column = struct {
    name: []const u8,
    data_type: []const u8, // Kept as string slice for flexibility (e.g. "VARCHAR(255)")
    nullable: bool = true, // SQL defaults to nullable
    primary_key: bool = false,
    unique: bool = false,
    default: ?[]const u8 = null, // DEFAULT expression as string
    references: ?ForeignKey = null,
};

pub const UniqueConstraint = struct {
    columns: std.ArrayList([]const u8),

    pub fn deinit(self: *UniqueConstraint, allocator: std.mem.Allocator) void {
        self.columns.deinit(allocator);
    }
};

pub const CreateTableStmt = struct {
    if_exists: bool = false,
    schema: ?[]const u8 = null,
    table: []const u8,
    columns: std.ArrayList(Column), // Dynamic List!
    primary_key_columns: std.ArrayList([]const u8) = .{}, // Table-level PRIMARY KEY
    unique_constraints: std.ArrayList(UniqueConstraint) = .{}, // Table-level UNIQUE

    pub fn deinit(self: *CreateTableStmt, allocator: std.mem.Allocator) void {
        self.columns.deinit(allocator);
        self.primary_key_columns.deinit(allocator);
        for (self.unique_constraints.items) |*uc| {
            uc.deinit(allocator);
        }
        self.unique_constraints.deinit(allocator);
    }
};

pub const CreateTypeStmt = struct {
    name: []const u8,
    values: std.ArrayList([]const u8), // ENUM values

    pub fn deinit(self: *CreateTypeStmt, allocator: std.mem.Allocator) void {
        self.values.deinit(allocator);
    }
};

pub const CreateSchemaStmt = struct {
    name: []const u8,
    if_not_exists: bool = false,

    pub fn deinit(self: *CreateSchemaStmt, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const CreateFunctionStmt = struct {
    name: []const u8,
    // We keep these simple for shallow parsing
    returns: []const u8 = "",
    body: []const u8 = "",

    pub fn deinit(self: *CreateFunctionStmt, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

// Generic bucket for statements we parse but don't analyze deeply (INSERT, INDEX, etc.)
pub const IgnoredStmt = struct {
    name: []const u8, // e.g. "INSERT", "INDEX"
    
    pub fn deinit(self: *IgnoredStmt, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

// Tagged union for different statement types
pub const Statement = union(enum) {
    create_table: CreateTableStmt,
    create_type: CreateTypeStmt,
    create_schema: CreateSchemaStmt,
    create_function: CreateFunctionStmt,
    ignored: IgnoredStmt,

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .create_table => |*s| s.deinit(allocator),
            .create_type => |*s| s.deinit(allocator),
            .create_schema => |*s| s.deinit(allocator),
            .create_function => |*s| s.deinit(allocator),
            .ignored => |*s| s.deinit(allocator),
        }
    }
};

// Container for multiple statements
pub const ParseResult = struct {
    statements: std.ArrayList(Statement),

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        for (self.statements.items) |*stmt| {
            stmt.deinit(allocator);
        }
        self.statements.deinit(allocator);
    }
};
