package console

// Embeddable quake-style dropdown terminal console for raylib games.
//
// Usage:
//   import con "ghosdin/console"
//
//   console := con.create()
//   defer con.destroy(&console)
//
//   // In your game loop:
//   con.update(&console)
//   con.draw(&console)

import "base:runtime"
import "core:c"
import "core:math"
import rl "vendor:raylib"
import gvt "../vendor/ghostty_vt"
import p "../pty"

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

Config :: struct {
	cols:           u16,
	rows:           u16,
	max_scrollback: uint,
	font_size:      f32,
	cell_w:         f32,
	cell_h:         f32,
	bg_color:       rl.Color,
	fg_color:       rl.Color,
	border_color:   rl.Color,
	opacity:        f32,
	height_ratio:   f32,
	slide_speed:    f32,
	toggle_key:     rl.KeyboardKey,
	shell:          cstring,
}

DEFAULT_CONFIG :: Config{
	cols           = 120,
	rows           = 20,
	max_scrollback = 5000,
	font_size      = 15,
	cell_w         = 8,
	cell_h         = 17,
	bg_color       = {0x0a, 0x0a, 0x0a, 0xdd},
	fg_color       = {0xcc, 0xcc, 0xcc, 0xff},
	border_color   = {0x55, 0xff, 0x55, 0xff},
	opacity        = 0.92,
	height_ratio   = 0.45,
	slide_speed    = 3000,
	toggle_key     = .GRAVE,
	shell          = nil,
}

// ---------------------------------------------------------------------------
// Console state
// ---------------------------------------------------------------------------

State :: enum {
	Closed,
	Opening,
	Open,
	Closing,
}

Console :: struct {
	config:        Config,
	term:          gvt.Term,
	pty:           p.Pty,
	state:         State,
	slide_y:       f32,
	target_h:      f32,
	font:          rl.Font,
	owns_font:     bool,
	read_buf:      [32768]u8,
	initialized:   bool,
	// Stored at struct level to avoid dangling pointer
	write_pty_fn:  gvt.Terminal_Write_Pty_Fn,
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

create :: proc(cfg: Config = DEFAULT_CONFIG) -> Console {
	con: Console
	con.config = cfg
	con.state = .Closed
	con.slide_y = -1
	return con
}

ensure_init :: proc(con: ^Console) -> bool {
	if con.initialized do return true
	cfg := &con.config

	// Create terminal
	t, err := gvt.term_init(cfg.cols, cfg.rows, cfg.max_scrollback)
	if err != .None do return false
	con.term = t

	// Install write_pty callback (stored in Console struct)
	write_pty_cb :: proc "c" (terminal: gvt.Terminal, userdata: rawptr, data: [^]u8, len: c.size_t) {
		context = #force_no_inline runtime.default_context()
		pt := cast(^p.Pty)userdata
		p.write_bytes(pt, data[:len])
	}
	con.write_pty_fn = gvt.Terminal_Write_Pty_Fn(write_pty_cb)
	gvt.term_set(&con.term, .WRITE_PTY, rawptr(&con.write_pty_fn))
	gvt.term_set(&con.term, .USERDATA, rawptr(&con.pty))

	// Load font (before PTY spawn so we can clean up on failure)
	con.font = rl.LoadFontEx(
		"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
		i32(cfg.font_size), nil, 0,
	)
	if con.font.texture.id == 0 {
		con.font = rl.LoadFontEx(
			"/usr/share/fonts/TTF/DejaVuSansMono.ttf",
			i32(cfg.font_size), nil, 0,
		)
	}
	if con.font.texture.id == 0 {
		con.font = rl.GetFontDefault()
	} else {
		con.owns_font = true
	}

	// Spawn PTY
	shell := cfg.shell
	if shell == nil {
		shell = p.get_default_shell()
	}
	ok: bool
	con.pty, ok = p.spawn(shell, cfg.cols, cfg.rows)
	if !ok {
		// Clean up font on failure
		if con.owns_font {
			rl.UnloadFont(con.font)
			con.owns_font = false
		}
		gvt.term_destroy(&con.term)
		return false
	}

	// Target height
	screen_h := f32(rl.GetScreenHeight())
	con.target_h = screen_h * cfg.height_ratio
	con.slide_y = -con.target_h

	gvt.term_ensure_render(&con.term)

	con.initialized = true
	return true
}

destroy :: proc(con: ^Console) {
	if !con.initialized do return
	p.destroy(&con.pty)
	gvt.term_destroy(&con.term)
	if con.owns_font {
		rl.UnloadFont(con.font)
	}
	con.initialized = false
}

// ---------------------------------------------------------------------------
// Control
// ---------------------------------------------------------------------------

toggle :: proc(con: ^Console) {
	switch con.state {
	case .Closed, .Closing:
		con.state = .Opening
	case .Open, .Opening:
		con.state = .Closing
	}
}

is_open :: proc(con: ^Console) -> bool {
	return con.state == .Open || con.state == .Opening
}

// ---------------------------------------------------------------------------
// Update (call every frame)
// ---------------------------------------------------------------------------

update :: proc(con: ^Console) {
	if !ensure_init(con) do return

	cfg := &con.config
	dt := rl.GetFrameTime()

	if rl.IsKeyPressed(cfg.toggle_key) {
		toggle(con)
	}

	switch con.state {
	case .Opening:
		con.slide_y += cfg.slide_speed * dt
		if con.slide_y >= 0 {
			con.slide_y = 0
			con.state = .Open
		}
	case .Closing:
		con.slide_y -= cfg.slide_speed * dt
		if con.slide_y <= -con.target_h {
			con.slide_y = -con.target_h
			con.state = .Closed
		}
	case .Open, .Closed:
	}

	if con.state == .Closed do return

	pump_pty(con)

	if con.state == .Open || con.state == .Opening {
		handle_console_input(con)
	}
}

pump_pty :: proc(con: ^Console) {
	total := 0
	for total < len(con.read_buf) {
		n := p.read_bytes(&con.pty, con.read_buf[total:])
		if n <= 0 do break
		total += n
	}
	if total > 0 {
		gvt.term_write_bytes(&con.term, con.read_buf[:total])
	}
}

handle_console_input :: proc(con: ^Console) {
	for {
		ch := rl.GetCharPressed()
		if ch == 0 do break
		if ch == '`' || ch == '~' do continue
		buf: [4]u8
		n := encode_utf8(buf[:], ch)
		p.write_bytes(&con.pty, buf[:n])
	}

	for {
		key := rl.GetKeyPressed()
		if key == .KEY_NULL do break
		if key == con.config.toggle_key do continue

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
		case .DELETE:    seq = "\x1b[3~"
		case:
			if ctrl {
				ki := int(key)
				if ki >= int(rl.KeyboardKey.A) && ki <= int(rl.KeyboardKey.Z) {
					b := u8(ki - int(rl.KeyboardKey.A) + 1)
					p.write_byte(&con.pty, b)
				}
			}
			continue
		}
		p.write_string(&con.pty, seq)
	}
}

