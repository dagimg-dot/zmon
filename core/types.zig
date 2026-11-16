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
    state: u8 = '?',
    /// Scheduling priority, -20 (most favoured) to 19.
    nice: i8 = 0,
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
