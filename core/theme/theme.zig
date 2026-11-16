//! Themes: a few colours a theme file sets, and every other colour zmon needs
//! derived from them, as vicinae derives its own (theme-file.cpp). A theme is
//! resolved once, into a dense `Palette` indexed by `Token`, when it is loaded.
const std = @import("std");
const toml = @import("toml.zig");
const Rgba = @import("color.zig").Rgba;

/// Every colour zmon draws with.
pub const Token = enum(u8) {
    background,
    panel,
    foreground,
    muted,
    placeholder,
    border,
    hairline,
    hover,
    selection_bg,
    selection_fg,
    card,
    stripe,
    accent,
    accent_fg,
    danger,
    success,
    blue,
    green,
    magenta,
    orange,
    red,
    yellow,
    cyan,
    purple,
};

pub const count = std.enums.values(Token).len;

/// A theme's colours, one per token.
pub const Palette = [count]Rgba;

pub fn get(p: *const Palette, t: Token) Rgba {
    return p[@backingInt(t)];
}

/// The eight accents, in the order theme cards show them.
pub const accents = [_]Token{ .blue, .cyan, .green, .yellow, .orange, .red, .magenta, .purple };

/// Where a theme file sets each token ("" when only derived).
const paths = blk: {
    var p: [count][]const u8 = @splat("");
    p[@backingInt(Token.background)] = "colors.core.background";
    p[@backingInt(Token.panel)] = "colors.core.secondary_background";
    p[@backingInt(Token.foreground)] = "colors.core.foreground";
    p[@backingInt(Token.muted)] = "colors.text.muted";
    p[@backingInt(Token.placeholder)] = "colors.text.placeholder";
    p[@backingInt(Token.border)] = "colors.core.border";
    p[@backingInt(Token.hover)] = "colors.list.item.hover.background";
    p[@backingInt(Token.selection_bg)] = "colors.list.item.selection.background";
    p[@backingInt(Token.selection_fg)] = "colors.list.item.selection.foreground";
    p[@backingInt(Token.card)] = "colors.grid.item.background";
    p[@backingInt(Token.accent)] = "colors.core.accent";
    p[@backingInt(Token.accent_fg)] = "colors.core.accent_foreground";
    p[@backingInt(Token.danger)] = "colors.text.danger";
    p[@backingInt(Token.success)] = "colors.text.success";
    for ([_]Token{ .blue, .green, .magenta, .orange, .red, .yellow, .cyan, .purple }) |t| {
        p[@backingInt(t)] = "colors.accents." ++ @tagName(t);
    }
    break :blk p;
};

/// The token a reference like "colors.core.accent" names.
fn tokenAt(path: []const u8) ?Token {
    if (std.mem.eql(u8, path, "colors.text.default")) return .foreground;
    for (paths, 0..) |p, i| if (p.len > 0 and std.mem.eql(u8, p, path)) return @fromBackingInt(@intCast(i));
    return null;
}

const Source = union(enum) {
    literal: Rgba,
    ref: Token,
};

/// How a theme file sets one token: a colour or a reference, and optionally
/// an opacity and a darker or lighter step.
const Spec = struct {
    source: Source,
    opacity: ?f32 = null,
    darker: ?f32 = null,
    lighter: ?f32 = null,
};

pub const Theme = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8 = "",
    /// The theme it inherits from ("" for none); vicinae's own bases map to Graphite.
    parent: []const u8 = "",
    /// What the file says; the background's luminance decides `dark` for real.
    declared_light: bool = false,
    specs: [count]?Spec = @splat(null),
    palette: Palette = undefined,
    dark: bool = true,
    /// Colours the file wrote in a way zmon couldn't read.
    unreadable: u8 = 0,

    pub fn color(t: *const Theme, tok: Token) Rgba {
        return get(&t.palette, tok);
    }
};

/// Reads a theme file's text. Strings are allocated in `a`.
pub fn parseTheme(a: std.mem.Allocator, id: []const u8, text: []const u8, problem: *toml.Problem) toml.Error!Theme {
    const entries = try toml.parse(a, text, problem);
    var t: Theme = .{
        .id = try a.dupe(u8, id),
        .name = toml.getString(entries, "meta.name") orelse try a.dupe(u8, id),
        .description = toml.getString(entries, "meta.description") orelse "",
        .declared_light = std.mem.eql(u8, toml.getString(entries, "meta.variant") orelse "", "light"),
    };
    const parent = toml.getString(entries, "meta.inherits") orelse "";
    t.parent = if (std.mem.eql(u8, parent, "vicinae-dark"))
        "graphite-dark"
    else if (std.mem.eql(u8, parent, "vicinae-light"))
        "graphite-light"
    else
        parent;
    for (paths, 0..) |path, i| {
        if (path.len == 0) continue;
        t.specs[i] = specAt(a, entries, path) catch blk: {
            t.unreadable +|= 1;
            break :blk null;
        };
    }
    return t;
}

