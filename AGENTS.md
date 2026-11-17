# zmon

A system monitor for Linux in Zig: every process grouped by app, live CPU, memory, disk and network, drawn natively by nanoui with no webview. It reimplements the ideas of Systo (github.com/MohammedIbrahim8887/systo): processes, performance, history, startup items, a disk analyzer and a Dynamic Island style overlay.

Systo has no license. Read it for what the product does, never copy or translate its code. nanoui's own apps (nanomon and others) are MIT but are inspiration only: learn the API from them, write our own code. Nothing is decided until it lands here as code.

## Stack

- **Zig 0.17.0 only.** The global `zig` may point at another version, so check `zig version` and use `~/.zvm/0.17.0/zig` when they differ. Other projects here still use 0.16.
- **nanoui** (github.com/justrach/nanoui) draws everything: flexbox layout, immediate-mode views, a CPU or OpenGL renderer inside GTK. It is pinned by release in `build.zig.zon`. While nanoui is 0.x a minor release may change its API, so bump it on purpose and rerun the tests.
- **Linux first.** Data comes from `/proc` and `/sys` with no helper process and no root. The only dependencies are nanoui and libc, and the bundled assets are the Lexend font, the theme files and the app icon. Ask before adding anything else, SQLite for history included.
- **`nui`** is nanoui's tool for checking an app without opening a window. It is built from a nanoui checkout with `zig build nui`. On this machine: `~/JDrive/Projects/rando/nanoui-src/nanoui/zig-out/bin/nui`.

## Layout

```
core/     module zmon-core: plain data and helpers. No OS calls, no nanoui.
  types.zig (processes, memory, a process's details)  devices.zig (disks, filesystems, interfaces, sensors, battery, pressure)
  ring.zig (an hour of history)  fmt.zig  text.zig  search.zig  focus.zig (the focus stack)  toml.zig (a TOML subset)
  settings.zig (the settings and their file)
  theme/      colours, the theme model and resolver, builtin.zig  themes/ (one .toml per theme)
system/   module zmon-system: reads the machine. Imports zmon-core, never nanoui.
  platform/   quiet file reads, the clock, the environment   linux/  dummy/
  sampler/    the sampler, rates and history; worker.zig (its thread) and the snapshots the app reads
              linux/{process,details,devices,cpu,memory,disk,network,load,machine,units}.zig  dummy/
  apps/       launcher index, icons, grouping (apps by what they run or the windows they own, then systemd unit, then process tree)   linux/{index,loader,paths,desktop_entry,icons}.zig  dummy/
  config/     the settings file and the user's theme folder (XDG)   linux/  dummy/
  users/      account names by uid, from /etc/passwd   linux/  dummy/
  window/     which process owns which window, from the compositor   linux/{niri,sway,hyprland,ipc}.zig  dummy/
  desktop/    the program's name for the shell, which matches it to zmon.desktop   linux/  dummy/
src/      the executable. The only place nanoui is imported.
  main.zig    the window and its wiring
  app/        state.zig (lists, selection, sorting, held order, ending tasks, settings and themes)  sidebar.zig (pages and device tiles)  view.zig (page switch)
              details.zig (the details pane)  keys.zig (shortcuts)  focus.zig (stepping in, Escape back)  shortcuts.zig (their overlay)  confirm.zig (End task dialog)
  ui/         theme.zig (palette to colours)  controls.zig (press, button, switch, segmented)  dialog.zig (a dialog that keeps the keyboard)
              table.zig (sortable rows, columns that give way)  app_icon.zig (an app's icon in a list)  fonts.zig  icon.zig  charts.zig  tile.zig
              motion.zig (named transitions, eased values, panels that slide open and shut)
              assets/fonts/  assets/app/ (icon PNGs and SVG, zmon.desktop)
  pages/      one folder per page: apps/ processes/ devices/ settings/  (root.zig is the page)
  tests.zig   the views, rendered offscreen, most against a fixed sample (`Fixture`)
```

- **A feature is a folder with a `root.zig`.** `root.zig` is its public API and its test aggregator. The data side lives in `system/<feature>/`, the page in `src/pages/<feature>/`.
- **OS code sits in `linux/` and `dummy/` folders.** `root.zig` picks one with `switch (builtin.os.tag)`. The dummy backend returns empty values with the same signatures, so everything compiles on any OS. Compositor-specific code nests one level deeper (`window/linux/niri/`).
- **Raw readers are separate from logic.** A `linux/` file reads one kind of counter and parses it; the code above it decides what the numbers mean.

## Rules

