class_name Hud
extends CanvasLayer
## Score, info, combo and pop-up messages during a run, plus the start menu and the
## crash screen. Built in code so it stays easy to read and change.

signal play_pressed
signal again_pressed
signal menu_pressed
signal pause_pressed
signal character_changed
signal boss_test(index: int)

var score_label: Label
var info_label: Label
var combo_label: Label
var flash_label: Label
var pop_label: Label
var menu_panel: PanelContainer
var over_panel: PanelContainer
var over_text: Label
var over_title: Label
var best_label: Label
var pause_button: Button
var diff_buttons := {}
var char_buttons := {}
var char_desc: Label
var sound_toggle: CheckButton
var powers_label: Label
var meter_bg: Panel
var meter_fill: ColorRect
var meter_label: Label
var fade: ColorRect
var boss_box: VBoxContainer
var boss_name: Label
var boss_fill: ColorRect
var boss_sub: Label
var _flash_t := 0.0
var _pop_t := 0.0


func _ready() -> void:
	score_label = _label(48, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, Vector2(24, 20))
	info_label = _label(24, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP, Vector2(-24, 20))
	combo_label = _label(26, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, Vector2(24, 84))
	combo_label.add_theme_color_override("font_color", Color("ffe14d"))
	flash_label = _label(64, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, Vector2(0, 260))
	pop_label = _label(36, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, Vector2(0, 420))
	pop_label.add_theme_color_override("font_color", Color("fff36b"))

	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.custom_minimum_size = Vector2(72, 72)
	pause_button.add_theme_font_size_override("font_size", 28)
	add_child(pause_button)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
	pause_button.pressed.connect(func(): pause_pressed.emit())

	powers_label = _label(24, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_BOTTOM, Vector2(24, 0))
	powers_label.offset_bottom = -40
	_build_meter()
	_build_boss_bar()
	fade = ColorRect.new()
	fade.color = Color(1, 1, 1, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_menu()
	_build_over()
	show_menu()


## Ability meter at the bottom centre; pulses "DOUBLE-TAP" when full.
func _build_meter() -> void:
	meter_bg = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.4)
	sb.set_corner_radius_all(18)
	meter_bg.add_theme_stylebox_override("panel", sb)
	meter_bg.clip_contents = true
	add_child(meter_bg)
	meter_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	meter_bg.custom_minimum_size = Vector2(380, 36)
	meter_bg.size = Vector2(380, 36)
	meter_bg.position = Vector2(-190, -84)
	meter_bg.offset_left = -190
	meter_bg.offset_right = 190
	meter_bg.offset_top = -84
	meter_bg.offset_bottom = -48
	meter_fill = ColorRect.new()
	meter_bg.add_child(meter_fill)
	meter_fill.position = Vector2.ZERO
	meter_fill.size = Vector2(0, 36)
	meter_label = Label.new()
	meter_bg.add_child(meter_label)
	meter_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meter_label.add_theme_font_size_override("font_size", 20)
	meter_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	meter_label.add_theme_constant_override("outline_size", 6)
	meter_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Boss name, chase progress and metres left, below the top HUD.
func _build_boss_bar() -> void:
	boss_box = VBoxContainer.new()
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(boss_box)
	boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_box.offset_left = -180
	boss_box.offset_right = 180
	boss_box.offset_top = 140
	boss_box.alignment = BoxContainer.ALIGNMENT_CENTER
	boss_name = _text(boss_box, "", 30)
	boss_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	boss_name.add_theme_constant_override("outline_size", 8)
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.4)
	sb.set_corner_radius_all(8)
	bg.add_theme_stylebox_override("panel", sb)
	bg.custom_minimum_size = Vector2(340, 18)
	bg.clip_contents = true
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.add_child(bg)
	boss_fill = ColorRect.new()
	boss_fill.color = Color("ff3a3a")
	boss_fill.size = Vector2(0, 18)
	bg.add_child(boss_fill)
	boss_sub = _text(boss_box, "", 20)
	boss_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	boss_sub.add_theme_constant_override("outline_size", 6)
	boss_box.visible = false


func set_boss(visible_: bool, name := "", progress := 0.0, sub := "") -> void:
	boss_box.visible = visible_
	if visible_:
		boss_name.text = name
		boss_fill.size = Vector2(340.0 * clampf(progress, 0.0, 1.0), 18)
		boss_sub.text = sub


