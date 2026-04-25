package ghostty_vt

// Idiomatic Odin wrapper layer over the raw libghostty-vt C bindings.
// Provides Odin-style iterators, union types, error handling, and RAII.

import "base:runtime"
import "core:c"
import "core:mem"

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------

Error :: enum {
	None,
	Out_Of_Memory,
	Invalid_Value,
	Out_Of_Space,
}

to_error :: proc(r: Result) -> Error {
	switch r {
	case .SUCCESS:       return .None
	case .OUT_OF_MEMORY: return .Out_Of_Memory
	case .INVALID_VALUE: return .Invalid_Value
	case .OUT_OF_SPACE:  return .Out_Of_Space
	}
	return .Invalid_Value
}

// ---------------------------------------------------------------------------
// Term — high-level terminal handle
// ---------------------------------------------------------------------------

// Heap-pinned bridge from a libghostty-vt `Allocator` into an Odin
// `mem.Allocator`. Pointed at by C; must outlive the Term.
@(private)
Term_Allocator :: struct {
	odin:   mem.Allocator,
	vtable: Allocator_Vtable,
	handle: Allocator,
}

Term :: struct {
	handle:      Terminal,
	_render:     Render_State,
	_row_iter:   Render_State_Row_Iterator,
	_row_cells:  Render_State_Row_Cells,
	_has_render: bool,
	_alloc:      ^Term_Allocator,
}

// libghostty-vt follows the Zig allocator convention: `alignment` is the
// log2 of the actual byte alignment (0 → 1, 3 → 8, etc.).
@(private)
_align_bytes :: #force_inline proc "contextless" (log2_align: u8) -> int {
	return 1 << uint(log2_align)
}

@(private)
_bridge_alloc :: proc "c" (ctx: rawptr, n: c.size_t, alignment: u8, _: c.uintptr_t) -> rawptr {
	context = runtime.default_context()
	b := cast(^Term_Allocator)ctx
	context.allocator = b.odin
	if n == 0 do return nil
	p, err := mem.alloc(int(n), _align_bytes(alignment))
	if err != .None do return nil
	return p
}

@(private)
_bridge_resize :: proc "c" (ctx: rawptr, ptr: rawptr, old_len: c.size_t, alignment: u8, new_len: c.size_t, _: c.uintptr_t) -> bool {
	context = runtime.default_context()
	b := cast(^Term_Allocator)ctx
	context.allocator = b.odin
	if new_len == 0 do return true
	p, err := mem.resize(ptr, int(old_len), int(new_len), _align_bytes(alignment))
	return err == .None && p == ptr
}

@(private)
_bridge_remap :: proc "c" (ctx: rawptr, ptr: rawptr, old_len: c.size_t, alignment: u8, new_len: c.size_t, _: c.uintptr_t) -> rawptr {
	context = runtime.default_context()
	b := cast(^Term_Allocator)ctx
	context.allocator = b.odin
	if new_len == 0 do return nil
	p, err := mem.resize(ptr, int(old_len), int(new_len), _align_bytes(alignment))
	if err != .None do return nil
	return p
}

@(private)
_bridge_free :: proc "c" (ctx: rawptr, ptr: rawptr, n: c.size_t, _: u8, _: c.uintptr_t) {
	context = runtime.default_context()
	b := cast(^Term_Allocator)ctx
	context.allocator = b.odin
	if ptr == nil do return
	mem.free_with_size(ptr, int(n))
}

@(private)
_make_term_allocator :: proc(odin_alloc: mem.Allocator) -> ^Term_Allocator {
	b := new(Term_Allocator, odin_alloc)
	b.odin   = odin_alloc
	b.vtable = Allocator_Vtable{
		alloc  = _bridge_alloc,
		resize = _bridge_resize,
		remap  = _bridge_remap,
		free   = _bridge_free,
	}
	b.handle = Allocator{ctx = b, vtable = &b.vtable}
	return b
}

// Create a new terminal. Allocations performed by libghostty-vt for this
// terminal (and its render state) are routed through `allocator`, so
// tracking allocators see them.
term_init :: proc(cols: u16, rows: u16, max_scrollback: uint = 10000, allocator := context.allocator) -> (Term, Error) {
	t: Term
	t._alloc = _make_term_allocator(allocator)
	opts := Terminal_Options{
		cols           = cols,
		rows           = rows,
		max_scrollback = c.size_t(max_scrollback),
	}
	res := terminal_new(&t._alloc.handle, &t.handle, opts)
	if res != .SUCCESS {
		mem.free(t._alloc, allocator)
		return {}, to_error(res)
	}
	return t, .None
}

