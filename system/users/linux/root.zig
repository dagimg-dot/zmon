//! Accounts from /etc/passwd. Accounts from a directory service (LDAP, sssd)
//! aren't listed there; their processes show their uid instead.
const std = @import("std");
const files = @import("../../platform/root.zig").files;

pub const Users = struct {
    gpa: std.mem.Allocator,
    names: std.AutoHashMapUnmanaged(u32, []const u8) = .empty,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) Users {
        var u: Users = .{ .gpa = gpa };
        var buf: [256 * 1024]u8 = undefined;
        const text = files.read(io, .cwd(), "/etc/passwd", &buf) catch return u;
        u.load(text);
        return u;
    }

    pub fn deinit(u: *Users) void {
        var it = u.names.valueIterator();
        while (it.next()) |n| u.gpa.free(n.*);
        u.names.deinit(u.gpa);
    }

    /// The account name for `uid`, or null when there is none.
    pub fn name(u: *const Users, uid: u32) ?[]const u8 {
        return u.names.get(uid);
    }

    /// Reads passwd lines: "name:x:uid:gid:...". The first name for a uid wins.
    fn load(u: *Users, text: []const u8) void {
        var lines = std.mem.tokenizeScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (line.len == 0 or line[0] == '#') continue;
            var f = std.mem.splitScalar(u8, line, ':');
            const n = f.next() orelse continue;
            _ = f.next() orelse continue;
            const uid = std.fmt.parseInt(u32, f.next() orelse continue, 10) catch continue;
            if (n.len == 0 or u.names.contains(uid)) continue;
            const owned = u.gpa.dupe(u8, n) catch return;
            u.names.put(u.gpa, uid, owned) catch {
                u.gpa.free(owned);
                return;
            };
        }
    }
};

test "passwd lines give names by uid, and junk is skipped" {
    var u: Users = .{ .gpa = std.testing.allocator };
    defer u.deinit();
    u.load(
        \\root:x:0:0:root:/root:/bin/bash
        \\# a comment
        \\jd:x:1000:1000:JD:/home/jd:/bin/zsh
        \\broken line
        \\twin:x:1000:1000::/:/bin/sh
        \\nobody:x:65534:65534::/:/usr/bin/nologin
    );
    try std.testing.expectEqualStrings("root", u.name(0).?);
    try std.testing.expectEqualStrings("jd", u.name(1000).?);
    try std.testing.expectEqualStrings("nobody", u.name(65534).?);
    try std.testing.expect(u.name(4242) == null);
}

test "on this machine, root has uid 0" {
    var u = Users.init(std.testing.allocator, std.testing.io);
    defer u.deinit();
    try std.testing.expectEqualStrings("root", u.name(0) orelse return error.SkipZigTest);
}
