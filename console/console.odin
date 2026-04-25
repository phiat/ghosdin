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
import rl "vendor:raylib"
import gvt "../vendor/ghostty_vt"
import p "../pty"
import r "../render_rl"

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
	session_ended: bool,
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

	t, err := gvt.term_init(cfg.cols, cfg.rows, cfg.max_scrollback)
	if err != .None do return false
	con.term = t

	write_pty_cb :: proc "c" (_terminal: gvt.Terminal, userdata: rawptr, data: [^]u8, length: c.size_t) {
		context = #force_no_inline runtime.default_context()
		pt := cast(^p.Pty)userdata
		p.write_bytes(pt, data[:length])
	}
	gvt.term_set(&con.term, .WRITE_PTY, rawptr(write_pty_cb))
	gvt.term_set(&con.term, .USERDATA, rawptr(&con.pty))

	con.font, con.owns_font = r.load_mono_font(i32(cfg.font_size))

	shell := cfg.shell
	if shell == nil do shell = p.get_default_shell()
	ok: bool
	con.pty, ok = p.spawn(shell, cfg.cols, cfg.rows)
	if !ok {
		if con.owns_font {
			rl.UnloadFont(con.font)
			con.owns_font = false
		}
		gvt.term_destroy(&con.term)
		return false
	}

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
	if con.session_ended do return
	data, eof := p.drain(&con.pty, con.read_buf[:])
	if len(data) > 0 {
		gvt.term_write_bytes(&con.term, data)
	}
	if eof do con.session_ended = true
}

handle_console_input :: proc(con: ^Console) {
	for {
		ch := rl.GetCharPressed()
		if ch == 0 do break
		if ch == '`' || ch == '~' do continue
		buf: [4]u8
		n := r.encode_utf8(buf[:], ch)
		p.write_bytes(&con.pty, buf[:n])
	}

	for {
		key := rl.GetKeyPressed()
		if key == .KEY_NULL do break
		if key == con.config.toggle_key do continue

		ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)

		if seq := r.key_to_vt_sequence(key); seq != "" {
			p.write_string(&con.pty, seq)
			continue
		}
		if ctrl {
			if b, ok := r.ctrl_byte(key); ok {
				p.write_byte(&con.pty, b)
			}
		}
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

	layout := r.Cell_Layout{
		cell_w    = cfg.cell_w,
		cell_h    = cfg.cell_h,
		padding_x = 4,
		padding_y = 4,
		y_offset  = y_offset,
		font_size = cfg.font_size,
	}

	row_it := gvt.term_render_rows(&con.term)
	for row in gvt.render_row_next(&row_it) {
		cell_it := gvt.term_render_cells(&con.term)
		for cell in gvt.render_cell_next(&cell_it) {
			r.draw_cell(con.font, row, cell, colors.foreground, layout)
		}
	}

	if cursor.visible && cursor.in_viewport {
		cx := f32(cursor.x) * cfg.cell_w + layout.padding_x
		cy := f32(cursor.y) * cfg.cell_h + layout.padding_y + y_offset
		rl.DrawRectangle(i32(cx), i32(cy), i32(cfg.cell_w), i32(cfg.cell_h), {0xcc, 0xcc, 0xcc, 0xaa})
	}

	if con.session_ended {
		rl.DrawText("[ shell exited ]",
			i32(layout.padding_x), i32(y_offset + console_h - 22), 14,
			{0xff, 0x88, 0x88, 0xff})
	}

	gvt.term_render_clean(&con.term)
}
