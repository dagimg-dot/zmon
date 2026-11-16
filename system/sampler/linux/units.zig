//! The kernel's units: clock ticks a second and bytes a page.

extern "c" fn sysconf(name: c_int) c_long;

pub fn clockTicks() u64 {
    return @intCast(@max(1, sysconf(2))); // _SC_CLK_TCK
}

pub fn pageSize() u64 {
    return @intCast(@max(1, sysconf(30))); // _SC_PAGESIZE
}
