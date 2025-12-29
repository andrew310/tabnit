const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: lexer.Lexer,
    sql: []const u8,

    pub fn init(allocator: std.mem.Allocator, sql: []const u8, dialect: ast.Dialect) Parser {
        return .{ 
            .allocator = allocator,
            .lexer = lexer.Lexer.init(sql, dialect),
            .sql = sql,
        };
    }

    pub fn parse(self: *Parser) !ast.ParseResult {
        var result = ast.ParseResult{ .statements = .{} };
        errdefer result.deinit(self.allocator);

        while (true) {
            const token = self.lexer.next();

            if (token.typ == .EOF) break;
            if (token.typ == .Semicolon) continue;

            if (token.typ == .Keyword and lexer.eqlIgnoreCase(token.text, "CREATE")) {
                var next_token = self.lexer.next();

                // Handle [OR REPLACE]
                if (lexer.eqlIgnoreCase(next_token.text, "OR")) {
                    const replace_token = self.lexer.next();
                    if (!lexer.eqlIgnoreCase(replace_token.text, "REPLACE")) return error.ExpectedReplace;
                    next_token = self.lexer.next();
                }

                if (lexer.eqlIgnoreCase(next_token.text, "TABLE")) {
                    var table_stmt = try self.parseCreateTable();
                    errdefer table_stmt.deinit(self.allocator);
                    try result.statements.append(self.allocator, ast.Statement{ .create_table = table_stmt });
                } else if (lexer.eqlIgnoreCase(next_token.text, "TYPE")) {
                    var type_stmt = try self.parseCreateType();
                    errdefer type_stmt.deinit(self.allocator);
                    try result.statements.append(self.allocator, ast.Statement{ .create_type = type_stmt });
                } else if (lexer.eqlIgnoreCase(next_token.text, "SCHEMA")) {
                    var schema_stmt = try self.parseCreateSchema();
                    errdefer schema_stmt.deinit(self.allocator);
                    try result.statements.append(self.allocator, ast.Statement{ .create_schema = schema_stmt });
                } else if (lexer.eqlIgnoreCase(next_token.text, "FUNCTION")) {
                    var func_stmt = try self.parseCreateFunction();
                    errdefer func_stmt.deinit(self.allocator);
                    try result.statements.append(self.allocator, ast.Statement{ .create_function = func_stmt });
                } else if (lexer.eqlIgnoreCase(next_token.text, "INDEX") or 
                           lexer.eqlIgnoreCase(next_token.text, "TRIGGER") or
                           lexer.eqlIgnoreCase(next_token.text, "EXTENSION") or
                           lexer.eqlIgnoreCase(next_token.text, "UNIQUE")) { // Handle CREATE UNIQUE INDEX
                    try result.statements.append(self.allocator, ast.Statement{ .ignored = .{ .name = next_token.text } });
                    try self.skipUntilSemicolon();
                } else {
                    return error.UnknownStatementType;
                }
            } else if (token.typ == .Keyword and lexer.eqlIgnoreCase(token.text, "INSERT")) {
                try result.statements.append(self.allocator, ast.Statement{ .ignored = .{ .name = "INSERT" } });
                try self.skipUntilSemicolon();
            } else if (token.typ == .Keyword and lexer.eqlIgnoreCase(token.text, "DO")) {
                try result.statements.append(self.allocator, ast.Statement{ .ignored = .{ .name = "DO" } });
                try self.skipUntilSemicolon();
            } else {
                // Ignore unexpected top-level tokens for now to be robust
                // but maybe we should error if it's really bad?
                // Let's just skip until semicolon if we don't recognize it.
                // return error.ExpectedCreate; 
                try self.skipUntilSemicolon();
            }
        }

        return result;
    }

    fn skipUntilSemicolon(self: *Parser) !void {
        while (true) {
            const t = self.lexer.next();
            if (t.typ == .Semicolon or t.typ == .EOF) break;
        }
    }

    fn parseCreateFunction(self: *Parser) !ast.CreateFunctionStmt {
        const name_token = self.lexer.next();
        if (name_token.typ != .Identifier and name_token.typ != .Keyword) return error.ExpectedIdentifier;

        var stmt = ast.CreateFunctionStmt{ .name = name_token.text };

        // Parse arguments (...)
        const open_paren = self.lexer.next();
        if (open_paren.typ == .OpenParen) {
            var depth: usize = 1;
            while (depth > 0) {
                const t = self.lexer.next();
                if (t.typ == .EOF) break;
                if (t.typ == .OpenParen) depth += 1;
                if (t.typ == .CloseParen) depth -= 1;
            }
        }

        // Parse metadata and body
        while (true) {
            const t = self.lexer.next();
            if (t.typ == .EOF or t.typ == .Semicolon) break;
            if (lexer.eqlIgnoreCase(t.text, "RETURNS")) {
                const ret = self.lexer.next();
                stmt.returns = ret.text;
            } else if (lexer.eqlIgnoreCase(t.text, "AS")) {
                const body = self.lexer.next();
                if (body.typ == .String) {
                    stmt.body = body.text;
                }
            }
        }

        return stmt;
    }

    fn parseCreateSchema(self: *Parser) !ast.CreateSchemaStmt {
        var stmt = ast.CreateSchemaStmt{ .name = "" };
        var token = self.lexer.next();

        if (lexer.eqlIgnoreCase(token.text, "IF")) {
            const not_kw = self.lexer.next();
            if (!lexer.eqlIgnoreCase(not_kw.text, "NOT")) return error.ExpectedNot;

            const exists_kw = self.lexer.next();
            if (!lexer.eqlIgnoreCase(exists_kw.text, "EXISTS")) return error.ExpectedExists;

            stmt.if_not_exists = true;
            token = self.lexer.next();
        }

        if (token.typ != .Identifier and token.typ != .Keyword) return error.ExpectedIdentifier;
        stmt.name = token.text;

        return stmt;
    }

    fn parseCreateType(self: *Parser) !ast.CreateTypeStmt {
        const name_token = self.lexer.next();
        if (name_token.typ != .Identifier and name_token.typ != .Keyword) return error.ExpectedIdentifier;

        const as_kw = self.lexer.next();
        if (!lexer.eqlIgnoreCase(as_kw.text, "AS")) return error.ExpectedAs;

        const enum_kw = self.lexer.next();
        if (!lexer.eqlIgnoreCase(enum_kw.text, "ENUM")) return error.ExpectedEnum;

        const open_paren = self.lexer.next();
        if (open_paren.typ != .OpenParen) return error.ExpectedOpenParen;

        var stmt = ast.CreateTypeStmt{ .name = name_token.text, .values = .{} };
        errdefer stmt.values.deinit(self.allocator);

        while (true) {
            const val_token = self.lexer.next();
            if (val_token.typ == .CloseParen) break;
            if (val_token.typ != .String) return error.ExpectedString;

            try stmt.values.append(self.allocator, val_token.text);

            const sep = self.lexer.next();
            if (sep.typ == .CloseParen) break;
            if (sep.typ != .Comma) return error.ExpectedCommaOrClose;
        }

        return stmt;
    }

    fn parseCreateTable(self: *Parser) !ast.CreateTableStmt {
        var token = self.lexer.next();
        var stmt = ast.CreateTableStmt{ .table = "", .columns = .{} };
        errdefer stmt.deinit(self.allocator);

        if (lexer.eqlIgnoreCase(token.text, "IF")) {
            _ = self.lexer.next(); // skip EXISTS
            stmt.if_exists = true;
            token = self.lexer.next();
        }

        if (token.typ != .Identifier and token.typ != .Keyword) return error.ExpectedIdentifier;
        const first_part = token.text;
        const saved_lexer = self.lexer; // Save state
        
        const next_tok = self.lexer.next();

        if (next_tok.typ == .Dot) {
            stmt.schema = first_part;
            const table_tok = self.lexer.next();
            stmt.table = table_tok.text;
        } else {
            stmt.table = first_part;
            self.lexer = saved_lexer; // Restore
        }

        const open_paren = self.lexer.next();
        if (open_paren.typ != .OpenParen) return error.ExpectedOpenParen;

        while (true) {
            const name_token = self.lexer.next();

            if (name_token.typ == .CloseParen) break;

            if (name_token.typ == .Keyword and lexer.eqlIgnoreCase(name_token.text, "PRIMARY")) {
                const key_token = self.lexer.next();
                if (!lexer.eqlIgnoreCase(key_token.text, "KEY")) return error.ExpectedKey;

                const pk_open = self.lexer.next();
                if (pk_open.typ != .OpenParen) return error.ExpectedOpenParen;

                while (true) {
                    const pk_col = self.lexer.next();
                    if (pk_col.typ != .Identifier and pk_col.typ != .Keyword) return error.ExpectedColumnName;
                    try stmt.primary_key_columns.append(self.allocator, pk_col.text);

                    const pk_sep = self.lexer.next();
                    if (pk_sep.typ == .CloseParen) break;
                    if (pk_sep.typ != .Comma) return error.ExpectedCommaOrClose;
                }

                const after_pk = self.lexer.next();
                if (after_pk.typ == .CloseParen) break;
                if (after_pk.typ != .Comma) return error.ExpectedCommaOrClose;
                continue;
            }

            if (name_token.typ == .Keyword and lexer.eqlIgnoreCase(name_token.text, "UNIQUE")) {
                const uq_open = self.lexer.next();
                if (uq_open.typ != .OpenParen) return error.ExpectedOpenParen;

                var uc = ast.UniqueConstraint{ .columns = .{} };
                errdefer uc.columns.deinit(self.allocator);

                while (true) {
                    const uq_col = self.lexer.next();
                    if (uq_col.typ != .Identifier and uq_col.typ != .Keyword) return error.ExpectedColumnName;
                    try uc.columns.append(self.allocator, uq_col.text);

                    const uq_sep = self.lexer.next();
                    if (uq_sep.typ == .CloseParen) break;
                    if (uq_sep.typ != .Comma) return error.ExpectedCommaOrClose;
                }

                try stmt.unique_constraints.append(self.allocator, uc);

                const after_uq = self.lexer.next();
                if (after_uq.typ == .CloseParen) break;
                if (after_uq.typ != .Comma) return error.ExpectedCommaOrClose;
                continue;
            }

            if (name_token.typ != .Identifier and name_token.typ != .Keyword) return error.ExpectedColumnName;

            const type_token = self.lexer.next();
            if (type_token.typ != .Identifier and type_token.typ != .Keyword) return error.ExpectedColumnType;

            var nullable: bool = true;
            var is_primary_key: bool = false;
            var is_unique: bool = false;
            var default_expr: ?[]const u8 = null;
            var foreign_key: ?ast.ForeignKey = null;
            var sep = self.lexer.next();

            while (sep.typ == .Keyword) {
                if (lexer.eqlIgnoreCase(sep.text, "NOT")) {
                    const null_token = self.lexer.next();
                    if (!lexer.eqlIgnoreCase(null_token.text, "NULL")) return error.ExpectedNull;
                    nullable = false;
                    sep = self.lexer.next();
                } else if (lexer.eqlIgnoreCase(sep.text, "NULL")) {
                    nullable = true;
                    sep = self.lexer.next();
                } else if (lexer.eqlIgnoreCase(sep.text, "PRIMARY")) {
                    const key_token = self.lexer.next();
                    if (!lexer.eqlIgnoreCase(key_token.text, "KEY")) return error.ExpectedKey;
                    is_primary_key = true;
                    sep = self.lexer.next();
                } else if (lexer.eqlIgnoreCase(sep.text, "UNIQUE")) {
                    is_unique = true;
                    sep = self.lexer.next();
                } else if (lexer.eqlIgnoreCase(sep.text, "DEFAULT")) {
                    const def_token = self.lexer.next();
                    const func_name_start = @intFromPtr(def_token.text.ptr) - @intFromPtr(self.sql.ptr);

                    const after_default = self.lexer.next();
                    if (after_default.typ == .OpenParen) {
                         var paren_depth: usize = 1;
                         while (paren_depth > 0) {
                             const t = self.lexer.next();
                             if (t.typ == .EOF) break;
                             if (t.typ == .OpenParen) paren_depth += 1;
                             if (t.typ == .CloseParen) paren_depth -= 1;
                         }
                         default_expr = self.sql[func_name_start..self.lexer.pos];
                         sep = self.lexer.next();
                    } else {
                        default_expr = def_token.text;
                        sep = after_default;
                    }
                } else if (lexer.eqlIgnoreCase(sep.text, "REFERENCES")) {
                    const ref_table = self.lexer.next();
                    if (ref_table.typ != .Identifier and ref_table.typ != .Keyword) return error.ExpectedIdentifier;

                    var table_name = ref_table.text;
                    var ref_next = self.lexer.next();

                    if (ref_next.typ == .Dot) {
                        const real_table = self.lexer.next();
                        if (real_table.typ != .Identifier and real_table.typ != .Keyword) return error.ExpectedIdentifier;
                        
                        // Reconstruct "schema.table" from source
                        const start = @intFromPtr(table_name.ptr) - @intFromPtr(self.sql.ptr);
                        const end = (@intFromPtr(real_table.text.ptr) + real_table.text.len) - @intFromPtr(self.sql.ptr);
                        table_name = self.sql[start..end];
                        
                        ref_next = self.lexer.next();
                    }

                    var fk = ast.ForeignKey{ .table = table_name };

                    if (ref_next.typ == .OpenParen) {
                        const ref_col = self.lexer.next();
                        if (ref_col.typ != .Identifier and ref_col.typ != .Keyword) return error.ExpectedColumnName;
                        fk.column = ref_col.text;

                        const ref_close = self.lexer.next();
                        if (ref_close.typ != .CloseParen) return error.ExpectedCloseParen;
                        ref_next = self.lexer.next();
                    }

                    if (ref_next.typ == .Keyword and lexer.eqlIgnoreCase(ref_next.text, "ON")) {
                        const delete_kw = self.lexer.next();
                        if (!lexer.eqlIgnoreCase(delete_kw.text, "DELETE")) return error.ExpectedDelete;

                        const action = self.lexer.next();
                        if (lexer.eqlIgnoreCase(action.text, "SET")) {
                            const null_kw = self.lexer.next();
                            if (!lexer.eqlIgnoreCase(null_kw.text, "NULL")) return error.ExpectedNull;
                            fk.on_delete = "SET NULL";
                        } else {
                            fk.on_delete = action.text;
                        }
                        sep = self.lexer.next();
                    } else {
                        sep = ref_next;
                    }

                    foreign_key = fk;
                } else {
                    break;
                }
            }

            try stmt.columns.append(self.allocator, ast.Column{
                .name = name_token.text,
                .data_type = type_token.text,
                .nullable = if (is_primary_key) false else nullable,
                .primary_key = is_primary_key,
                .unique = is_unique,
                .default = default_expr,
                .references = foreign_key,
            });

            if (sep.typ == .CloseParen) break;
            if (sep.typ != .Comma) return error.ExpectedCommaOrClose;
        }

        return stmt;
    }
};

