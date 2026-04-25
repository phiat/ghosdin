# ghosdin — Odin bindings for libghostty-vt

set dotenv-load := false

ghostty_dir   := "ghostty"
lib_dir       := ghostty_dir / "zig-out/lib"
odin_flags    := "-extra-linker-flags:\"-L" + lib_dir + " -lghostty-vt\""
demo_bin      := "demo_bin"
termview_bin  := "termview_bin"
example_bin   := "example_bin"
export LD_LIBRARY_PATH := lib_dir

# List available recipes
default:
    @just --list

# ── Build ──────────────────────────────────────────────────────────

# Build libghostty-vt from source (shared + static, ReleaseFast suppresses info logs)
build-lib:
    cd {{ghostty_dir}} && zig build -Demit-lib-vt=true -Doptimize=ReleaseFast

# Build the headless demo
build-demo: build-lib
    odin build demo -out:{{demo_bin}} {{odin_flags}}

# Build the graphical terminal (raylib)
build-termview: build-lib
    odin build termview -out:{{termview_bin}} {{odin_flags}}

# Build the example game with embedded console
build-example: build-lib
    odin build example -out:{{example_bin}} {{odin_flags}}

# Build everything
build: build-demo build-termview build-example

# ── Run ────────────────────────────────────────────────────────────

# Run the headless demo
run-demo: build-demo
    ./{{demo_bin}}

# Launch the graphical terminal
run-termview: build-termview
    ./{{termview_bin}}

# Launch the example game (press ` for console)
run-example: build-example
    ./{{example_bin}}

# Default: launch the graphical terminal
run: run-termview

# Build and launch in one shot
dev: run

# ── Debug ──────────────────────────────────────────────────────────

# Build + run headless demo in debug mode
debug-demo: build-lib
    odin build demo -out:{{demo_bin}} -debug {{odin_flags}}
    ./{{demo_bin}}

# Build + run termview in debug mode
debug-termview: build-lib
    odin build termview -out:{{termview_bin}} -debug {{odin_flags}}
    ./{{termview_bin}}

# Build + run example game in debug mode
debug-example: build-lib
    odin build example -out:{{example_bin}} -debug {{odin_flags}}
    ./{{example_bin}}

# Default debug: termview
debug: debug-termview

# ── Check ──────────────────────────────────────────────────────────

# Type-check the vendor bindings
check:
    odin check vendor/ghostty_vt -no-entry-point

# Type-check all packages
check-all: check
    odin check pty -no-entry-point
    odin check render_rl -no-entry-point
    odin check demo
    odin check termview
    odin check console -no-entry-point
    odin check example

# ── Clean ──────────────────────────────────────────────────────────

# Clean all build artifacts
clean:
    rm -f {{demo_bin}} {{termview_bin}} {{example_bin}}
    rm -rf ghostty/zig-out ghostty/.zig-cache

# Clean only Odin artifacts (keep the lib)
clean-odin:
    rm -f {{demo_bin}} {{termview_bin}} {{example_bin}}

# Rebuild everything from scratch
rebuild: clean build

# ── Maintain ───────────────────────────────────────────────────────

# Update the ghostty source
update-ghostty:
    cd {{ghostty_dir}} && git pull --ff-only

# Update ghostty and rebuild lib
update: update-ghostty build-lib

# Run the libghostty-vt test suite
test-lib:
    cd {{ghostty_dir}} && zig build test-lib-vt

# Show toolchain and library info
info:
    @echo "── Library ──"
    @ls -lh {{lib_dir}}/libghostty-vt.so 2>/dev/null || echo "  (not built — run 'just build-lib')"
    @ls -lh {{lib_dir}}/libghostty-vt.a 2>/dev/null || true
    @echo ""
    @echo "── Toolchain ──"
    @odin version
    @zig version
    @echo ""
    @echo "── Binaries ──"
    @ls -lh {{demo_bin}} 2>/dev/null || echo "  demo: (not built)"
    @ls -lh {{termview_bin}} 2>/dev/null || echo "  termview: (not built)"
    @ls -lh {{example_bin}} 2>/dev/null || echo "  example: (not built)"
