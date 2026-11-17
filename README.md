# zmon

A system monitor for Linux, written in Zig and drawn natively by [nanoui](https://github.com/justrach/nanoui). One small binary, no webview, no root, no helper process: everything comes from `/proc`.

## What it does today

- **Apps:** the apps you opened, with their launcher icons and the helpers they started folded in, with CPU, memory, disk and threads. Sort by any column, open an app to see its processes, end a task with a confirmation.
- **Processes:** every process on the machine, one line each with its user, PID and the icon of the app it belongs to. Search by name or PID, or type `:8080` to find who holds a port. When another user's process holds it, "Show with administrator rights" asks for your password once (pkexec) and shows which one; nothing else runs as root. Sort by any column, end or force quit one process.
- **Details** (Ctrl+I): the selected process's command line, state, priority, age and parent, and why it is running, an idea learned from [witr](https://github.com/pranshuparmar/witr): the chain of processes that started it, the systemd unit or container that keeps it, the Git repository it works in, the sockets it holds, and warnings such as running as root or running a program that has since been updated.
- **Devices:** a sidebar tile for the CPU, memory, disk, network and (where there is one) battery, with its live value and a chart of the last minute, five minutes or hour. Each opens a page:
  - CPU: each core's load and clock speed, the machine's temperatures and how often tasks waited.
  - Memory: how it is split between apps and cache, and swap with its history.
  - Disk: each disk's rates and how busy it is, and the free space on each filesystem.
  - Network: each interface's rates, address and link speed.
  - Battery: charge, power drawn and time left.
- **Themes:** 34 to choose from, Graphite Dark and Light by default and 32 ported from vicinae (Catppuccin, Nord, Gruvbox, Rosé Pine, Tokyo Night and more), one for dark and one for light, following the desktop or fixed. Your own go in `~/.local/share/zmon/themes/`; see `THEMES.md`.
- **Settings:** appearance and the theme gallery, coloured or plain graphs, an update every 0.5, 1, 2 or 5 seconds, a minute, five minutes or an hour of history, kernel threads shown or hidden, CPU as a share of the whole machine or of one core, and whether End task asks first. Saved in `~/.config/zmon/settings.toml`.

History, startup items, a disk analyzer and a floating overlay are planned.

## Keyboard

Every page, list and action has a key. Ctrl+? (or F1) shows them all in zmon.

| Keys | Does |
|---|---|
| Ctrl+F | Search apps and processes |
| Ctrl+, | Settings |
| Ctrl+? or F1 | Keyboard shortcuts |
| Ctrl+Shift+P | Pause or resume updates |
| Ctrl+B | Collapse or expand the sidebar |
| Ctrl+Q | Quit |
| Ctrl+1, Ctrl+2 | Apps, Processes |
| Ctrl+3 to Ctrl+6 | CPU, Memory, Disk, Network |
| Ctrl+Page Down, Ctrl+Page Up | Next or previous page |
| Up, Down | Select the row above or below |
| Home, End | First or last row |
| Right, Left | Show an app's processes; hide them, or go back to the app |
| Ctrl+I | Show or hide the selected process's details |
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
