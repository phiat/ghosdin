package termview

// termview — a graphical terminal emulator powered by ghostty-vt + raylib.
//
// Spawns a PTY with your shell, feeds output through libghostty-vt for
// VT parsing, and renders the terminal grid using raylib.

import p "../pty"
import r "../render_rl"
import gvt "../vendor/ghostty_vt"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

TERM_COLS :: 100
TERM_ROWS :: 35
CELL_W :: 9
CELL_H :: 18
FONT_SIZE :: 16
MAX_SCROLLBACK :: 5000
PADDING :: 4

WINDOW_W :: TERM_COLS * CELL_W + PADDING * 2
WINDOW_H :: TERM_ROWS * CELL_H + PADDING * 2

CURSOR_COLOR :: rl.Color{0xc5, 0xc8, 0xc6, 0xcc}
SELECTION_COLOR :: rl.Color{0x88, 0xcc, 0xff, 0x55}
SELECTION_BORDER :: rl.Color{0x88, 0xcc, 0xff, 0xff}

// ---------------------------------------------------------------------------
// State (package-level so callbacks can access)
// ---------------------------------------------------------------------------

term: gvt.Term
pty: p.Pty
font: rl.Font
owns_font: bool
read_buf: [65536]u8
session_ended: bool

// Mouse-drag screenshot state.
selecting:    bool
sel_anchor:   rl.Vector2
sel_current:  rl.Vector2
flash_until:  f64    // timestamp until which a brief overlay confirms a capture
flash_msg:    string

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

main :: proc() {
	t, err := gvt.term_init(TERM_COLS, TERM_ROWS, MAX_SCROLLBACK)
	if err != .None {
		fmt.eprintln("Failed to create terminal:", err)
		return
	}
	term = t
	defer gvt.term_destroy(&term)

	write_pty_cb :: proc "c" (
		_terminal: gvt.Terminal,
		userdata: rawptr,
		data: [^]u8,
		length: c.size_t,
	) {
		context = #force_no_inline runtime.default_context()
		pt := cast(^p.Pty)userdata
		p.write_bytes(pt, data[:length])
	}
	gvt.term_set(&term, .WRITE_PTY, rawptr(write_pty_cb))
	gvt.term_set(&term, .USERDATA, rawptr(&pty))

	if e := gvt.term_ensure_render(&term); e != .None {
		fmt.eprintln("Failed to allocate render state:", e)
		return
	}

	shell := p.get_default_shell()
	ok: bool
	pty, ok = p.spawn(shell, TERM_COLS, TERM_ROWS)
	if !ok {
		fmt.eprintln("Failed to spawn PTY")
		return
	}
	defer p.destroy(&pty)
	p.resize(&pty, TERM_COLS, TERM_ROWS)

	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(WINDOW_W, WINDOW_H, "ghosdin — termview")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	font, owns_font = r.load_mono_font(FONT_SIZE)
	defer if owns_font do rl.UnloadFont(font)

	for !rl.WindowShouldClose() {
		pump_pty()
		handle_input()
		handle_screenshot_input()
		draw_frame()
	}
}

// ---------------------------------------------------------------------------
// PTY I/O
// ---------------------------------------------------------------------------

pump_pty :: proc() {
	if session_ended do return
	data, eof := p.drain(&pty, read_buf[:])
	if len(data) > 0 {
		gvt.term_write_bytes(&term, data)
	}
	if eof do session_ended = true
}

// ---------------------------------------------------------------------------
// Keyboard Input
// ---------------------------------------------------------------------------

