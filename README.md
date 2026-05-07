# ghosdin

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Odin](https://img.shields.io/badge/odin-nightly-orange.svg)](https://odin-lang.org/)
[![Zig](https://img.shields.io/badge/zig-0.15.2-f7a41d.svg)](https://ziglang.org/)
[![raylib](https://img.shields.io/badge/raylib-5.5-white.svg)](https://www.raylib.com/)
[![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)](#)

Odin bindings for [libghostty-vt](https://github.com/ghostty-org/ghostty) — the
zero-dependency VT terminal parser/state library from the Ghostty project.

Includes a graphical terminal emulator, an embeddable game dev console,
and an idiomatic Odin wrapper.

## What's Here

```
ghosdin/
├── vendor/ghostty_vt/
│   ├── ghostty_vt.odin    Raw C FFI bindings (complete API)
│   └── terminal.odin      Idiomatic Odin wrapper (Term, iterators, helpers)
├── pty/                   Shared POSIX PTY interface (forkpty, non-blocking I/O)
├── render_rl/             Shared raylib helpers (cell render, font, key encoding)
├── console/               Embeddable quake-style dropdown console
├── termview/              Standalone graphical terminal (raylib + PTY)
├── demo/                  Headless demo (bindings smoke test)
├── example/               Example game with embedded console
├── docs/architecture.md   Architecture and data flow
├── justfile               Build commands
└── ghostty/               Ghostty source (cloned, gitignored)
```

## Quick Start

### Prerequisites

- [Odin](https://odin-lang.org/) (nightly)
- [Zig](https://ziglang.org/) 0.15.2 — to build libghostty-vt
  (pinned in `.mise.toml`; upstream ghostty does not yet support 0.16)
- [just](https://github.com/casey/just) — task runner

### Setup

```bash
git clone <repo-url> ghosdin && cd ghosdin
git clone --depth 1 https://github.com/ghostty-org/ghostty.git
just dev
```

### Commands

```
just dev              Build + launch the graphical terminal
just run-demo         Run the headless demo
just run-example      Launch the example game (` to toggle console)
just build            Build everything
just check-all        Type-check all packages
just debug            Build + run in debug mode
just info             Show toolchain and build info
just clean            Clean all artifacts
just update           Pull latest ghostty + rebuild
just test-lib         Run libghostty-vt's test suite
```

## Packages

### vendor/ghostty_vt — Bindings

Complete Odin mapping of the libghostty-vt C API, plus an idiomatic wrapper.

#### Raw bindings (`ghostty_vt.odin`)

```odin
import gvt "vendor/ghostty_vt"

term: gvt.Terminal
opts := gvt.Terminal_Options{cols = 80, rows = 24, max_scrollback = 1000}
gvt.terminal_new(nil, &term, opts)
defer gvt.terminal_free(term)

data := "\x1b[1;32mHello!\x1b[0m\r\n"
gvt.terminal_vt_write(term, raw_data(data), len(data))
```

#### Idiomatic wrapper (`terminal.odin`)

```odin
import gvt "vendor/ghostty_vt"

t, err := gvt.term_init(80, 24)
defer gvt.term_destroy(&t)

gvt.term_write(&t, "\x1b[1;32mHello!\x1b[0m\r\n")

title := gvt.term_title(&t)
cx    := gvt.term_cursor_x(&t)

// Render iteration
gvt.term_render_update(&t)
row_it := gvt.term_render_rows(&t)
for row in gvt.render_row_next(&row_it) {
    cell_it := gvt.term_render_cells(&t)
    for cell in gvt.render_cell_next(&cell_it) {
        // cell.codepoint, cell.fg_color, cell.style, etc.
    }
}
```

#### API Coverage

| Module          | Description                                        |
|-----------------|----------------------------------------------------|
| Terminal        | Create terminals, feed VT data, query/set state    |
| Render State    | Incremental dirty-tracking for renderers           |
| Screen/Grid Ref | Cell and row access, grapheme clusters, hyperlinks |
| SGR Parser      | Parse styling escape sequences                     |
| OSC Parser      | Parse operating system commands                    |
| Key Encoder     | Encode keyboard events to escape sequences         |
| Mouse Encoder   | Encode mouse events to escape sequences            |
| Formatter       | Export content as plain text, VT, or HTML          |
| Modes           | ANSI and DEC terminal mode utilities               |
| Focus/Paste     | Focus encoding, paste safety + bracketed encoding  |
| Selection       | Grid-ref selection ranges                          |
| Kitty Graphics  | Image storage, placement iteration, render geometry|
| Sys             | Runtime callbacks (PNG decode, log)                |
| Allocator       | Custom memory allocator support                    |
| Build Info      | Query compile-time library configuration + version |

### console — Embeddable Game Dev Console

Drop-in quake-style terminal for raylib games. Press `` ` `` to toggle.

```odin
import con "ghosdin/console"

// In your game init:
console := con.create()    // or con.create(con.Config{...})
defer con.destroy(&console)

// In your game loop:
con.update(&console)       // handles toggle key + keyboard when open
con.draw(&console)         // renders the overlay (call after your game draws)

// Game input gating:
if !con.is_open(&console) {
    // process game input only when console is closed
}
```

Features:
- Spawns a real PTY shell — run any command
- Smooth slide-in/out animation
- Configurable: dimensions, colors, opacity, toggle key, font size
- Captures keyboard when open so game doesn't get stray input
- Full VT escape sequence support (colors, cursor, modes)

### termview — Graphical Terminal

A working terminal emulator in ~300 lines of Odin:

- Spawns a PTY with `$SHELL`
- Feeds output through libghostty-vt
- Renders the grid with raylib (OpenGL)
- Keyboard input (printable chars, special keys, ctrl combos)
- Colors, bold, underline, strikethrough, cursor

```
just run-termview
```

#### Screenshots

- `F12` — save the full window as `termview_<timestamp>.png` in the working directory.
- Click and drag — capture a cell-aligned region as `termview-region_<timestamp>.png`,
  and copy the underlying text into the system clipboard at the same time.

### example — Game + Console Demo

A small raylib game (WASD movement, particles) with the console embedded.
Press `` ` `` to drop down a terminal overlay.

```
just run-example
```

## Architecture

```
PTY ──bytes──> ghostty-vt ──render state──> raylib
 ^                                            |
 └──────────── keyboard input ────────────────┘
```

See [docs/architecture.md](docs/architecture.md) for the full writeup.

## Roadmap

The `vendor/ghostty_vt` bindings will eventually be extracted into their
own standalone repository as a proper Odin package, making them easy to
import without pulling in the full ghosdin project.

## License

Bindings and demo code: MIT

libghostty-vt: See [Ghostty's license](https://github.com/ghostty-org/ghostty/blob/main/LICENSE)