/// The token at `path`: a plain value, or a table `{ name, opacity, darker, lighter }`.
fn specAt(a: std.mem.Allocator, entries: []const toml.Entry, path: []const u8) error{ Unreadable, OutOfMemory }!?Spec {
    if (toml.getString(entries, path)) |v| return .{ .source = try source(v) };
    const name_path = try std.mem.concat(a, u8, &.{ path, ".name" });
    const name = toml.getString(entries, name_path) orelse return null;
    var spec: Spec = .{ .source = try source(name) };
    // A theme file is anyone's text: numbers are held to what they can mean.
    spec.opacity = within(try numberAt(a, entries, path, ".opacity"), 0, 1);
    spec.darker = within(try numberAt(a, entries, path, ".darker"), 0, max_factor);
    spec.lighter = within(try numberAt(a, entries, path, ".lighter"), 0, max_factor);
    return spec;
}

/// Qt's darker and lighter take a percentage; past 100x is black or white anyway.
const max_factor = 10000;

/// `v` held between `lo` and `hi`; a number that isn't one (NaN) is dropped.
fn within(v: ?f32, lo: f32, hi: f32) ?f32 {
    const n = v orelse return null;
    if (std.math.isNan(n)) return null;
    return std.math.clamp(n, lo, hi);
}

fn numberAt(a: std.mem.Allocator, entries: []const toml.Entry, path: []const u8, key: []const u8) error{OutOfMemory}!?f32 {
    const p = try std.mem.concat(a, u8, &.{ path, key });
    const v = toml.get(entries, p) orelse return null;
    return switch (v) {
        .number => |n| @floatCast(n),
        else => null,
    };
}

fn source(v: []const u8) error{Unreadable}!Source {
    if (std.mem.startsWith(u8, v, "colors.")) return .{ .ref = tokenAt(v) orelse return error.Unreadable };
    return .{ .literal = Rgba.parse(v) orelse return error.Unreadable };
}

/// A theme file that couldn't be read, and where.
pub const Problem = struct {
    id: []const u8,
    line: u32,
    message: []const u8,
};