// Destroy a terminal and all associated resources.
term_destroy :: proc(t: ^Term) {
	if t._has_render {
		render_state_row_cells_free(t._row_cells)
		render_state_row_iterator_free(t._row_iter)
		render_state_free(t._render)
	}
	terminal_free(t.handle)
	t.handle = nil
	if t._alloc != nil {
		mem.free(t._alloc, t._alloc.odin)
		t._alloc = nil
	}
}

// Feed raw VT data into the terminal.
term_write :: proc(t: ^Term, data: string) {
	if len(data) == 0 do return
	terminal_vt_write(t.handle, raw_data(data), c.size_t(len(data)))
}

// Feed raw bytes into the terminal.
term_write_bytes :: proc(t: ^Term, data: []u8) {
	if len(data) == 0 do return
	terminal_vt_write(t.handle, raw_data(data), c.size_t(len(data)))
}

// Reset the terminal (RIS).
term_reset :: proc(t: ^Term) {
	terminal_reset(t.handle)
}

// Resize the terminal.
term_resize :: proc(t: ^Term, cols: u16, rows: u16, cell_w_px: u32 = 0, cell_h_px: u32 = 0) -> Error {
	return to_error(terminal_resize(t.handle, cols, rows, cell_w_px, cell_h_px))
}

// Set a callback / option on the terminal.
term_set :: proc(t: ^Term, option: Terminal_Option, value: rawptr) -> Error {
	return to_error(terminal_set(t.handle, option, value))
}

// Scroll the viewport.
term_scroll_top :: proc(t: ^Term) {
	terminal_scroll_viewport(t.handle, {tag = .TOP})
}

term_scroll_bottom :: proc(t: ^Term) {
	terminal_scroll_viewport(t.handle, {tag = .BOTTOM})
}

term_scroll_delta :: proc(t: ^Term, delta: int) {
	sv := Terminal_Scroll_Viewport{
		tag   = .DELTA,
		value = {delta = c.intptr_t(delta)},
	}
	terminal_scroll_viewport(t.handle, sv)
}

// ---------------------------------------------------------------------------
// Terminal state queries — typed getters
// ---------------------------------------------------------------------------

term_cols :: proc(t: ^Term) -> u16 {
	v: u16
	terminal_get(t.handle, .COLS, &v)
	return v
}

term_rows :: proc(t: ^Term) -> u16 {
	v: u16
	terminal_get(t.handle, .ROWS, &v)
	return v
}

term_cursor_x :: proc(t: ^Term) -> u16 {
	v: u16
	terminal_get(t.handle, .CURSOR_X, &v)
	return v
}

term_cursor_y :: proc(t: ^Term) -> u16 {
	v: u16
	terminal_get(t.handle, .CURSOR_Y, &v)
	return v
}

term_cursor_visible :: proc(t: ^Term) -> bool {
	v: bool
	terminal_get(t.handle, .CURSOR_VISIBLE, &v)
	return v
}

term_title :: proc(t: ^Term) -> string {
	s: String
	if terminal_get(t.handle, .TITLE, &s) != .SUCCESS do return ""
	if s.len == 0 do return ""
	return string(s.ptr[:s.len])
}

term_pwd :: proc(t: ^Term) -> string {
	s: String
	if terminal_get(t.handle, .PWD, &s) != .SUCCESS do return ""
	if s.len == 0 do return ""
	return string(s.ptr[:s.len])
}

term_active_screen :: proc(t: ^Term) -> Terminal_Screen {
	v: Terminal_Screen
	terminal_get(t.handle, .ACTIVE_SCREEN, &v)
	return v
}

term_mouse_tracking :: proc(t: ^Term) -> bool {
	v: bool
	terminal_get(t.handle, .MOUSE_TRACKING, &v)
	return v
}

term_scrollbar :: proc(t: ^Term) -> Terminal_Scrollbar {
	v: Terminal_Scrollbar
	terminal_get(t.handle, .SCROLLBAR, &v)
	return v
}

term_total_rows :: proc(t: ^Term) -> uint {
	v: c.size_t
	terminal_get(t.handle, .TOTAL_ROWS, &v)
	return uint(v)
}

// ---------------------------------------------------------------------------
// Mode queries
// ---------------------------------------------------------------------------

term_mode_get :: proc(t: ^Term, mode: Mode) -> bool {
	v: bool
	terminal_mode_get(t.handle, mode, &v)
	return v
}

term_mode_set :: proc(t: ^Term, mode: Mode, value: bool) -> Error {
	return to_error(terminal_mode_set(t.handle, mode, value))
}

// ---------------------------------------------------------------------------
// Grid cell access
// ---------------------------------------------------------------------------

// Information about a single cell, resolved from the grid.
Cell_Info :: struct {
	codepoint:    rune,
	has_text:     bool,
	wide:         Cell_Wide,
	style:        Style,
	content_tag:  Cell_Content_Tag,
	semantic:     Cell_Semantic_Content,
}