// --- TESTS ---

test "basic CREATE TABLE" {
    const allocator = std.testing.allocator;
    const sql = "CREATE TABLE users (id INT, name TEXT)";
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.statements.items.len);
    const stmt = result.statements.items[0].create_table;

    try std.testing.expectEqualStrings("users", stmt.table);
    try std.testing.expectEqual(@as(usize, 2), stmt.columns.items.len);
}

test "complex table with all features" {
    const allocator = std.testing.allocator;
    const sql = "CREATE TABLE orders (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE, total DECIMAL NOT NULL DEFAULT 0, status TEXT UNIQUE, UNIQUE(user_id, status))";

    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    const stmt = result.statements.items[0].create_table;
    try std.testing.expectEqualStrings("orders", stmt.table);
    try std.testing.expectEqual(@as(usize, 4), stmt.columns.items.len);
}

test "quoted identifiers with spaces" {
    const allocator = std.testing.allocator;
    const sql = "CREATE TABLE \"my table\" (\"user name\" TEXT)";
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    const stmt = result.statements.items[0].create_table;
    try std.testing.expectEqualStrings("my table", stmt.table);
    try std.testing.expectEqualStrings("user name", stmt.columns.items[0].name);
}

test "CREATE TYPE AS ENUM" {
    const allocator = std.testing.allocator;
    const sql = "CREATE TYPE status AS ENUM ('pending', 'active')";
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    const stmt = result.statements.items[0].create_type;
    try std.testing.expectEqualStrings("status", stmt.name);
    try std.testing.expectEqualStrings("pending", stmt.values.items[0]);
    try std.testing.expectEqualStrings("active", stmt.values.items[1]);
}

