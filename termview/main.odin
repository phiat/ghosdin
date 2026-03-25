package termview

// termview — a graphical terminal emulator powered by ghostty-vt + raylib.
//
// Spawns a PTY with your shell, feeds output through libghostty-vt for
// VT parsing, and renders the terminal grid using raylib.

import "base:runtime"
import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import gvt "../vendor/ghostty_vt"
import p "../pty"

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

TERM_COLS      :: 100
TERM_ROWS      :: 35
CELL_W         :: 9
CELL_H         :: 18
FONT_SIZE      :: 16
MAX_SCROLLBACK :: 5000
PADDING        :: 4

WINDOW_W :: TERM_COLS * CELL_W + PADDING * 2
WINDOW_H :: TERM_ROWS * CELL_H + PADDING * 2

// ---------------------------------------------------------------------------
// Palette (Ghostty default-ish dark theme)
// ---------------------------------------------------------------------------

BG_COLOR :: rl.Color{0x1d, 0x1f, 0x21, 0xff}
FG_COLOR :: rl.Color{0xc5, 0xc8, 0xc6, 0xff}
CURSOR_COLOR :: rl.Color{0xc5, 0xc8, 0xc6, 0xcc}

// ---------------------------------------------------------------------------
// State (package-level so callbacks can access)
// ---------------------------------------------------------------------------

term:         gvt.Terminal
render_state: gvt.Render_State
row_iter:     gvt.Render_State_Row_Iterator
row_cells:    gvt.Render_State_Row_Cells
pty:          p.Pty
font:         rl.Font
read_buf:     [65536]u8

// Package-level callback storage (avoids dangling stack pointer)
write_pty_fn: gvt.Terminal_Write_Pty_Fn

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

main :: proc() {
	// -- Init ghostty-vt terminal --
	opts := gvt.Terminal_Options{
		cols           = TERM_COLS,
		rows           = TERM_ROWS,
		max_scrollback = MAX_SCROLLBACK,
	}
	if gvt.terminal_new(nil, &term, opts) != .SUCCESS {
		fmt.eprintln("Failed to create terminal")
		return
	}
	defer gvt.terminal_free(term)

	// Install write_pty callback (stored at package level)
	write_pty_cb :: proc "c" (terminal: gvt.Terminal, userdata: rawptr, data: [^]u8, len: c.size_t) {
		context = #force_no_inline runtime.default_context()
		pt := cast(^p.Pty)userdata
		p.write_bytes(pt, data[:len])
	}
	write_pty_fn = gvt.Terminal_Write_Pty_Fn(write_pty_cb)
	gvt.terminal_set(term, .WRITE_PTY, rawptr(&write_pty_fn))
	gvt.terminal_set(term, .USERDATA, rawptr(&pty))

	// -- Init render state --
	if gvt.render_state_new(nil, &render_state) != .SUCCESS {
		fmt.eprintln("Failed to create render state")
		return
	}
	defer gvt.render_state_free(render_state)

	if gvt.render_state_row_iterator_new(nil, &row_iter) != .SUCCESS {
		fmt.eprintln("Failed to create row iterator")
		return
	}
	defer gvt.render_state_row_iterator_free(row_iter)

	if gvt.render_state_row_cells_new(nil, &row_cells) != .SUCCESS {
		fmt.eprintln("Failed to create row cells")
		return
	}
	defer gvt.render_state_row_cells_free(row_cells)

	// -- Spawn PTY --
	shell := p.get_default_shell()
	ok: bool
	pty, ok = p.spawn(shell, TERM_COLS, TERM_ROWS)
	if !ok {
		fmt.eprintln("Failed to spawn PTY")
		return
	}
	defer p.destroy(&pty)

	p.resize(&pty, TERM_COLS, TERM_ROWS)

	// -- Init raylib --
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(WINDOW_W, WINDOW_H, "ghosdin — termview")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	// Load a monospace font
	font = rl.LoadFontEx("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", FONT_SIZE, nil, 0)
	if font.texture.id == 0 {
		font = rl.LoadFontEx("/usr/share/fonts/TTF/DejaVuSansMono.ttf", FONT_SIZE, nil, 0)
	}
	if font.texture.id == 0 {
		font = rl.GetFontDefault()
	}
	defer rl.UnloadFont(font)

	// -- Main loop --
	for !rl.WindowShouldClose() {
		pump_pty()
		handle_input()
		draw_frame()
	}
}

