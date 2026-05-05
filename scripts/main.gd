extends Node
## Scene manager — Menu → Game → GameOver (polished version)

var game_scene: Node = null

func _ready() -> void:
	show_menu()

func show_menu() -> void:
	cleanup()
	var menu := CanvasLayer.new()

	var bg := ColorRect.new()
	bg.color = Color8(15, 35, 45)
	bg.size = Vector2(1200, 800)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(bg)

	var sky := ColorRect.new()
	sky.color = Color8(57, 200, 200)
	sky.size = Vector2(1200, 400)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(sky)

	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.35)
	panel.position = Vector2(300, 130)
	panel.size = Vector2(600, 160)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(panel)

	var title := make_label("地铁疾跑", 68, Color8(57, 200, 190))
	title.position = Vector2(300, 140)
	title.size = Vector2(600, 80)
	menu.add_child(title)

	var sub := make_label("SUBWAY RUNNER 3D", 16, Color8(255, 255, 255, 160))
	sub.position = Vector2(300, 215)
	sub.size = Vector2(600, 25)
	menu.add_child(sub)

	var best: int = load_best_score()
	if best > 0:
		var best_lbl := make_label("最高分 " + str(best), 20, Color8(57, 200, 190))
		best_lbl.position = Vector2(300, 305)
		best_lbl.size = Vector2(600, 30)
		menu.add_child(best_lbl)

	var btn := make_button("[ 开始奔跑 ]", 24, Color8(40, 170, 170))
	btn.position = Vector2(460, 365)
	btn.size = Vector2(280, 60)
	btn.pressed.connect(start_game)
	menu.add_child(btn)

	var hint_bg := ColorRect.new()
	hint_bg.color = Color(0, 0, 0, 0.3)
	hint_bg.position = Vector2(340, 480)
	hint_bg.size = Vector2(520, 150)
	hint_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(hint_bg)

	var hints := [
		"[<-] [->] / [A] [D]     切换轨道",
		"[^] / [W] / 触控上滑    跳跃",
		"[v] / [S] / 触控下滑    滑铲",
		"[P] / 触控双击          暂停",
		"触控左右滑动            换轨",
	]
	for i in hints.size():
		var h := make_label(hints[i], 14, Color8(180, 240, 245))
		h.position = Vector2(340, 490 + i * 28)
		h.size = Vector2(520, 25)
		menu.add_child(h)

	var footer := make_label("按 Enter 或 空格 或 点击屏幕 开始", 13, Color8(160, 220, 225))
	footer.position = Vector2(300, 650)
	footer.size = Vector2(600, 20)
	menu.add_child(footer)

	add_child(menu)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			if game_scene == null:
				start_game()
	if event is InputEventScreenTouch and event.pressed and game_scene == null:
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

	# Wire pause toggle
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
	bg.color = Color(0, 0, 0, 0.7)
	bg.size = Vector2(1200, 800)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.25, 0.25, 0.92)
	panel.position = Vector2(320, 150)
	panel.size = Vector2(560, 400)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(panel)

	var title := make_label("游戏结束", 44, Color8(40, 170, 170))
	title.position = Vector2(320, 170)
	title.size = Vector2(560, 55)
	overlay.add_child(title)

	var score_lbl := make_label(str(score), 72, Color8(57, 200, 190))
	score_lbl.position = Vector2(320, 240)
	score_lbl.size = Vector2(560, 80)
	overlay.add_child(score_lbl)

	if score >= best:
		var new_lbl := make_label("新纪录！", 18, Color8(57, 200, 190))
		new_lbl.position = Vector2(320, 320)
		new_lbl.size = Vector2(560, 25)
		overlay.add_child(new_lbl)

	var coin_lbl := make_label("[C] " + str(coins) + " 金币", 22, Color8(57, 200, 190))
	coin_lbl.position = Vector2(320, 350)
	coin_lbl.size = Vector2(560, 30)
	overlay.add_child(coin_lbl)

	var best_lbl := make_label("最高分 " + str(best), 18, Color8(255, 255, 255))
	best_lbl.position = Vector2(320, 390)
	best_lbl.size = Vector2(560, 25)
	overlay.add_child(best_lbl)

	var btn := make_button("[ 再来一局 ]", 22, Color8(40, 170, 170))
	btn.position = Vector2(460, 450)
	btn.size = Vector2(280, 55)
	btn.pressed.connect(start_game)
	overlay.add_child(btn)

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
	lbl.add_theme_constant_override(&"outline_size", clampi(size / 8, 2, 8))
	# Artistic cute font (ZCOOL for main, WenKai fallback)
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
	# Artistic cute font
	var fnt := load("res://assets/fonts/ZCOOL-Regular.ttf")
	if not fnt: fnt = load("res://assets/fonts/WenKai-Medium.ttf")
	if fnt: btn.add_theme_font_override(&"font", fnt)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.bg_color = color
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(2, 3)
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
