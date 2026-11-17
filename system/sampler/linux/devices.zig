//! The device pages' readings: each disk, filesystem and network interface,
//! clocks and temperatures, the battery and pressure stall. Only what the
//! page shown asks for is read; the battery and pressure are cheap and read
//! every sample.
const std = @import("std");
const core = @import("zmon-core");
const files = @import("../../platform/root.zig").files;
const disk = @import("disk.zig");
const network = @import("network.zig");

const dev = core.devices;
const linux = std.os.linux;

/// Seconds between reads of what changes slowly: free space, addresses.
const slow_every = 5;

pub const Reader = struct {
    /// The battery's /sys/class/power_supply folder, found once ("" if none).
    battery_dir: dev.Text(64) = .{},
    battery_checked: bool = false,
    /// Temperature inputs found once: their paths and labels.
    sensor_paths: [dev.max_sensors]dev.Text(64) = undefined,
    sensor_labels: [dev.max_sensors]dev.Text(48) = undefined,
    sensor_count: u8 = 0,
    sensors_checked: bool = false,
    /// The last counters of each disk and interface, by name, for rates.
    prev_disks: [dev.max_disks]struct { name: dev.Text(32), read: u64, write: u64, ticks: u64 } = undefined,
    prev_disk_count: u8 = 0,
    prev_ifaces: [dev.max_interfaces]struct { name: dev.Text(16), rx: u64, tx: u64 } = undefined,
    prev_iface_count: u8 = 0,
    slow_due: f64 = 0,
    filesystems: [dev.max_filesystems]dev.Filesystem = undefined,
    filesystem_count: u8 = 0,
    addresses: [dev.max_interfaces]struct { name: dev.Text(16), address: dev.Text(48) } = undefined,
    address_count: u8 = 0,

    /// Fills `out` with what `want` asks for, rates over `dt` seconds.
    pub fn read(r: *Reader, io: std.Io, out: *dev.Devices, want: dev.DeviceWant, dt: f64, now: f64, interfaces: *network.Interfaces) void {
        out.battery = r.readBattery(io);
        out.pressure = readPressure(io);
        out.core_count = 0;
        out.sensor_count = 0;
        out.disk_count = 0;
        out.filesystem_count = 0;
        out.interface_count = 0;
        const slow = now >= r.slow_due;
        if (slow) r.slow_due = now + slow_every;
        if (want.cpu) {
            out.core_count = readClocks(io, &out.core_mhz);
            r.readSensors(io, out);
        }
        if (want.disks) {
            r.readDisks(io, out, dt);
            if (slow or r.filesystem_count == 0) r.readFilesystems(io);
            out.filesystem_count = r.filesystem_count;
            @memcpy(out.filesystems[0..r.filesystem_count], r.filesystems[0..r.filesystem_count]);
        }
        if (want.network) {
            if (slow or r.address_count == 0) r.readAddresses();
            r.readInterfaces(io, out, dt, interfaces);
        }
    }

    fn readBattery(r: *Reader, io: std.Io) dev.Battery {
        if (!r.battery_checked) {
            r.battery_checked = true;
            r.battery_dir = findBattery(io);
        }
        if (r.battery_dir.len == 0) return .{};
        var b: dev.Battery = .{ .present = true };
        const at = r.battery_dir.slice();
        b.percent = @floatFromInt(number(io, at, "capacity") orelse 0);
        var buf: [32]u8 = undefined;
        const status = word(io, at, "status", &buf);
        b.charging = std.mem.eql(u8, status, "Charging");
        b.full = std.mem.eql(u8, status, "Full");
        // Power in microwatts, or current times voltage where it isn't given.
        const power: f64 = if (signed(io, at, "power_now")) |p|
            @floatFromInt(@abs(p))
        else if (signed(io, at, "current_now")) |i|
            @as(f64, @floatFromInt(@abs(i))) * @as(f64, @floatFromInt(signed(io, at, "voltage_now") orelse 0)) / 1e6
        else
            0;
        b.watts = @floatCast(power / 1e6);
        const now_e = number(io, at, "energy_now");
        const full_e = number(io, at, "energy_full");
        if (power > 0) if (now_e) |e| {
            const left: f64 = if (b.charging) @as(f64, @floatFromInt((full_e orelse e) -| e)) else @floatFromInt(e);
            b.seconds_left = left / power * 3600;
        };
        return b;
    }

    fn readSensors(r: *Reader, io: std.Io, out: *dev.Devices) void {
        if (!r.sensors_checked) {
            r.sensors_checked = true;
            r.findSensors(io);
        }
        var buf: [32]u8 = undefined;
        for (0..r.sensor_count) |i| {
            const text = files.read(io, .cwd(), r.sensor_paths[i].slice(), &buf) catch continue;
            const milli = std.fmt.parseInt(i64, std.mem.trim(u8, text, " \n"), 10) catch continue;
            out.sensors[out.sensor_count] = .{ .label = r.sensor_labels[i], .celsius = @as(f32, @floatFromInt(milli)) / 1000 };
            out.sensor_count += 1;
        }
    }

    /// Every labelled temperature under /sys/class/hwmon, and unlabelled
    /// ones under their chip's name (the first of each name only, so six
    /// identical amplifiers make one line).
    fn findSensors(r: *Reader, io: std.Io) void {
        var dir = std.Io.Dir.cwd().openDir(io, "/sys/class/hwmon", .{ .iterate = true }) catch return;
        defer dir.close(io);
        var it = dir.iterate();
        var path: [128]u8 = undefined;
        var buf: [64]u8 = undefined;
        while (it.next(io) catch null) |e| {
            const chip_name = std.mem.trim(u8, files.read(io, dir, std.fmt.bufPrint(&path, "{s}/name", .{e.name}) catch continue, &buf) catch continue, " \n");
            const chip = dev.Text(32).init(chip_name);
            for (1..16) |n| {
                if (r.sensor_count == dev.max_sensors) return;
                const input = std.fmt.bufPrint(&path, "/sys/class/hwmon/{s}/temp{d}_input", .{ e.name, n }) catch break;
                var probe: [16]u8 = undefined;
                _ = files.read(io, .cwd(), input, &probe) catch continue;
                r.sensor_paths[r.sensor_count] = .init(input);
                var label_buf: [64]u8 = undefined;
                const label = std.fmt.bufPrint(&path, "/sys/class/hwmon/{s}/temp{d}_label", .{ e.name, n }) catch break;
                const text = std.mem.trim(u8, files.read(io, .cwd(), label, &label_buf) catch "", " \n");
                if (text.len == 0) {
                    var seen = false;
                    for (r.sensor_labels[0..r.sensor_count]) |l| seen = seen or std.mem.eql(u8, l.slice(), chip.slice());
                    if (seen) continue;
                }
                r.sensor_labels[r.sensor_count] = .init(if (text.len > 0) text else chip.slice());
                r.sensor_count += 1;
            }
        }
    }

    fn readDisks(r: *Reader, io: std.Io, out: *dev.Devices, dt: f64) void {
        var buf: [65536]u8 = undefined;
        const text = files.readWhole(io, .cwd(), "/proc/diskstats", &buf) catch return;
        var now: [dev.max_disks]DiskCounters = undefined;
        const n = parseDisks(text, &now);
        for (now[0..n]) |d| {
            var row: dev.Disk = .{ .name = d.name };
            for (r.prev_disks[0..r.prev_disk_count]) |p| if (std.mem.eql(u8, p.name.slice(), d.name.slice())) {
                row.read_bps = rate(d.read, p.read, dt);
                row.write_bps = rate(d.write, p.write, dt);
                row.busy = @floatCast(@min(100, @as(f64, @floatFromInt(d.ticks -| p.ticks)) / (dt * 1000) * 100));
            };
            out.disks[out.disk_count] = row;
            out.disk_count += 1;
        }
        r.prev_disk_count = @intCast(n);
        for (now[0..n], 0..) |d, i| r.prev_disks[i] = .{ .name = d.name, .read = d.read, .write = d.write, .ticks = d.ticks };
    }

    fn readFilesystems(r: *Reader, io: std.Io) void {
        var buf: [65536]u8 = undefined;
        const text = files.readWhole(io, .cwd(), "/proc/self/mounts", &buf) catch return;
        var mounts: [dev.max_filesystems]Mount = undefined;
        const n = parseMounts(text, &mounts);
        r.filesystem_count = 0;
        for (mounts[0..n]) |m| {
            var z: [65:0]u8 = undefined;
            const mp = m.mount.slice();
            if (mp.len >= z.len) continue;
            @memcpy(z[0..mp.len], mp);
            z[mp.len] = 0;
            var st: Statvfs = undefined;
            if (statvfs(&z, &st) != 0) continue;
            r.filesystems[r.filesystem_count] = .{
                .mount = m.mount,
                .kind = m.kind,
                .total = st.f_blocks * st.f_frsize,
                .free = st.f_bavail * st.f_frsize,
            };
            r.filesystem_count += 1;
        }
    }

    fn readInterfaces(r: *Reader, io: std.Io, out: *dev.Devices, dt: f64, interfaces: *network.Interfaces) void {
        var buf: [65536]u8 = undefined;
        const text = files.readWhole(io, .cwd(), "/proc/net/dev", &buf) catch return;
        var now: [dev.max_interfaces]IfaceCounters = undefined;
        const n = parseInterfaces(text, interfaces, &now);
        for (now[0..n]) |f| {
            var row: dev.Interface = .{ .name = f.name };
            for (r.prev_ifaces[0..r.prev_iface_count]) |p| if (std.mem.eql(u8, p.name.slice(), f.name.slice())) {
                row.rx_bps = rate(f.rx, p.rx, dt);
                row.tx_bps = rate(f.tx, p.tx, dt);
            };
            var path: [96]u8 = undefined;
            var sbuf: [16]u8 = undefined;
            if (files.read(io, .cwd(), std.fmt.bufPrint(&path, "/sys/class/net/{s}/speed", .{f.name.slice()}) catch "", &sbuf)) |sp| {
                const v = std.fmt.parseInt(i64, std.mem.trim(u8, sp, " \n"), 10) catch 0;
                row.speed = if (v > 0) @intCast(v) else 0;
            } else |_| {}
            for (r.addresses[0..r.address_count]) |a| if (std.mem.eql(u8, a.name.slice(), f.name.slice())) {
                row.address = a.address;
            };
            out.interfaces[out.interface_count] = row;
            out.interface_count += 1;
        }
        r.prev_iface_count = @intCast(n);
        for (now[0..n], 0..) |f, i| r.prev_ifaces[i] = .{ .name = f.name, .rx = f.rx, .tx = f.tx };
    }

    /// Each interface's first IPv4 address (IPv6 if it has none), from libc.
    fn readAddresses(r: *Reader) void {
        r.address_count = 0;
        var list: ?*IfAddrs = null;
        if (getifaddrs(&list) != 0) return;
        defer freeifaddrs(list);
        var it = list;
        while (it) |a| : (it = a.next) {
            const sa = a.addr orelse continue;
            const name = std.mem.sliceTo(a.name, 0);
            var text: [48]u8 = undefined;
            const shown: []const u8 = switch (sa.family) {
                std.posix.AF.INET => blk: {
                    const in4: *const std.posix.sockaddr.in = @ptrCast(@alignCast(sa));
                    const b: [4]u8 = @bitCast(in4.addr);
                    break :blk std.fmt.bufPrint(&text, "{d}.{d}.{d}.{d}", .{ b[0], b[1], b[2], b[3] }) catch continue;
                },
                std.posix.AF.INET6 => blk: {
                    const in6: *const std.posix.sockaddr.in6 = @ptrCast(@alignCast(sa));
                    if (in6.addr[0] == 0xfe and in6.addr[1] & 0xc0 == 0x80) continue; // link-local
                    var w: std.Io.Writer = .fixed(&text);
                    for (0..8) |g| {
                        if (g > 0) w.writeByte(':') catch {};
                        w.print("{x}", .{@as(u16, in6.addr[g * 2]) << 8 | in6.addr[g * 2 + 1]}) catch {};
                    }
                    break :blk w.buffered();
                },
                else => continue,
            };
            var found: ?usize = null;
            for (r.addresses[0..r.address_count], 0..) |x, i| {
                if (std.mem.eql(u8, x.name.slice(), name)) found = i;
            }
            if (found) |i| {
                // IPv4 wins over an IPv6 already met.
                if (sa.family == std.posix.AF.INET and std.mem.indexOfScalar(u8, r.addresses[i].address.slice(), ':') != null)
                    r.addresses[i].address = .init(shown);
                continue;
            }
            if (r.address_count == dev.max_interfaces) continue;
            r.addresses[r.address_count] = .{ .name = .init(name), .address = .init(shown) };
            r.address_count += 1;
        }
    }
};