func set_meter(fraction: float, color: Color, text: String, pulse: bool) -> void:
	meter_fill.size = Vector2(380.0 * clampf(fraction, 0.0, 1.0), 36)
	meter_fill.color = color
	meter_label.text = text
	var s := 1.0 + (0.06 * sin(Time.get_ticks_msec() / 100.0) if pulse else 0.0)
	meter_bg.pivot_offset = Vector2(190, 18)
	meter_bg.scale = Vector2(s, s)


func _label(size: int, h: HorizontalAlignment, v: VerticalAlignment, offset: Vector2) -> Label:
	var l := Label.new()
	add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_left = maxf(0.0, offset.x)
	l.offset_right = minf(0.0, offset.x)
	l.offset_top = offset.y
	l.horizontal_alignment = h
	l.vertical_alignment = v
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 8)
	return l


func _panel() -> Array:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.2, 0.93)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	return [panel, box]


func _text(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 84)
	b.add_theme_font_size_override("font_size", 32)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(16)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	parent.add_child(b)
	return b


func _build_menu() -> void:
	var pb := _panel()
	menu_panel = pb[0]
	var box: VBoxContainer = pb[1]
	_text(box, "Sphere Runner", 52)
	_text(box, "Swipe left/right to switch lane, up to jump (hold to float), down to slide or slam.", 24)
	_text(box, "Character", 26)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	box.add_child(crow)
	for c in Config.CHARS:
		var b := _button(crow, Config.CHARS[c]["name"], Config.CHARS[c]["body"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 72)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_set_character.bind(c))
		char_buttons[c] = b
	char_desc = _text(box, "", 21)
	char_desc.custom_minimum_size = Vector2(536, 0)
	_text(box, "Difficulty", 26)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for d in ["easy", "medium", "hard"]:
		var b := Button.new()
		b.text = d.capitalize()
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 64)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_set_difficulty.bind(d))
		row.add_child(b)
		diff_buttons[d] = b
	_set_difficulty(Config.difficulty)
	_set_character(Config.character, false)
	sound_toggle = CheckButton.new()
	sound_toggle.text = "Sound"
	sound_toggle.button_pressed = Config.sound
	sound_toggle.add_theme_font_size_override("font_size", 26)
	sound_toggle.toggled.connect(func(on): Config.sound = on)
	box.add_child(sound_toggle)
	_button(box, "Play", Color("3d8bff")).pressed.connect(func(): play_pressed.emit())
	best_label = _text(box, "", 22)
	_text(box, "Boss test: start just before a boss (not saved)", 20)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	box.add_child(brow)
	for i in Config.THEMES.size():
		var b := Button.new()
		b.text = Config.THEMES[i]["boss"]["name"].split(" ")[-1].capitalize()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func(): boss_test.emit(i))
		brow.add_child(b)


func _set_difficulty(d: String) -> void:
	Config.difficulty = d
	for k in diff_buttons:
		diff_buttons[k].button_pressed = k == d


func _set_character(c: String, emit := true) -> void:
	Config.character = c
	for k in char_buttons:
		char_buttons[k].modulate = Color.WHITE if k == c else Color(1, 1, 1, 0.45)
	char_desc.text = Config.CHARS[c]["desc"] + " Double-tap when the meter is full."
	if emit:
		character_changed.emit()


func _build_over() -> void:
	var pb := _panel()
	over_panel = pb[0]
	var box: VBoxContainer = pb[1]
	over_title = _text(box, "Crashed", 48)
	over_text = _text(box, "", 28)
	_button(box, "Run again", Color("3d8bff")).pressed.connect(func(): again_pressed.emit())
	_button(box, "Menu", Color(1, 1, 1, 0.15)).pressed.connect(func(): menu_pressed.emit())


func show_menu(best := 0) -> void:
	menu_panel.visible = true
	over_panel.visible = false
	pause_button.visible = false
	meter_bg.visible = false
	boss_box.visible = false
	best_label.text = "Best: %d" % best


func show_run() -> void:
	menu_panel.visible = false
	over_panel.visible = false
	pause_button.visible = true
	meter_bg.visible = true


func show_over(text: String, title := "Crashed") -> void:
	over_title.text = title
	over_text.text = text
	over_panel.visible = true
	pause_button.visible = false
	meter_bg.visible = false


func flash(text: String) -> void:
	flash_label.text = text
	_flash_t = 1.2


func pop(text: String) -> void:
	pop_label.text = text
	_pop_t = 0.7


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			flash_label.text = ""
	if _pop_t > 0.0:
		_pop_t -= delta
		if _pop_t <= 0.0:
			pop_label.text = ""