/// Every theme zmon knows: the built-ins, then a person's own, which replace a
/// built-in with the same id. Load, then `resolveAll`.
pub const Library = struct {
    arena: std.heap.ArenaAllocator,
    themes: std.ArrayList(Theme) = .empty,
    problems: std.ArrayList(Problem) = .empty,

    pub fn init(gpa: std.mem.Allocator) Library {
        return .{ .arena = .init(gpa) };
    }

    pub fn deinit(lib: *Library) void {
        lib.arena.deinit();
    }

    /// Adds the theme in `text`; a theme with the same id is replaced, a file
    /// that can't be read is kept as a problem.
    pub fn add(lib: *Library, id: []const u8, text: []const u8) void {
        const a = lib.arena.allocator();
        var problem: toml.Problem = .{};
        const theme = parseTheme(a, id, text, &problem) catch {
            const owned = a.dupe(u8, id) catch return;
            lib.problems.append(a, .{ .id = owned, .line = problem.line, .message = problem.message }) catch {};
            return;
        };
        if (lib.index(id)) |i| {
            lib.themes.items[i] = theme;
        } else {
            lib.themes.append(a, theme) catch {};
        }
    }

    pub fn index(lib: *const Library, id: []const u8) ?usize {
        for (lib.themes.items, 0..) |t, i| if (std.mem.eql(u8, t.id, id)) return i;
        return null;
    }

    pub fn find(lib: *const Library, id: []const u8) ?*const Theme {
        return &lib.themes.items[lib.index(id) orelse return null];
    }

    /// Resolves every theme's palette. Call after the last `add`.
    pub fn resolveAll(lib: *Library) void {
        for (lib.themes.items, 0..) |*t, i| {
            for (0..count) |k| t.palette[k] = lib.resolve(i, @fromBackingInt(@intCast(k)), 0);
            t.palette[@backingInt(Token.accent_fg)] = lib.readableOn(i, .accent_fg, .accent);
            t.palette[@backingInt(Token.selection_fg)] = lib.readableOn(i, .selection_fg, .selection_bg);
            t.dark = t.color(.background).luminance() < 0.4;
        }
    }

    fn parentOf(lib: *const Library, i: usize) ?usize {
        const p = lib.themes.items[i].parent;
        if (p.len == 0) return null;
        const pi = lib.index(p) orelse return null;
        return if (pi == i) null else pi;
    }

    /// The base theme a theme falls back to for the colours it never sets.
    fn base(lib: *const Library, i: usize) ?usize {
        const id = if (lib.themes.items[i].declared_light) "graphite-light" else "graphite-dark";
        const bi = lib.index(id) orelse return null;
        return if (bi == i) null else bi;
    }

    const max_depth = 16;

    /// A token's colour: the theme's own value, then the value a parent sets
    /// itself, then the derivation rule, then the base theme's.
    fn resolve(lib: *const Library, i: usize, tok: Token, depth: u8) Rgba {
        if (depth > max_depth) return Rgba.black;
        if (lib.themes.items[i].specs[@backingInt(tok)]) |spec| return lib.apply(i, spec, depth);
        var p = lib.parentOf(i);
        var hops: u8 = 0;
        while (p) |pi| : (hops += 1) {
            if (hops > 8) break;
            if (lib.themes.items[pi].specs[@backingInt(tok)]) |spec| return lib.apply(pi, spec, depth + 1);
            p = lib.parentOf(pi);
        }
        return lib.derive(i, tok, depth + 1);
    }

    fn apply(lib: *const Library, i: usize, spec: Spec, depth: u8) Rgba {
        var c = switch (spec.source) {
            .literal => |c| c,
            .ref => |t| lib.resolve(i, t, depth + 1),
        };
        const is_ref = spec.source == .ref;
        if (spec.opacity) |o| {
            // On a reference, opacity blends over the background into a solid
            // colour; on a literal it is the colour's own alpha (as vicinae does).
            c = if (is_ref) Rgba.mix(lib.resolve(i, .background, depth + 1), c, o) else c.withAlpha(o);
        }
        if (spec.darker) |d| c = c.darker(factor(d, is_ref));
        if (spec.lighter) |l| c = c.lighter(factor(l, is_ref));
        return c;
    }

    fn factor(v: f32, is_ref: bool) u32 {
        const f = if (is_ref) v + 100 else v;
        return @intFromFloat(std.math.clamp(@round(f), 0, max_factor + 100));
    }

    fn derive(lib: *const Library, i: usize, tok: Token, depth: u8) Rgba {
        const r = struct {
            fn at(l: *const Library, idx: usize, t: Token, d: u8) Rgba {
                return l.resolve(idx, t, d);
            }
        }.at;
        const bg = r(lib, i, .background, depth);
        return switch (tok) {
            .muted => r(lib, i, .foreground, depth).withAlpha(0.7).over(bg),
            .placeholder => r(lib, i, .foreground, depth).withAlpha(0.5).over(bg),
            .hairline => Rgba.mix(r(lib, i, .border, depth), bg, 0.5),
            .selection_bg => r(lib, i, .panel, depth),
            .selection_fg => r(lib, i, .foreground, depth),
            .hover => blk: {
                const sel = r(lib, i, .selection_bg, depth);
                break :blk if (bg.luminance() < 0.4) sel.darker(110) else Rgba.mix(sel, bg, 0.25);
            },
            .card => r(lib, i, .panel, depth),
            .stripe => Rgba.mix(bg, r(lib, i, .panel, depth), 0.5),
            .accent => r(lib, i, .blue, depth),
            .accent_fg => lib.bestOn(i, r(lib, i, .accent, depth)),
            .danger => r(lib, i, .red, depth),
            .success => r(lib, i, .green, depth),
            .purple => r(lib, i, .magenta, depth),
            else => if (lib.base(i)) |b| r(lib, b, tok, depth) else switch (tok) {
                .background => Rgba.black,
                .foreground => Rgba.white,
                else => Rgba{ .r = 128, .g = 128, .b = 128 },
            },
        };
    }

    /// Text drawn on `under` (the accent, a selected row): the theme's own
    /// colour when it can be read there (3:1 or better), else whichever of the
    /// theme's background, foreground, black or white reads best.
    fn readableOn(lib: *const Library, i: usize, text: Token, under: Token) Rgba {
        const t = &lib.themes.items[i];
        const bg = t.palette[@backingInt(Token.background)];
        const fill = t.palette[@backingInt(under)].over(bg);
        const own = t.palette[@backingInt(text)].over(fill);
        if (Rgba.contrast(own, fill) >= 3) return own;
        return lib.bestOn(i, fill);
    }

    fn bestOn(lib: *const Library, i: usize, under: Rgba) Rgba {
        const t = &lib.themes.items[i];
        const candidates = [_]Rgba{ t.palette[@backingInt(Token.background)], t.palette[@backingInt(Token.foreground)], Rgba.black, Rgba.white };
        var best = candidates[0];
        for (candidates[1..]) |c| if (Rgba.contrast(c, under) > Rgba.contrast(best, under)) {
            best = c;
        };
        return best;
    }
};

