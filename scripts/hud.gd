extends CanvasLayer
signal pause_toggled

@onready var score_label: Label = $ScoreLabel
@onready var coins_label: Label = $CoinsLabel
@onready var speed_label: Label = $SpeedLabel
@onready var combo_label: Label = $ComboLabel
@onready var pause_btn: Button = $PauseBtn

var shield_label: Label
var multiplier_label: Label
var pause_overlay: ColorRect
var pause_text: Label

func _ready() -> void:
	var fnt := load("res://assets/fonts/ZCOOL-Regular.ttf")
	if pause_btn:
		pause_btn.pressed.connect(_on_pause)
		if fnt: pause_btn.add_theme_font_override(&"font", fnt)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(8)
		style.bg_color = Color(0, 0, 0, 0.4)
		style.content_margin_left = 8
		style.content_margin_right = 8
		pause_btn.add_theme_stylebox_override(&"normal", style)

	# Shield indicator
	shield_label = Label.new()
	shield_label.text = "[S] 护盾"
	shield_label.position = Vector2(20, 80)
	shield_label.add_theme_font_size_override(&"font_size", 18)
	shield_label.add_theme_color_override(&"font_color", Color8(57, 200, 190))
	shield_label.add_theme_color_override(&"font_outline_color", Color8(0, 0, 0))
	shield_label.add_theme_constant_override(&"outline_size", 4)
	shield_label.visible = false
	if fnt: shield_label.add_theme_font_override(&"font", fnt)
	add_child(shield_label)

	# Score multiplier indicator
	multiplier_label = Label.new()
	multiplier_label.text = "x2"
	multiplier_label.position = Vector2(20, 110)
	multiplier_label.add_theme_font_size_override("font_size", 24)
	multiplier_label.add_theme_color_override("font_color", Color8(255, 215, 70))
	multiplier_label.add_theme_color_override("font_outline_color", Color8(0, 0, 0))
	multiplier_label.add_theme_constant_override("outline_size", 4)
	multiplier_label.visible = false
	# Load cute font
	var fnt_m := load("res://assets/fonts/ZCOOL-Regular.ttf")
	if not fnt_m: fnt_m = load("res://assets/fonts/WenKai-Medium.ttf")
	if fnt_m: multiplier_label.add_theme_font_override("font", fnt_m)
	add_child(multiplier_label)
	# Pause overlay
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0, 0, 0, 0.6)
	pause_overlay.size = Vector2(1200, 800)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.visible = false
	add_child(pause_overlay)

	pause_text = Label.new()
	pause_text.text = "暂停"
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
	resume_hint.text = "按 P 或点击继续"
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

func reset() -> void:
	update_score(0)
	update_coins(0)
	update_speed(1.0)
	if combo_label:
		combo_label.hide()
	hide_pause()

func update_score(s: int) -> void:
	if score_label:
		score_label.text = str(s)

func update_coins(c: int) -> void:
	if coins_label:
		coins_label.text = "[C] " + str(c)

func update_speed(spd: float) -> void:
	if speed_label:
		speed_label.text = "x" + str(snapped(spd, 0.1))

func show_combo(c: int) -> void:
	if combo_label:
		if c > 1:
			combo_label.text = "连击 x" + str(c)
			combo_label.show()
			combo_label.scale = Vector2(1.0 + sin(Time.get_ticks_msec() * 0.01) * 0.08, 1.0 + sin(Time.get_ticks_msec() * 0.01) * 0.08)
		else:
			combo_label.hide()

func update_multiplier(t: float) -> void:
	if multiplier_label:
		multiplier_label.visible = t > 0
		if t > 0:
			multiplier_label.text = "x2 " + str(snapped(t, 0.1)) + "s"

func update_shield(t: float) -> void:
	if shield_label:
		shield_label.visible = t > 0
		if t > 0:
			shield_label.text = "[S] " + str(snapped(t, 0.1)) + "s"

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
