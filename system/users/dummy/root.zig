//! No accounts where zmon doesn't read the machine.
const std = @import("std");

pub const Users = struct {
    pub fn init(gpa: std.mem.Allocator, io: std.Io) Users {
        _ = .{ gpa, io };
        return .{};
    }
    pub fn deinit(u: *Users) void {
        _ = u;
    }
    pub fn name(u: *const Users, uid: u32) ?[]const u8 {
        _ = .{ u, uid };
        return null;
    }
};