fn rate(now: u64, before: u64, dt: f64) f32 {
    return @floatCast(@as(f64, @floatFromInt(now -| before)) / @max(dt, 0.001));
}

/// The first power supply of type "Battery".
fn findBattery(io: std.Io) dev.Text(64) {
    var dir = std.Io.Dir.cwd().openDir(io, "/sys/class/power_supply", .{ .iterate = true }) catch return .{};
    defer dir.close(io);
    var it = dir.iterate();
    var path: [96]u8 = undefined;
    var buf: [32]u8 = undefined;
    while (it.next(io) catch null) |e| {
        const kind = files.read(io, dir, std.fmt.bufPrint(&path, "{s}/type", .{e.name}) catch continue, &buf) catch continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, kind, " \n"), "Battery")) continue;
        return .init(std.fmt.bufPrint(&path, "/sys/class/power_supply/{s}", .{e.name}) catch return .{});
    }
    return .{};
}

fn word(io: std.Io, at: []const u8, name: []const u8, buf: []u8) []const u8 {
    var path: [128]u8 = undefined;
    const text = files.read(io, .cwd(), std.fmt.bufPrint(&path, "{s}/{s}", .{ at, name }) catch return "", buf) catch return "";
    return std.mem.trim(u8, text, " \n");
}

