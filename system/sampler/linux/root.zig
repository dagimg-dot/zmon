//! The Linux readers: /proc and /sys, one file per kind of counter.
pub const units = @import("units.zig");
pub const process = @import("process.zig");
pub const cpu = @import("cpu.zig");
pub const memory = @import("memory.zig");
pub const disk = @import("disk.zig");
pub const network = @import("network.zig");
pub const load = @import("load.zig");
pub const machine = @import("machine.zig");
pub const details = @import("details.zig");

pub const clockTicks = units.clockTicks;
pub const pageSize = units.pageSize;

test {
    _ = units;
    _ = process;
    _ = cpu;
    _ = memory;
    _ = disk;
    _ = network;
    _ = load;
    _ = machine;
    _ = details;
}
