extends CanvasLayer
signal pause_toggled

@onready var score_label: Label = $ScoreLabel
@onready var coins_label: Label = $CoinsLabel
@onready var speed_label: Label = $SpeedLabel
@onready var combo_label: Label = $ComboLabel
@onready var pause_btn: Button = $PauseBtn

var shield_label: Label
var magnet_label: Label
var multiplier_label: Label
var dash_label: Label
var pause_overlay: ColorRect
var pause_text: Label
var combo_pulse: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var fnt := load("res://assets/fonts/ZCOOL-Regular.ttf")
	if pause_btn:
		pause_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		pause_btn.pressed.connect(_on_pause)
		if fnt: pause_btn.add_theme_font_override(&"font", fnt)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(8)
		style.bg_color = Color(0, 0, 0, 0.4)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = Color(1, 1, 1, 0.2)
		pause_btn.add_theme_stylebox_override(&"normal", style)

	# Shield indicator (bottom-left)
	shield_label = Label.new()
	shield_label.text = "[S] Miku Shield"
	shield_label.position = Vector2(20, 80)
	shield_label.add_theme_font_size_override(&"font_size", 18)
	shield_label.add_theme_color_override(&"font_color", Color8(57, 200, 190))
	shield_label.add_theme_color_override(&"font_outline_color", Color8(0, 0, 0))
	shield_label.add_theme_constant_override(&"outline_size", 4)
	shield_label.visible = false
	if fnt: shield_label.add_theme_font_override(&"font", fnt)
	add_child(shield_label)

	# Magnet indicator
	magnet_label = Label.new()
	magnet_label.text = "[M] Leek Magnet"
	magnet_label.position = Vector2(20, 105)
	magnet_label.add_theme_font_size_override(&"font_size", 18)
	magnet_label.add_theme_color_override(&"font_color", Color8(255, 100, 150))
	magnet_label.add_theme_color_override(&"font_outline_color", Color8(0, 0, 0))
	magnet_label.add_theme_constant_override(&"outline_size", 4)
	magnet_label.visible = false
	if fnt: magnet_label.add_theme_font_override(&"font", fnt)
	add_child(magnet_label)

	# Score multiplier indicator (bottom-left)
	multiplier_label = Label.new()
	multiplier_label.text = "x2"
	multiplier_label.position = Vector2(20, 130)
	multiplier_label.add_theme_font_size_override("font_size", 24)
	multiplier_label.add_theme_color_override("font_color", Color8(255, 215, 70))
	multiplier_label.add_theme_color_override("font_outline_color", Color8(0, 0, 0))
	multiplier_label.add_theme_constant_override("outline_size", 4)
	multiplier_label.visible = false
	if fnt: multiplier_label.add_theme_font_override("font", fnt)
	add_child(multiplier_label)

	dash_label = Label.new()
	dash_label.text = "[D] Rhythm Dash"
	dash_label.position = Vector2(20, 158)
	dash_label.add_theme_font_size_override("font_size", 20)
	dash_label.add_theme_color_override("font_color", Color8(120, 180, 255))
	dash_label.add_theme_color_override("font_outline_color", Color8(0, 0, 0))
	dash_label.add_theme_constant_override("outline_size", 4)
	dash_label.visible = false
	if fnt: dash_label.add_theme_font_override("font", fnt)
	add_child(dash_label)

	# Pause overlay
	pause_overlay = ColorRect.new()
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.color = Color(0.0, 0.08, 0.10, 0.72)
	pause_overlay.size = Vector2(1200, 800)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.visible = false
	add_child(pause_overlay)

	pause_text = Label.new()
	pause_text.text = "MIKU PAUSED"
	pause_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_text.position = Vector2(400, 280)
	pause_text.size = Vector2(400, 80)
	pause_text.add_theme_font_size_override(&"font_size", 52)
	pause_text.add_theme_color_override(&"font_color", Color8(255, 255, 255))
	pause_text.add_theme_color_override(&"font_outline_color", Color8(0, 0, 0))
	pause_text.add_theme_constant_override(&"outline_size", 6)
	if fnt: pause_text.add_theme_font_override(&"font", fnt)
	pause_overlay.add_child(pause_text)

	var resume_hint := Label.new()
	resume_hint.text = "Press P or tap the button to resume"
	resume_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resume_hint.position = Vector2(400, 360)
	resume_hint.size = Vector2(400, 40)
	resume_hint.add_theme_font_size_override(&"font_size", 20)
	resume_hint.add_theme_color_override(&"font_color", Color8(180, 180, 180))
	resume_hint.add_theme_color_override(&"font_outline_color", Color8(0, 0, 0))
	resume_hint.add_theme_constant_override(&"outline_size", 3)
	if fnt: resume_hint.add_theme_font_override(&"font", fnt)
	pause_overlay.add_child(resume_hint)

	reset()

func _process(_delta: float) -> void:
	# Pulse combo animation
	if combo_label and combo_label.visible:
		combo_pulse += _delta * 4.0
		var s: float = 1.0 + sin(combo_pulse) * 0.06
		combo_label.scale = Vector2(s, s)

func reset() -> void:
	update_score(0)
	update_coins(0)
	update_speed(1.0)
	combo_pulse = 0.0
	if combo_label:
		combo_label.hide()
	hide_pause()

func update_score(s: int) -> void:
	if score_label:
		score_label.text = str(s)

func update_coins(c: int) -> void:
	if coins_label:
		coins_label.text = "[♪] " + str(c)

func update_speed(spd: float) -> void:
	if speed_label:
		speed_label.text = "x" + str(snapped(spd, 0.1))

func show_combo(c: int) -> void:
	if combo_label:
		if c > 1:
			combo_label.text = "LIVE COMBO x" + str(c)
			combo_label.show()
		else:
			combo_label.hide()

func update_multiplier(t: float) -> void:
	if multiplier_label:
		multiplier_label.visible = t > 0
		if t > 0:
			multiplier_label.text = "x2 " + str(snapped(t, 0.1)) + "s"

func update_magnet(t: float) -> void:
	if magnet_label:
		magnet_label.visible = t > 0
		if t > 0:
			magnet_label.text = "[M] Leek " + str(snapped(t, 0.1)) + "s"

func update_shield(t: float) -> void:
	if shield_label:
		shield_label.visible = t > 0
		if t > 0:
			shield_label.text = "[S] Shield " + str(snapped(t, 0.1)) + "s"

func update_dash(t: float) -> void:
	if dash_label:
		dash_label.visible = t > 0
		if t > 0:
			dash_label.text = "[D] Dash " + str(snapped(t, 0.1)) + "s"

func show_pause() -> void:
	pause_overlay.visible = true
	if pause_btn:
		pause_btn.text = "▶"

func hide_pause() -> void:
	pause_overlay.visible = false
	if pause_btn:
		pause_btn.text = "⏸"

func _on_pause() -> void:
	pause_toggled.emit()