// ---------------------------------------------------------------------------
// PTY I/O
// ---------------------------------------------------------------------------

pump_pty :: proc() {
	total := 0
	for total < len(read_buf) {
		n := p.read_bytes(&pty, read_buf[total:])
		if n <= 0 do break
		total += n
	}
	if total > 0 {
		gvt.terminal_vt_write(term, raw_data(read_buf[:total]), c.size_t(total))
	}
}

// ---------------------------------------------------------------------------
// Keyboard Input
// ---------------------------------------------------------------------------

handle_input :: proc() {
	for {
		ch := rl.GetCharPressed()
		if ch == 0 do break
		buf: [4]u8
		n := encode_utf8(buf[:], ch)
		p.write_bytes(&pty, buf[:n])
	}

	for {
		key := rl.GetKeyPressed()
		if key == .KEY_NULL do break

		ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)

		seq: string
		#partial switch key {
		case .ENTER:     seq = "\r"
		case .BACKSPACE: seq = "\x7f"
		case .TAB:       seq = "\t"
		case .ESCAPE:    seq = "\x1b"
		case .UP:        seq = "\x1b[A"
		case .DOWN:      seq = "\x1b[B"
		case .RIGHT:     seq = "\x1b[C"
		case .LEFT:      seq = "\x1b[D"
		case .HOME:      seq = "\x1b[H"
		case .END:       seq = "\x1b[F"
		case .PAGE_UP:   seq = "\x1b[5~"
		case .PAGE_DOWN: seq = "\x1b[6~"
		case .INSERT:    seq = "\x1b[2~"
		case .DELETE:    seq = "\x1b[3~"
		case .F1:        seq = "\x1bOP"
		case .F2:        seq = "\x1bOQ"
		case .F3:        seq = "\x1bOR"
		case .F4:        seq = "\x1bOS"
		case .F5:        seq = "\x1b[15~"
		case .F6:        seq = "\x1b[17~"
		case .F7:        seq = "\x1b[18~"
		case .F8:        seq = "\x1b[19~"
		case .F9:        seq = "\x1b[20~"
		case .F10:       seq = "\x1b[21~"
		case .F11:       seq = "\x1b[23~"
		case .F12:       seq = "\x1b[24~"
		case:
			if ctrl {
				ki := int(key)
				if ki >= int(rl.KeyboardKey.A) && ki <= int(rl.KeyboardKey.Z) {
					ctrl_byte := u8(ki - int(rl.KeyboardKey.A) + 1)
					p.write_byte(&pty, ctrl_byte)
				}
			}
			continue
		}
		p.write_string(&pty, seq)
	}
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

draw_frame :: proc() {
	gvt.render_state_update(render_state, term)

	colors := gvt.Render_State_Colors{size = size_of(gvt.Render_State_Colors)}
	gvt.render_state_colors_get(render_state, &colors)

	cursor_visible: bool
	cursor_x, cursor_y: u16
	cursor_in_viewport: bool
	gvt.render_state_get(render_state, .CURSOR_VISIBLE, &cursor_visible)
	gvt.render_state_get(render_state, .CURSOR_VIEWPORT_HAS_VALUE, &cursor_in_viewport)
	gvt.render_state_get(render_state, .CURSOR_VIEWPORT_X, &cursor_x)
	gvt.render_state_get(render_state, .CURSOR_VIEWPORT_Y, &cursor_y)

	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(to_rl_color(colors.background))

	gvt.render_state_get(render_state, .ROW_ITERATOR, &row_iter)
	row_idx: u16 = 0
	for gvt.render_state_row_iterator_next(row_iter) {
		gvt.render_state_row_get(row_iter, .CELLS, &row_cells)
		col_idx: u16 = 0
		for gvt.render_state_row_cells_next(row_cells) {
			draw_cell(col_idx, row_idx, &colors)
			col_idx += 1
		}
		row_idx += 1
	}

	if cursor_visible && cursor_in_viewport {
		cx := f32(cursor_x) * CELL_W + PADDING
		cy := f32(cursor_y) * CELL_H + PADDING
		rl.DrawRectangle(i32(cx), i32(cy), CELL_W, CELL_H, CURSOR_COLOR)
	}

	dirty_false := gvt.Render_State_Dirty.FALSE
	gvt.render_state_set(render_state, .DIRTY, &dirty_false)

	gvt.render_state_get(render_state, .ROW_ITERATOR, &row_iter)
	for gvt.render_state_row_iterator_next(row_iter) {
		dirty_val := false
		gvt.render_state_row_set(row_iter, .DIRTY, &dirty_val)
	}
}

