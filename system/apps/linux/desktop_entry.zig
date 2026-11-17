//! A .desktop launcher entry: the few keys zmon needs (name, icon, window class,
//! the program it runs), and the program's name pulled out of an Exec= line.
const std = @import("std");

pub const DesktopEntry = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    icon: []const u8 = "",
    wm_class: []const u8 = "",
    exec: []const u8 = "",
    no_display: bool = false,
    /// `Terminal=true`: a program that runs inside a terminal, not an app
    /// with a window of its own.
    terminal: bool = false,
    is_app: bool = true,

    const Key = enum {
        Type,
        Name,
        Icon,
        StartupWMClass,
        Exec,
        NoDisplay,
        Terminal,
        Hidden,
    };

    pub fn parse(content: []const u8) DesktopEntry {
        var entry = DesktopEntry{};
        var in_desktop_entry = false;

        var line_it = std.mem.splitScalar(u8, content, '\n');
        while (line_it.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

            if (line[0] == '[') {
                if (!handleSectionHeader(line, &in_desktop_entry)) break;
                continue;
            }

            if (in_desktop_entry) {
                applyKeyValuePair(&entry, line);
            }
        }

        return entry;
    }

    fn handleSectionHeader(line: []const u8, in_desktop_entry: *bool) bool {
        if (std.mem.eql(u8, line, "[Desktop Entry]")) {
            in_desktop_entry.* = true;
            return true;
        }
        if (in_desktop_entry.*) return false;
        return true;
    }

    fn applyKeyValuePair(entry: *DesktopEntry, line: []const u8) void {
        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return;
        const key = std.mem.trim(u8, line[0..eq_idx], " \t");
        const val = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");

        const k = std.meta.stringToEnum(Key, key) orelse return;
        applyKey(entry, k, val);
    }

    fn applyKey(entry: *DesktopEntry, k: Key, val: []const u8) void {
        switch (k) {
            .Type => if (!std.mem.eql(u8, val, "Application")) {
                entry.is_app = false;
            },
            .Name => setIfEmpty(&entry.name, val),
            .Icon => setIfEmpty(&entry.icon, val),
            .StartupWMClass => setIfEmpty(&entry.wm_class, val),
            .Exec => setIfEmpty(&entry.exec, val),
            .NoDisplay, .Hidden => if (std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1")) {
                entry.no_display = true;
            },
            .Terminal => entry.terminal = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1"),
        }
    }

    fn setIfEmpty(dest: *[]const u8, val: []const u8) void {
        if (dest.len == 0) dest.* = val;
    }
};

const WRAPPER_TOKENS = [_][]const u8{ "env", "sh", "bash", "-c", "flatpak", "run" };

fn isIgnoredExecToken(token: []const u8) bool {
    if (token.len == 0) return true;
    if (token[0] == '-' or token[0] == '%') return true;
    if (std.mem.indexOfScalar(u8, token, '=') != null) return true;

    for (WRAPPER_TOKENS) |wrapper| {
        if (std.mem.eql(u8, token, wrapper)) return true;
    }
    return false;
}

fn extractQuotedBinary(trimmed: []const u8) ?[]const u8 {
    if (trimmed.len < 2) return null;
    const first = trimmed[0];
    if (first != '"' and first != '\'') return null;

    const end = std.mem.indexOfScalar(u8, trimmed[1..], first) orelse return null;
    const base = std.fs.path.basename(trimmed[1 .. 1 + end]);
    return if (base.len > 0) base else null;
}

/// Extract the binary name from an Exec= string, skipping wrappers
/// (env, sh -c, flatpak run) and field codes (%F, %U).
pub fn extractExecBinary(raw_exec: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, raw_exec, " \t\r\n");
    if (trimmed.len == 0) return null;

    if (extractQuotedBinary(trimmed)) |quoted| return quoted;

    var it = std.mem.splitScalar(u8, trimmed, ' ');
    while (it.next()) |raw_token| {
        const token = std.mem.trim(u8, raw_token, " \t\r\n\"'");
        if (isIgnoredExecToken(token)) continue;

        const base = std.fs.path.basename(token);
        if (base.len > 0) return base;
    }

    return null;
}

test "DesktopEntry parses standard desktop file correctly" {
    const fixture =
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Visual Studio Code
        \\GenericName=Text Editor
        \\Comment=Code Editing. Redefined.
        \\Exec=code %F
        \\Icon=com.visualstudio.code
        \\Terminal=false
        \\Categories=Development;IDE;
        \\StartupWMClass=Code
    ;

    const entry = DesktopEntry.parse(fixture);
    try std.testing.expect(entry.is_app);
    try std.testing.expect(!entry.no_display);
    try std.testing.expectEqualStrings("Visual Studio Code", entry.name);
    try std.testing.expectEqualStrings("com.visualstudio.code", entry.icon);
    try std.testing.expectEqualStrings("Code", entry.wm_class);
    try std.testing.expectEqualStrings("code %F", entry.exec);
}

test "DesktopEntry handles NoDisplay and non-Application types" {
    const fixture =
        \\[Desktop Entry]
        \\Type=Link
        \\Name=Some URL Link
        \\NoDisplay=true
    ;

    const entry = DesktopEntry.parse(fixture);
    try std.testing.expect(!entry.is_app);
    try std.testing.expect(entry.no_display);
}

test "extractExecBinary parses varied exec patterns" {
    const testing = std.testing;

    try testing.expectEqualStrings("code", extractExecBinary("code --unity-launch %F").?);
    try testing.expectEqualStrings("google-chrome-stable", extractExecBinary("\"/usr/bin/google-chrome-stable\" %U").?);
    try testing.expectEqualStrings("app", extractExecBinary("\"/opt/My Custom App/app\" %U").?);
    try testing.expectEqualStrings("slack", extractExecBinary("env GDK_BACKEND=wayland /usr/bin/slack %u").?);
    try testing.expectEqualStrings("org.mozilla.firefox", extractExecBinary("flatpak run org.mozilla.firefox").?);
    try testing.expectEqualStrings("launcher", extractExecBinary("sh -c /opt/bin/launcher").?);
    try testing.expect(extractExecBinary("") == null);
    try testing.expect(extractExecBinary("env -c") == null);
}
