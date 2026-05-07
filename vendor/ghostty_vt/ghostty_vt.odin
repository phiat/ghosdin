package ghostty_vt

// Odin bindings for libghostty-vt — the zero-dependency VT terminal
// parser/state library from the Ghostty project.
//
// See: https://github.com/ghostty-org/ghostty

import "core:c"

// ---------------------------------------------------------------------------
// Foreign library import
// ---------------------------------------------------------------------------

when ODIN_OS == .Linux {
	foreign import lib {
		"system:ghostty-vt",
	}
} else when ODIN_OS == .Darwin {
	foreign import lib {
		"system:ghostty-vt",
	}
} else when ODIN_OS == .Windows {
	foreign import lib {
		"ghostty-vt.lib",
	}
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

Result :: enum c.int {
	SUCCESS        =  0,
	OUT_OF_MEMORY  = -1,
	INVALID_VALUE  = -2,
	OUT_OF_SPACE   = -3,
	NO_VALUE       = -4,
}

// ---------------------------------------------------------------------------
// String (borrowed byte slice)
// ---------------------------------------------------------------------------

String :: struct {
	ptr: [^]u8,
	len: c.size_t,
}

// ---------------------------------------------------------------------------
// Color
// ---------------------------------------------------------------------------

Color_Rgb :: struct {
	r: u8,
	g: u8,
	b: u8,
}

Color_Palette_Index :: u8

// Named color constants
COLOR_NAMED_BLACK          :: Color_Palette_Index(0)
COLOR_NAMED_RED            :: Color_Palette_Index(1)
COLOR_NAMED_GREEN          :: Color_Palette_Index(2)
COLOR_NAMED_YELLOW         :: Color_Palette_Index(3)
COLOR_NAMED_BLUE           :: Color_Palette_Index(4)
COLOR_NAMED_MAGENTA        :: Color_Palette_Index(5)
COLOR_NAMED_CYAN           :: Color_Palette_Index(6)
COLOR_NAMED_WHITE          :: Color_Palette_Index(7)
COLOR_NAMED_BRIGHT_BLACK   :: Color_Palette_Index(8)
COLOR_NAMED_BRIGHT_RED     :: Color_Palette_Index(9)
COLOR_NAMED_BRIGHT_GREEN   :: Color_Palette_Index(10)
COLOR_NAMED_BRIGHT_YELLOW  :: Color_Palette_Index(11)
COLOR_NAMED_BRIGHT_BLUE    :: Color_Palette_Index(12)
COLOR_NAMED_BRIGHT_MAGENTA :: Color_Palette_Index(13)
COLOR_NAMED_BRIGHT_CYAN    :: Color_Palette_Index(14)
COLOR_NAMED_BRIGHT_WHITE   :: Color_Palette_Index(15)

// ---------------------------------------------------------------------------
// Allocator
// ---------------------------------------------------------------------------

Allocator_Vtable :: struct {
	alloc:  #type proc "c" (ctx: rawptr, len: c.size_t, alignment: u8, ret_addr: c.uintptr_t) -> rawptr,
	resize: #type proc "c" (ctx: rawptr, memory: rawptr, memory_len: c.size_t, alignment: u8, new_len: c.size_t, ret_addr: c.uintptr_t) -> bool,
	remap:  #type proc "c" (ctx: rawptr, memory: rawptr, memory_len: c.size_t, alignment: u8, new_len: c.size_t, ret_addr: c.uintptr_t) -> rawptr,
	free:   #type proc "c" (ctx: rawptr, memory: rawptr, memory_len: c.size_t, alignment: u8, ret_addr: c.uintptr_t),
}

Allocator :: struct {
	ctx:    rawptr,
	vtable: ^Allocator_Vtable,
}

// ---------------------------------------------------------------------------
// Style
// ---------------------------------------------------------------------------

Style_Id :: u16

Style_Color_Tag :: enum c.int {
	NONE    = 0,
	PALETTE = 1,
	RGB     = 2,
}

Style_Color_Value :: struct #raw_union {
	palette:  Color_Palette_Index,
	rgb:      Color_Rgb,
	_padding: u64,
}

Style_Color :: struct {
	tag:   Style_Color_Tag,
	value: Style_Color_Value,
}

Style :: struct {
	size:             c.size_t,
	fg_color:         Style_Color,
	bg_color:         Style_Color,
	underline_color:  Style_Color,
	bold:             bool,
	italic:           bool,
	faint:            bool,
	blink:            bool,
	inverse:          bool,
	invisible:        bool,
	strikethrough:    bool,
	overline:         bool,
	underline:        c.int, // Sgr_Underline value
}

// ---------------------------------------------------------------------------
// SGR
// ---------------------------------------------------------------------------

Sgr_Underline :: enum c.int {
	NONE   = 0,
	SINGLE = 1,
	DOUBLE = 2,
	CURLY  = 3,
	DOTTED = 4,
	DASHED = 5,
}

Sgr_Parser :: distinct rawptr

Sgr_Attribute_Tag :: enum c.int {
	UNSET                  = 0,
	UNKNOWN                = 1,
	BOLD                   = 2,
	RESET_BOLD             = 3,
	ITALIC                 = 4,
	RESET_ITALIC           = 5,
	FAINT                  = 6,
	UNDERLINE              = 7,
	UNDERLINE_COLOR        = 8,
	UNDERLINE_COLOR_256    = 9,
	RESET_UNDERLINE_COLOR  = 10,
	OVERLINE               = 11,
	RESET_OVERLINE         = 12,
	BLINK                  = 13,
	RESET_BLINK            = 14,
	INVERSE                = 15,
	RESET_INVERSE          = 16,
	INVISIBLE              = 17,
	RESET_INVISIBLE        = 18,
	STRIKETHROUGH          = 19,
	RESET_STRIKETHROUGH    = 20,
	DIRECT_COLOR_FG        = 21,
	DIRECT_COLOR_BG        = 22,
	BG_8                   = 23,
	FG_8                   = 24,
	RESET_FG               = 25,
	RESET_BG               = 26,
	BRIGHT_BG_8            = 27,
	BRIGHT_FG_8            = 28,
	BG_256                 = 29,
	FG_256                 = 30,
}

Sgr_Unknown :: struct {
	full_ptr:    [^]u16,
	full_len:    c.size_t,
	partial_ptr: [^]u16,
	partial_len: c.size_t,
}