- **Layering.**
  - Imports go one way: `core`, then `system`, then `src`. The modules enforce it: `core` and `system` are built without nanoui, so importing it there fails to compile.
  - Inside `src`: `app/state.zig` knows no page, `app/view.zig` knows the pages, a page knows `app/state.zig` and `ui/`, and `ui/` knows nothing of the pages.
  - Logic goes in the layer that owns it, never in `main.zig`.
  - A new backend function must be referenced by its `root.zig` test (`std.testing.refAllDecls`), because Zig only analyses what is used and `check-cross` would otherwise never look inside it.
- **Views.**
  - A view is a function of the state, drawn again on every input. Widgets report input as they are drawn.
  - Items in a list get a stable `ui.key`, so selection and animation follow the item as the list changes.
  - The window is never opened while working: render with `nui snapshot` and look at the PNG, drive behaviour with `ui.Tester`.
- **Frame memory.**
  - Text handed to `ui.text` is drawn after the function returns, so it must outlive it. Format with `c.print`, or copy a stack buffer with `fmt.own(c.alloc(), ...)`.
  - Never keep a slice into a buffer that is read again. Copy names out of the read buffer at once.
  - nanoui draws images from the caller's memory, so icon bytes live in the `Icons` cache (`system/apps`) for the whole run.
- **Reading /proc.**
  - Go through `files.read` (`system/platform`). It reads straight from the kernel and returns plain errors, because Zig's file reader prints a stack trace when `/proc` refuses a read.
  - A process that vanishes or hides its files is skipped, never an error.
- **Sampling.**
  - One sampler, on its own thread (`system/sampler/worker.zig`): reading /proc costs 8 to 17 ms a sample on a slow-clocked core, which stalled a frame a second on the UI thread. Only the worker touches the `Sampler`; the app reads `Snapshot`s, handed over through a lock-free triple buffer, and the worker wakes the view when one is ready. Nothing polls while idle.
  - The app tells the worker what to read (`Worker.ask`): the process list only while a list is open or a quit is being watched. Tests leave `State.threaded` off and `tick` samples on the test's thread through the same hand-over (`Worker.step`).
  - Work that can block a frame, such as scanning a disk, runs on a worker thread and reports back through state.