test "comments are ignored" {
    const allocator = std.testing.allocator;
    const sql = "/* Block comment */ CREATE TABLE t (id INT -- Inline comment\n);";
        
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);
    
    try std.testing.expectEqual(@as(usize, 1), result.statements.items.len);
}

test "CREATE SCHEMA" {
    const allocator = std.testing.allocator;
    const sql = "CREATE SCHEMA myschema";
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    const stmt = result.statements.items[0].create_schema;
    try std.testing.expectEqualStrings("myschema", stmt.name);
    try std.testing.expect(stmt.if_not_exists == false);
}

test "CREATE SCHEMA IF NOT EXISTS" {
    const allocator = std.testing.allocator;
    const sql = "CREATE SCHEMA IF NOT EXISTS myschema";
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    const stmt = result.statements.items[0].create_schema;
    try std.testing.expectEqualStrings("myschema", stmt.name);
    try std.testing.expect(stmt.if_not_exists == true);
}

test "REFERENCES schema qualified" {
    const allocator = std.testing.allocator;
    const sql = "CREATE TABLE t (id INT REFERENCES schema.table(id))";
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    const stmt = result.statements.items[0].create_table;
    const ref = stmt.columns.items[0].references.?;
    try std.testing.expectEqualStrings("schema.table", ref.table);
}

