# zmon

A system monitor for Linux, written in Zig and drawn natively by [nanoui](https://github.com/justrach/nanoui). One small binary, no webview, no root, no helper process: everything comes from `/proc`.

## What it does today

- **Processes:** apps with the helpers they started, background services and kernel threads, with CPU, memory, disk and threads. Sort by any column, open a group to see its processes, end a task with a confirmation.
- **Performance:** live CPU (total and per core), memory, disk and network over the last minute, with load and uptime.

History, startup items, a disk analyzer and a floating overlay are planned.

## Build and run

You need Zig 0.17.0 and GTK 3 or 4 at run time.

```bash
zig build run
zig build test
```

`AGENTS.md` has the project's rules, including how to check the look without opening a window.

## Credits

Inspired by [Systo](https://github.com/MohammedIbrahim8887/systo). Drawn with [nanoui](https://github.com/justrach/nanoui) (MIT).
