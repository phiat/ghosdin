# Architecture

ghosdin is built on two core libraries — **libghostty-vt** for terminal
emulation and **raylib** for rendering — connected by **Odin** FFI
bindings and a thin POSIX PTY layer.

## System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         termview (Odin)                         │
│                                                                 │
│  ┌──────────┐    ┌──────────────────┐    ┌───────────────────┐  │
│  │   PTY    │───>│  libghostty-vt   │───>│     raylib        │  │
│  │  (POSIX) │    │  (VT parser +    │    │  (OpenGL window   │  │
│  │          │<───│   terminal state) │<───│   + font render)  │  │
│  └──────────┘    └──────────────────┘    └───────────────────┘  │
│       │                                          │              │
│       │            ┌────────────┐                │              │
│       └────────────│   shell    │                │              │
│         stdin/out  │ (bash/zsh) │     keyboard/  │              │
│                    └────────────┘     mouse input│              │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### vendor/ghostty_vt — Odin Bindings

A direct mapping of the `libghostty-vt` C API into Odin's foreign
function interface. The binding covers the complete API surface:

| Module          | Purpose                                           |
|-----------------|---------------------------------------------------|
| Terminal        | Create/destroy terminals, feed VT data, query state |
| Render State    | Incremental dirty-tracking for efficient rendering |
| Screen/Grid Ref | Cell and row access, grapheme clusters, styles     |
| SGR Parser      | Parse styling escape sequences standalone          |
| OSC Parser      | Parse operating system command sequences            |
| Key Encoder     | Encode keyboard events to VT escape sequences      |
| Mouse Encoder   | Encode mouse events to VT escape sequences         |
| Formatter       | Export terminal content as plain text, VT, or HTML |
| Modes           | Pack/unpack ANSI and DEC terminal mode identifiers |
| Focus/Paste     | Focus event encoding, paste safety validation      |
| Allocator       | Custom memory allocator interface                  |
| Build Info      | Query compile-time library configuration           |

**Design choices:**

- Opaque handles (`Terminal`, `Formatter`, etc.) are `distinct rawptr`
  for type safety — you can't accidentally pass a `Terminal` where a
  `Formatter` is expected.
- Tagged unions (e.g., `Style_Color`, `Point`) use `struct` with an
  enum tag + `#raw_union` value, matching the C ABI layout.
- Enums strip the `GHOSTTY_` prefix and use `PascalCase` members.
- The `link_prefix = "ghostty_"` attribute maps Odin names to C symbols
  automatically.
- Constants like modifier bitmasks and named colors are exposed as
  typed Odin constants.

### pty/ — PTY Layer

A minimal POSIX PTY interface using `forkpty(3)` from libutil, shared by
both `termview/` and `console/`:

- `spawn` — forks, execs a shell, returns a non-blocking master fd
- `read_bytes` — single non-blocking read; returns `(n, eof)` so callers
  can distinguish a closed PTY from a transient `EAGAIN`
- `drain` — repeated `read_bytes` until the kernel buffer empties or the
  caller's buffer fills; returns the populated slice plus an `eof` flag
- `write_bytes` / `write_string` / `write_byte` — writes to the master fd
- `resize` — send `TIOCSWINSZ` to update terminal dimensions

The master fd is set to `O_NONBLOCK` so reads never stall the render
loop.

### render_rl/ — Shared Raylib Helpers

A package shared by `termview/` and `console/` that holds everything
raylib-flavored that would otherwise be duplicated between them:

- `draw_cell` — render one resolved cell (bg fill, glyph, underline,
  strikethrough, bold brightening) given a `Cell_Layout` and the
  `Render_Cell` from the wrapper iterator
- `load_mono_font` — probe a list of standard system mono fonts, fall
  back to raylib's bundled default
- `key_to_vt_sequence` / `ctrl_byte` — map raylib keyboard events to
  the VT/xterm escape sequences the shell expects
- `to_rl_color` / `encode_utf8` — small color and UTF-8 helpers

### termview/main.odin — Rendering Pipeline

The main loop runs at 60 FPS (vsync) with three phases per frame:

#### 1. Pump PTY

```
PTY master fd ──read──> raw bytes ──vt_write──> ghostty-vt terminal
```

Up to 64 KB of PTY output is read per frame and fed into
`ghostty_terminal_vt_write()`. The terminal parses VT sequences
and updates its internal state (screen buffer, cursor, modes, styles).

#### 2. Handle Input

```
raylib window ──GetCharPressed──> UTF-8 bytes ──write──> PTY master fd
               ──GetKeyPressed──> escape seqs ──write──> PTY master fd
```

- Printable characters from `GetCharPressed()` are UTF-8 encoded and
  written to the PTY.