draw_cell :: proc(col: u16, row: u16, colors: ^gvt.Render_State_Colors) {
	px := f32(col) * CELL_W + PADDING
	py := f32(row) * CELL_H + PADDING

	bg_rgb: gvt.Color_Rgb
	if gvt.render_state_row_cells_get(row_cells, .BG_COLOR, &bg_rgb) == .SUCCESS {
		rl.DrawRectangle(i32(px), i32(py), CELL_W, CELL_H, to_rl_color(bg_rgb))
	}

	raw_cell: gvt.Cell
	gvt.render_state_row_cells_get(row_cells, .RAW, &raw_cell)

	has_text: bool
	gvt.cell_get(raw_cell, .HAS_TEXT, &has_text)
	if !has_text do return

	cp: u32
	gvt.cell_get(raw_cell, .CODEPOINT, &cp)
	if cp == 0 || cp < 32 do return

	fg_rgb: gvt.Color_Rgb
	fg_color: rl.Color
	if gvt.render_state_row_cells_get(row_cells, .FG_COLOR, &fg_rgb) == .SUCCESS {
		fg_color = to_rl_color(fg_rgb)
	} else {
		fg_color = to_rl_color(colors.foreground)
	}

	style: gvt.Style
	style.size = size_of(gvt.Style)
	if gvt.render_state_row_cells_get(row_cells, .STYLE, &style) == .SUCCESS {
		if style.bold {
			fg_color.r = u8(min(255, int(fg_color.r) + 40))
			fg_color.g = u8(min(255, int(fg_color.g) + 40))
			fg_color.b = u8(min(255, int(fg_color.b) + 40))
		}
		if style.underline != 0 {
			rl.DrawLine(i32(px), i32(py) + CELL_H - 1, i32(px) + CELL_W, i32(py) + CELL_H - 1, fg_color)
		}
		if style.strikethrough {
			rl.DrawLine(i32(px), i32(py) + CELL_H / 2, i32(px) + CELL_W, i32(py) + CELL_H / 2, fg_color)
		}
	}

	rl.DrawTextCodepoint(font, rune(cp), {px, py}, FONT_SIZE, fg_color)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

to_rl_color :: proc(c: gvt.Color_Rgb) -> rl.Color {
	return {c.r, c.g, c.b, 0xff}
}

encode_utf8 :: proc(buf: []u8, cp: rune) -> int {
	v := u32(cp)
	if v < 0x80 {
		buf[0] = u8(v)
		return 1
	} else if v < 0x800 {
		buf[0] = u8(0xC0 | (v >> 6))
		buf[1] = u8(0x80 | (v & 0x3F))
		return 2
	} else if v < 0x10000 {
		buf[0] = u8(0xE0 | (v >> 12))
		buf[1] = u8(0x80 | ((v >> 6) & 0x3F))
		buf[2] = u8(0x80 | (v & 0x3F))
		return 3
	} else {
		buf[0] = u8(0xF0 | (v >> 18))
		buf[1] = u8(0x80 | ((v >> 12) & 0x3F))
		buf[2] = u8(0x80 | ((v >> 6) & 0x3F))
		buf[3] = u8(0x80 | (v & 0x3F))
		return 4
	}
}
