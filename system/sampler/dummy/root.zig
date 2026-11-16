//! For systems without /proc: every counter reads as zero, so the sampler and
//! the UI compile and run unchanged.
const std = @import("std");
const core = @import("zmon-core");

pub fn clockTicks() u64 {
    return 100;
}

pub fn pageSize() u64 {
    return 4096;
}

pub const process = struct {
    pub const Signal = enum { quit, kill };
    pub fn currentUid() u32 {
        return 0;
    }
    pub fn selfPid() i32 {
        return 0;
    }
    pub fn signal(io: std.Io, pid: i32, start: u64, sig: Signal) bool {
        _ = .{ io, pid, start, sig };
        return false;
    }
    pub const ScanOptions = struct { kernel_threads: bool = true };
    pub const Reader = struct {
        pub fn init(gpa: std.mem.Allocator) Reader {
            _ = gpa;
            return .{};
        }
        pub fn deinit(r: *Reader) void {
            _ = r;
        }
        pub fn scan(r: *Reader, io: std.Io, a: std.mem.Allocator, out: *std.ArrayList(core.Proc), opts: ScanOptions) u32 {
            _ = .{ r, io, a, out, opts };
            return 0;
        }
        pub fn count(r: *Reader, io: std.Io) u32 {
            _ = .{ r, io };
            return 0;
        }
    };
};

pub const cpu = struct {
    pub const Times = struct { busy: u64 = 0, total: u64 = 0 };
    pub fn read(io: std.Io, out: []Times) usize {
        _ = .{ io, out };
        return 0;
    }
};

pub const memory = struct {
    pub fn read(io: std.Io) core.Memory {
        _ = io;
        return .{};
    }
};

pub const disk = struct {
    pub fn read(io: std.Io) [2]u64 {
        _ = io;
        return .{ 0, 0 };
    }
};

pub const network = struct {
    pub const Interfaces = struct {};
    pub fn read(io: std.Io, interfaces: *Interfaces) [2]u64 {
        _ = .{ io, interfaces };
        return .{ 0, 0 };
    }
};

pub const machine = struct {
    pub fn name(io: std.Io, out: []u8) []const u8 {
        _ = .{ io, out };
        return "";
    }
};

pub const load = struct {
    pub const Load = struct { avg: [3]f32 = .{ 0, 0, 0 }, uptime: f64 = 0, threads: u32 = 0 };
    pub fn read(io: std.Io) Load {
        _ = io;
        return .{};
    }
};
