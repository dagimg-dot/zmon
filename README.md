# zmon

A system monitor for Linux, written in Zig and drawn natively by [nanoui](https://github.com/justrach/nanoui). One small binary, no webview, no root, no helper process: everything comes from `/proc`.

## What it does today

- **Apps:** the apps you opened, with their launcher icons and the helpers they started folded in, with CPU, memory, disk and threads. Sort by any column, open an app to see its processes, end a task with a confirmation.
- **Processes:** every process on the machine, one line each with its PID and the icon of the app it belongs to. Search by name or PID, sort by any column, end one process.
- **Devices:** a sidebar tile for the CPU, memory, disk and network with its live value and the last minute as a chart, opening a page with the history drawn large, the per-core load, load averages and uptime.
- **Themes:** 34 to choose from, Graphite Dark and Light by default and 32 ported from vicinae (Catppuccin, Nord, Gruvbox, Rosé Pine, Tokyo Night and more), one for dark and one for light, following the desktop or fixed. Your own go in `~/.local/share/zmon/themes/`; see `THEMES.md`.
- **Settings:** appearance and the theme gallery, coloured or plain graphs, one or five minutes of history, the system's own tasks shown or hidden, and whether End task asks first. Saved in `~/.config/zmon/settings.toml`.

History, startup items, a disk analyzer and a floating overlay are planned.

## Keyboard

Every page, list and action has a key. Ctrl+? (or F1) shows them all in zmon.

| Keys | Does |
|---|---|
| Ctrl+F | Search apps and processes |
| Ctrl+, | Settings |
| Ctrl+? or F1 | Keyboard shortcuts |
| Ctrl+Q | Quit |
| Ctrl+1, Ctrl+2 | Apps, Processes |
| Ctrl+3 to Ctrl+6 | CPU, Memory, Disk, Network |
| Ctrl+Page Down, Ctrl+Page Up | Next or previous page |
| Up, Down | Select the row above or below |
| Home, End | First or last row |
| Right, Left | Show an app's processes; hide them, or go back to the app |
| Delete | End task (Return confirms) |
| Shift+Delete | Force quit: stop it at once, losing unsaved work |
| Esc | Go back where you came from: out of the search (clearing it), the list, the page |
| Any letter | Start a search |
| Tab, Shift+Tab | Move between controls |
| Return | On the sidebar, open that page and move into it |
| Space or Return | Press the focused control |

## Accessibility

- Every control can be reached with Tab and pressed with Space or Return, and the focus is outlined in the theme's accent once you use the keyboard.
- Settings has Text size (Default, Large, Larger), More contrast, which strengthens quiet text and lines in any theme, and Reduce motion.
- Every built-in theme is tested for readable contrast.
- Controls and list rows carry names, roles and states for screen readers. nanoui doesn't yet pass them to Linux's accessibility bus (AT-SPI), so Orca can't read zmon until it does.

## Build and run

You need Zig 0.17.0 and GTK 3 or 4 at run time.

```bash
zig build run
zig build test
```

To put zmon in your launcher with its icon, install it under your home:

```bash
zig build install -Doptimize=ReleaseFast --prefix ~/.local
```

`AGENTS.md` has the project's rules, including how to check the look without opening a window.

## Credits

Inspired by [Systo](https://github.com/MohammedIbrahim8887/systo). Drawn with [nanoui](https://github.com/justrach/nanoui) (MIT), in [Lexend](https://github.com/googlefonts/lexend) (SIL Open Font License, in `src/ui/assets/fonts`). The launcher entry parser comes from gize. The ported themes come from [vicinae](https://github.com/vicinaehq/vicinae) (GPL-3.0), with palettes by their authors; `THEMES.md` lists them.
