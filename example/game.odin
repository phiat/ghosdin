package example

// Example raylib game with an embedded ghosdin console.
// Press ` (backtick) to toggle the quake-style dropdown terminal.

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import con "../console"

SCREEN_W :: 1024
SCREEN_H :: 768

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(SCREEN_W, SCREEN_H, "ghosdin — game console example")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	// Create the console
	console := con.create()
	defer con.destroy(&console)

	// Game state
	player_x: f32 = SCREEN_W / 2
	player_y: f32 = SCREEN_H / 2
	player_speed: f32 = 200
	time: f32 = 0
	hue: f32 = 0

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		time += dt
		hue += dt * 30
		if hue >= 360 do hue -= 360

		// Update console (handles toggle key + input when open)
		con.update(&console)

		// Only process game input when console is closed
		if !con.is_open(&console) {
			if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)    do player_y -= player_speed * dt
			if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)  do player_y += player_speed * dt
			if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)  do player_x -= player_speed * dt
			if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do player_x += player_speed * dt
		}

		// Clamp player
		player_x = clamp(player_x, 20, SCREEN_W - 20)
		player_y = clamp(player_y, 20, SCREEN_H - 20)

		// Draw
		rl.BeginDrawing()

		rl.ClearBackground({0x18, 0x18, 0x28, 0xff})

		// Background grid
		for x: i32 = 0; x < SCREEN_W; x += 40 {
			rl.DrawLine(x, 0, x, SCREEN_H, {0x25, 0x25, 0x35, 0xff})
		}
		for y: i32 = 0; y < SCREEN_H; y += 40 {
			rl.DrawLine(0, y, SCREEN_W, y, {0x25, 0x25, 0x35, 0xff})
		}

		// Bouncing particles
		for i in 0..<12 {
			fi := f32(i)
			angle := time * (0.5 + fi * 0.1) + fi * 0.523
			px := player_x + math.cos(angle) * (60 + fi * 8)
			py := player_y + math.sin(angle) * (60 + fi * 8)
			size := 4 + math.sin(time * 2 + fi) * 2
			color := rl.ColorFromHSV(hue + fi * 30, 0.8, 0.9)
			rl.DrawCircle(i32(px), i32(py), size, color)
		}

		// Player
		player_color := rl.ColorFromHSV(hue, 0.7, 1.0)
		rl.DrawCircle(i32(player_x), i32(player_y), 16, player_color)
		rl.DrawCircleLines(i32(player_x), i32(player_y), 20, {0xff, 0xff, 0xff, 0x44})

		// HUD
		rl.DrawText("WASD to move  |  ` to toggle console", 10, SCREEN_H - 30, 16, {0x88, 0x88, 0x88, 0xff})
		rl.DrawText(
			rl.TextFormat("pos: (%.0f, %.0f)  fps: %d", player_x, player_y, rl.GetFPS()),
			10, 10, 16, {0x88, 0xcc, 0x88, 0xff},
		)

		// Console overlay (draws on top of everything)
		con.draw(&console)

		rl.EndDrawing()
	}
}
