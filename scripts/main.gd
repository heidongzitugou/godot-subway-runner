extends Node
## Scene manager — Splash → Menu → Game → GameOver

var game_scene: Node = null
var _on_splash: bool = true

func _ready() -> void:
	show_splash()

func show_splash() -> void:
	cleanup()
	var splash := CanvasLayer.new()

	# Canva-generated MIKU快跑 logo as full-screen splash art
	var img_rect := TextureRect.new()
	var splash_tex := load("res://assets/textures/ui/logo_miku.png")
	if splash_tex:
		img_rect.texture = splash_tex
		img_rect.size = Vector2(1200, 800)
		img_rect.position = Vector2(0, 0)
		img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		splash.add_child(img_rect)
	else:
		var bg := ColorRect.new()
		bg.color = Color8(10, 25, 35)
		bg.size = Vector2(1200, 800)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		splash.add_child(bg)

	# Loading indicator at bottom
	var loading := make_label("Loading...", 14, Color8(200, 240, 255))
	loading.position = Vector2(480, 730)
	loading.size = Vector2(240, 20)
	splash.add_child(loading)

	# Bottom hint
	var footer := make_label("Press any key or tap to start the live run", 13, Color8(160, 210, 220))
	footer.position = Vector2(350, 755)
	footer.size = Vector2(500, 20)
	splash.add_child(footer)

	add_child(splash)

	# Auto-advance after 3 seconds or on input
	_on_splash = true
	get_tree().create_timer(3.0).timeout.connect(
		func():
			if is_instance_valid(splash) and _on_splash:
				show_menu()
	)

func show_menu() -> void:
	_on_splash = false
	cleanup()
	var menu := CanvasLayer.new()

	# Deep blue-teal gradient background
	var bg := ColorRect.new()
	bg.color = Color8(8, 18, 28)
	bg.size = Vector2(1200, 800)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(bg)

	# Top accent sky
	var sky := ColorRect.new()
	sky.color = Color8(32, 128, 160)
	sky.size = Vector2(1200, 350)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(sky)

	# Decorative gradient strip
	var strip := ColorRect.new()
	strip.color = Color8(255, 100, 170, 150)
	strip.size = Vector2(1200, 3)
	strip.position = Vector2(0, 350)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(strip)

	# Semi-transparent panel behind title
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.35)
	panel.position = Vector2(250, 120)
	panel.size = Vector2(700, 180)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(panel)

	# Title
	var title := make_label("MIKU 音速疾跑", 64, Color8(57, 240, 220))
	title.position = Vector2(250, 130)
	title.size = Vector2(700, 80)
	menu.add_child(title)

	var sub := make_label("SUBWAY RUNNER 3D  /  NEON LIVE STAGE", 16, Color8(255, 210, 235, 190))
	sub.position = Vector2(250, 210)
	sub.size = Vector2(700, 25)
	menu.add_child(sub)

	# Best score
	var best: int = load_best_score()
	if best > 0:
		var best_lbl := make_label("Best: " + str(best), 22, Color8(57, 200, 190))
		best_lbl.position = Vector2(250, 315)
		best_lbl.size = Vector2(700, 35)
		menu.add_child(best_lbl)

	# Start button
	var btn := make_button("[ START LIVE ]", 24, Color8(40, 170, 170))
	btn.position = Vector2(450, 380)
	btn.size = Vector2(300, 65)
	btn.pressed.connect(start_game)
	menu.add_child(btn)

	# Controls info panel
	var hint_bg := ColorRect.new()
	hint_bg.color = Color(0, 0, 0, 0.3)
	hint_bg.position = Vector2(300, 490)
	hint_bg.size = Vector2(600, 160)
	hint_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(hint_bg)

	var hint_title := make_label("-- Live Controls --", 16, Color8(57, 240, 220))
	hint_title.position = Vector2(300, 495)
	hint_title.size = Vector2(600, 22)
	menu.add_child(hint_title)

	var hints := [
		"[<-] [->] / [A] [D]     Switch Lane",
		"[^] / [W] / Swipe Up     Jump",
		"[v] / [S] / Swipe Down   Slide",
		"[P] / Double-tap         Pause",
		"Swipe Left/Right         Change Lane",
	]
	for i in hints.size():
		var h := make_label(hints[i], 13, Color8(180, 240, 245))
		h.position = Vector2(300, 522 + i * 26)
		h.size = Vector2(600, 22)
		menu.add_child(h)

	var footer := make_label("Collect rhythm coins, dodge trains, keep the combo alive", 12, Color8(180, 230, 235))
	footer.position = Vector2(350, 670)
	footer.size = Vector2(500, 20)
	menu.add_child(footer)

	add_child(menu)

func _unhandled_input(event: InputEvent) -> void:
	if _on_splash:
		if event is InputEventKey and event.pressed:
			show_menu()
		if event is InputEventScreenTouch and event.pressed:
			show_menu()
		return
	if game_scene == null:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				start_game()
		if event is InputEventScreenTouch and event.pressed:
			start_game()