Sgr_Attribute_Value :: struct #raw_union {
	unknown:              Sgr_Unknown,
	underline:            Sgr_Underline,
	underline_color:      Color_Rgb,
	underline_color_256:  Color_Palette_Index,
	direct_color_fg:      Color_Rgb,
	direct_color_bg:      Color_Rgb,
	bg_8:                 Color_Palette_Index,
	fg_8:                 Color_Palette_Index,
	bright_bg_8:          Color_Palette_Index,
	bright_fg_8:          Color_Palette_Index,
	bg_256:               Color_Palette_Index,
	fg_256:               Color_Palette_Index,
	_padding:             [8]u64,
}

Sgr_Attribute :: struct {
	tag:   Sgr_Attribute_Tag,
	value: Sgr_Attribute_Value,
}

// ---------------------------------------------------------------------------
// Point
// ---------------------------------------------------------------------------

Point_Coordinate :: struct {
	x: u16,
	y: u32,
}

Point_Tag :: enum c.int {
	ACTIVE   = 0,
	VIEWPORT = 1,
	SCREEN   = 2,
	HISTORY  = 3,
}

Point_Value :: struct #raw_union {
	coordinate: Point_Coordinate,
	_padding:   [2]u64,
}

Point :: struct {
	tag:   Point_Tag,
	value: Point_Value,
}

// ---------------------------------------------------------------------------
// Screen (Cell / Row)
// ---------------------------------------------------------------------------

Cell :: u64
Row  :: u64

Cell_Content_Tag :: enum c.int {
	CODEPOINT          = 0,
	CODEPOINT_GRAPHEME = 1,
	BG_COLOR_PALETTE   = 2,
	BG_COLOR_RGB       = 3,
}

Cell_Wide :: enum c.int {
	NARROW      = 0,
	WIDE        = 1,
	SPACER_TAIL = 2,
	SPACER_HEAD = 3,
}

Cell_Semantic_Content :: enum c.int {
	OUTPUT = 0,
	INPUT  = 1,
	PROMPT = 2,
}

Cell_Data :: enum c.int {
	INVALID          = 0,
	CODEPOINT        = 1,
	CONTENT_TAG      = 2,
	WIDE             = 3,
	HAS_TEXT         = 4,
	HAS_STYLING      = 5,
	STYLE_ID         = 6,
	HAS_HYPERLINK    = 7,
	PROTECTED        = 8,
	SEMANTIC_CONTENT = 9,
	COLOR_PALETTE    = 10,
	COLOR_RGB        = 11,
}

Row_Semantic_Prompt :: enum c.int {
	NONE                = 0,
	PROMPT              = 1,
	PROMPT_CONTINUATION = 2,
}

Row_Data :: enum c.int {
	INVALID                     = 0,
	WRAP                        = 1,
	WRAP_CONTINUATION           = 2,
	GRAPHEME                    = 3,
	STYLED                      = 4,
	HYPERLINK                   = 5,
	SEMANTIC_PROMPT             = 6,
	KITTY_VIRTUAL_PLACEHOLDER   = 7,
	DIRTY                       = 8,
}

// ---------------------------------------------------------------------------
// Grid Reference
// ---------------------------------------------------------------------------

Grid_Ref :: struct {
	size: c.size_t,
	node: rawptr,
	x:    u16,
	y:    u16,
}

// ---------------------------------------------------------------------------
// Modes
// ---------------------------------------------------------------------------

Mode :: u16

mode_new :: #force_inline proc "contextless" (value: u16, ansi: bool) -> Mode {
	return Mode((value & 0x7FFF) | (u16(ansi) << 15))
}

mode_value :: #force_inline proc "contextless" (mode: Mode) -> u16 {
	return u16(mode) & 0x7FFF
}

mode_ansi :: #force_inline proc "contextless" (mode: Mode) -> bool {
	return (u16(mode) >> 15) != 0
}

// ANSI modes (high bit set marks ANSI vs DEC private)
MODE_KAM      :: Mode(2    | 0x8000)
MODE_INSERT   :: Mode(4    | 0x8000)
MODE_SRM      :: Mode(12   | 0x8000)
MODE_LINEFEED :: Mode(20   | 0x8000)

// DEC private modes
MODE_DECCKM              :: Mode(1)
MODE_132_COLUMN          :: Mode(3)
MODE_SLOW_SCROLL         :: Mode(4)
MODE_REVERSE_COLORS      :: Mode(5)
MODE_ORIGIN              :: Mode(6)
MODE_WRAPAROUND          :: Mode(7)
MODE_AUTOREPEAT          :: Mode(8)
MODE_X10_MOUSE           :: Mode(9)
MODE_CURSOR_BLINKING     :: Mode(12)
MODE_CURSOR_VISIBLE      :: Mode(25)
MODE_ENABLE_MODE_3       :: Mode(40)
MODE_REVERSE_WRAP        :: Mode(45)
MODE_ALT_SCREEN_LEGACY   :: Mode(47)
MODE_KEYPAD_KEYS         :: Mode(66)
MODE_BACKARROW_KEY_MODE  :: Mode(67) // DECBKM
MODE_LEFT_RIGHT_MARGIN   :: Mode(69)
MODE_NORMAL_MOUSE        :: Mode(1000)
MODE_BUTTON_MOUSE        :: Mode(1002)
MODE_ANY_MOUSE           :: Mode(1003)
MODE_FOCUS_EVENT         :: Mode(1004)
MODE_UTF8_MOUSE          :: Mode(1005)
MODE_SGR_MOUSE           :: Mode(1006)
MODE_ALT_SCROLL          :: Mode(1007)
MODE_URXVT_MOUSE         :: Mode(1015)
MODE_SGR_PIXELS_MOUSE    :: Mode(1016)
MODE_NUMLOCK_KEYPAD      :: Mode(1035)
MODE_ALT_ESC_PREFIX      :: Mode(1036)
MODE_ALT_SENDS_ESC       :: Mode(1039)
MODE_REVERSE_WRAP_EXT    :: Mode(1045)
MODE_ALT_SCREEN          :: Mode(1047)
MODE_SAVE_CURSOR         :: Mode(1048)
MODE_ALT_SCREEN_SAVE     :: Mode(1049)
MODE_BRACKETED_PASTE     :: Mode(2004)
MODE_SYNC_OUTPUT         :: Mode(2026)
MODE_GRAPHEME_CLUSTER    :: Mode(2027)
MODE_COLOR_SCHEME_REPORT :: Mode(2031)
MODE_IN_BAND_RESIZE      :: Mode(2048)

Mode_Report_State :: enum c.int {
	NOT_RECOGNIZED     = 0,
	SET                = 1,
	RESET              = 2,
	PERMANENTLY_SET    = 3,
	PERMANENTLY_RESET  = 4,
}