// Look up a cell at (x, y) in the active area.
term_cell_at :: proc(t: ^Term, x: u16, y: u16) -> (Cell_Info, Error) {
	pt := Point{
		tag   = .ACTIVE,
		value = {coordinate = {x = x, y = u32(y)}},
	}
	ref := Grid_Ref{size = size_of(Grid_Ref)}
	res := terminal_grid_ref(t.handle, pt, &ref)
	if res != .SUCCESS do return {}, to_error(res)

	info: Cell_Info

	raw_cell: Cell
	if grid_ref_cell(&ref, &raw_cell) == .SUCCESS {
		cp: u32
		cell_get(raw_cell, .CODEPOINT, &cp)
		info.codepoint = rune(cp)

		cell_get(raw_cell, .HAS_TEXT, &info.has_text)
		cell_get(raw_cell, .WIDE, &info.wide)
		cell_get(raw_cell, .CONTENT_TAG, &info.content_tag)
		cell_get(raw_cell, .SEMANTIC_CONTENT, &info.semantic)
	}

	info.style.size = size_of(Style)
	grid_ref_style(&ref, &info.style)

	return info, .None
}

// Get the full grapheme cluster at (x, y).
term_grapheme_at :: proc(t: ^Term, x: u16, y: u16, buf: []u32) -> ([]u32, Error) {
	pt := Point{
		tag   = .ACTIVE,
		value = {coordinate = {x = x, y = u32(y)}},
	}
	ref := Grid_Ref{size = size_of(Grid_Ref)}
	res := terminal_grid_ref(t.handle, pt, &ref)
	if res != .SUCCESS do return nil, to_error(res)

	out_len: c.size_t
	res = grid_ref_graphemes(&ref, raw_data(buf), c.size_t(len(buf)), &out_len)
	if res != .SUCCESS do return nil, to_error(res)

	return buf[:out_len], .None
}

// ---------------------------------------------------------------------------
// Row iteration (for-in compatible)
// ---------------------------------------------------------------------------

// Iterate over all cells in a row, yielding (col, codepoint, style).
Row_Cell :: struct {
	col:       u16,
	codepoint: rune,
	has_text:  bool,
	wide:      Cell_Wide,
	style:     Style,
}

// ---------------------------------------------------------------------------
// Render state helpers
// ---------------------------------------------------------------------------

// Ensure the render state objects are allocated.
term_ensure_render :: proc(t: ^Term) -> Error {
	if t._has_render do return .None

	a := t._alloc != nil ? &t._alloc.handle : nil
	res := render_state_new(a, &t._render)
	if res != .SUCCESS do return to_error(res)

	res = render_state_row_iterator_new(a, &t._row_iter)
	if res != .SUCCESS {
		render_state_free(t._render)
		return to_error(res)
	}

	res = render_state_row_cells_new(a, &t._row_cells)
	if res != .SUCCESS {
		render_state_row_iterator_free(t._row_iter)
		render_state_free(t._render)
		return to_error(res)
	}

	t._has_render = true
	return .None
}

// Sync render state from terminal.
term_render_update :: proc(t: ^Term) -> Error {
	if err := term_ensure_render(t); err != .None do return err
	return to_error(render_state_update(t._render, t.handle))
}

// Get render colors.
term_render_colors :: proc(t: ^Term) -> (Render_State_Colors, Error) {
	if err := term_ensure_render(t); err != .None do return {}, err
	colors := Render_State_Colors{size = size_of(Render_State_Colors)}
	res := render_state_colors_get(t._render, &colors)
	return colors, to_error(res)
}

// Render cursor info.
Cursor_Info :: struct {
	x:          u16,
	y:          u16,
	visible:    bool,
	in_viewport: bool,
	blinking:   bool,
	style:      Render_State_Cursor_Visual_Style,
}

term_render_cursor :: proc(t: ^Term) -> Cursor_Info {
	if !t._has_render do return {}
	info: Cursor_Info
	render_state_get(t._render, .CURSOR_VISIBLE, &info.visible)
	render_state_get(t._render, .CURSOR_VIEWPORT_HAS_VALUE, &info.in_viewport)
	render_state_get(t._render, .CURSOR_VIEWPORT_X, &info.x)
	render_state_get(t._render, .CURSOR_VIEWPORT_Y, &info.y)
	render_state_get(t._render, .CURSOR_BLINKING, &info.blinking)
	render_state_get(t._render, .CURSOR_VISUAL_STYLE, &info.style)
	return info
}

// Reset render dirty state.
term_render_clean :: proc(t: ^Term) {
	if !t._has_render do return

	dirty_false := Render_State_Dirty.FALSE
	render_state_set(t._render, .DIRTY, &dirty_false)

	render_state_get(t._render, .ROW_ITERATOR, &t._row_iter)
	for render_state_row_iterator_next(t._row_iter) {
		dirty_val := false
		render_state_row_set(t._row_iter, .DIRTY, &dirty_val)
	}
}

