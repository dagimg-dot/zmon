//! The launcher entries installed on this machine, found by the program they
//! run, their window class or their file name. Entries come from the user's
//! directory first, and the first to claim a name keeps it.
const std = @import("std");
const desktop = @import("desktop_entry.zig");

pub const Entry = struct {
    name: []const u8,
    icon: []const u8 = "",
    /// The name of the program the entry runs (the first word of Exec).
    program: []const u8 = "",
    wm_class: []const u8 = "",
    id: []const u8 = "",
    /// NoDisplay: it runs a program but isn't something a person launches.
    hidden: bool = false,
};

/// The launcher entries installed on this machine.
pub const Index = struct {
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry) = .empty,
    by_key: std.StringHashMapUnmanaged(u32) = .empty,

    pub fn init(gpa: std.mem.Allocator) Index {
        return .{ .arena = .init(gpa) };
    }

    pub fn deinit(ix: *Index) void {
        ix.arena.deinit();
    }

    /// Adds the entry in `text` (the contents of a .desktop file called `id`).
    pub fn add(ix: *Index, id: []const u8, text: []const u8) void {
        const parsed = desktop.DesktopEntry.parse(text);
        if (!parsed.is_app or parsed.name.len == 0) return;
        const aa = ix.arena.allocator();
        const e: Entry = .{
            .name = aa.dupe(u8, parsed.name) catch return,
            .icon = aa.dupe(u8, parsed.icon) catch "",
            .program = aa.dupe(u8, desktop.extractExecBinary(parsed.exec) orelse "") catch "",
            .wm_class = aa.dupe(u8, parsed.wm_class) catch "",
            .id = aa.dupe(u8, id) catch "",
            .hidden = parsed.no_display,
        };
        // A web app launcher (`brave --app-id=...`) runs the browser, which is not it:
        // it must not claim the browser's program name.
        const web_app = std.mem.indexOf(u8, parsed.exec, "--app-id=") != null or std.mem.indexOf(u8, parsed.exec, " --app=") != null;
        const at: u32 = @intCast(ix.entries.items.len);
        ix.entries.append(ix.arena.allocator(), e) catch return;
        const a = ix.arena.allocator();
        for ([_][]const u8{ if (web_app) "" else e.program, e.wm_class, e.id }) |key| {
            if (key.len == 0) continue;
            const lower = std.ascii.allocLowerString(a, key) catch continue;
            // The first entry to claim a name keeps it, unless that one is hidden
            // and this one is not: a URL handler must not stand for the app itself.
            const slot = ix.by_key.getOrPut(a, lower) catch continue;
            if (!slot.found_existing or (ix.entries.items[slot.value_ptr.*].hidden and !e.hidden)) slot.value_ptr.* = at;
        }
    }

    pub fn lookup(ix: *const Index, key: []const u8) ?*const Entry {
        var buf: [128]u8 = undefined;
        if (key.len == 0 or key.len > buf.len) return null;
        const lower = std.ascii.lowerString(&buf, key);
        const at = ix.by_key.get(lower) orelse return null;
        return &ix.entries.items[at];
    }
};

test "a launcher entry is read from its main group only" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("browser", "[Desktop Entry]\nType=Application\nName=Web Browser\nExec=/usr/lib/browser/browser-bin %u\nIcon=browser\nStartupWMClass=Browser\n\n[Desktop Action new-window]\nName=New Window\nExec=browser --new-window\n");
    const e = ix.lookup("browser-bin").?;
    try std.testing.expectEqualStrings("Web Browser", e.name);
    try std.testing.expectEqualStrings("browser", e.icon);
    try std.testing.expectEqualStrings("Browser", e.wm_class);
    try std.testing.expect(ix.lookup("browser") == e); // the launcher's file name finds it too
    try std.testing.expect(ix.lookup("BROWSER-BIN") == e);
}

test "a web app launcher does not take the browser's name" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("brave-abc-Default", "[Desktop Entry]\nType=Application\nName=Google Keep\nExec=brave --profile-directory=Default --app-id=abc\nStartupWMClass=crx_abc\n");
    ix.add("brave-browser", "[Desktop Entry]\nType=Application\nName=Brave\nExec=brave %U\n");
    try std.testing.expectEqualStrings("Brave", ix.lookup("brave").?.name);
    try std.testing.expectEqualStrings("Google Keep", ix.lookup("crx_abc").?.name);
}

test "a visible launcher beats a hidden one that runs the same program, whatever order they load in" {
    const hidden = "[Desktop Entry]\nType=Application\nName=VSCodium - URL Handler\nExec=/usr/bin/codium --open-url %U\nNoDisplay=true\n";
    const visible = "[Desktop Entry]\nType=Application\nName=VSCodium\nExec=/usr/bin/codium %F\nStartupWMClass=VSCodium\n";
    for ([_][2][]const u8{ .{ hidden, visible }, .{ visible, hidden } }) |pair| {
        var ix = Index.init(std.testing.allocator);
        defer ix.deinit();
        ix.add("one", pair[0]);
        ix.add("two", pair[1]);
        const e = ix.lookup("codium").?;
        try std.testing.expectEqualStrings("VSCodium", e.name);
        try std.testing.expect(!e.hidden);
    }
}

test "the first entry to claim a name keeps it, so the user's own wins" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("tool", "[Desktop Entry]\nType=Application\nName=Mine\nExec=tool\n");
    ix.add("tool", "[Desktop Entry]\nType=Application\nName=System\nExec=tool\n");
    try std.testing.expectEqualStrings("Mine", ix.lookup("tool").?.name);
}