// ---------------------------------------------------------------------------
// Device Attributes
// ---------------------------------------------------------------------------

Color_Scheme :: enum c.int {
	LIGHT = 0,
	DARK  = 1,
}

Device_Attributes_Primary :: struct {
	conformance_level: u16,
	features:          [64]u16,
	num_features:      c.size_t,
}

Device_Attributes_Secondary :: struct {
	device_type:      u16,
	firmware_version: u16,
	rom_cartridge:    u16,
}

Device_Attributes_Tertiary :: struct {
	unit_id: u32,
}

Device_Attributes :: struct {
	primary:   Device_Attributes_Primary,
	secondary: Device_Attributes_Secondary,
	tertiary:  Device_Attributes_Tertiary,
}

// ---------------------------------------------------------------------------
// Size Report
// ---------------------------------------------------------------------------

Size_Report_Style :: enum c.int {
	MODE_2048 = 0,
	CSI_14_T  = 1,
	CSI_16_T  = 2,
	CSI_18_T  = 3,
}

Size_Report_Size :: struct {
	rows:        u16,
	columns:     u16,
	cell_width:  u32,
	cell_height: u32,
}

// ---------------------------------------------------------------------------
// Terminal
// ---------------------------------------------------------------------------

Terminal :: distinct rawptr

Terminal_Options :: struct {
	cols:           u16,
	rows:           u16,
	max_scrollback: c.size_t,
}

Terminal_Scroll_Viewport_Tag :: enum c.int {
	TOP    = 0,
	BOTTOM = 1,
	DELTA  = 2,
}

Terminal_Scroll_Viewport_Value :: struct #raw_union {
	delta:    c.intptr_t,
	_padding: [2]u64,
}

Terminal_Scroll_Viewport :: struct {
	tag:   Terminal_Scroll_Viewport_Tag,
	value: Terminal_Scroll_Viewport_Value,
}

Terminal_Screen :: enum c.int {
	PRIMARY   = 0,
	ALTERNATE = 1,
}

Terminal_Scrollbar :: struct {
	total:  u64,
	offset: u64,
	len:    u64,
}

// Callback types
Terminal_Bell_Fn              :: #type proc "c" (terminal: Terminal, userdata: rawptr)
Terminal_Title_Changed_Fn     :: #type proc "c" (terminal: Terminal, userdata: rawptr)
Terminal_Write_Pty_Fn         :: #type proc "c" (terminal: Terminal, userdata: rawptr, data: [^]u8, len: c.size_t)
Terminal_Color_Scheme_Fn      :: #type proc "c" (terminal: Terminal, userdata: rawptr, out_scheme: ^Color_Scheme) -> bool
Terminal_Device_Attributes_Fn :: #type proc "c" (terminal: Terminal, userdata: rawptr, out_attrs: ^Device_Attributes) -> bool
Terminal_Enquiry_Fn           :: #type proc "c" (terminal: Terminal, userdata: rawptr) -> String
Terminal_Size_Fn              :: #type proc "c" (terminal: Terminal, userdata: rawptr, out_size: ^Size_Report_Size) -> bool
Terminal_Xtversion_Fn         :: #type proc "c" (terminal: Terminal, userdata: rawptr) -> String

Terminal_Option :: enum c.int {
	USERDATA                       = 0,
	WRITE_PTY                      = 1,
	BELL                           = 2,
	ENQUIRY                        = 3,
	XTVERSION                      = 4,
	TITLE_CHANGED                  = 5,
	SIZE                           = 6,
	COLOR_SCHEME                   = 7,
	DEVICE_ATTRIBUTES              = 8,
	TITLE                          = 9,
	PWD                            = 10,
	COLOR_FOREGROUND               = 11,
	COLOR_BACKGROUND               = 12,
	COLOR_CURSOR                   = 13,
	COLOR_PALETTE                  = 14,
	KITTY_IMAGE_STORAGE_LIMIT      = 15,
	KITTY_IMAGE_MEDIUM_FILE        = 16,
	KITTY_IMAGE_MEDIUM_TEMP_FILE   = 17,
	KITTY_IMAGE_MEDIUM_SHARED_MEM  = 18,
	APC_MAX_BYTES                  = 19,
	APC_MAX_BYTES_KITTY            = 20,
}

Terminal_Data :: enum c.int {
	INVALID                        = 0,
	COLS                           = 1,
	ROWS                           = 2,
	CURSOR_X                       = 3,
	CURSOR_Y                       = 4,
	CURSOR_PENDING_WRAP            = 5,
	ACTIVE_SCREEN                  = 6,
	CURSOR_VISIBLE                 = 7,
	KITTY_KEYBOARD_FLAGS           = 8,
	SCROLLBAR                      = 9,
	CURSOR_STYLE                   = 10,
	MOUSE_TRACKING                 = 11,
	TITLE                          = 12,
	PWD                            = 13,
	TOTAL_ROWS                     = 14,
	SCROLLBACK_ROWS                = 15,
	WIDTH_PX                       = 16,
	HEIGHT_PX                      = 17,
	COLOR_FOREGROUND               = 18,
	COLOR_BACKGROUND               = 19,
	COLOR_CURSOR                   = 20,
	COLOR_PALETTE                  = 21,
	COLOR_FOREGROUND_DEFAULT       = 22,
	COLOR_BACKGROUND_DEFAULT       = 23,
	COLOR_CURSOR_DEFAULT           = 24,
	COLOR_PALETTE_DEFAULT          = 25,
	KITTY_IMAGE_STORAGE_LIMIT      = 26,
	KITTY_IMAGE_MEDIUM_FILE        = 27,
	KITTY_IMAGE_MEDIUM_TEMP_FILE   = 28,
	KITTY_IMAGE_MEDIUM_SHARED_MEM  = 29,
	KITTY_GRAPHICS                 = 30,
}

// ---------------------------------------------------------------------------
// OSC Parser
// ---------------------------------------------------------------------------

Osc_Parser  :: distinct rawptr
Osc_Command :: distinct rawptr