// ---------------------------------------------------------------------------
// Render iteration — for use in draw loops
// ---------------------------------------------------------------------------

// Call this to iterate render rows. Use with for loop:
//   term_render_update(&t)
//   for row_idx in term_render_rows(&t) { ... }
Render_Row_Iterator :: struct {
	term:    ^Term,
	row_idx: u16,
}

term_render_rows :: proc(t: ^Term) -> Render_Row_Iterator {
	render_state_get(t._render, .ROW_ITERATOR, &t._row_iter)
	return Render_Row_Iterator{term = t, row_idx = 0}
}

render_row_next :: proc(it: ^Render_Row_Iterator) -> (row: u16, ok: bool) {
	if !render_state_row_iterator_next(it.term._row_iter) do return 0, false
	render_state_row_get(it.term._row_iter, .CELLS, &it.term._row_cells)
	row = it.row_idx
	it.row_idx += 1
	return row, true
}

// Iterate cells within the current render row.
Render_Cell_Iterator :: struct {
	term:    ^Term,
	col_idx: u16,
}

term_render_cells :: proc(t: ^Term) -> Render_Cell_Iterator {
	return Render_Cell_Iterator{term = t, col_idx = 0}
}

// Resolved cell data from the render state.
Render_Cell :: struct {
	col:       u16,
	codepoint: rune,
	has_text:  bool,
	wide:      Cell_Wide,
	style:     Style,
	fg_color:  Color_Rgb,
	bg_color:  Color_Rgb,
	has_fg:    bool,
	has_bg:    bool,
}

render_cell_next :: proc(it: ^Render_Cell_Iterator) -> (cell: Render_Cell, ok: bool) {
	if !render_state_row_cells_next(it.term._row_cells) do return {}, false

	cell.col = it.col_idx
	it.col_idx += 1

	// Raw cell for basic info
	raw: Cell
	render_state_row_cells_get(it.term._row_cells, .RAW, &raw)
	cell_get(raw, .HAS_TEXT, &cell.has_text)
	if cell.has_text {
		cp: u32
		cell_get(raw, .CODEPOINT, &cp)
		cell.codepoint = rune(cp)
	}
	cell_get(raw, .WIDE, &cell.wide)

	// Style
	cell.style.size = size_of(Style)
	render_state_row_cells_get(it.term._row_cells, .STYLE, &cell.style)

	// Colors
	cell.has_fg = render_state_row_cells_get(it.term._row_cells, .FG_COLOR, &cell.fg_color) == .SUCCESS
	cell.has_bg = render_state_row_cells_get(it.term._row_cells, .BG_COLOR, &cell.bg_color) == .SUCCESS

	return cell, true
}

// ---------------------------------------------------------------------------
// Formatter helpers
// ---------------------------------------------------------------------------

// Run libghostty-vt's formatter and copy the result into the caller's allocator.
// The C-side buffer is freed before returning, so the caller owns a normal
// Odin slice releasable with `delete`.
term_format :: proc(t: ^Term, emit: Formatter_Format, trim: bool, allocator := context.allocator) -> ([]u8, Error) {
	opts := Formatter_Terminal_Options{
		size = size_of(Formatter_Terminal_Options),
		emit = emit,
		trim = trim,
	}
	fmtr: Formatter
	res := formatter_terminal_new(nil, &fmtr, t.handle, opts)
	if res != .SUCCESS do return nil, to_error(res)
	defer formatter_free(fmtr)

	out_ptr: [^]u8
	out_len: c.size_t
	res = formatter_format_alloc(fmtr, nil, &out_ptr, &out_len)
	if res != .SUCCESS do return nil, to_error(res)
	defer free(nil, out_ptr, out_len)

	if out_len == 0 do return nil, .None

	owned, err := mem.make_aligned([]u8, int(out_len), 1, allocator)
	if err != .None do return nil, .Out_Of_Memory
	mem.copy(raw_data(owned), out_ptr, int(out_len))
	return owned, .None
}

// Format terminal contents as plain text. Returns a slice owned by `allocator`
// (defaults to the context allocator); release with `delete`.
term_format_plain :: proc(t: ^Term, trim: bool = true, allocator := context.allocator) -> ([]u8, Error) {
	return term_format(t, .PLAIN, trim, allocator)
}

// Format terminal contents as HTML. Returns a slice owned by `allocator`
// (defaults to the context allocator); release with `delete`.
term_format_html :: proc(t: ^Term, allocator := context.allocator) -> ([]u8, Error) {
	return term_format(t, .HTML, true, allocator)
}
