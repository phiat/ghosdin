package pty

// Shared POSIX PTY interface — forkpty + non-blocking reads.
// Used by both termview and console packages.

import "core:c"
import "core:os"

foreign import util_lib "system:util"
foreign import libc_lib "system:c"

@(default_calling_convention = "c")
foreign util_lib {
	forkpty :: proc(amaster: ^c.int, name: [^]u8, termp: rawptr, winp: rawptr) -> c.int ---
}

TIOCSWINSZ :: 0x5414

Winsize :: struct {
	ws_row:    c.ushort,
	ws_col:    c.ushort,
	ws_xpixel: c.ushort,
	ws_ypixel: c.ushort,
}

@(default_calling_convention = "c")
foreign libc_lib {
	ioctl   :: proc(fd: c.int, request: c.ulong, #c_vararg args: ..any) -> c.int ---
	execvp  :: proc(file: cstring, argv: [^]cstring) -> c.int ---
	close   :: proc(fd: c.int) -> c.int ---
	read    :: proc(fd: c.int, buf: rawptr, count: c.size_t) -> c.ssize_t ---
	write   :: proc(fd: c.int, buf: rawptr, count: c.size_t) -> c.ssize_t ---
	fcntl   :: proc(fd: c.int, cmd: c.int, #c_vararg args: ..any) -> c.int ---
	waitpid :: proc(pid: c.int, status: ^c.int, options: c.int) -> c.int ---
	setenv  :: proc(name: cstring, value: cstring, overwrite: c.int) -> c.int ---
	_exit   :: proc(status: c.int) ---
}

F_GETFL    :: 3
F_SETFL    :: 4
O_NONBLOCK :: 0o4000
WNOHANG    :: 1

Pty :: struct {
	master_fd: c.int,
	child_pid: c.int,
}

spawn :: proc(shell: cstring, cols: u16, rows: u16) -> (Pty, bool) {
	master_fd: c.int
	pid := forkpty(&master_fd, nil, nil, nil)

	if pid < 0 {
		return {}, false
	}

	if pid == 0 {
		// Child process — set TERM so shell doesn't emit screen-specific escapes
		setenv("TERM", "xterm-256color", 1)
		args := [?]cstring{shell, nil}
		execvp(shell, raw_data(&args))
		_exit(1)
	}

	// Parent — set non-blocking
	flags := fcntl(master_fd, F_GETFL)
	fcntl(master_fd, F_SETFL, flags | O_NONBLOCK)

	// Set window size
	ws := Winsize{
		ws_col = c.ushort(cols),
		ws_row = c.ushort(rows),
	}
	ioctl(master_fd, TIOCSWINSZ, &ws)

	return Pty{master_fd = master_fd, child_pid = pid}, true
}

read_bytes :: proc(p: ^Pty, buf: []u8) -> int {
	n := read(p.master_fd, raw_data(buf), len(buf))
	if n <= 0 {
		return 0
	}
	return int(n)
}

write_bytes :: proc(p: ^Pty, data: []u8) {
	if len(data) == 0 do return
	write(p.master_fd, raw_data(data), len(data))
}

write_byte :: proc(p: ^Pty, b: u8) {
	buf := [1]u8{b}
	write(p.master_fd, &buf[0], 1)
}

write_string :: proc(p: ^Pty, s: string) {
	if len(s) == 0 do return
	write(p.master_fd, raw_data(s), len(s))
}

resize :: proc(p: ^Pty, cols: u16, rows: u16) {
	ws := Winsize{
		ws_col = c.ushort(cols),
		ws_row = c.ushort(rows),
	}
	ioctl(p.master_fd, TIOCSWINSZ, &ws)
}

destroy :: proc(p: ^Pty) {
	close(p.master_fd)
	// Reap the child process to avoid zombie
	if p.child_pid > 0 {
		status: c.int
		waitpid(p.child_pid, &status, WNOHANG)
	}
	p.master_fd = -1
	p.child_pid = 0
}

get_default_shell :: proc() -> cstring {
	buf: [256]u8
	shell := os.get_env_buf(buf[:], "SHELL")
	if len(shell) > 0 {
		@(static) shell_buf: [256]u8
		copy(shell_buf[:], shell)
		shell_buf[len(shell)] = 0
		return cstring(&shell_buf[0])
	}
	return "/bin/bash"
}