Osc_Command_Type :: enum c.int {
	INVALID                               = 0,
	CHANGE_WINDOW_TITLE                   = 1,
	CHANGE_WINDOW_ICON                    = 2,
	SEMANTIC_PROMPT                       = 3,
	CLIPBOARD_CONTENTS                    = 4,
	REPORT_PWD                            = 5,
	MOUSE_SHAPE                           = 6,
	COLOR_OPERATION                       = 7,
	KITTY_COLOR_PROTOCOL                  = 8,
	SHOW_DESKTOP_NOTIFICATION             = 9,
	HYPERLINK_START                       = 10,
	HYPERLINK_END                         = 11,
	CONEMU_SLEEP                          = 12,
	CONEMU_SHOW_MESSAGE_BOX               = 13,
	CONEMU_CHANGE_TAB_TITLE               = 14,
	CONEMU_PROGRESS_REPORT                = 15,
	CONEMU_WAIT_INPUT                     = 16,
	CONEMU_GUIMACRO                       = 17,
	CONEMU_RUN_PROCESS                    = 18,
	CONEMU_OUTPUT_ENVIRONMENT_VARIABLE    = 19,
	CONEMU_XTERM_EMULATION               = 20,
	CONEMU_COMMENT                        = 21,
	KITTY_TEXT_SIZING                     = 22,
}

Osc_Command_Data :: enum c.int {
	INVALID                       = 0,
	CHANGE_WINDOW_TITLE_STR       = 1,
}

// ---------------------------------------------------------------------------
// Focus
// ---------------------------------------------------------------------------

Focus_Event :: enum c.int {
	GAINED = 0,
	LOST   = 1,
}

// ---------------------------------------------------------------------------
// Formatter
// ---------------------------------------------------------------------------

Formatter :: distinct rawptr

Formatter_Format :: enum c.int {
	PLAIN = 0,
	VT    = 1,
	HTML  = 2,
}

Formatter_Screen_Extra :: struct {
	size:            c.size_t,
	cursor:          bool,
	style:           bool,
	hyperlink:       bool,
	protection:      bool,
	kitty_keyboard:  bool,
	charsets:        bool,
}

Formatter_Terminal_Extra :: struct {
	size:              c.size_t,
	palette:           bool,
	modes:             bool,
	scrolling_region:  bool,
	tabstops:          bool,
	pwd:               bool,
	keyboard:          bool,
	screen:            Formatter_Screen_Extra,
}

Formatter_Terminal_Options :: struct {
	size:   c.size_t,
	emit:   Formatter_Format,
	unwrap: bool,
	trim:   bool,
	extra:  Formatter_Terminal_Extra,
}

// ---------------------------------------------------------------------------
// Build Info
// ---------------------------------------------------------------------------

Optimize_Mode :: enum c.int {
	DEBUG         = 0,
	RELEASE_SAFE  = 1,
	RELEASE_SMALL = 2,
	RELEASE_FAST  = 3,
}

Build_Info :: enum c.int {
	INVALID            = 0,
	SIMD               = 1,
	KITTY_GRAPHICS     = 2,
	TMUX_CONTROL_MODE  = 3,
	OPTIMIZE           = 4,
	VERSION_STRING     = 5,
	VERSION_MAJOR      = 6,
	VERSION_MINOR      = 7,
	VERSION_PATCH      = 8,
	VERSION_PRE        = 9,
	VERSION_BUILD      = 10,
}

// ---------------------------------------------------------------------------
// Paste
// ---------------------------------------------------------------------------

// (paste_is_safe declared in foreign block below)

// ---------------------------------------------------------------------------
// Key Event / Encoder
// ---------------------------------------------------------------------------

Key_Event   :: distinct rawptr
Key_Encoder :: distinct rawptr

Key_Action :: enum c.int {
	RELEASE = 0,
	PRESS   = 1,
	REPEAT  = 2,
}

Mods :: u16

MODS_SHIFT      :: Mods(1 << 0)
MODS_CTRL       :: Mods(1 << 1)
MODS_ALT        :: Mods(1 << 2)
MODS_SUPER      :: Mods(1 << 3)
MODS_CAPS_LOCK  :: Mods(1 << 4)
MODS_NUM_LOCK   :: Mods(1 << 5)
MODS_SHIFT_SIDE :: Mods(1 << 6)
MODS_CTRL_SIDE  :: Mods(1 << 7)
MODS_ALT_SIDE   :: Mods(1 << 8)
MODS_SUPER_SIDE :: Mods(1 << 9)

Key :: enum c.int {
	UNIDENTIFIED = 0,
	BACKQUOTE,
	BACKSLASH,
	BRACKET_LEFT,
	BRACKET_RIGHT,
	COMMA,
	DIGIT_0, DIGIT_1, DIGIT_2, DIGIT_3, DIGIT_4,
	DIGIT_5, DIGIT_6, DIGIT_7, DIGIT_8, DIGIT_9,
	EQUAL,
	INTL_BACKSLASH,
	INTL_RO,
	INTL_YEN,
	A, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	MINUS, PERIOD, QUOTE, SEMICOLON, SLASH,
	ALT_LEFT, ALT_RIGHT,
	BACKSPACE, CAPS_LOCK, CONTEXT_MENU,
	CONTROL_LEFT, CONTROL_RIGHT,
	ENTER, META_LEFT, META_RIGHT,
	SHIFT_LEFT, SHIFT_RIGHT,
	SPACE, TAB, CONVERT, KANA_MODE, NON_CONVERT,
	DELETE, END, HELP, HOME, INSERT, PAGE_DOWN, PAGE_UP,
	ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT, ARROW_UP,
	NUM_LOCK,
	NUMPAD_0, NUMPAD_1, NUMPAD_2, NUMPAD_3, NUMPAD_4,
	NUMPAD_5, NUMPAD_6, NUMPAD_7, NUMPAD_8, NUMPAD_9,
	NUMPAD_ADD, NUMPAD_BACKSPACE, NUMPAD_CLEAR, NUMPAD_CLEAR_ENTRY,
	NUMPAD_COMMA, NUMPAD_DECIMAL, NUMPAD_DIVIDE, NUMPAD_ENTER,
	NUMPAD_EQUAL, NUMPAD_MEMORY_ADD, NUMPAD_MEMORY_CLEAR,
	NUMPAD_MEMORY_RECALL, NUMPAD_MEMORY_STORE, NUMPAD_MEMORY_SUBTRACT,
	NUMPAD_MULTIPLY, NUMPAD_PAREN_LEFT, NUMPAD_PAREN_RIGHT,
	NUMPAD_SUBTRACT, NUMPAD_SEPARATOR,
	NUMPAD_UP, NUMPAD_DOWN, NUMPAD_RIGHT, NUMPAD_LEFT,
	NUMPAD_BEGIN, NUMPAD_HOME, NUMPAD_END,
	NUMPAD_INSERT, NUMPAD_DELETE, NUMPAD_PAGE_UP, NUMPAD_PAGE_DOWN,
	ESCAPE,
	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
	F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24, F25,
	FN, FN_LOCK,
	PRINT_SCREEN, SCROLL_LOCK, PAUSE,
	BROWSER_BACK, BROWSER_FAVORITES, BROWSER_FORWARD,
	BROWSER_HOME, BROWSER_REFRESH, BROWSER_SEARCH, BROWSER_STOP,
	EJECT, LAUNCH_APP_1, LAUNCH_APP_2, LAUNCH_MAIL,
	MEDIA_PLAY_PAUSE, MEDIA_SELECT, MEDIA_STOP,
	MEDIA_TRACK_NEXT, MEDIA_TRACK_PREVIOUS,
	POWER, SLEEP,
	AUDIO_VOLUME_DOWN, AUDIO_VOLUME_MUTE, AUDIO_VOLUME_UP,
	WAKE_UP, COPY, CUT, PASTE,
}

