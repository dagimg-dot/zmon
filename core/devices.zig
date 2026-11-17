//! What the device pages show beyond the totals: each disk, filesystem and
//! network interface, the sensors, the battery and how often tasks wait.
//! Plain fixed-size data, so a sample is copied between threads whole.
const std = @import("std");

/// A short name kept inline (a disk, an interface, a sensor).
pub fn Text(comptime n: usize) type {
    return struct {
        buf: [n]u8 = undefined,
        len: u8 = 0,

        const Self = @This();

        pub fn init(s: []const u8) Self {
            var t: Self = .{};
            const m: u8 = @intCast(@min(s.len, n));
            @memcpy(t.buf[0..m], s[0..m]);
            t.len = m;
            return t;
        }

        pub fn slice(t: *const Self) []const u8 {
            return t.buf[0..t.len];
        }
    };
}

pub const Disk = struct {
    name: Text(32) = .{},
    read_bps: f32 = 0,
    write_bps: f32 = 0,
    /// Percent of the time it was busy with requests.
    busy: f32 = 0,
};

pub const Filesystem = struct {
    mount: Text(64) = .{},
    kind: Text(16) = .{},
    total: u64 = 0,
    free: u64 = 0,

    pub fn used(f: Filesystem) u64 {
        return f.total -| f.free;
    }
};

pub const Interface = struct {
    name: Text(16) = .{},
    rx_bps: f32 = 0,
    tx_bps: f32 = 0,
    /// Link speed in megabits a second; 0 when the link doesn't say (wireless).
    speed: u32 = 0,
    /// Its first IPv4 address, or IPv6 when it has no IPv4.
    address: Text(48) = .{},
};

pub const Sensor = struct {
    label: Text(48) = .{},
    celsius: f32 = 0,
};

pub const Battery = struct {
    present: bool = false,
    percent: f32 = 0,
    charging: bool = false,
    full: bool = false,
    /// Watts flowing in or out; 0 when the battery doesn't say.
    watts: f32 = 0,
    /// Seconds until empty (discharging) or full (charging); 0 when unknown.
    seconds_left: f64 = 0,
};

/// Pressure stall: the share of the last ten seconds in which some tasks
/// waited for a resource ("full": all of them did).
pub const Pressure = struct {
    cpu: f32 = 0,
    memory: f32 = 0,
    memory_full: f32 = 0,
    io: f32 = 0,
    io_full: f32 = 0,
    known: bool = false,
};

pub const max_disks = 16;
pub const max_filesystems = 16;
pub const max_interfaces = 16;
pub const max_sensors = 32;
pub const max_cores = 256;

pub const Devices = struct {
    disks: [max_disks]Disk = undefined,
    disk_count: u8 = 0,
    filesystems: [max_filesystems]Filesystem = undefined,
    filesystem_count: u8 = 0,
    interfaces: [max_interfaces]Interface = undefined,
    interface_count: u8 = 0,
    sensors: [max_sensors]Sensor = undefined,
    sensor_count: u8 = 0,
    /// Each core's clock in MHz (0: unknown).
    core_mhz: [max_cores]u32 = @splat(0),
    core_count: u16 = 0,
    battery: Battery = .{},
    pressure: Pressure = .{},

    pub fn diskList(d: *const Devices) []const Disk {
        return d.disks[0..d.disk_count];
    }
    pub fn filesystemList(d: *const Devices) []const Filesystem {
        return d.filesystems[0..d.filesystem_count];
    }
    pub fn interfaceList(d: *const Devices) []const Interface {
        return d.interfaces[0..d.interface_count];
    }
    pub fn sensorList(d: *const Devices) []const Sensor {
        return d.sensors[0..d.sensor_count];
    }
    pub fn coreMhz(d: *const Devices) []const u32 {
        return d.core_mhz[0..d.core_count];
    }
};

/// Which of the costlier readings a sample takes: the page shown decides.
pub const DeviceWant = struct {
    cpu: bool = false,
    disks: bool = false,
    network: bool = false,
    /// The battery each sample, not only every few seconds.
    battery: bool = false,
};

test "inline text keeps what fits" {
    const t = Text(4).init("nvme0n1");
    try std.testing.expectEqualStrings("nvme", t.slice());
    try std.testing.expectEqualStrings("", (Text(4){}).slice());
}