- **Ending tasks.**
  - Only the user's own processes, and never pid 1, kernel threads or zmon itself. Quit with SIGTERM first and kill only on request.
  - Ask before adding anything that signals other users' processes or needs privilege.
  - The one privileged path (the owner's decision): "Show with administrator rights" on a port search runs `zmon --port-holders PORT` through pkexec, only when pressed. That mode reads which processes hold the port, prints their pids and exits (`main.zig`, `app/root_lookup.zig`). Nothing else may run as root, and it never signals anything.
- **Look.**
  - One typeface: Lexend, bundled in `src/ui/assets/fonts` and named by the theme, so every widget uses it, numbers included. Never set another font or `.mono`. The window must carry the themed font too (`main.zig`), because nanoui takes its font from the window's theme, not from the context's, and a render is only proof when compared against glyphs drawn from the font file. Glyphs it lacks fall back to the system's fonts.
  - Anything that moves goes through `ui/motion.zig`: a named transition (`motion.panel`, `motion.quick`), `motion.value` for a number that eases, `motion.reveal` for a panel that opens and closes. Its keys name the thing that moves, unique in the window. Reduce motion makes every value jump, so a test that checks where something ends up settles first (`t.settle`).
  - Every colour comes from the active theme, through `theme.Colors` (`src/ui/theme.zig`). No raw hex colours in a page or widget. Graphite Dark and Graphite Light are zmon's own themes and the defaults; keep them monochrome, where emphasis is weight and contrast, not hue.
  - A theme is a vicinae-format `.toml` in `core/theme/themes/`, listed in `builtin.zig`. It names few colours and the rest are derived when it loads (`core/theme/theme.zig`), so a page asks for a role (panel, muted, selection), never a theme's own key. A new built-in must pass the contrast tests in `builtin.zig` and gets a line in `THEMES.md`.
  - Use zmon's own controls (`ui/controls.zig`, `ui/dialog.zig`), not nanoui's toggle, segmented control, `kit.button` or `kit.dialog`, which take fixed colours from nanoui's theme and can't take the keyboard's focus.
- **Keyboard and accessibility.**
  - Everything the mouse can do, the keyboard can. A new control goes through `controls.press`, so Tab reaches it, Space or Return presses it, and a screen reader is told its role, name and state. A list row gets `table.describeRow`.
  - Shortcuts are handled in `app/keys.zig` and written once, in `ui/shortcut.zig`: the overlay (`app/shortcuts.zig`) and every control's tooltip read them from there, and README's table follows. A control a shortcut acts on shows it on hover: pass `.shortcut` to `controls.button`, or wrap the box with `shortcut.tooltip`. Follow GNOME's conventions first (Ctrl+F, Ctrl+Q, Ctrl+?), and never take a key a focused text field needs (arrows left and right, Home, End, Delete).
  - Focus is drawn only after a key (`State.keyboard`), never after a click.
  - An open dialog keeps the keyboard: Tab moves only between its controls, the focus starts on its main button, a screen reader is told only of it, and closing it returns the focus where it was. A new dialog goes through `ui/dialog.zig` and `State.dialogOpen`.
  - Focus moves in and out through one stack (`core/focus.zig`, `app/focus.zig`). Any key that steps into something (a page from the sidebar, the search) remembers where the focus was, with `focus.stepIn` or `focus.remember`; Escape only ever calls `focus.back`. Never set `c.focus` for a step in without them, or Escape stops retracing the way in. A click clears the stack.
  - Text size, more contrast and reduced motion are settings, because nanoui's Linux backend doesn't read the desktop's. Layouts must survive Larger text (1.3x): truncate with an ellipsis rather than clip.
  - Words on screen are the ones a person uses ("Processes", "End task"), never internal terms, ids or counters that mean nothing to them.
- **Settings.**
  - Kept in `$XDG_CONFIG_HOME/zmon/settings.toml`, written whole on every change (a new file renamed over the old). User themes come from `$XDG_DATA_HOME/zmon/themes/`, read again when Settings opens.
  - Tests pass no config location to `State.init`, so they never read or write the real files.
  - A test that walks a list or checks an order feeds `State.useSample` a fixed sample (`Fixture` in `src/tests.zig`): the live machine re-sorts between key presses.
- **Privacy.** Never log or persist process command lines or environments. A command line may be shown on screen, in the details pane only (the owner's decision), and is read for the selected process alone.

## Zig 0.17 idioms

- `std.ArrayList(T)` and the hash maps are unmanaged. Initialise with `.empty` and pass the allocator on every call.
- `main` takes `nanoui.Init`, which carries the allocator and the `std.Io`. Pass them down; never reach for globals.
- Every list or duped string in a fallible builder gets its own `errdefer` before the next fallible call.
- Fill arrays with `@splat`, and compute lengths once for `@memcpy`.

## Code style

- Format with `zig fmt`. A file that is a struct is TitleCase; every other file is snake_case.
- No comments that restate the code. Write a doc comment only when the code can't say it itself.
- Name tests for the behaviour they check ("clicking a column header sorts, and again reverses"), not for the function.
- Parse functions take a slice and return values, so they test against fixture text. Anything that reads the live machine asserts only what must always hold.

## Verification

Run both before reporting a change as done. Both must pass with 0 failures and 0 leaks:

```bash
zig build check   # zig fmt --check + full build + check-cross
zig build test    # test-core, test-system and test-ui together
```

`zig build test-system` runs the machine readers without compiling nanoui, which is the quick loop for data changes. `zig build check-cross` builds the data layers for macOS without running them, so the dummy backends stay compiling.

A visible change is also rendered and looked at:

```bash
nui snapshot --out /tmp/zmon.png --script "click:CPU;live:8"
```

`click:TEXT` clicks the first match, and the sidebar is drawn first, so `click:CPU` opens the CPU tile, not the column header. Script steps are `click:TEXT`, `type:TEXT`, `key:enter`, `wait:SECONDS` and `live:SECONDS` (the real event loop), separated by `;`. The app reads its settings when it starts, so render with `XDG_CONFIG_HOME` and `XDG_DATA_HOME` pointing at a scratch folder, never the real one; a `settings.toml` there picks the theme to render (`[appearance]` with `mode`, `dark_theme`, `light_theme`). A change in behaviour comes with a test in the module that owns it.

## Docs

- `README.md`, `AGENTS.md` and `CLAUDE.md` are tracked, and `CLAUDE.md` is a symlink to this file. Other documents go in `docs/`.
- Write plain prose and tables. No em-dashes and no emojis.
- Put decisions to the user as choices, not as open lists inside documents.

## Commits

- Commit only when asked and push only when asked. Keep each commit atomic.
- Use present tense with a semantic prefix (`feat:`, `fix:`, `refactor:`, `docs:`, `build:`, `chore:`). The body is 2 or 3 sentences at most.
- No `Co-authored-by:` or attribution footers.
- Before committing run `zig build check` and `zig build test`.

## Reports

Say what changed, what was verified and how, and what was left out and why. Lead with anything that couldn't be verified. Give numbers only when they change what the reader does next.
