//! For systems without freedesktop launchers: no entries and no icons, so the
//! rest of zmon compiles and runs unchanged.
const std = @import("std");

pub const Entry = struct {
    name: []const u8 = "",
    icon: []const u8 = "",
    hidden: bool = false,
};

pub const Index = struct {
    pub fn init(gpa: std.mem.Allocator) Index {
        _ = gpa;
        return .{};
    }
    pub fn deinit(ix: *Index) void {
        _ = ix;
    }
    pub fn add(ix: *Index, id: []const u8, text: []const u8) void {
        _ = .{ ix, id, text };
    }
    pub fn lookup(ix: *const Index, key: []const u8) ?*const Entry {
        _ = .{ ix, key };
        return null;
    }
};

pub fn loadEntries(ix: *Index, io: std.Io) void {
    _ = .{ ix, io };
}

pub const IconKind = enum { png, jpeg, svg };

pub const Icon = struct {
    path: []const u8,
    bytes: []const u8,
    kind: IconKind,
};

pub const Icons = struct {
    pub fn init(gpa: std.mem.Allocator, io: std.Io) Icons {
        _ = .{ gpa, io };
        return .{};
    }
    pub fn deinit(c: *Icons) void {
        _ = c;
    }
    pub fn get(c: *Icons, name: []const u8) ?Icon {
        _ = .{ c, name };
        return null;
    }
};
