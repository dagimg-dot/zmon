# zmon

A system monitor for Linux in Zig: every process grouped by app, live CPU, memory, disk and network, drawn natively by nanoui with no webview. It reimplements the ideas of Systo (github.com/MohammedIbrahim8887/systo): processes, performance, history, startup items, a disk analyzer and a Dynamic Island style overlay.

Systo has no license. Read it for what the product does, never copy or translate its code. nanoui's own apps (nanomon and others) are MIT but are inspiration only: learn the API from them, write our own code. Nothing is decided until it lands here as code.

## Stack

- **Zig 0.17.0 only.** The global `zig` may point at another version, so check `zig version` and use `~/.zvm/0.17.0/zig` when they differ. Other projects here still use 0.16.
- **nanoui** (github.com/justrach/nanoui) draws everything: flexbox layout, immediate-mode views, a CPU or OpenGL renderer inside GTK. It is pinned by release in `build.zig.zon`. While nanoui is 0.x a minor release may change its API, so bump it on purpose and rerun the tests.
- **Linux first.** Data comes from `/proc` and `/sys` with no helper process and no root. The only dependencies are nanoui and libc, and the one bundled asset is the Lexend font. Ask before adding anything else, SQLite for history included.
- **`nui`** is nanoui's tool for checking an app without opening a window. It is built from a nanoui checkout with `zig build nui`. On this machine: `~/JDrive/Projects/rando/nanoui-src/nanoui/zig-out/bin/nui`.

## Rules

- **Layering.**
  - Imports go one way: `procfs`, `sampler`, `xdg`, `desktop`, `apps` and `icons` (data, no nanoui), then `app.zig` (state and the sampling clock), then the `*_view.zig` pages, with `fmt`, `theme` and `charts` as shared helpers.
  - Data modules never import nanoui. A page never reads `/proc`.
  - Logic goes in the layer that owns it, never in `main.zig`.
- **Views.**
  - A view is a function of the state, drawn again on every input. Widgets report input as they are drawn.
  - Items in a list get a stable `ui.key`, so selection and animation follow the item as the list changes.
  - The window is never opened while working: render with `nui snapshot` and look at the PNG, drive behaviour with `ui.Tester`.
- **Frame memory.**
  - Text handed to `ui.text` is drawn after the function returns, so it must outlive it. Format with `c.print`, or copy a stack buffer with `fmt.own(c.alloc(), ...)`.
  - Never keep a slice into a buffer that is read again. Copy names out of the read buffer at once.
  - nanoui draws images from the caller's memory, so icon bytes live in the `icons` cache for the whole run.
- **Reading /proc.**
  - Go through `procfs.read`. It reads straight from the kernel and returns plain errors, because Zig's file reader prints a stack trace when `/proc` refuses a read.
  - A process that vanishes or hides its files is skipped, never an error.
- **Sampling.**
  - One sampler, on the UI thread, driven by `c.frameIn` from the view. Nothing polls while idle.
  - Work that can block a frame, such as scanning a disk, runs on a worker thread and reports back through state.
- **Ending tasks.**
  - Only the user's own processes, and never pid 1, kernel threads or zmon itself. Quit with SIGTERM first and kill only on request.
  - Ask before adding anything that signals other users' processes or needs privilege.
- **Look.**
  - One typeface: Lexend, bundled in `src/fonts` and named by the theme, so every widget uses it, numbers included. Never set another font or `.mono`. Glyphs it lacks fall back to the system's fonts.
  - Every colour comes from `theme.zig`, which is monochrome: emphasis is weight and contrast, not hue. No raw hex colours in a page.
  - Words on screen are the ones a person uses ("Processes", "End task"), never internal terms, ids or counters that mean nothing to them.
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
zig build check   # zig fmt --check + full build
zig build test
```

A visible change is also rendered and looked at:

```bash
nui snapshot --out /tmp/zmon.png --script "click:Performance;live:8"
```

Script steps are `click:TEXT`, `type:TEXT`, `key:enter`, `wait:SECONDS` and `live:SECONDS` (the real event loop), separated by `;`. A change in behaviour comes with a test in the module that owns it.

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
