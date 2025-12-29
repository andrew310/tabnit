const std = @import("std");
const ast = @import("ast.zig");

pub const TokenType = enum {
    Keyword,
    Identifier,
    String,
    Dot,
    EOF,
    OpenParen,
    CloseParen,
    Comma,
    Semicolon,
};

pub const Token = struct {
    typ: TokenType,
    text: []const u8,
    line: usize,
    col: usize,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize = 0,
    line: usize = 1,
    line_start_pos: usize = 0,
    dialect: ast.Dialect,

    pub fn init(source: []const u8, dialect: ast.Dialect) Lexer {
        return .{ 
            .source = source,
            .dialect = dialect,
        };
    }

    pub fn peek(self: *Lexer) Token {
        const saved = self.*;
        defer self.* = saved;
        return self.next();
    }

    fn current_col(self: *Lexer) usize {
        return self.pos - self.line_start_pos + 1;
    }

    fn advance(self: *Lexer) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.line_start_pos = self.pos + 1;
            }
            self.pos += 1;
        }
    }

    pub fn next(self: *Lexer) Token {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];

            // Skip whitespace
            if (std.ascii.isWhitespace(c)) {
                self.advance();
                continue;
            }

            // Skip -- comments
            if (self.pos + 1 < self.source.len and c == '-' and self.source[self.pos + 1] == '-') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.advance();
                }
                continue;
            }

            // Skip /* */ comments
            if (self.pos + 1 < self.source.len and c == '/' and self.source[self.pos + 1] == '*') {
                self.advance(); // /
                self.advance(); // *
                while (self.pos + 1 < self.source.len) {
                    if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                        self.advance(); // *
                        self.advance(); // /
                        break;
                    }
                    self.advance();
                }
                continue;
            }

            // Skip psql commands (lines starting with backslash)
            if (c == '\\') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.advance();
                }
                continue;
            }

            break;
        }

        if (self.pos >= self.source.len) {
            return .{ .typ = .EOF, .text = self.source[self.source.len..], .line = self.line, .col = self.current_col() };
        }

        const start = self.pos;
        const start_col = self.current_col();
        const start_line = self.line;
        const char = self.source[self.pos];

        // Punctuation
        if (char == '(') {
            self.advance();
            return .{ .typ = .OpenParen, .text = self.source[start .. start + 1], .line = start_line, .col = start_col };
        }
        if (char == ')') {
            self.advance();
            return .{ .typ = .CloseParen, .text = self.source[start .. start + 1], .line = start_line, .col = start_col };
        }
        if (char == ',') {
            self.advance();
            return .{ .typ = .Comma, .text = self.source[start .. start + 1], .line = start_line, .col = start_col };
        }
        if (char == ';') {
            self.advance();
            return .{ .typ = .Semicolon, .text = self.source[start .. start + 1], .line = start_line, .col = start_col };
        }
        if (char == '.') {
            self.advance();
            return .{ .typ = .Dot, .text = self.source[start .. start + 1], .line = start_line, .col = start_col };
        }

        // Single-quoted strings (values)
        if (char == '\'') {
            self.advance(); // skip opening '
            const content_start = self.pos;
            while (self.pos < self.source.len) {
                if (self.source[self.pos] == '\'') {
                    // Check for escaped quote ''
                    if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\'') {
                        self.advance(); // first ''
                        self.advance(); // second ''
                        continue;
                    } else {
                        break; // End of string
                    }
                }
                self.advance();
            }
            const content = self.source[content_start..self.pos];
            if (self.pos < self.source.len) self.advance(); // skip closing ''
            return .{ .typ = .String, .text = content, .line = start_line, .col = start_col };
        }

        // Dollar-quoted strings ($$ or $tag$)
        if (char == '$') {
             const tag_start = self.pos;
             self.advance(); // $
             
             // Scan rest of tag
             while (self.pos < self.source.len) {
                 const c = self.source[self.pos];
                 if (c == '$') {
                     self.advance();
                     break;
                 }
                 if (!std.ascii.isAlphanumeric(c) and c != '_') {
                     break; 
                 }
                 self.advance();
             }
             const tag = self.source[tag_start..self.pos];
             
             // If valid tag (ends with $), consume content
             if (std.mem.endsWith(u8, tag, "$")) {
                 const content_start = self.pos;
                 
                 while (self.pos < self.source.len) {
                     // Check for closing tag
                     if (std.mem.startsWith(u8, self.source[self.pos..], tag)) {
                         const content_end = self.pos;
                         // Consume closing tag
                         for (0..tag.len) |_| self.advance();
                         return .{ .typ = .String, .text = self.source[content_start..content_end], .line = start_line, .col = start_col };
                     }
                     self.advance();
                 }
             }
             return .{ .typ = .Identifier, .text = tag, .line = start_line, .col = start_col };
        }

        // Double-quoted identifiers - DIALECT AWARE
        const quote_char = self.dialect.identifierQuoteChar();
        if (char == quote_char) {
            self.advance();
            const content_start = self.pos;
            while (self.pos < self.source.len and self.source[self.pos] != quote_char) {
                self.advance();
            }
            const content = self.source[content_start..self.pos];
            if (self.pos < self.source.len) self.advance();
            return .{ .typ = .Identifier, .text = content, .line = start_line, .col = start_col };
        }

        // Unquoted Identifiers / Keywords
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isWhitespace(c) or c == '.' or c == quote_char or c == '\'' or c == '(' or c == ')' or c == ',' or c == ';') break;
            self.advance();
        }

        const text = self.source[start..self.pos];
        const typ: TokenType = if (isKeyword(text)) .Keyword else .Identifier;

        return .{ .typ = typ, .text = text, .line = start_line, .col = start_col };
    }
};

fn isKeyword(text: []const u8) bool {
    const keywords = .{ 
        "CREATE", "TABLE", "TYPE", "AS", "ENUM", "IF", "EXISTS",
        "NULL", "NOT", "PRIMARY", "KEY", "DEFAULT", "REFERENCES",
        "ON", "DELETE", "CASCADE", "SET", "UNIQUE", "SCHEMA",
        "FUNCTION", "RETURNS", "LANGUAGE", "OR", "REPLACE",
        "INSERT", "INTO", "VALUES", "INDEX", "TRIGGER", "EXTENSION",
        "DO", "BEGIN", "END", "GENERATED", "ALWAYS", "BY", "IDENTITY",
        "CONSTRAINT", "CHECK",
    };
    inline for (keywords) |kw| {
        if (eqlIgnoreCase(text, kw)) return true;
    }
    return false;
}

pub fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |char, i| {
        if (std.ascii.toUpper(char) != std.ascii.toUpper(b[i])) return false;
    }
    return true;
}