func start_game() -> void:
	cleanup()
	game_scene = preload("res://scenes/game.tscn").instantiate()
	add_child(game_scene)

	game_scene.game_over.connect(_on_game_over)
	var player := find_player(game_scene)
	if player and player.has_signal(&"hit_obstacle"):
		if game_scene.has_method(&"on_player_hit"):
			player.hit_obstacle.connect(game_scene.on_player_hit)
		else:
			player.hit_obstacle.connect(_on_hit)

	var hud := find_hud(game_scene)
	if hud and hud.has_signal(&"pause_toggled"):
		if game_scene.has_method(&"toggle_pause"):
			hud.pause_toggled.connect(game_scene.toggle_pause)

	if game_scene.has_method(&"start_game"):
		game_scene.start_game()

func find_player(root: Node) -> Node:
	for c in root.get_children():
		if c is CharacterBody3D:
			return c
		var found := find_player(c)
		if found: return found
	return null

func find_hud(root: Node) -> Node:
	for c in root.get_children():
		if c is CanvasLayer:
			return c
		var found := find_hud(c)
		if found: return found
	return null

func _on_hit(_kind: String) -> void:
	if game_scene and is_instance_valid(game_scene) and game_scene.has_method(&"end_run"):
		game_scene.end_run()

func _on_game_over(score: int, coins: int, best: int) -> void:
	cleanup()
	game_scene = null
	show_game_over(score, coins, best)

func show_game_over(score: int, coins: int, best: int) -> void:
	var overlay := CanvasLayer.new()

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.size = Vector2(1200, 800)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	var panel := ColorRect.new()
	panel.color = Color(0.06, 0.22, 0.22, 0.94)
	panel.position = Vector2(300, 130)
	panel.size = Vector2(600, 440)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(panel)

	# Decorative line
	var line := ColorRect.new()
	line.color = Color8(57, 200, 190)
	line.position = Vector2(450, 180)
	line.size = Vector2(300, 2)
	overlay.add_child(line)

	var title := make_label("Game Over", 44, Color8(40, 170, 170))
	title.position = Vector2(300, 140)
	title.size = Vector2(600, 55)
	overlay.add_child(title)

	var score_lbl := make_label(str(score), 72, Color8(57, 200, 190))
	score_lbl.position = Vector2(300, 210)
	score_lbl.size = Vector2(600, 80)
	overlay.add_child(score_lbl)

	var meter_lbl := make_label("meters", 16, Color8(140, 200, 210))
	meter_lbl.position = Vector2(300, 285)
	meter_lbl.size = Vector2(600, 20)
	overlay.add_child(meter_lbl)

	if score >= best and score > 0:
		var new_lbl := make_label("NEW RECORD!", 20, Color8(57, 200, 190))
		new_lbl.position = Vector2(300, 310)
		new_lbl.size = Vector2(600, 28)
		overlay.add_child(new_lbl)

	var coin_lbl := make_label("[C] " + str(coins) + " coins", 22, Color8(57, 200, 190))
	coin_lbl.position = Vector2(300, 350)
	coin_lbl.size = Vector2(600, 30)
	overlay.add_child(coin_lbl)

	var best_lbl := make_label("Best: " + str(best), 18, Color8(200, 200, 200))
	best_lbl.position = Vector2(300, 390)
	best_lbl.size = Vector2(600, 25)
	overlay.add_child(best_lbl)

	var btn := make_button("[ PLAY AGAIN ]", 24, Color8(40, 170, 170))
	btn.position = Vector2(450, 450)
	btn.size = Vector2(300, 60)
	btn.pressed.connect(start_game)
	overlay.add_child(btn)

	var menu_btn := make_button("[ MENU ]", 18, Color8(80, 80, 80))
	menu_btn.position = Vector2(480, 525)
	menu_btn.size = Vector2(240, 40)
	menu_btn.pressed.connect(show_menu)
	overlay.add_child(menu_btn)

	add_child(overlay)

static func load_best_score() -> int:
	var file := FileAccess.open("user://save.dat", FileAccess.READ)
	if file:
		var val := file.get_32()
		file.close()
		return val
	return 0

static func make_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override(&"font_size", size)
	lbl.add_theme_color_override(&"font_color", color)
	lbl.add_theme_color_override(&"font_outline_color", Color8(0, 0, 0))
	lbl.add_theme_constant_override(&"outline_size", clampi(int(size / 8.0), 2, 8))
	var fnt := load("res://assets/fonts/ZCOOL-Regular.ttf")
	if not fnt: fnt = load("res://assets/fonts/WenKai-Medium.ttf")
	if fnt: lbl.add_theme_font_override(&"font", fnt)
	return lbl

static func make_button(text: String, size: int, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size = Vector2(260, 55)
	btn.add_theme_font_size_override(&"font_size", size)
	btn.add_theme_color_override(&"font_color", Color8(255, 255, 255))
	btn.add_theme_color_override(&"font_outline_color", Color8(0, 0, 0))
	btn.add_theme_constant_override(&"outline_size", 3)
	var fnt := load("res://assets/fonts/ZCOOL-Regular.ttf")
	if not fnt: fnt = load("res://assets/fonts/WenKai-Medium.ttf")
	if fnt: btn.add_theme_font_override(&"font", fnt)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.bg_color = color
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 5
	style.shadow_offset = Vector2(2, 3)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = color.lightened(0.2)
	btn.add_theme_stylebox_override(&"normal", style)
	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override(&"hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = color.darkened(0.15)
	btn.add_theme_stylebox_override(&"pressed", pressed)
	return btn

func cleanup() -> void:
	for c in get_children():
		if is_instance_valid(c):
			c.queue_free()
