//! What the machine readers produce and the UI shows, as plain data.

pub const Proc = struct {
    pid: i32,
    ppid: i32,
    uid: u32 = 0,
    /// A kernel thread: no executable, no memory of its own.
    kthread: bool = false,
    /// Display name: the kernel's 15-character name, or the executable's
    /// when that is the longer form of it.
    name: []const u8,
    /// The kernel's own name, cut at 15 characters: stable whether or not the
    /// executable can be read, so it is what names are matched against.
    comm: []const u8 = "",
    /// Path of the executable, or "" when it can't be read.
    exe: []const u8 = "",
    /// The program it runs, by file name: the executable's, or the first
    /// word of its command line when the executable can't be read. Tells
    /// apart processes whose names say nothing ("MainThread" is node).
    program: []const u8 = "",
    /// The systemd unit it runs in, the last part of its control group
    /// ("app-com.anthropic.Claude-1926.scope", "docker.service"); "" when
    /// there is none. It says which app or service a process belongs to.
    unit: []const u8 = "",
    state: u8 = '?',
    /// Scheduling priority, -20 (most favoured) to 19.
    nice: i8 = 0,
    /// Its executable was replaced on disk since it started (an update): it
    /// runs the old one until restarted.
    exe_replaced: bool = false,
    threads: u32 = 1,
    /// Memory that belongs to the process alone (resident minus shared), bytes.
    memory: u64 = 0,
    /// Percent of one core since the last sample, so it can pass 100.
    cpu: f32 = 0,
    cpu_ticks: u64 = 0,
    start: u64 = 0,
    disk_read: u64 = 0,
    disk_write: u64 = 0,
    /// Bytes a second since the last sample; only for processes whose
    /// I/O counters Linux lets us read (our own).
    disk_bps: f32 = 0,
    io_known: bool = false,
    /// The I/O counters were read in this sample, not kept from an earlier one
    /// (an idle process's are read only every few samples).
    io_fresh: bool = false,
};

/// A window the compositor shows, by the process that owns it: its app id
/// (the Wayland app id, or the X11 class) names the app a person sees.
pub const Window = struct {
    pid: i32,
    app_id: @import("devices.zig").Text(96) = .{},
};

/// What the details pane shows of one process beyond its row: read only for
/// the selected process. Text belongs to whoever read it.
pub const Details = struct {
    pid: i32,
    start: u64,
    /// The whole command line, arguments separated by spaces. Shown on screen
    /// only: never logged or saved.
    cmdline: []const u8 = "",
    /// The working folder: only the user's own processes say.
    cwd: []const u8 = "",
    /// Its control group (cgroup v2 path), which names its app or service.
    cgroup: []const u8 = "",
    read_total: u64 = 0,
    write_total: u64 = 0,
    io_known: bool = false,
    /// The unit that keeps it, from its file: its Description and path.
    unit_description: []const u8 = "",
    unit_file: []const u8 = "",
    /// The Git repository its working folder is in, and the branch.
    repo: []const u8 = "",
    branch: []const u8 = "",
    /// What it listens on and is connected to; known only for the user's
    /// own processes (`sockets_known`).
    sockets: [16]Socket = undefined,
    socket_count: u8 = 0,
    sockets_known: bool = false,
};

/// A network socket a process holds, as one line.
pub const Socket = struct {
    proto: @import("devices.zig").Text(4) = .{},
    /// "127.0.0.1:5000", or "local to remote" when connected.
    text: @import("devices.zig").Text(112) = .{},
    listening: bool = false,
};

pub const Memory = struct {
    total: u64 = 0,
    available: u64 = 0,
    cached: u64 = 0,
    shmem: u64 = 0,
    swap_total: u64 = 0,
    swap_free: u64 = 0,

    pub fn used(m: Memory) u64 {
        return m.total -| m.available;
    }
    pub fn swapUsed(m: Memory) u64 {
        return m.swap_total -| m.swap_free;
    }
};
