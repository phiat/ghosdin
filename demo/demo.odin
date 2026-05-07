package demo

// Demo of libghostty-vt Odin bindings.
//
// Creates a virtual terminal, feeds VT escape sequences into it, and
// reads back the resulting state (cursor position, title, cell contents).
//
// Build:
//   odin build demo -out:demo_bin
//
// Requires libghostty-vt to be installed (shared or static library
// discoverable by the system linker).

import "core:fmt"
import "core:c"
import gvt "../vendor/ghostty_vt"

main :: proc() {
	fmt.println("=== ghosdin — libghostty-vt demo ===")
	fmt.println()

	// ---------------------------------------------------------------
	// 1. Create a terminal (80×24, 1000 lines of scrollback)
	// ---------------------------------------------------------------
	term: gvt.Terminal
	opts := gvt.Terminal_Options{cols = 80, rows = 24, max_scrollback = 1000}
	res := gvt.terminal_new(nil, &term, opts)
	if res != .SUCCESS {
		fmt.printfln("terminal_new failed: %v", res)
		return
	}
	defer gvt.terminal_free(term)
	fmt.println("[+] Terminal created (80x24)")

	// ---------------------------------------------------------------
	// 2. Install a write_pty callback so query responses are handled
	// ---------------------------------------------------------------
	write_pty_cb :: proc "c" (terminal: gvt.Terminal, userdata: rawptr, data: [^]u8, len: c.size_t) {
		// In a real app you'd write this back to the PTY.
		// Here we just note that a response was generated.
	}
	// Store at package level to avoid dangling stack pointer
	@(static) write_fn: gvt.Terminal_Write_Pty_Fn
	write_fn = gvt.Terminal_Write_Pty_Fn(write_pty_cb)
	gvt.terminal_set(term, .WRITE_PTY, rawptr(&write_fn))

	// ---------------------------------------------------------------
	// 3. Feed some VT data
	// ---------------------------------------------------------------

	// Set title via OSC 2
	feed(term, "\x1b]2;Hello from Odin!\x07")

	// Print some styled text
	feed(term, "\x1b[1;32mBold green text\x1b[0m  ")
	feed(term, "\x1b[4;31mUnderlined red\x1b[0m\r\n")
	feed(term, "Second line of text\r\n")
	feed(term, "Third line — cursor is here")

	fmt.println("[+] VT data written")
	fmt.println()

	// ---------------------------------------------------------------
	// 4. Query terminal state
	// ---------------------------------------------------------------

	cols: u16
	rows: u16
	cursor_x: u16
	cursor_y: u16
	gvt.terminal_get(term, .COLS, &cols)
	gvt.terminal_get(term, .ROWS, &rows)
	gvt.terminal_get(term, .CURSOR_X, &cursor_x)
	gvt.terminal_get(term, .CURSOR_Y, &cursor_y)
	fmt.printfln("  Terminal size: %vx%v", cols, rows)
	fmt.printfln("  Cursor pos:   (%v, %v)", cursor_x, cursor_y)

	title: gvt.String
	if gvt.terminal_get(term, .TITLE, &title) == .SUCCESS && title.len > 0 {
		title_str := string(title.ptr[:title.len])
		fmt.printfln("  Title:        \"%s\"", title_str)
	}

	active_screen: gvt.Terminal_Screen
	gvt.terminal_get(term, .ACTIVE_SCREEN, &active_screen)
	fmt.printfln("  Screen:       %v", active_screen)

	fmt.println()

	// ---------------------------------------------------------------
	// 5. Read cells from the first row via grid_ref
	// ---------------------------------------------------------------
	fmt.println("  Row 0 contents:")
	fmt.print("    ")

	buf: [16]u32
	for x: u16 = 0; x < cols; x += 1 {
		pt := gvt.Point{
			tag = .ACTIVE,
			value = {coordinate = {x = x, y = 0}},
		}
		ref := gvt.Grid_Ref{size = size_of(gvt.Grid_Ref)}
		if gvt.terminal_grid_ref(term, pt, &ref) != .SUCCESS {
			break
		}

		out_len: c.size_t
		gr_res := gvt.grid_ref_graphemes(&ref, raw_data(&buf), c.size_t(len(buf)), &out_len)
		if gr_res == .SUCCESS && out_len > 0 {
			cp := buf[0]
			if cp >= 32 && cp < 127 {
				fmt.printf("%c", rune(cp))
			}
		} else {
			fmt.print(" ")
		}
	}
	fmt.println()
	fmt.println()

	// ---------------------------------------------------------------
	// 6. Check a terminal mode
	// ---------------------------------------------------------------
	wrap_enabled: bool
	if gvt.terminal_mode_get(term, gvt.MODE_WRAPAROUND, &wrap_enabled) == .SUCCESS {
		fmt.printfln("  Wraparound mode: %v", wrap_enabled)
	}

	// ---------------------------------------------------------------
	// 7. Build info
	// ---------------------------------------------------------------
	simd_enabled: bool
	if gvt.build_info(.SIMD, &simd_enabled) == .SUCCESS {
		fmt.printfln("  SIMD enabled:    %v", simd_enabled)
	}

	version: gvt.String
	if gvt.build_info(.VERSION_STRING, &version) == .SUCCESS && version.len > 0 {
		fmt.printfln("  libghostty-vt:   %s", string(version.ptr[:version.len]))
	}

	fmt.println()
	fmt.println("=== done ===")
}

// Helper to feed a string as VT data.
feed :: proc(term: gvt.Terminal, data: string) {
	gvt.terminal_vt_write(term, raw_data(data), len(data))
}