test "absurd numbers in a theme file are held in range instead of crashing" {
    var lib = Library.init(std.testing.allocator);
    defer lib.deinit();
    lib.add("wild",
        \\[meta]
        \\name = "Wild"
        \\[colors.core]
        \\background = "#202020"
        \\foreground = "#eeeeee"
        \\accent = { name = "colors.core.foreground", lighter = 1e30 }
        \\border = { name = "colors.core.foreground", darker = -1e30 }
        \\secondary_background = { name = "colors.core.background", opacity = 7 }
    );
    lib.resolveAll();
    const t = lib.find("wild").?;
    try std.testing.expectEqual(@as(usize, 0), lib.problems.items.len);
    try std.testing.expectEqual(@as(u8, 255), t.color(.panel).a);
}

test "a token set as a table with a reference and opacity blends over the background" {
    var lib = Library.init(std.testing.allocator);
    defer lib.deinit();
    lib.add("graphite-dark", "[colors.core]\nbackground = \"#000000\"\nforeground = \"#ffffff\"\n");
    lib.add("t",
        \\[meta]
        \\inherits = "vicinae-dark"
        \\[colors.core]
        \\background = "#000000"
        \\accent = "#ffffff"
        \\[colors.list.item.selection]
        \\background = { name = "colors.core.accent", opacity = 0.5 }
        \\[colors.grid.item]
        \\background = { name = "#ffffff", opacity = 0.5 }
    );
    lib.resolveAll();
    const t = lib.find("t").?;
    try std.testing.expect(t.color(.selection_bg).eql(.{ .r = 128, .g = 128, .b = 128 })); // solid grey
    try std.testing.expectEqual(@as(u8, 128), t.color(.card).a); // translucent white
    try std.testing.expectEqualStrings("graphite-dark", t.parent);
}

test "a parent's own colour wins over the child's derived one, and a loop of parents ends" {
    var lib = Library.init(std.testing.allocator);
    defer lib.deinit();
    lib.add("p", "[meta]\ninherits = \"c\"\n[colors.core]\nbackground = \"#101010\"\n[colors.list.item.selection]\nbackground = \"#123456\"\n");
    lib.add("c", "[meta]\ninherits = \"p\"\n[colors.core]\nbackground = \"#202020\"\n");
    lib.resolveAll();
    try std.testing.expect(lib.find("c").?.color(.selection_bg).eql(Rgba.parse("#123456").?));
    try std.testing.expect(lib.find("c").?.color(.background).eql(Rgba.parse("#202020").?));
}

test "text on the accent is readable even when the theme's own choice is not" {
    var lib = Library.init(std.testing.allocator);
    defer lib.deinit();
    lib.add("t", "[colors.core]\nbackground = \"#1e1e2e\"\nforeground = \"#cdd6f4\"\naccent = \"#3584e4\"\naccent_foreground = \"#3584e4\"\n");
    lib.resolveAll();
    const t = lib.find("t").?;
    try std.testing.expect(Rgba.contrast(t.color(.accent_fg), t.color(.accent)) >= 3);
}

test "dark or light comes from the background, not the declared variant" {
    var lib = Library.init(std.testing.allocator);
    defer lib.deinit();
    lib.add("summer", "[meta]\nvariant = \"dark\"\n[colors.core]\nbackground = \"#f5f0e1\"\nforeground = \"#2d3a33\"\n");
    lib.resolveAll();
    try std.testing.expect(!lib.find("summer").?.dark);
}

test "a file that can't be read is kept as a problem with its line, and a user theme replaces a built-in" {
    var lib = Library.init(std.testing.allocator);
    defer lib.deinit();
    lib.add("nord", "[meta]\nname = \"Nord\"\n");
    lib.add("nord", "[meta]\nname = \"My Nord\"\n");
    lib.add("broken", "[meta]\nname = \"x\"\ncolors = [1]\n");
    try std.testing.expectEqual(@as(usize, 1), lib.themes.items.len);
    try std.testing.expectEqualStrings("My Nord", lib.find("nord").?.name);
    try std.testing.expectEqual(@as(usize, 1), lib.problems.items.len);
    try std.testing.expectEqual(@as(u32, 3), lib.problems.items[0].line);
}

test "a colour zmon can't read is counted and the token falls back" {
    var lib = Library.init(std.testing.allocator);
    defer lib.deinit();
    lib.add("t", "[colors.core]\nbackground = \"#000000\"\naccent = \"red\"\n[colors.accents]\nblue = \"#0000ff\"\n");
    lib.resolveAll();
    const t = lib.find("t").?;
    try std.testing.expectEqual(@as(u8, 1), t.unreadable);
    try std.testing.expect(t.color(.accent).eql(Rgba.parse("#0000ff").?)); // accent falls back to blue
}
