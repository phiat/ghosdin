package render_rl

// Shared raylib rendering helpers for ghosdin's terminal targets.
// Used by both `termview` and `console`; nothing here is target-specific.

import gvt "../vendor/ghostty_vt"
import rl "vendor:raylib"

// ---------------------------------------------------------------------------
// Color + text helpers
// ---------------------------------------------------------------------------

to_rl_color :: #force_inline proc "contextless" (c: gvt.Color_Rgb) -> rl.Color {
	return {c.r, c.g, c.b, 0xff}
}

// Encode a single codepoint as UTF-8. Returns the number of bytes written.
encode_utf8 :: proc "contextless" (buf: []u8, cp: rune) -> int {
	v := u32(cp)
	switch {
	case v < 0x80:
		buf[0] = u8(v)
		return 1
	case v < 0x800:
		buf[0] = u8(0xC0 | (v >> 6))
		buf[1] = u8(0x80 | (v & 0x3F))
		return 2
	case v < 0x10000:
		buf[0] = u8(0xE0 | (v >> 12))
		buf[1] = u8(0x80 | ((v >> 6) & 0x3F))
		buf[2] = u8(0x80 | (v & 0x3F))
		return 3
	case:
		buf[0] = u8(0xF0 | (v >> 18))
		buf[1] = u8(0x80 | ((v >> 12) & 0x3F))
		buf[2] = u8(0x80 | ((v >> 6) & 0x3F))
		buf[3] = u8(0x80 | (v & 0x3F))
		return 4
	}
}

// ---------------------------------------------------------------------------
// Font loading
// ---------------------------------------------------------------------------

DEFAULT_MONO_FONTS :: []cstring{
	"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
	"/usr/share/fonts/TTF/DejaVuSansMono.ttf",
	"/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
	"/Library/Fonts/Menlo.ttc",
	"/System/Library/Fonts/Menlo.ttc",
}

// Load a monospace font, probing standard locations first.
// `owned` is true when raylib loaded a TTF and the caller must `UnloadFont`;
// false when we fell back to the raylib default (do not unload).
load_mono_font :: proc(size: i32, override_paths: []cstring = nil) -> (font: rl.Font, owned: bool) {
	paths := override_paths
	if len(paths) == 0 do paths = DEFAULT_MONO_FONTS
	for path in paths {
		f := rl.LoadFontEx(path, size, nil, 0)
		if f.texture.id != 0 do return f, true
	}
	return rl.GetFontDefault(), false
}

// ---------------------------------------------------------------------------
// Cell rendering
// ---------------------------------------------------------------------------

Cell_Layout :: struct {
	cell_w:    f32,
	cell_h:    f32,
	padding_x: f32,
	padding_y: f32,
	y_offset:  f32, // shift applied to every cell (used by the dropdown console)
	font_size: f32,
}

// Render one resolved cell. Caller drives the row/cell iterators and supplies
// the row index plus terminal default colors; this proc handles bg fill, text,
// underline, strikethrough, and bold brightening uniformly across consumers.
draw_cell :: proc(
	font: rl.Font,
	row: u16,
	cell: gvt.Render_Cell,
	default_fg: gvt.Color_Rgb,
	layout: Cell_Layout,
) {
	px := f32(cell.col) * layout.cell_w + layout.padding_x
	py := f32(row) * layout.cell_h + layout.padding_y + layout.y_offset

	if py + layout.cell_h < 0 do return

	if cell.has_bg {
		rl.DrawRectangle(i32(px), i32(py), i32(layout.cell_w), i32(layout.cell_h),
			to_rl_color(cell.bg_color))
	}

	if !cell.has_text || cell.codepoint == 0 || cell.codepoint < 32 do return

	fg: rl.Color
	if cell.has_fg {
		fg = to_rl_color(cell.fg_color)
	} else {
		fg = to_rl_color(default_fg)
	}

	if cell.style.bold {
		fg.r = u8(min(255, int(fg.r) + 40))
		fg.g = u8(min(255, int(fg.g) + 40))
		fg.b = u8(min(255, int(fg.b) + 40))
	}

	if cell.style.underline != 0 {
		y := i32(py + layout.cell_h - 1)
		rl.DrawLine(i32(px), y, i32(px + layout.cell_w), y, fg)
	}

	if cell.style.strikethrough {
		y := i32(py + layout.cell_h * 0.5)
		rl.DrawLine(i32(px), y, i32(px + layout.cell_w), y, fg)
	}

	rl.DrawTextCodepoint(font, cell.codepoint, {px, py}, layout.font_size, fg)
}

// ---------------------------------------------------------------------------
// Keyboard → VT escape sequences
// ---------------------------------------------------------------------------

// Map a non-printable raylib key to its VT/xterm escape sequence.
// Returns "" for keys that don't translate (printable chars, modifiers, etc.).
key_to_vt_sequence :: proc "contextless" (key: rl.KeyboardKey) -> string {
	#partial switch key {
	case .ENTER:     return "\r"
	case .BACKSPACE: return "\x7f"
	case .TAB:       return "\t"
	case .ESCAPE:    return "\x1b"
	case .UP:        return "\x1b[A"
	case .DOWN:      return "\x1b[B"
	case .RIGHT:     return "\x1b[C"
	case .LEFT:      return "\x1b[D"
	case .HOME:      return "\x1b[H"
	case .END:       return "\x1b[F"
	case .PAGE_UP:   return "\x1b[5~"
	case .PAGE_DOWN: return "\x1b[6~"
	case .INSERT:    return "\x1b[2~"
	case .DELETE:    return "\x1b[3~"
	case .F1:        return "\x1bOP"
	case .F2:        return "\x1bOQ"
	case .F3:        return "\x1bOR"
	case .F4:        return "\x1bOS"
	case .F5:        return "\x1b[15~"
	case .F6:        return "\x1b[17~"
	case .F7:        return "\x1b[18~"
	case .F8:        return "\x1b[19~"
	case .F9:        return "\x1b[20~"
	case .F10:       return "\x1b[21~"
	case .F11:       return "\x1b[23~"
	case .F12:       return "\x1b[24~"
	}
	return ""
}

// Map a key + ctrl modifier to an ASCII control byte (Ctrl-A..Ctrl-Z → 0x01..0x1A).
// Returns (0, false) if the key isn't an A–Z letter.
ctrl_byte :: proc "contextless" (key: rl.KeyboardKey) -> (b: u8, ok: bool) {
	ki := int(key)
	if ki >= int(rl.KeyboardKey.A) && ki <= int(rl.KeyboardKey.Z) {
		return u8(ki - int(rl.KeyboardKey.A) + 1), true
	}
	return 0, false
}