Kitty_Key_Flags :: u8

KITTY_KEY_DISABLED          :: Kitty_Key_Flags(0)
KITTY_KEY_DISAMBIGUATE      :: Kitty_Key_Flags(1 << 0)
KITTY_KEY_REPORT_EVENTS     :: Kitty_Key_Flags(1 << 1)
KITTY_KEY_REPORT_ALTERNATES :: Kitty_Key_Flags(1 << 2)
KITTY_KEY_REPORT_ALL        :: Kitty_Key_Flags(1 << 3)
KITTY_KEY_REPORT_ASSOCIATED :: Kitty_Key_Flags(1 << 4)

Option_As_Alt :: enum c.int {
	FALSE = 0,
	TRUE  = 1,
	LEFT  = 2,
	RIGHT = 3,
}

Key_Encoder_Option :: enum c.int {
	CURSOR_KEY_APPLICATION     = 0,
	KEYPAD_KEY_APPLICATION     = 1,
	IGNORE_KEYPAD_WITH_NUMLOCK = 2,
	ALT_ESC_PREFIX             = 3,
	MODIFY_OTHER_KEYS_STATE_2  = 4,
	KITTY_FLAGS                = 5,
	MACOS_OPTION_AS_ALT        = 6,
	BACKARROW_KEY_MODE         = 7, // DECBKM
}

// ---------------------------------------------------------------------------
// Mouse Event / Encoder
// ---------------------------------------------------------------------------

Mouse_Event   :: distinct rawptr
Mouse_Encoder :: distinct rawptr

Mouse_Action :: enum c.int {
	PRESS   = 0,
	RELEASE = 1,
	MOTION  = 2,
}

Mouse_Button :: enum c.int {
	UNKNOWN = 0,
	LEFT    = 1,
	RIGHT   = 2,
	MIDDLE  = 3,
	FOUR    = 4,
	FIVE    = 5,
	SIX     = 6,
	SEVEN   = 7,
	EIGHT   = 8,
	NINE    = 9,
	TEN     = 10,
	ELEVEN  = 11,
}

Mouse_Position :: struct {
	x: f32,
	y: f32,
}

Mouse_Tracking_Mode :: enum c.int {
	NONE   = 0,
	X10    = 1,
	NORMAL = 2,
	BUTTON = 3,
	ANY    = 4,
}

Mouse_Format :: enum c.int {
	X10        = 0,
	UTF8       = 1,
	SGR        = 2,
	URXVT      = 3,
	SGR_PIXELS = 4,
}

Mouse_Encoder_Size :: struct {
	size:           c.size_t,
	screen_width:   u32,
	screen_height:  u32,
	cell_width:     u32,
	cell_height:    u32,
	padding_top:    u32,
	padding_bottom: u32,
	padding_right:  u32,
	padding_left:   u32,
}

Mouse_Encoder_Option :: enum c.int {
	EVENT              = 0,
	FORMAT             = 1,
	SIZE               = 2,
	ANY_BUTTON_PRESSED = 3,
	TRACK_LAST_CELL    = 4,
}

// ---------------------------------------------------------------------------
// Render State
// ---------------------------------------------------------------------------

Render_State              :: distinct rawptr
Render_State_Row_Iterator :: distinct rawptr
Render_State_Row_Cells    :: distinct rawptr

Render_State_Dirty :: enum c.int {
	FALSE   = 0,
	PARTIAL = 1,
	FULL    = 2,
}

Render_State_Cursor_Visual_Style :: enum c.int {
	BAR          = 0,
	BLOCK        = 1,
	UNDERLINE    = 2,
	BLOCK_HOLLOW = 3,
}

Render_State_Data :: enum c.int {
	INVALID                    = 0,
	COLS                       = 1,
	ROWS                       = 2,
	DIRTY                      = 3,
	ROW_ITERATOR               = 4,
	COLOR_BACKGROUND           = 5,
	COLOR_FOREGROUND           = 6,
	COLOR_CURSOR               = 7,
	COLOR_CURSOR_HAS_VALUE     = 8,
	COLOR_PALETTE              = 9,
	CURSOR_VISUAL_STYLE        = 10,
	CURSOR_VISIBLE             = 11,
	CURSOR_BLINKING            = 12,
	CURSOR_PASSWORD_INPUT      = 13,
	CURSOR_VIEWPORT_HAS_VALUE  = 14,
	CURSOR_VIEWPORT_X          = 15,
	CURSOR_VIEWPORT_Y          = 16,
	CURSOR_VIEWPORT_WIDE_TAIL  = 17,
}

Render_State_Option :: enum c.int {
	DIRTY = 0,
}

Render_State_Row_Data :: enum c.int {
	INVALID = 0,
	DIRTY   = 1,
	RAW     = 2,
	CELLS   = 3,
}

Render_State_Row_Option :: enum c.int {
	DIRTY = 0,
}

Render_State_Row_Cells_Data :: enum c.int {
	INVALID        = 0,
	RAW            = 1,
	STYLE          = 2,
	GRAPHEMES_LEN  = 3,
	GRAPHEMES_BUF  = 4,
	BG_COLOR       = 5,
	FG_COLOR       = 6,
}

Render_State_Colors :: struct {
	size:            c.size_t,
	background:      Color_Rgb,
	foreground:      Color_Rgb,
	cursor:          Color_Rgb,
	cursor_has_value: bool,
	palette:         [256]Color_Rgb,
}

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

Selection :: struct {
	size:      c.size_t,
	start:     Grid_Ref,
	end:       Grid_Ref,
	rectangle: bool,
}

// ---------------------------------------------------------------------------
// Sys (process-global runtime callbacks)
// ---------------------------------------------------------------------------

Sys_Image :: struct {
	width:    u32,
	height:   u32,
	data:     [^]u8,
	data_len: c.size_t,
}

Sys_Log_Level :: enum c.int {
	ERROR   = 0,
	WARNING = 1,
	INFO    = 2,
	DEBUG   = 3,
}