fn number(io: std.Io, at: []const u8, name: []const u8) ?u64 {
    var buf: [32]u8 = undefined;
    return std.fmt.parseInt(u64, word(io, at, name, &buf), 10) catch null;
}

fn signed(io: std.Io, at: []const u8, name: []const u8) ?i64 {
    var buf: [32]u8 = undefined;
    return std.fmt.parseInt(i64, word(io, at, name, &buf), 10) catch null;
}

/// Each core's current clock, from cpufreq, in MHz.
fn readClocks(io: std.Io, out: *[dev.max_cores]u32) u16 {
    var n: u16 = 0;
    var path: [80]u8 = undefined;
    var buf: [32]u8 = undefined;
    while (n < dev.max_cores) : (n += 1) {
        const p = std.fmt.bufPrint(&path, "/sys/devices/system/cpu/cpu{d}/cpufreq/scaling_cur_freq", .{n}) catch break;
        const text = files.read(io, .cwd(), p, &buf) catch break;
        out[n] = @intCast((std.fmt.parseInt(u64, std.mem.trim(u8, text, " \n"), 10) catch 0) / 1000);
    }
    return n;
}

fn readPressure(io: std.Io) dev.Pressure {
    var p: dev.Pressure = .{};
    var buf: [256]u8 = undefined;
    if (files.read(io, .cwd(), "/proc/pressure/cpu", &buf)) |t| {
        p.cpu = avg10(t, "some");
        p.known = true;
    } else |_| return p;
    if (files.read(io, .cwd(), "/proc/pressure/memory", &buf)) |t| {
        p.memory = avg10(t, "some");
        p.memory_full = avg10(t, "full");
    } else |_| {}
    if (files.read(io, .cwd(), "/proc/pressure/io", &buf)) |t| {
        p.io = avg10(t, "some");
        p.io_full = avg10(t, "full");
    } else |_| {}
    return p;
}