- Special keys (arrows, function keys, etc.) are mapped to their
  standard VT escape sequences.
- Ctrl+letter combinations generate the corresponding control character.

#### 3. Draw Frame

```
ghostty-vt render state ──iterate rows/cells──> raylib draw calls
```

1. `render_state_update()` syncs from the terminal.
2. The row iterator walks each row; the cell iterator walks each cell.
3. For each cell:
   - Background: `DrawRectangle` with the resolved bg color.
   - Foreground: `DrawTextCodepoint` with the glyph and resolved fg color.
   - Decorations: underline and strikethrough lines.
4. The cursor is drawn as a filled rectangle.
5. Dirty state is reset after the frame.

### vendor/ghostty_vt/terminal.odin — Idiomatic Wrapper

A higher-level Odin API built on top of the raw C bindings:

- **`Term`** struct — wraps `Terminal` + render state objects with
  automatic lifecycle management via `term_init`/`term_destroy`.
- **Typed getters** — `term_cols()`, `term_cursor_x()`, `term_title()`
  return proper Odin types instead of requiring void pointer casts.
- **`Error` enum** — replaces raw `Result` codes with a proper Odin enum
  compatible with `or_return` patterns.
- **Render iterators** — `term_render_rows()` / `term_render_cells()`
  yield `Render_Cell` structs with resolved codepoint, colors, and style
  already extracted. No manual cell/row/style API wrangling.
- **Formatter helpers** — `term_format_plain()` / `term_format_html()`
  return byte slices owned by the caller's allocator (default
  `context.allocator`); release with `delete`.
- **Allocator bridge** — `term_init` accepts an `mem.Allocator` (default
  `context.allocator`) and routes every `libghostty-vt` allocation
  through it via a heap-pinned C-vtable bridge, so tracking allocators
  see leaks inside the C library.

### console/ — Embeddable Game Dev Console

A self-contained quake-style dropdown terminal for raylib games:

- **`Console` struct** — holds terminal, PTY, font, animation state.
- **Lazy init** — the PTY and terminal are created on first use (after
  `InitWindow`), so the import has zero cost until toggled.
- **Input gating** — when open, the console consumes all keyboard input
  so the game doesn't receive stray keypresses. Check `is_open()`.
- **Slide animation** — configurable speed, slides down from the top
  edge of the screen.
- **Config** — dimensions, colors, opacity, toggle key, font size, shell
  are all configurable via the `Config` struct.

### example/ — Game + Console Demo

A small raylib game (WASD movement, orbiting particles) that
demonstrates the console integration. Press `` ` `` to toggle.

### demo/ — Headless Demo

A simpler program that exercises the bindings without any GUI. It
creates a terminal, feeds hardcoded VT sequences, and prints the
resulting state (cursor position, title, cell contents, modes) to
stdout. Useful for testing the bindings in CI or headless environments.

## Data Flow

```
User types 'ls' + Enter
    │
    ▼
raylib captures keystrokes
    │
    ▼
Characters encoded as bytes / escape sequences
    │
    ▼
Written to PTY master fd
    │
    ▼
Shell receives input, executes 'ls'
    │
    ▼
Shell writes output (with ANSI colors, etc.) to PTY
    │
    ▼
termview reads from PTY master fd (non-blocking)
    │
    ▼
Raw bytes fed to ghostty_terminal_vt_write()
    │
    ▼
ghostty-vt parses VT sequences, updates terminal state
    │
    ▼
render_state_update() captures current frame
    │
    ▼
Row/cell iteration extracts codepoints, colors, styles
    │
    ▼
raylib draws glyphs and colored rectangles
    │
    ▼
Frame displayed on screen
```

## Build Pipeline

```
ghostty (Zig) ──zig build──> libghostty-vt.so / .a
                                    │
                                    ▼
vendor/ghostty_vt (Odin) ──foreign import──> bindings
                                    │
demo/ termview/ console/ example/ (Odin) ──odin build──> binary
                                    │
                              -lghostty-vt (link)
```

The `justfile` orchestrates this: `just dev` builds the library,
compiles the Odin code, links against it, and runs the result.

## Dependencies

| Dependency     | Version   | Source          | Purpose              |
|----------------|-----------|-----------------|----------------------|
| Odin           | nightly   | mise            | Language / compiler  |
| Zig            | 0.15.2    | mise            | Build libghostty-vt  |
| libghostty-vt  | HEAD      | git (ghostty/)  | VT terminal engine   |
| raylib         | 5.5       | Odin vendor     | Windowing + rendering|
| libutil        | system    | glibc           | forkpty(3)           |
| just           | any       | mise            | Task runner          |