Sys_Log_Fn        :: #type proc "c" (userdata: rawptr, level: Sys_Log_Level, scope: [^]u8, scope_len: c.size_t, message: [^]u8, message_len: c.size_t)
Sys_Decode_Png_Fn :: #type proc "c" (userdata: rawptr, allocator: ^Allocator, data: [^]u8, data_len: c.size_t, out: ^Sys_Image) -> bool

Sys_Option :: enum c.int {
	USERDATA   = 0,
	DECODE_PNG = 1,
	LOG        = 2,
}

// ---------------------------------------------------------------------------
// Kitty Graphics
// ---------------------------------------------------------------------------

Kitty_Graphics                     :: distinct rawptr
Kitty_Graphics_Image               :: distinct rawptr
Kitty_Graphics_Placement_Iterator  :: distinct rawptr

Kitty_Graphics_Data :: enum c.int {
	INVALID            = 0,
	PLACEMENT_ITERATOR = 1,
}

Kitty_Graphics_Placement_Data :: enum c.int {
	INVALID        = 0,
	IMAGE_ID       = 1,
	PLACEMENT_ID   = 2,
	IS_VIRTUAL     = 3,
	X_OFFSET       = 4,
	Y_OFFSET       = 5,
	SOURCE_X       = 6,
	SOURCE_Y       = 7,
	SOURCE_WIDTH   = 8,
	SOURCE_HEIGHT  = 9,
	COLUMNS        = 10,
	ROWS           = 11,
	Z              = 12,
}

Kitty_Placement_Layer :: enum c.int {
	ALL         = 0,
	BELOW_BG    = 1,
	BELOW_TEXT  = 2,
	ABOVE_TEXT  = 3,
}

Kitty_Graphics_Placement_Iterator_Option :: enum c.int {
	LAYER = 0,
}

Kitty_Image_Format :: enum c.int {
	RGB         = 0,
	RGBA        = 1,
	PNG         = 2,
	GRAY_ALPHA  = 3,
	GRAY        = 4,
}

Kitty_Image_Compression :: enum c.int {
	NONE          = 0,
	ZLIB_DEFLATE  = 1,
}

Kitty_Graphics_Image_Data :: enum c.int {
	INVALID      = 0,
	ID           = 1,
	NUMBER       = 2,
	WIDTH        = 3,
	HEIGHT       = 4,
	FORMAT       = 5,
	COMPRESSION  = 6,
	DATA_PTR     = 7,
	DATA_LEN     = 8,
}

Kitty_Graphics_Placement_Render_Info :: struct {
	size:             c.size_t,
	pixel_width:      u32,
	pixel_height:     u32,
	grid_cols:        u32,
	grid_rows:        u32,
	viewport_col:     i32,
	viewport_row:     i32,
	viewport_visible: bool,
	source_x:         u32,
	source_y:         u32,
	source_width:     u32,
	source_height:    u32,
}

// ===========================================================================
// Foreign function declarations
// ===========================================================================

