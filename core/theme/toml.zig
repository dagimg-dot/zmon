//! The part of TOML that theme and settings files use: comments, `[a.b]`
//! headers, and `key = value` where a value is a string, a number, true or
//! false, or an inline table `{ k = v, ... }` of those. Every value comes out
//! under its full dotted path (`colors.list.item.selection.background`).
//! Arrays, multi-line strings and dates are refused with the line they're on.
const std = @import("std");

pub const Value = union(enum) {
    string: []const u8,
    number: f64,
    boolean: bool,
};

pub const Entry = struct {
    path: []const u8,
    value: Value,
};

/// Where a file went wrong: its line (from 1) and what was expected there.
pub const Problem = struct {
    line: u32 = 0,
    message: []const u8 = "",
};

pub const Error = error{ Invalid, OutOfMemory };

/// Parses `text`; paths and strings are allocated in `a`. On `error.Invalid`,
/// `problem` says where.
pub fn parse(a: std.mem.Allocator, text: []const u8, problem: *Problem) Error![]Entry {
    var entries: std.ArrayList(Entry) = .empty;
    var section: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    var number: u32 = 0;
    while (lines.next()) |raw| {
        number += 1;
        const line = std.mem.trim(u8, stripComment(raw), " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '[') {
            if (line.len < 3 or line[line.len - 1] != ']' or line[1] == '[')
                return fail(problem, number, "a section header like [colors.core]");
            const name = std.mem.trim(u8, line[1 .. line.len - 1], " \t");
            if (!validPath(name)) return fail(problem, number, "a section name of letters, digits, _ and -");
            section = try a.dupe(u8, name);
            continue;
        }
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse return fail(problem, number, "key = value");
        const key = std.mem.trim(u8, line[0..eq], " \t");
        if (!validPath(key)) return fail(problem, number, "a key of letters, digits, _ and -");
        const rest = std.mem.trim(u8, line[eq + 1 ..], " \t");
        const path = try join(a, section, key);
        if (rest.len > 0 and rest[0] == '{') {
            if (rest[rest.len - 1] != '}') return fail(problem, number, "an inline table closed with }");
            try inlineTable(a, &entries, path, rest[1 .. rest.len - 1], problem, number);
        } else {
            const value = scalar(a, rest) catch |e| switch (e) {
                error.Invalid => return fail(problem, number, "a string in quotes, a number, true or false"),
                error.OutOfMemory => return error.OutOfMemory,
            };
            try entries.append(a, .{ .path = path, .value = value });
        }
    }
    return entries.items;
}

/// The value at `path`, or null.
pub fn get(entries: []const Entry, path: []const u8) ?Value {
    for (entries) |e| if (std.mem.eql(u8, e.path, path)) return e.value;
    return null;
}

/// The string at `path`, or null when there is none or it isn't a string.
pub fn getString(entries: []const Entry, path: []const u8) ?[]const u8 {
    const v = get(entries, path) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

fn inlineTable(a: std.mem.Allocator, entries: *std.ArrayList(Entry), prefix: []const u8, body: []const u8, problem: *Problem, number: u32) Error!void {
    var i: usize = 0;
    while (i < body.len) {
        while (i < body.len and (body[i] == ' ' or body[i] == '\t' or body[i] == ',')) i += 1;
        if (i == body.len) break;
        const eq = std.mem.indexOfScalarPos(u8, body, i, '=') orelse return fail(problem, number, "key = value inside { }");
        const key = std.mem.trim(u8, body[i..eq], " \t");
        if (!validPath(key)) return fail(problem, number, "a key inside { }");
        var j = eq + 1;
        while (j < body.len and (body[j] == ' ' or body[j] == '\t')) j += 1;
        const end = valueEnd(body, j);
        const value = scalar(a, std.mem.trim(u8, body[j..end], " \t")) catch |e| switch (e) {
            error.Invalid => return fail(problem, number, "a string, number, true or false inside { }"),
            error.OutOfMemory => return error.OutOfMemory,
        };
        try entries.append(a, .{ .path = try join(a, prefix, key), .value = value });
        i = end;
    }
}

/// Where a value starting at `start` ends: after its closing quote, or at the next comma.
fn valueEnd(body: []const u8, start: usize) usize {
    if (start < body.len and body[start] == '"') {
        var k = start + 1;
        while (k < body.len) : (k += 1) {
            if (body[k] == '\\') {
                k += 1;
                continue;
            }
            if (body[k] == '"') return k + 1;
        }
        return body.len;
    }
    return std.mem.indexOfScalarPos(u8, body, start, ',') orelse body.len;
}

fn scalar(a: std.mem.Allocator, text: []const u8) error{ Invalid, OutOfMemory }!Value {
    if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') return .{ .string = try unescape(a, text[1 .. text.len - 1]) };
    if (std.mem.eql(u8, text, "true")) return .{ .boolean = true };
    if (std.mem.eql(u8, text, "false")) return .{ .boolean = false };
    const n = std.fmt.parseFloat(f64, text) catch return error.Invalid;
    return .{ .number = n };
}

fn unescape(a: std.mem.Allocator, s: []const u8) error{ Invalid, OutOfMemory }![]const u8 {
    if (std.mem.indexOfScalar(u8, s, '\\') == null) return a.dupe(u8, s);
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] != '\\') {
            try out.append(a, s[i]);
            continue;
        }
        i += 1;
        if (i == s.len) return error.Invalid;
        try out.append(a, switch (s[i]) {
            'n' => '\n',
            't' => '\t',
            '"' => '"',
            '\\' => '\\',
            else => return error.Invalid,
        });
    }
    return out.items;
}