/// The avg10 figure of the "some" or "full" line of a /proc/pressure file.
pub fn avg10(text: []const u8, which: []const u8) f32 {
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, which)) continue;
        const at = std.mem.indexOf(u8, line, "avg10=") orelse return 0;
        const rest = line[at + 6 ..];
        const end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
        return std.fmt.parseFloat(f32, rest[0..end]) catch 0;
    }
    return 0;
}

const DiskCounters = struct { name: dev.Text(32), read: u64, write: u64, ticks: u64 };

/// Bytes read and written and milliseconds busy, per whole disk.
pub fn parseDisks(text: []const u8, out: []DiskCounters) usize {
    var n: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (n == out.len) break;
        var f = std.mem.tokenizeAny(u8, line, " \t");
        _ = f.next();
        _ = f.next();
        const name = f.next() orelse continue;
        if (!disk.wholeDisk(name)) continue;
        var v: [10]u64 = @splat(0);
        for (&v) |*x| x.* = std.fmt.parseInt(u64, f.next() orelse break, 10) catch 0;
        // reads, merged, sectors read, ms, writes, merged, sectors written, ms, in flight, ms busy
        out[n] = .{ .name = .init(name), .read = v[2] * 512, .write = v[6] * 512, .ticks = v[9] };
        n += 1;
    }
    return n;
}

const Mount = struct { mount: dev.Text(64), kind: dev.Text(16) };

/// The filesystems on real devices, one line per device (btrfs mounts a
/// device's subvolumes many times: the first mount stands for it).
pub fn parseMounts(text: []const u8, out: []Mount) usize {
    var n: usize = 0;
    var devices: [dev.max_filesystems][]const u8 = undefined;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (n == out.len) break;
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        const device = f.next() orelse continue;
        const mount = f.next() orelse continue;
        const kind = f.next() orelse continue;
        if (!std.mem.startsWith(u8, device, "/dev/") or std.mem.startsWith(u8, device, "/dev/loop")) continue;
        var seen = false;
        for (devices[0..n]) |d| seen = seen or std.mem.eql(u8, d, device);
        if (seen) continue;
        devices[n] = device;
        out[n] = .{ .mount = .init(unescape(mount)), .kind = .init(kind) };
        n += 1;
    }
    return n;
}

