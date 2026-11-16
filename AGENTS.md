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
  types.zig ring.zig fmt.zig text.zig search.zig settings.zig (the settings and their file)
  theme/      colours, a TOML subset, the theme model and resolver, builtin.zig  themes/ (one .toml per theme)
system/   module zmon-system: reads the machine. Imports zmon-core, never nanoui.
  platform/   quiet file reads              linux/  dummy/
  sampler/    rates and history             linux/{process,cpu,memory,disk,network,load,units}.zig  dummy/
  apps/       launcher index, icons, grouping   linux/{index,loader,paths,desktop_entry,icons}.zig  dummy/
  config/     the settings file and the user's theme folder (XDG)   linux/  dummy/
  desktop/    the program's name for the shell, which matches it to zmon.desktop   linux/  dummy/
src/      the executable. The only place nanoui is imported.
  main.zig    the window and its wiring
  app/        state.zig (lists, selection, sorting, sampling clock, ending tasks, settings and themes)  sidebar.zig (pages and device tiles)  view.zig (page switch)
              keys.zig (shortcuts)  shortcuts.zig (their overlay)  confirm.zig (End task dialog)
  ui/         theme.zig (palette to colours) controls.zig (press, button, switch, segmented) table.zig (sortable rows) app_icon.zig (an app's icon in a list) fonts.zig icon.zig charts.zig tile.zig  assets/fonts/  assets/app/ (icon PNGs and SVG, zmon.desktop)
  pages/      one folder per page: apps/ processes/ devices/ settings/  (root.zig is the page)
  tests.zig   the views, rendered offscreen
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
  - One sampler, on the UI thread, driven by `c.frameIn` from the view. Nothing polls while idle.
  - Work that can block a frame, such as scanning a disk, runs on a worker thread and reports back through state.
- **Ending tasks.**
  - Only the user's own processes, and never pid 1, kernel threads or zmon itself. Quit with SIGTERM first and kill only on request.
  - Ask before adding anything that signals other users' processes or needs privilege.
- **Look.**
  - One typeface: Lexend, bundled in `src/ui/assets/fonts` and named by the theme, so every widget uses it, numbers included. Never set another font or `.mono`. The window must carry the themed font too (`main.zig`), because nanoui takes its font from the window's theme, not from the context's, and a render is only proof when compared against glyphs drawn from the font file. Glyphs it lacks fall back to the system's fonts.
  - Every colour comes from the active theme, through `theme.Colors` (`src/ui/theme.zig`). No raw hex colours in a page or widget. Graphite Dark and Graphite Light are zmon's own themes and the defaults; keep them monochrome, where emphasis is weight and contrast, not hue.
  - A theme is a vicinae-format `.toml` in `core/theme/themes/`, listed in `builtin.zig`. It names few colours and the rest are derived when it loads (`core/theme/theme.zig`), so a page asks for a role (panel, muted, selection), never a theme's own key. A new built-in must pass the contrast tests in `builtin.zig` and gets a line in `THEMES.md`.
  - Use zmon's own controls (`ui/controls.zig`), not nanoui's toggle, segmented control or `kit.button`, which take fixed colours from nanoui's theme and can't take the keyboard's focus.
- **Keyboard and accessibility.**
  - Everything the mouse can do, the keyboard can. A new control goes through `controls.press`, so Tab reaches it, Space or Return presses it, and a screen reader is told its role, name and state. A list row gets `table.describeRow`.
  - Shortcuts live in `app/keys.zig` and are listed once, in `app/shortcuts.zig`, which draws the overlay; README's table follows it. Follow GNOME's conventions first (Ctrl+F, Ctrl+Q, Ctrl+?), and never take a key a focused text field needs (arrows left and right, Home, End, Delete).
  - Focus is drawn only after a key (`State.keyboard`), never after a click.
  - Text size, more contrast and reduced motion are settings, because nanoui's Linux backend doesn't read the desktop's. Layouts must survive Larger text (1.3x): truncate with an ellipsis rather than clip.
  - Words on screen are the ones a person uses ("Processes", "End task"), never internal terms, ids or counters that mean nothing to them.
- **Settings.**
  - Kept in `$XDG_CONFIG_HOME/zmon/settings.toml`, written whole on every change (a new file renamed over the old). User themes come from `$XDG_DATA_HOME/zmon/themes/`, read again when Settings opens.
  - Tests pass no config location to `State.init`, so they never read or write the real files.
- **Privacy.** Never log or persist process command lines or environments.

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