/// The line without a `#` comment, minding `#` inside quoted strings ("#1e1e2e").
fn stripComment(line: []const u8) []const u8 {
    var quoted = false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        switch (line[i]) {
            '\\' => i += 1,
            '"' => quoted = !quoted,
            '#' => if (!quoted) return line[0..i],
            else => {},
        }
    }
    return line;
}

fn validPath(p: []const u8) bool {
    if (p.len == 0 or p[0] == '.' or p[p.len - 1] == '.') return false;
    for (p) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.')) return false;
    return std.mem.indexOf(u8, p, "..") == null;
}

fn join(a: std.mem.Allocator, prefix: []const u8, key: []const u8) error{OutOfMemory}![]const u8 {
    if (prefix.len == 0) return a.dupe(u8, key);
    return std.mem.concat(a, u8, &.{ prefix, ".", key });
}

fn fail(problem: *Problem, line: u32, expected: []const u8) error{Invalid} {
    problem.* = .{ .line = line, .message = expected };
    return error.Invalid;
}

test "sections, strings with # inside, comments and inline tables come out as dotted paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    const entries = try parse(arena.allocator(),
        \\# Catppuccin Mocha
        \\[meta]
        \\version = 1
        \\name = "Catppuccin Mocha"
        \\
        \\[colors.core]
        \\background = "#1E1E2E"        # Base
        \\[colors.text]
        \\selection = { background = "colors.core.accent", foreground = "#0f1014" }
        \\[colors.list.item.selection]
        \\secondary_background = { name = "colors.core.accent", opacity = 0.45 }
        \\dark = true
    , &problem);
    try std.testing.expectEqualStrings("Catppuccin Mocha", getString(entries, "meta.name").?);
    try std.testing.expectEqual(@as(f64, 1), get(entries, "meta.version").?.number);
    try std.testing.expectEqualStrings("#1E1E2E", getString(entries, "colors.core.background").?);
    try std.testing.expectEqualStrings("colors.core.accent", getString(entries, "colors.text.selection.background").?);
    try std.testing.expectEqualStrings("#0f1014", getString(entries, "colors.text.selection.foreground").?);
    try std.testing.expectEqual(@as(f64, 0.45), get(entries, "colors.list.item.selection.secondary_background.opacity").?.number);
    try std.testing.expect(get(entries, "colors.list.item.selection.dark").?.boolean);
}

test "a broken file says which line and what was expected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    try std.testing.expectError(error.Invalid, parse(arena.allocator(), "[meta]\nname = \"ok\"\ncolors = [1, 2]\n", &problem));
    try std.testing.expectEqual(@as(u32, 3), problem.line);
    try std.testing.expectError(error.Invalid, parse(arena.allocator(), "[meta\n", &problem));
    try std.testing.expectEqual(@as(u32, 1), problem.line);
    try std.testing.expectError(error.Invalid, parse(arena.allocator(), "just words\n", &problem));
}

test "escapes in strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    const entries = try parse(arena.allocator(), "description = \"Say \\\"hi\\\"\"\n", &problem);
    try std.testing.expectEqualStrings("Say \"hi\"", getString(entries, "description").?);
}