// ---------------------------------------------------------------------------
// Draw (call every frame, after BeginDrawing)
// ---------------------------------------------------------------------------

draw :: proc(con: ^Console) {
	if con.state == .Closed do return
	if !con.initialized do return

	cfg := &con.config
	screen_w := f32(rl.GetScreenWidth())

	gvt.term_render_update(&con.term)
	colors, _ := gvt.term_render_colors(&con.term)
	cursor := gvt.term_render_cursor(&con.term)

	y_offset := con.slide_y
	console_h := con.target_h

	rl.DrawRectangle(0, i32(y_offset), i32(screen_w), i32(console_h),
		rl.Color{cfg.bg_color.r, cfg.bg_color.g, cfg.bg_color.b,
			u8(f32(cfg.bg_color.a) * cfg.opacity)})

	rl.DrawRectangle(0, i32(y_offset + console_h - 2), i32(screen_w), 2, cfg.border_color)

	padding_x: f32 = 4
	padding_y: f32 = 4

	row_it := gvt.term_render_rows(&con.term)
	for row_idx in gvt.render_row_next(&row_it) {
		cell_it := gvt.term_render_cells(&con.term)
		for cell in gvt.render_cell_next(&cell_it) {
			px := f32(cell.col) * cfg.cell_w + padding_x
			py := f32(row_idx) * cfg.cell_h + padding_y + y_offset

			if py + cfg.cell_h < 0 do continue

			if cell.has_bg {
				rl.DrawRectangle(i32(px), i32(py), i32(cfg.cell_w), i32(cfg.cell_h), to_rl_color(cell.bg_color))
			}

			if !cell.has_text || cell.codepoint == 0 || cell.codepoint < 32 do continue

			fg: rl.Color
			if cell.has_fg {
				fg = to_rl_color(cell.fg_color)
			} else {
				fg = to_rl_color(colors.foreground)
			}

			if cell.style.bold {
				fg.r = u8(min(255, int(fg.r) + 40))
				fg.g = u8(min(255, int(fg.g) + 40))
				fg.b = u8(min(255, int(fg.b) + 40))
			}

			if cell.style.underline != 0 {
				rl.DrawLine(i32(px), i32(py + cfg.cell_h - 1), i32(px + cfg.cell_w), i32(py + cfg.cell_h - 1), fg)
			}

			rl.DrawTextCodepoint(con.font, cell.codepoint, {px, py}, cfg.font_size, fg)
		}
	}

	if cursor.visible && cursor.in_viewport {
		cx := f32(cursor.x) * cfg.cell_w + padding_x
		cy := f32(cursor.y) * cfg.cell_h + padding_y + y_offset
		rl.DrawRectangle(i32(cx), i32(cy), i32(cfg.cell_w), i32(cfg.cell_h), {0xcc, 0xcc, 0xcc, 0xaa})
	}

	gvt.term_render_clean(&con.term)
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