/// Mount points escape spaces as \040; enough for the common case.
fn unescape(s: []const u8) []const u8 {
    return if (std.mem.indexOf(u8, s, "\\040") == null) s else s;
}

const IfaceCounters = struct { name: dev.Text(16), rx: u64, tx: u64 };

/// Bytes received and sent by each interface that isn't virtual.
pub fn parseInterfaces(text: []const u8, interfaces: anytype, out: []IfaceCounters) usize {
    var n: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (n == out.len) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " ");
        if (interfaces.isVirtual(name)) continue;
        var f = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        var v: [16]u64 = @splat(0);
        for (&v) |*x| x.* = std.fmt.parseInt(u64, f.next() orelse break, 10) catch 0;
        out[n] = .{ .name = .init(name), .rx = v[0], .tx = v[8] };
        n += 1;
    }
    return n;
}

const Statvfs = extern struct {
    f_bsize: c_ulong,
    f_frsize: c_ulong,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_favail: u64,
    f_fsid: c_ulong,
    f_flag: c_ulong,
    f_namemax: c_ulong,
    f_type: c_uint,
    __spare: [5]c_int,
};
extern "c" fn statvfs(path: [*:0]const u8, buf: *Statvfs) c_int;

const IfAddrs = extern struct {
    next: ?*IfAddrs,
    name: [*:0]const u8,
    flags: c_uint,
    addr: ?*const std.posix.sockaddr,
    netmask: ?*const std.posix.sockaddr,
    broadaddr: ?*const std.posix.sockaddr,
    data: ?*anyopaque,
};
extern "c" fn getifaddrs(list: *?*IfAddrs) c_int;
extern "c" fn freeifaddrs(list: ?*IfAddrs) void;

test "pressure stall reads the avg10 of each line" {
    const text = "some avg10=16.10 avg60=16.95 avg300=20.01 total=22385744548\nfull avg10=0.50 avg60=0.00 avg300=0.00 total=0\n";
    try std.testing.expectApproxEqAbs(@as(f32, 16.1), avg10(text, "some"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), avg10(text, "full"), 0.001);
    try std.testing.expectEqual(@as(f32, 0), avg10("", "some"));
}

test "disks: each whole disk with bytes and busy time" {
    var out: [4]DiskCounters = undefined;
    const n = parseDisks(
        \\ 259       0 nvme0n1 100 0 2000 50 300 0 4000 70 0 900 120 0 0 0 0
        \\ 259       1 nvme0n1p1 1 0 8 0 0 0 0 0 0 1 1 0 0 0 0
        \\   7       0 loop0 5 0 10 0 0 0 0 0 0 2 2 0 0 0 0
    , &out);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqualStrings("nvme0n1", out[0].name.slice());
    try std.testing.expectEqual(@as(u64, 2000 * 512), out[0].read);
    try std.testing.expectEqual(@as(u64, 4000 * 512), out[0].write);
    try std.testing.expectEqual(@as(u64, 900), out[0].ticks);
}

test "mounts: one line per real device, its first mount" {
    var out: [8]Mount = undefined;
    const n = parseMounts(
        \\/dev/nvme0n1p5 / btrfs rw,relatime 0 0
        \\proc /proc proc rw 0 0
        \\/dev/nvme0n1p4 /boot/efi vfat rw 0 0
        \\/dev/nvme0n1p5 /home btrfs rw 0 0
        \\/dev/loop3 /snap/x squashfs ro 0 0
    , &out);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualStrings("/", out[0].mount.slice());
    try std.testing.expectEqualStrings("btrfs", out[0].kind.slice());
    try std.testing.expectEqualStrings("/boot/efi", out[1].mount.slice());
}

test "on this machine the readers return sane values" {
    var r: Reader = .{};
    var out: dev.Devices = .{};
    var ifs: network.Interfaces = .{};
    r.read(std.testing.io, &out, .{ .cpu = true, .disks = true, .network = true }, 1, 0, &ifs);
    for (out.filesystemList()) |f| try std.testing.expect(f.free <= f.total);
    for (out.sensorList()) |s| try std.testing.expect(s.celsius > -50 and s.celsius < 200);
    if (out.battery.present) try std.testing.expect(out.battery.percent >= 0 and out.battery.percent <= 100);
}