test "Array Type" {
    const allocator = std.testing.allocator;
    const sql = "CREATE TABLE t (tags TEXT[])";
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    const stmt = result.statements.items[0].create_table;
    try std.testing.expectEqualStrings("TEXT[]", stmt.columns.items[0].data_type);
}

test "CREATE OR REPLACE FUNCTION" {
    const allocator = std.testing.allocator;
    const sql = "CREATE OR REPLACE FUNCTION func(a INT) RETURNS trigger AS $$ BEGIN RETURN NEW; END $$ LANGUAGE plpgsql;";
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.statements.items.len);
    const stmt = result.statements.items[0].create_function;
    try std.testing.expectEqualStrings("func", stmt.name);
    try std.testing.expectEqualStrings("trigger", stmt.returns);
    try std.testing.expectEqualStrings(" BEGIN RETURN NEW; END ", stmt.body);
}

test "INSERT and metadata ignored" {
    const allocator = std.testing.allocator;
    const sql = "INSERT INTO t VALUES (1); CREATE INDEX i ON t(a);";
    var parser = Parser.init(allocator, sql, .Postgres);
    var result = try parser.parse();
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.statements.items.len);
    try std.testing.expect(result.statements.items[0] == .ignored);
    try std.testing.expectEqualStrings("INSERT", result.statements.items[0].ignored.name);
}