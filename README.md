# zmon

A system monitor for Linux, written in Zig and drawn natively by [nanoui](https://github.com/justrach/nanoui). One small binary, no webview, no root, no helper process: everything comes from `/proc`.

## What it does today

- **Processes:** apps with their launcher icons and the helpers they started, background services and kernel threads, with CPU, memory, disk and threads. Sort by any column, open a group to see its processes, end a task with a confirmation.
- **Devices:** a sidebar tile for the CPU, memory, disk and network with its live value and the last minute as a chart, opening a page with the history drawn large, the per-core load, load averages and uptime.
- **Themes:** 34 to choose from, Graphite Dark and Light by default and 32 ported from vicinae (Catppuccin, Nord, Gruvbox, Rosé Pine, Tokyo Night and more), one for dark and one for light, following the desktop or fixed. Your own go in `~/.local/share/zmon/themes/`; see `THEMES.md`.
- **Settings:** appearance and the theme gallery, coloured or plain graphs, one or five minutes of history, the system's own tasks shown or hidden, and whether End task asks first. Saved in `~/.config/zmon/settings.toml`.

History, startup items, a disk analyzer and a floating overlay are planned.

## Build and run

You need Zig 0.17.0 and GTK 3 or 4 at run time.

```bash
zig build run
zig build test
```

`AGENTS.md` has the project's rules, including how to check the look without opening a window.

## Credits

Inspired by [Systo](https://github.com/MohammedIbrahim8887/systo). Drawn with [nanoui](https://github.com/justrach/nanoui) (MIT), in [Lexend](https://github.com/googlefonts/lexend) (SIL Open Font License, in `src/ui/assets/fonts`). The launcher entry parser comes from gize. The ported themes come from [vicinae](https://github.com/vicinaehq/vicinae) (GPL-3.0), with palettes by their authors; `THEMES.md` lists them.