handle_input :: proc() {
	for {
		ch := rl.GetCharPressed()
		if ch == 0 do break
		buf: [4]u8
		n := r.encode_utf8(buf[:], ch)
		p.write_bytes(&pty, buf[:n])
	}

	for {
		key := rl.GetKeyPressed()
		if key == .KEY_NULL do break

		// F12 is reserved for full-window screenshot (see handle_screenshot_input).
		if key == .F12 do continue

		ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)

		if seq := r.key_to_vt_sequence(key); seq != "" {
			p.write_string(&pty, seq)
			continue
		}
		if ctrl {
			if b, ok := r.ctrl_byte(key); ok {
				p.write_byte(&pty, b)
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Screenshot — F12 for full window, drag-select for a cell-aligned region.
// Region capture also pushes the selected text into the system clipboard.
// ---------------------------------------------------------------------------

handle_screenshot_input :: proc() {
	if rl.IsKeyPressed(.F12) {
		path := timestamped_path("termview", "png")
		defer delete(path)
		cpath := strings.clone_to_cstring(path)
		defer delete(cpath)
		rl.TakeScreenshot(cpath)
		set_flash(fmt.tprintf("saved %s", path))
	}

	if rl.IsMouseButtonPressed(.LEFT) {
		selecting = true
		sel_anchor = rl.GetMousePosition()
		sel_current = sel_anchor
	}
	if selecting {
		sel_current = rl.GetMousePosition()
		if rl.IsMouseButtonReleased(.LEFT) {
			selecting = false
			capture_selection(sel_anchor, sel_current)
		}
	}
}

// Snap pixel coords to a cell-aligned (col, row) range covering the gesture.
selection_to_cells :: proc(a, b: rl.Vector2) -> (col0, row0, col1, row1: int, valid: bool) {
	min_x := min(a.x, b.x) - PADDING
	max_x := max(a.x, b.x) - PADDING
	min_y := min(a.y, b.y) - PADDING
	max_y := max(a.y, b.y) - PADDING
	col0 = max(0, int(min_x / CELL_W))
	row0 = max(0, int(min_y / CELL_H))
	col1 = min(TERM_COLS - 1, int(max_x / CELL_W))
	row1 = min(TERM_ROWS - 1, int(max_y / CELL_H))
	if col1 < col0 || row1 < row0 do return 0, 0, 0, 0, false
	if (col1 - col0) < 1 && (row1 - row0) < 1 do return 0, 0, 0, 0, false
	return col0, row0, col1, row1, true
}

capture_selection :: proc(a, b: rl.Vector2) {
	col0, row0, col1, row1, ok := selection_to_cells(a, b)
	if !ok do return

	// Pixel rect — inclusive of the right/bottom cells.
	x := f32(col0) * CELL_W + PADDING
	y := f32(row0) * CELL_H + PADDING
	w := f32(col1 - col0 + 1) * CELL_W
	h := f32(row1 - row0 + 1) * CELL_H
	rect := rl.Rectangle{x = x, y = y, width = w, height = h}

	full := rl.LoadImageFromScreen()
	defer rl.UnloadImage(full)
	cropped := rl.ImageFromImage(full, rect)
	defer rl.UnloadImage(cropped)

	path := timestamped_path("termview-region", "png")
	defer delete(path)
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)
	rl.ExportImage(cropped, cpath)

	text := selection_text(col0, row0, col1, row1)
	defer delete(text)
	ctext := strings.clone_to_cstring(text)
	defer delete(ctext)
	rl.SetClipboardText(ctext)
	set_flash(fmt.tprintf("saved %s + clipboard (%dx%d cells)", path, col1 - col0 + 1, row1 - row0 + 1))
}

// Build a UTF-8 string from the cells in the given inclusive rectangle.
selection_text :: proc(col0, row0, col1, row1: int) -> string {
	b := strings.builder_make()
	for y := row0; y <= row1; y += 1 {
		for x := col0; x <= col1; x += 1 {
			info, e := gvt.term_cell_at(&term, u16(x), u16(y))
			if e != .None do continue
			if info.has_text && info.codepoint >= 32 {
				strings.write_rune(&b, info.codepoint)
			} else {
				strings.write_byte(&b, ' ')
			}
		}
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

timestamped_path :: proc(prefix, ext: string) -> string {
	now := time.now()
	y, m, d := time.date(now)
	hh, mm, ss := time.clock(now)
	return fmt.aprintf("%s_%04d%02d%02d_%02d%02d%02d.%s", prefix, y, int(m), d, hh, mm, ss, ext)
}

set_flash :: proc(msg: string) {
	flash_msg = msg
	flash_until = rl.GetTime() + 2.5
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

draw_frame :: proc() {
	gvt.term_render_update(&term)
	colors, _ := gvt.term_render_colors(&term)
	cursor := gvt.term_render_cursor(&term)

	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(r.to_rl_color(colors.background))

	layout := r.Cell_Layout{
		cell_w    = CELL_W,
		cell_h    = CELL_H,
		padding_x = PADDING,
		padding_y = PADDING,
		y_offset  = 0,
		font_size = FONT_SIZE,
	}

	row_it := gvt.term_render_rows(&term)
	for row in gvt.render_row_next(&row_it) {
		cell_it := gvt.term_render_cells(&term)
		for cell in gvt.render_cell_next(&cell_it) {
			r.draw_cell(font, row, cell, colors.foreground, layout)
		}
	}

	if cursor.visible && cursor.in_viewport {
		cx := f32(cursor.x) * CELL_W + PADDING
		cy := f32(cursor.y) * CELL_H + PADDING
		rl.DrawRectangle(i32(cx), i32(cy), CELL_W, CELL_H, CURSOR_COLOR)
	}

	if selecting {
		x := min(sel_anchor.x, sel_current.x)
		y := min(sel_anchor.y, sel_current.y)
		w := abs(sel_current.x - sel_anchor.x)
		h := abs(sel_current.y - sel_anchor.y)
		rl.DrawRectangle(i32(x), i32(y), i32(w), i32(h), SELECTION_COLOR)
		rl.DrawRectangleLines(i32(x), i32(y), i32(w), i32(h), SELECTION_BORDER)
	}

	if session_ended {
		rl.DrawText("[ session ended — close window to exit ]",
			PADDING, WINDOW_H - 24, 16, {0xff, 0x88, 0x88, 0xff})
	}

	if rl.GetTime() < flash_until && len(flash_msg) > 0 {
		cmsg := strings.clone_to_cstring(flash_msg, context.temp_allocator)
		rl.DrawText(cmsg, PADDING, PADDING, 14, {0x88, 0xff, 0x88, 0xff})
	}

	gvt.term_render_clean(&term)
}