@(default_calling_convention = "c", link_prefix = "ghostty_")
foreign lib {
	// -- Allocator --
	alloc :: proc(allocator: ^Allocator, len: c.size_t) -> [^]u8 ---
	free  :: proc(allocator: ^Allocator, ptr: [^]u8, len: c.size_t) ---

	// -- Color --
	color_rgb_get :: proc(color: Color_Rgb, r: ^u8, g: ^u8, b: ^u8) ---

	// -- Style --
	style_default    :: proc(style: ^Style) ---
	style_is_default :: proc(style: ^Style) -> bool ---

	// -- Terminal --
	terminal_new                 :: proc(allocator: ^Allocator, terminal: ^Terminal, options: Terminal_Options) -> Result ---
	terminal_free                :: proc(terminal: Terminal) ---
	terminal_reset               :: proc(terminal: Terminal) ---
	terminal_resize              :: proc(terminal: Terminal, cols: u16, rows: u16, cell_width_px: u32, cell_height_px: u32) -> Result ---
	terminal_set                 :: proc(terminal: Terminal, option: Terminal_Option, value: rawptr) -> Result ---
	terminal_vt_write            :: proc(terminal: Terminal, data: [^]u8, len: c.size_t) ---
	terminal_scroll_viewport     :: proc(terminal: Terminal, behavior: Terminal_Scroll_Viewport) ---
	terminal_mode_get            :: proc(terminal: Terminal, mode: Mode, out_value: ^bool) -> Result ---
	terminal_mode_set            :: proc(terminal: Terminal, mode: Mode, value: bool) -> Result ---
	terminal_get                 :: proc(terminal: Terminal, data: Terminal_Data, out: rawptr) -> Result ---
	terminal_get_multi           :: proc(terminal: Terminal, count: c.size_t, keys: [^]Terminal_Data, values: [^]rawptr, out_written: ^c.size_t) -> Result ---
	terminal_grid_ref            :: proc(terminal: Terminal, point: Point, out_ref: ^Grid_Ref) -> Result ---
	terminal_point_from_grid_ref :: proc(terminal: Terminal, ref: ^Grid_Ref, tag: Point_Tag, out: ^Point_Coordinate) -> Result ---

	// -- Screen --
	cell_get       :: proc(cell: Cell, data: Cell_Data, out: rawptr) -> Result ---
	cell_get_multi :: proc(cell: Cell, count: c.size_t, keys: [^]Cell_Data, values: [^]rawptr, out_written: ^c.size_t) -> Result ---
	row_get        :: proc(row: Row, data: Row_Data, out: rawptr) -> Result ---
	row_get_multi  :: proc(row: Row, count: c.size_t, keys: [^]Row_Data, values: [^]rawptr, out_written: ^c.size_t) -> Result ---

	// -- Grid Ref --
	grid_ref_cell          :: proc(ref: ^Grid_Ref, out_cell: ^Cell) -> Result ---
	grid_ref_row           :: proc(ref: ^Grid_Ref, out_row: ^Row) -> Result ---
	grid_ref_graphemes     :: proc(ref: ^Grid_Ref, buf: [^]u32, buf_len: c.size_t, out_len: ^c.size_t) -> Result ---
	grid_ref_hyperlink_uri :: proc(ref: ^Grid_Ref, buf: [^]u8, buf_len: c.size_t, out_len: ^c.size_t) -> Result ---
	grid_ref_style         :: proc(ref: ^Grid_Ref, out_style: ^Style) -> Result ---

	// -- Mode Report --
	mode_report_encode :: proc(mode: Mode, state: Mode_Report_State, buf: [^]u8, buf_len: c.size_t, out_written: ^c.size_t) -> Result ---

	// -- SGR --
	sgr_new             :: proc(allocator: ^Allocator, parser: ^Sgr_Parser) -> Result ---
	sgr_free            :: proc(parser: Sgr_Parser) ---
	sgr_reset           :: proc(parser: Sgr_Parser) ---
	sgr_set_params      :: proc(parser: Sgr_Parser, params: [^]u16, separators: [^]u8, len: c.size_t) -> Result ---
	sgr_next            :: proc(parser: Sgr_Parser, attr: ^Sgr_Attribute) -> bool ---
	sgr_unknown_full    :: proc(unknown: Sgr_Unknown, ptr: ^[^]u16) -> c.size_t ---
	sgr_unknown_partial :: proc(unknown: Sgr_Unknown, ptr: ^[^]u16) -> c.size_t ---
	sgr_attribute_tag   :: proc(attr: Sgr_Attribute) -> Sgr_Attribute_Tag ---
	sgr_attribute_value :: proc(attr: ^Sgr_Attribute) -> ^Sgr_Attribute_Value ---

	// -- OSC --
	osc_new          :: proc(allocator: ^Allocator, parser: ^Osc_Parser) -> Result ---
	osc_free         :: proc(parser: Osc_Parser) ---
	osc_reset        :: proc(parser: Osc_Parser) ---
	osc_next         :: proc(parser: Osc_Parser, byte: u8) ---
	osc_end          :: proc(parser: Osc_Parser, terminator: u8) -> Osc_Command ---
	osc_command_type :: proc(command: Osc_Command) -> Osc_Command_Type ---
	osc_command_data :: proc(command: Osc_Command, data: Osc_Command_Data, out: rawptr) -> bool ---

	// -- Focus --
	focus_encode :: proc(event: Focus_Event, buf: [^]u8, buf_len: c.size_t, out_written: ^c.size_t) -> Result ---

	// -- Size Report --
	size_report_encode :: proc(style: Size_Report_Style, size: Size_Report_Size, buf: [^]u8, buf_len: c.size_t, out_written: ^c.size_t) -> Result ---

	// -- Paste --
	paste_is_safe :: proc(data: cstring, len: c.size_t) -> bool ---
	paste_encode  :: proc(data: [^]u8, data_len: c.size_t, bracketed: bool, buf: [^]u8, buf_len: c.size_t, out_written: ^c.size_t) -> Result ---

	// -- Formatter --
	formatter_terminal_new :: proc(allocator: ^Allocator, formatter: ^Formatter, terminal: Terminal, options: Formatter_Terminal_Options) -> Result ---
	formatter_format_buf   :: proc(formatter: Formatter, buf: [^]u8, buf_len: c.size_t, out_written: ^c.size_t) -> Result ---
	formatter_format_alloc :: proc(formatter: Formatter, allocator: ^Allocator, out_ptr: ^[^]u8, out_len: ^c.size_t) -> Result ---
	formatter_free         :: proc(formatter: Formatter) ---

	// -- Build Info --
	build_info :: proc(data: Build_Info, out: rawptr) -> Result ---

	// -- Type metadata (struct layout JSON, mainly for non-C bindings) --
	type_json :: proc() -> cstring ---

	// -- Sys (process-global runtime callbacks) --
	sys_set        :: proc(option: Sys_Option, value: rawptr) -> Result ---
	sys_log_stderr :: proc(userdata: rawptr, level: Sys_Log_Level, scope: [^]u8, scope_len: c.size_t, message: [^]u8, message_len: c.size_t) ---

	// -- Kitty Graphics --
	kitty_graphics_get                       :: proc(graphics: Kitty_Graphics, data: Kitty_Graphics_Data, out: rawptr) -> Result ---
	kitty_graphics_image                     :: proc(graphics: Kitty_Graphics, image_id: u32) -> Kitty_Graphics_Image ---
	kitty_graphics_image_get                 :: proc(image: Kitty_Graphics_Image, data: Kitty_Graphics_Image_Data, out: rawptr) -> Result ---
	kitty_graphics_image_get_multi           :: proc(image: Kitty_Graphics_Image, count: c.size_t, keys: [^]Kitty_Graphics_Image_Data, values: [^]rawptr, out_written: ^c.size_t) -> Result ---

	kitty_graphics_placement_iterator_new    :: proc(allocator: ^Allocator, out_iterator: ^Kitty_Graphics_Placement_Iterator) -> Result ---
	kitty_graphics_placement_iterator_free   :: proc(iterator: Kitty_Graphics_Placement_Iterator) ---
	kitty_graphics_placement_iterator_set    :: proc(iterator: Kitty_Graphics_Placement_Iterator, option: Kitty_Graphics_Placement_Iterator_Option, value: rawptr) -> Result ---
	kitty_graphics_placement_next            :: proc(iterator: Kitty_Graphics_Placement_Iterator) -> bool ---
	kitty_graphics_placement_get             :: proc(iterator: Kitty_Graphics_Placement_Iterator, data: Kitty_Graphics_Placement_Data, out: rawptr) -> Result ---
	kitty_graphics_placement_get_multi       :: proc(iterator: Kitty_Graphics_Placement_Iterator, count: c.size_t, keys: [^]Kitty_Graphics_Placement_Data, values: [^]rawptr, out_written: ^c.size_t) -> Result ---
	kitty_graphics_placement_rect            :: proc(iterator: Kitty_Graphics_Placement_Iterator, image: Kitty_Graphics_Image, terminal: Terminal, out_selection: ^Selection) -> Result ---
	kitty_graphics_placement_pixel_size      :: proc(iterator: Kitty_Graphics_Placement_Iterator, image: Kitty_Graphics_Image, terminal: Terminal, out_width: ^u32, out_height: ^u32) -> Result ---
	kitty_graphics_placement_grid_size       :: proc(iterator: Kitty_Graphics_Placement_Iterator, image: Kitty_Graphics_Image, terminal: Terminal, out_cols: ^u32, out_rows: ^u32) -> Result ---
	kitty_graphics_placement_viewport_pos    :: proc(iterator: Kitty_Graphics_Placement_Iterator, image: Kitty_Graphics_Image, terminal: Terminal, out_col: ^i32, out_row: ^i32) -> Result ---
	kitty_graphics_placement_source_rect     :: proc(iterator: Kitty_Graphics_Placement_Iterator, image: Kitty_Graphics_Image, out_x: ^u32, out_y: ^u32, out_width: ^u32, out_height: ^u32) -> Result ---
	kitty_graphics_placement_render_info     :: proc(iterator: Kitty_Graphics_Placement_Iterator, image: Kitty_Graphics_Image, terminal: Terminal, out_info: ^Kitty_Graphics_Placement_Render_Info) -> Result ---

	// -- Key Event --
	key_event_new                    :: proc(allocator: ^Allocator, event: ^Key_Event) -> Result ---
	key_event_free                   :: proc(event: Key_Event) ---
	key_event_set_action             :: proc(event: Key_Event, action: Key_Action) ---
	key_event_get_action             :: proc(event: Key_Event) -> Key_Action ---
	key_event_set_key                :: proc(event: Key_Event, key: Key) ---
	key_event_get_key                :: proc(event: Key_Event) -> Key ---
	key_event_set_mods               :: proc(event: Key_Event, mods: Mods) ---
	key_event_get_mods               :: proc(event: Key_Event) -> Mods ---
	key_event_set_consumed_mods      :: proc(event: Key_Event, consumed_mods: Mods) ---
	key_event_get_consumed_mods      :: proc(event: Key_Event) -> Mods ---
	key_event_set_composing          :: proc(event: Key_Event, composing: bool) ---
	key_event_get_composing          :: proc(event: Key_Event) -> bool ---
	key_event_set_utf8               :: proc(event: Key_Event, utf8: cstring, len: c.size_t) ---
	key_event_get_utf8               :: proc(event: Key_Event, len: ^c.size_t) -> cstring ---
	key_event_set_unshifted_codepoint :: proc(event: Key_Event, codepoint: u32) ---
	key_event_get_unshifted_codepoint :: proc(event: Key_Event) -> u32 ---

	// -- Key Encoder --
	key_encoder_new                   :: proc(allocator: ^Allocator, encoder: ^Key_Encoder) -> Result ---
	key_encoder_free                  :: proc(encoder: Key_Encoder) ---
	key_encoder_setopt                :: proc(encoder: Key_Encoder, option: Key_Encoder_Option, value: rawptr) ---
	key_encoder_setopt_from_terminal  :: proc(encoder: Key_Encoder, terminal: Terminal) ---
	key_encoder_encode                :: proc(encoder: Key_Encoder, event: Key_Event, out_buf: [^]u8, out_buf_size: c.size_t, out_len: ^c.size_t) -> Result ---

	// -- Mouse Event --
	mouse_event_new          :: proc(allocator: ^Allocator, event: ^Mouse_Event) -> Result ---
	mouse_event_free         :: proc(event: Mouse_Event) ---
	mouse_event_set_action   :: proc(event: Mouse_Event, action: Mouse_Action) ---
	mouse_event_get_action   :: proc(event: Mouse_Event) -> Mouse_Action ---
	mouse_event_set_button   :: proc(event: Mouse_Event, button: Mouse_Button) ---
	mouse_event_clear_button :: proc(event: Mouse_Event) ---
	mouse_event_get_button   :: proc(event: Mouse_Event, out_button: ^Mouse_Button) -> bool ---
	mouse_event_set_mods     :: proc(event: Mouse_Event, mods: Mods) ---
	mouse_event_get_mods     :: proc(event: Mouse_Event) -> Mods ---
	mouse_event_set_position :: proc(event: Mouse_Event, position: Mouse_Position) ---
	mouse_event_get_position :: proc(event: Mouse_Event) -> Mouse_Position ---

	// -- Mouse Encoder --
	mouse_encoder_new                   :: proc(allocator: ^Allocator, encoder: ^Mouse_Encoder) -> Result ---
	mouse_encoder_free                  :: proc(encoder: Mouse_Encoder) ---
	mouse_encoder_setopt                :: proc(encoder: Mouse_Encoder, option: Mouse_Encoder_Option, value: rawptr) ---
	mouse_encoder_setopt_from_terminal  :: proc(encoder: Mouse_Encoder, terminal: Terminal) ---
	mouse_encoder_reset                 :: proc(encoder: Mouse_Encoder) ---
	mouse_encoder_encode                :: proc(encoder: Mouse_Encoder, event: Mouse_Event, out_buf: [^]u8, out_buf_size: c.size_t, out_len: ^c.size_t) -> Result ---

	// -- Render State --
	render_state_new             :: proc(allocator: ^Allocator, state: ^Render_State) -> Result ---
	render_state_free            :: proc(state: Render_State) ---
	render_state_update          :: proc(state: Render_State, terminal: Terminal) -> Result ---
	render_state_get             :: proc(state: Render_State, data: Render_State_Data, out: rawptr) -> Result ---
	render_state_get_multi       :: proc(state: Render_State, count: c.size_t, keys: [^]Render_State_Data, values: [^]rawptr, out_written: ^c.size_t) -> Result ---
	render_state_set             :: proc(state: Render_State, option: Render_State_Option, value: rawptr) -> Result ---
	render_state_colors_get      :: proc(state: Render_State, out_colors: ^Render_State_Colors) -> Result ---

	render_state_row_iterator_new  :: proc(allocator: ^Allocator, out_iterator: ^Render_State_Row_Iterator) -> Result ---
	render_state_row_iterator_free :: proc(iterator: Render_State_Row_Iterator) ---
	render_state_row_iterator_next :: proc(iterator: Render_State_Row_Iterator) -> bool ---
	render_state_row_get           :: proc(iterator: Render_State_Row_Iterator, data: Render_State_Row_Data, out: rawptr) -> Result ---
	render_state_row_get_multi     :: proc(iterator: Render_State_Row_Iterator, count: c.size_t, keys: [^]Render_State_Row_Data, values: [^]rawptr, out_written: ^c.size_t) -> Result ---
	render_state_row_set           :: proc(iterator: Render_State_Row_Iterator, option: Render_State_Row_Option, value: rawptr) -> Result ---

	render_state_row_cells_new       :: proc(allocator: ^Allocator, out_cells: ^Render_State_Row_Cells) -> Result ---
	render_state_row_cells_next      :: proc(cells: Render_State_Row_Cells) -> bool ---
	render_state_row_cells_select    :: proc(cells: Render_State_Row_Cells, x: u16) -> Result ---
	render_state_row_cells_get       :: proc(cells: Render_State_Row_Cells, data: Render_State_Row_Cells_Data, out: rawptr) -> Result ---
	render_state_row_cells_get_multi :: proc(cells: Render_State_Row_Cells, count: c.size_t, keys: [^]Render_State_Row_Cells_Data, values: [^]rawptr, out_written: ^c.size_t) -> Result ---
	render_state_row_cells_free      :: proc(cells: Render_State_Row_Cells) ---
}
