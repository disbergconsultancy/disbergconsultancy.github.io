class_name Hud
extends CanvasLayer
## All screens, in the block-pixel style (see the UI designs canvas): the home screen and
## its tabs (Heroes, Skills, Shop), the in-run HUD, pause and settings, and run over.
## Built in code with the UI kit (ui_kit.gd). Layout space: 720 x 1280.

signal play_pressed
signal again_pressed
signal menu_pressed
signal pause_pressed
signal character_changed
signal boss_test(index: int)
signal progress_changed       # skills or shop changed: main recomputes stats
signal settings_changed       # pixel world, sound...
signal tutorial_pressed       # replay the trial world

const M := 26.0               # screen margin
const NODE_ICONS := {
	"rhythm": "note", "showtime": "star", "chain": "chain", "crescendo": "crown",
	"quickfeet": "boot", "aircontrol": "wing", "spring": "spring", "slipstream": "wind",
	"charge": "bolt", "readthrow": "eye", "still": "clock", "field": "magnet",
	"fuel": "bolt", "wreck": "skull", "overdrive": "clock", "aftershock": "star",
	"legs": "boot", "pound": "spring", "sprinter": "wind", "ram": "heart",
	"scrap": "coin", "salvage": "coin", "rampage": "skull", "jackpot": "crown",
	"springlegs": "spring", "glider": "wing", "quickland": "boot", "djump": "crown",
	"windup": "bolt", "vault": "star", "hang": "clock", "meteor": "skull",
	"daredevil": "heart", "flyer": "wing", "windrider": "wind", "updraft": "crown"}
const CORE_ICONS := {"luck": "star", "dur": "bolt", "stumble": "heart"}

# In-run HUD (main writes these)
var score_label: Label
var combo_label: Label
var info_label: Label         # kept for older callers; set_info() is the way now
var powers_label: Label
var fade: ColorRect
var stats_label: Label

var _run: Control
var _combo_chip: Control
var _coin_val: Label
var _where_val: Label
var _speed_val: Label
var _powers_row: HBoxContainer
var _boss_box: Control
var _boss_name: Label
var _boss_bar: Control
var _boss_sub: Label
var _meter_box: Control
var _meter_bar: Control
var _meter_label: Label
var _meter_hint: Label
var _pause_btn: Button
var _flash: Label
var _pop: Label
var _flash_t := 0.0
var _pop_t := 0.0
var _tip: Control             # trial world: the gesture tip while the world is frozen
var _tip_icon: Control

# Menu screens
var _menu: Control             # home + tabs
var _tab := "home"
var _pages := {}
var _tab_buttons := {}
var _wallet_val: Label
var _overlay: Control          # pause / settings / run over
var _best := 0
var _sk_sel := Vector2i(1, 2)


func _ready() -> void:
	_build_run()
	_build_menu()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	fade = ColorRect.new()
	fade.color = Color(1, 1, 1, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_menu()


# =====================================================================
# Helpers
# =====================================================================

## Places c from the top of the screen. With `right`, it is attached to both side edges
## (so it stretches and stays centred on wider screens); otherwise it sits at `left`.
func _place(c: Control, parent: Control, left: float, top: float, right := -1.0, bottom := -1.0) -> Control:
	_anchor(c, parent, left, top, right, 0.0)
	if bottom >= 0.0:
		c.anchor_bottom = 1.0
		c.offset_bottom = -bottom
	return c


## Like _place, but y is measured from a fraction of the screen height (0 top, 0.5 middle,
## 1 bottom), so the layout fits taller phones: bottom bars stay at the bottom.
## right < 0: as wide as its content, at `left` (or, with from_right, `left` from the right edge).
func _anchor(c: Control, parent: Control, left: float, y: float, right: float, frac: float, from_right := false) -> Control:
	parent.add_child(c)
	c.anchor_top = frac
	c.anchor_bottom = frac
	c.offset_top = y
	c.offset_bottom = y
	if right >= 0.0:
		c.anchor_left = 0.0
		c.anchor_right = 1.0
		c.offset_left = left
		c.offset_right = -right
	elif from_right:
		c.anchor_left = 1.0
		c.anchor_right = 1.0
		c.offset_left = -left - c.custom_minimum_size.x
		c.offset_right = -left
	else:
		c.anchor_left = 0.0
		c.anchor_right = 0.0
		c.offset_left = left
		c.offset_right = left
	return c


func _vbox(sep := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _ignore_mouse(n: Node) -> void:
	for ch in n.get_children():
		if ch is Control:
			ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(ch)


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


# =====================================================================
# In-run HUD
# =====================================================================

func _build_run() -> void:
	_run = _layer()
	add_child(_run)
	# Score and combo, top left
	var tl := _vbox(10)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(tl, _run, M, 24)
	score_label = UI.label("0", 72, Color.WHITE, 700, true)
	score_label.custom_minimum_size.y = 84      # same height as the coin chip: centres line up
	tl.add_child(score_label)
	combo_label = UI.label("", 30, Color("ff8c26"))
	_combo_chip = UI.chip([combo_label], "chip", Vector2(0, 64))
	_combo_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tl.add_child(_combo_chip)
	# Coins, lap and speed, top right
	var tr := _vbox(10)
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_run.add_child(tr)
	tr.offset_right = -M
	tr.offset_top = 24
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_coin_val = UI.label("0", 34)
	var coin_chip := UI.chip([UI.icon("coin", 40, UI.GOLD), _coin_val], "chip", Vector2(220, 84))
	coin_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	tr.add_child(coin_chip)
	_where_val = UI.label("", 26)
	var wchip := UI.chip([_where_val], "chip", Vector2(220, 64))
	wchip.size_flags_horizontal = Control.SIZE_SHRINK_END
	tr.add_child(wchip)
	_speed_val = UI.label("", 26)
	var schip := UI.chip([_speed_val], "chip", Vector2(220, 64))
	schip.size_flags_horizontal = Control.SIZE_SHRINK_END
	tr.add_child(schip)
	info_label = Label.new()        # unused placeholder for old callers
	# Boss bar
	_boss_box = UI.panel("panel", 10)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bb := _vbox(8)
	bb.alignment = BoxContainer.ALIGNMENT_CENTER
	_boss_box.add_child(bb)
	var bn := _hbox(10)
	bn.alignment = BoxContainer.ALIGNMENT_CENTER
	bn.add_child(UI.icon("skull", 40, Color("ff6b5e")))
	_boss_name = UI.label("", 36)
	bn.add_child(_boss_name)
	bb.add_child(bn)
	_boss_bar = UI.seg_bar(20, Vector2(18, 24), 4)
	bb.add_child(_boss_bar)
	_boss_sub = UI.label("", 26, Color.WHITE, 600)
	_boss_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bb.add_child(_boss_sub)
	_place(_boss_box, _run, 92, 236, 92)
	# Flash and pop messages
	_flash = UI.label("", 84, Color.WHITE, 700, true)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_flash, _run, 0, -170, 0, 0.5)
	_pop = UI.label("", 52, UI.GOLD, 700, true)
	_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_pop, _run, 0, 20, 0, 0.5)
	# Power-ups, bottom left (above the meter)
	_powers_row = _hbox(10)
	_powers_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_powers_row, _run, M, -226, -1, 1.0)
	powers_label = Label.new()      # unused placeholder for old callers
	# Ability meter and pause, bottom
	_meter_box = UI.panel("panel", 10)
	_meter_box.custom_minimum_size.y = 136       # as tall as the pause block next to it
	_meter_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mb := _vbox(8)
	mb.alignment = BoxContainer.ALIGNMENT_CENTER
	_meter_box.add_child(mb)
	var mrow := _hbox()
	_meter_label = UI.label("", 30)
	_meter_hint = UI.label("", 30, UI.GOLD)
	_meter_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mrow.add_child(_meter_label)
	mrow.add_child(_meter_hint)
	mb.add_child(mrow)
	_meter_bar = UI.seg_bar(12, Vector2(30, 26), 4)
	mb.add_child(_meter_bar)
	_anchor(_meter_box, _run, M, -148, 156, 1.0)
	_pause_btn = UI.button("", "stone", 32, "pause", 136)
	_pause_btn.custom_minimum_size = Vector2(112, 136)
	_pause_btn.pressed.connect(func(): pause_pressed.emit())
	_anchor(_pause_btn, _run, M, -148, -1, 1.0, true)


## Trial world: the world is frozen and this tip shows the gesture to make.
func show_tip(icon_name: String, title: String, text: String) -> void:
	hide_tip()
	_tip = _layer()
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.07, 0.1, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_full(dim))
	var panel := UI.panel("panel", 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := _vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	_tip_icon = UI.icon(icon_name, 96, UI.GOLD)
	v.add_child(_tip_icon)
	var t := UI.label(title, 52, Color.WHITE, 700, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var d := UI.label(text, 30, Color.WHITE, 600)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	_anchor(panel, _tip, 60, -330, 60, 0.5)
	_run.add_child(_tip)


func hide_tip() -> void:
	if _tip:
		_tip.queue_free()
		_tip = null
		_tip_icon = null


func set_info(coins_: int, where: String, kmh: int) -> void:
	_coin_val.text = str(coins_)
	_where_val.text = where
	_speed_val.text = "%d km/h" % kmh


## powers: [[icon, text, color], ...]
func set_powers(list: Array) -> void:
	_clear(_powers_row)
	for p in list:
		_powers_row.add_child(UI.chip([UI.icon(p[0], 32, p[2]), UI.label(p[1], 28)], "chip", Vector2(0, 64)))


func set_boss(visible_: bool, name := "", progress := 0.0, sub := "") -> void:
	_boss_box.visible = visible_ and _run.visible
	if visible_:
		_boss_name.text = name
		UI.set_bar(_boss_bar, progress, Color("d93333"))
		_boss_sub.text = sub


func set_meter(fraction: float, color: Color, text: String, pulse: bool) -> void:
	UI.set_bar(_meter_bar, fraction, color)
	var parts := text.split(": ")
	_meter_label.text = parts[-1]
	_meter_hint.text = "DOUBLE-TAP" if pulse else ""
	_meter_hint.modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 160.0)) if pulse else 1.0


func flash(text: String) -> void:
	_flash.text = text
	_flash_t = 1.2


func pop(text: String) -> void:
	_pop.text = text
	_pop_t = 0.7


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.text = ""
	if _pop_t > 0.0:
		_pop_t -= delta
		if _pop_t <= 0.0:
			_pop.text = ""
	if _combo_chip:
		_combo_chip.visible = combo_label.text != ""
	if _tip_icon:                 # the gesture icon bobs
		_tip_icon.position.y = -6.0 * absf(sin(Time.get_ticks_msec() / 220.0))


# =====================================================================
# Menu: home and tabs
# =====================================================================

func _build_menu() -> void:
	_menu = _layer()
	add_child(_menu)
	for t in ["home", "heroes", "skills", "shop"]:
		var p := _layer()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE if t == "home" else Control.MOUSE_FILTER_STOP
		_menu.add_child(p)
		_pages[t] = p
	# Tab bar
	var bar := _hbox(14)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_anchor(bar, _menu, 18, -176, 18, 1.0)
	bar.offset_bottom = -16
	for t in [["home", "play", "RUN"], ["heroes", "hero", "HEROES"], ["skills", "star", "SKILLS"], ["shop", "coin", "SHOP"]]:
		var b := UI.button(t[2], "stone", 26, t[1], 140, true, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_END
		b.pressed.connect(show_tab.bind(t[0]))
		bar.add_child(b)
		_tab_buttons[t[0]] = b


## The coin wallet (top left) and the settings button (top right), on every menu page.
func _topbar(page: Control, title := "") -> void:
	_wallet_val = UI.label(str(Progress.wallet), 36)
	var coins := UI.chip([UI.icon("coin", 40, UI.GOLD), _wallet_val], "chip", Vector2(0, 100))
	_place(coins, page, M, 24)
	if title != "":
		var t := UI.label(title, 56, Color.WHITE, 700, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.custom_minimum_size.y = 100
		_place(t, page, 0, 24, 0)
	var gear := UI.button("", "stone", 32, "gear", 100)
	gear.custom_minimum_size = Vector2(100, 100)
	gear.pressed.connect(show_settings.bind(false))
	_anchor(gear, page, M, 24, -1, 0.0, true)


func show_tab(t: String) -> void:
	_tab = t
	for k in _pages:
		_pages[k].visible = k == t
	for k in _tab_buttons:
		var on: bool = k == t
		var b: Button = _tab_buttons[k]
		UI.style(b, "green" if on else "stone")
		b.custom_minimum_size.y = 156 if on else 140
	match t:
		"home":
			_render_home()
		"heroes":
			_render_heroes()
		"skills":
			_render_skills()
		"shop":
			_render_shop()


func _render_home() -> void:
	var p: Control = _pages["home"]
	_clear(p)
	_topbar(p)
	# Logo: SPHERE in coloured blocks above RUNNER
	var logo := _vbox(4)
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	var letters := _hbox(10)
	letters.alignment = BoxContainer.ALIGNMENT_CENTER
	var cols := ["3380ff", "ff8c26", "22b357", "d940cc", "ffb020", "d93333"]
	for i in 6:
		var blk := UI.panel("block_white", 0)
		blk.self_modulate = Color(cols[i])
		blk.custom_minimum_size = Vector2(82, 90)
		var l := UI.label("SPHERE"[i], 62)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		blk.add_child(l)
		letters.add_child(blk)
	letters.rotation = -0.05
	logo.add_child(letters)
	var runner := UI.label("RUNNER", 122, Color.WHITE, 700, true)
	runner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_child(runner)
	_place(logo, p, 0, 170, 0)
	# Hero switcher: name plate above the hero, arrows beside them
	var c := Config.character
	var d: Dictionary = Config.CHARS[c]
	var mid := _vbox(8)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	var plate := UI.panel("block_white", 8)
	plate.self_modulate = Color(d["body"]) if c != "smasher" else Color("c98612")
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.add_child(UI.label("%s · LV %d" % [d["name"].to_upper(), Progress.prog[c]["lvl"]], 44))
	mid.add_child(plate)
	var ab := UI.chip([UI.label(_ability_line(c), 26, Color.WHITE, 600)], "chip", Vector2(0, 56))
	ab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid.add_child(ab)
	_anchor(mid, p, 0, -128, 0, 0.5)
	for side in [-1, 1]:
		var arrow := UI.button("", "stone", 32, "left" if side < 0 else "right", 118)
		arrow.custom_minimum_size = Vector2(96, 118)
		arrow.pressed.connect(_cycle_hero.bind(side))
		_anchor(arrow, p, 40, 50, -1, 0.5, side > 0)
	# Play and the best score / planet
	var col := _vbox(16)
	var play := UI.button("PLAY", "green", 84, "play", 168)
	play.pressed.connect(func(): play_pressed.emit())
	col.add_child(play)
	var chips := _hbox(14)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(UI.chip([UI.icon("star", 32, UI.GOLD), UI.label("Best %d" % _best, 28)], "chip", Vector2(0, 64)))
	chips.add_child(UI.chip([UI.label(Config.THEME["name"].capitalize(), 28)], "chip", Vector2(0, 64)))
	col.add_child(chips)
	_anchor(col, p, 44, -428, 44, 1.0)


func _ability_line(c: String) -> String:
	match Config.CHARS[c]["ability"]:
		"focus":
			return "Focus: time slows for 3 s"
		"smash":
			return "Smash: break through blocks"
		_:
			return "Super jump: leap over anything"


func _cycle_hero(step: int) -> void:
	var keys := Config.CHARS.keys()
	var i := (keys.find(Config.character) + step + keys.size()) % keys.size()
	_set_character(keys[i])


func _set_character(c: String) -> void:
	Config.character = c
	character_changed.emit()
	show_tab(_tab)


# --- Heroes --------------------------------------------------------------

func _render_heroes() -> void:
	var p: Control = _pages["heroes"]
	_clear(p)
	p.add_child(UI.backdrop())
	_topbar(p, "HEROES")
	var list := _vbox(14)
	for c in Config.CHARS:
		var d: Dictionary = Config.CHARS[c]
		var s := Progress.stats(c)
		var sel: bool = c == Config.character
		var card := UI.panel("panel", 14)
		if sel:
			card.self_modulate = Color("fff2b8")
		var row := _hbox(18)
		card.add_child(row)
		var frame := UI.panel("block_white", 0)
		frame.self_modulate = Color(d["body"]) if c != "smasher" else Color("c98612")
		var portrait := TextureRect.new()
		portrait.texture = UI.tex("hero_" + c)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.custom_minimum_size = Vector2(140, 140)
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.add_child(portrait)
		row.add_child(frame)
		var info := _vbox(6)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := _hbox()
		var nm := UI.label(d["name"].to_upper(), 38)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		head.add_child(UI.label("LV %d" % Progress.prog[c]["lvl"], 32, UI.GOLD))
		info.add_child(head)
		info.add_child(UI.label(_ability_line(c), 24, Color.WHITE, 500))
		var col := Color(d["body"]) if c != "smasher" else Color("ffb020")
		for st in [["Jump", (s["jump_v"] - 9.5) * 1.3], ["Meter", 5.0 + (s["meter_mul"] - 1.0) * 7.5], ["Combo", 5.0 + (s["combo_time"] - 2.5) * 3.0]]:
			var r := _hbox(10)
			var lbl := UI.label(st[0], 24, Color.WHITE, 600)
			lbl.custom_minimum_size.x = 100
			r.add_child(lbl)
			var bar := UI.seg_bar(10, Vector2(14, 16), 3)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UI.set_bar(bar, st[1] / 10.0, col)
			r.add_child(bar)
			info.add_child(r)
		if sel:
			var tag := UI.chip([UI.label("SELECTED", 28, UI.GOLD)], "chip", Vector2(220, 64))
			tag.size_flags_horizontal = Control.SIZE_SHRINK_END
			info.add_child(tag)
		row.add_child(info)
		# The whole card is the button: tap it to pick this hero.
		_ignore_mouse(card)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
				_set_character(c))
		list.add_child(card)
	_place(list, p, M, 160, M)


# --- Skills --------------------------------------------------------------

func _render_skills() -> void:
	var p: Control = _pages["skills"]
	_clear(p)
	p.add_child(UI.backdrop())
	_topbar(p, "SKILLS")
	var c := Config.character
	var pr: Dictionary = Progress.prog[c]
	var tree: Array = Progress.TREES[c]
	# Hero line and free points
	var head := _hbox(14)
	var frame := UI.panel("block_white", 0)
	frame.self_modulate = Color(Config.CHARS[c]["body"]) if c != "smasher" else Color("c98612")
	var portrait := TextureRect.new()
	portrait.texture = UI.tex("hero_" + c)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.custom_minimum_size = Vector2(72, 72)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(portrait)
	head.add_child(frame)
	var hl := UI.label("%s · LV %d" % [Config.CHARS[c]["name"].to_upper(), pr["lvl"]], 36)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	var fp := Progress.free_points(c)
	head.add_child(UI.chip([UI.label("%d POINT%s" % [fp, "" if fp == 1 else "S"], 30, UI.GOLD)], "chip", Vector2(0, 72)))
	var list := _vbox(14)            # header, tree card, skill details: spaced like the shop
	list.add_child(head)
	# Three branches, tier 1 at the top
	var tree_card := UI.panel("panel", 6)
	var grid := _hbox(12)
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	for b in 3:
		var colr := Color(tree[b][1])
		var col := _vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_BEGIN
		var bt := UI.chip([UI.label(tree[b][0].to_upper(), 26, colr), UI.label("· %d" % Progress.branch_points(c, b), 26)], "chip", Vector2(186, 60))
		bt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(bt)
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		col.add_child(gap)
		for tier in 4:
			var id: String = tree[b][2][tier]
			var rank: int = pr["alloc"].get(id, 0)
			var mr := Progress.max_rank(tier)
			var open_: bool = Progress.branch_points(c, b) >= Progress.TIER_REQ[tier]
			var nb := UI.button("", "stone" if open_ else "off", 40 if open_ else 32, NODE_ICONS.get(id, "star") if open_ else "lock", 88)
			nb.custom_minimum_size = Vector2(88, 88)
			nb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			UI.set_icon_color(nb, colr if open_ else Color("7a7a82"))
			if _sk_sel == Vector2i(b, tier):
				UI.style(nb, "blue")
			nb.pressed.connect(func():
				_sk_sel = Vector2i(b, tier)
				_render_skills())
			col.add_child(nb)
			var pips := _hbox(5)
			pips.alignment = BoxContainer.ALIGNMENT_CENTER
			for i in mr:
				var pip := ColorRect.new()
				pip.custom_minimum_size = Vector2(16, 16)
				pip.color = colr if i < rank else Color("2b2d36")
				pips.add_child(pip)
			col.add_child(pips)
		grid.add_child(col)
	tree_card.add_child(grid)
	list.add_child(tree_card)
	# The selected skill
	var detail := UI.panel("panel", 10)
	var dv := _vbox(8)
	detail.add_child(dv)
	var sb: int = _sk_sel.x
	var stier: int = _sk_sel.y
	var sid: String = tree[sb][2][stier]
	var srank: int = pr["alloc"].get(sid, 0)
	var smax := Progress.max_rank(stier)
	var dh := _hbox()
	var dn := UI.label(Progress.NODE_NAMES[sid].to_upper(), 40, Color(tree[sb][1]))
	dn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(dn)
	dh.add_child(UI.label("%d/%d" % [srank, smax], 32))
	dv.add_child(dh)
	var txt := ("Now: %s\n" % Progress.describe(sid, srank)) if srank > 0 else ""
	txt += ("Next: %s" % Progress.describe(sid, srank + 1)) if srank < smax else "Fully learned"
	if Progress.branch_points(c, sb) < Progress.TIER_REQ[stier]:
		txt += "\nOpens with %d points in %s." % [Progress.TIER_REQ[stier], tree[sb][0]]
	var dl := UI.label(txt, 26, Color.WHITE, 500)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size.x = 600
	dv.add_child(dl)
	var row := _hbox(10)
	var learn := UI.button("LEARN · 1 POINT", "green", 30, "check", 84)
	learn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.disable(learn, not Progress.can_learn(c, sb, stier))
	learn.pressed.connect(func():
		Progress.learn(c, sb, stier)
		progress_changed.emit()
		_render_skills())
	row.add_child(learn)
	var reset := UI.button("RESET", "stone", 22, "", 84)
	reset.custom_minimum_size.x = 110
	reset.pressed.connect(func():
		Progress.respec(c)
		progress_changed.emit()
		_render_skills())
	row.add_child(reset)
	var test := UI.button("+1 LV", "stone", 22, "", 84)
	test.custom_minimum_size.x = 100
	test.pressed.connect(func():
		if pr["lvl"] < Progress.MAX_LEVEL:
			pr["lvl"] += 1
			pr["xp"] = 0
			Progress.save()
		_render_skills())
	row.add_child(test)
	dv.add_child(row)
	list.add_child(detail)
	_place(list, p, M, 144, M)


# --- Shop --------------------------------------------------------------

func _render_shop() -> void:
	var p: Control = _pages["shop"]
	_clear(p)
	p.add_child(UI.backdrop())
	_topbar(p, "SHOP")
	var list := _vbox(16)
	var hrow := _hbox()
	var hl := UI.label("CORE UPGRADES · ALL HEROES", 30, UI.GOLD)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(hl)
	var test := UI.button("+500 (TEST)", "stone", 18, "", 48)
	test.custom_minimum_size.x = 150
	test.pressed.connect(func():
		Progress.wallet += 500
		Progress.save()
		_render_shop())
	hrow.add_child(test)
	list.add_child(hrow)
	for k in Progress.CORE:
		var u: Dictionary = Progress.CORE[k]
		var l: int = Progress.core[k]
		var card := UI.panel("panel", 14)
		var row := _hbox(16)
		card.add_child(row)
		var slot := UI.panel("panel_stone", 6)
		slot.custom_minimum_size = Vector2(96, 96)
		var ic := UI.icon(CORE_ICONS.get(k, "star"), 56, Color(u["color"]))
		slot.add_child(ic)
		row.add_child(slot)
		var info := _vbox(6)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_child(UI.label(u["name"], 34))
		var desc := UI.label(("Next: %s" % Progress.core_text(k, l + 1)) if l < u["max"] else Progress.core_text(k, l), 24, Color("e8e8ec"), 500)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 230
		info.add_child(desc)
		var pips := _hbox(6)
		for i in u["max"]:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(24, 24)
			pip.color = Color(u["color"]) if i < l else Color("2b2d36")
			pips.add_child(pip)
		info.add_child(pips)
		row.add_child(info)
		var price: int = u["prices"][l] if l < u["max"] else 0
		var buy := UI.button("MAX" if l >= u["max"] else str(price), "gold", 32, "" if l >= u["max"] else "coin", 100)
		buy.custom_minimum_size.x = 168
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI.disable(buy, l >= u["max"] or Progress.wallet < price)
		buy.pressed.connect(func():
			Progress.buy(k)
			progress_changed.emit()
			_render_shop())
		row.add_child(buy)
		list.add_child(card)
	list.add_child(UI.label("SKINS · COMING LATER", 32, UI.GOLD))
	var skins := _hbox(14)
	for i in 4:
		var s := UI.panel("panel_stone", 6)
		s.custom_minimum_size = Vector2(130, 130)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.self_modulate = Color(0.75, 0.75, 0.78)
		s.add_child(UI.icon("lock", 48, Color("9a9aa0")))
		skins.add_child(s)
	list.add_child(skins)
	_place(list, p, M, 160, M)


# =====================================================================
# Screens shown by the game
# =====================================================================

func show_menu(best := 0) -> void:
	_best = best
	_run.visible = false
	_clear(_overlay)
	_menu.visible = true
	show_tab("home")


func show_run() -> void:
	hide_tip()
	_menu.visible = false
	_clear(_overlay)
	_run.visible = true
	_meter_box.visible = true
	_pause_btn.visible = true


## Kept for older callers (tests): opens a tab from the menu.
func open_skills(_from := "menu") -> void:
	show_menu(_best)
	show_tab("skills")


func open_shop(_from := "menu") -> void:
	show_menu(_best)
	show_tab("shop")


## Pause (in a run) or settings (from the menu): toggles, difficulty, and in the menu the
## boss tests.
func show_settings(paused: bool) -> void:
	_clear(_overlay)
	if not paused and not _menu.visible:
		return
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.07, 0.1, 0.6)
	_overlay.add_child(_full(dim))
	var panel := UI.panel("panel_stone", 22)
	var v := _vbox(18)
	panel.add_child(v)
	var title := UI.label("PAUSED" if paused else "SETTINGS", 70, Color.WHITE, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	if paused:
		var resume := UI.button("RESUME", "green", 50, "play", 120)
		resume.pressed.connect(func():
			_clear(_overlay)
			pause_pressed.emit())
		v.add_child(resume)
		var restart := UI.button("RESTART", "stone", 38, "", 96)
		restart.pressed.connect(func():
			_clear(_overlay)
			again_pressed.emit())
		v.add_child(restart)
	var box := UI.panel("chip", 16)
	var bv := _vbox(18)
	box.add_child(bv)
	bv.add_child(_toggle("Sound", Config.sound, func(on): Config.sound = on))
	bv.add_child(_toggle("Vibration", Config.vibration, func(on): Config.vibration = on))
	bv.add_child(_toggle("Pixel world", Config.pixel_world, func(on): Config.pixel_world = on))
	bv.add_child(_toggle("3D models", Config.hero_models, func(on):
		Config.hero_models = on
		character_changed.emit()))
	bv.add_child(UI.label("Difficulty", 36))
	var drow := _hbox(10)
	for dd in ["easy", "medium", "hard"]:
		var b := UI.button(dd.capitalize(), "gold" if dd == Config.difficulty else "stone", 30, "", 80)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			Config.difficulty = dd
			settings_changed.emit()
			show_settings(paused))
		drow.add_child(b)
	bv.add_child(drow)
	if paused:
		bv.add_child(UI.label("Changes from the next run", 24, Color("e8e8ec"), 500))
	v.add_child(box)
	if paused:
		var quit := UI.button("QUIT RUN", "red", 38, "", 96)
		quit.pressed.connect(func():
			_clear(_overlay)
			menu_pressed.emit())
		v.add_child(quit)
	else:
		v.add_child(UI.label("Boss test (not saved)", 28, UI.GOLD))
		var trow := _hbox(8)
		for i in Config.THEMES.size() + 1:
			var nm: String = "Forge" if i == Config.THEMES.size() else Config.THEMES[i]["boss"]["name"].split(" ")[-1].capitalize()
			var b := UI.button(nm, "stone", 22, "", 70)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func():
				_clear(_overlay)
				boss_test.emit(i))
			trow.add_child(b)
		v.add_child(trow)
		var tut := UI.button("PLAY THE TRIAL AGAIN", "stone", 26, "play", 76)
		tut.pressed.connect(func():
			_clear(_overlay)
			tutorial_pressed.emit())
		v.add_child(tut)
		var close := UI.button("DONE", "green", 40, "check", 100)
		close.pressed.connect(func():
			_clear(_overlay)
			Progress.save()
			show_tab(_tab))
		v.add_child(close)
	_place(panel, _overlay, 44, 110, 44)


func _toggle(text: String, on: bool, set_fn: Callable) -> Control:
	var row := _hbox(12)
	var l := UI.label(text, 36)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := UI.button("ON" if on else "OFF", "green" if on else "off", 28, "", 64)
	b.custom_minimum_size.x = 130
	b.add_theme_stylebox_override("disabled", UI.box("btn_off", 6))
	b.pressed.connect(func():
		var now := UI.get_text(b) != "ON"
		UI.set_text(b, "ON" if now else "OFF")
		UI.style(b, "green" if now else "off")
		set_fn.call(now)
		Progress.save()
		settings_changed.emit())
	row.add_child(b)
	return row


## Run over. data: title, score, best (bool), rows [[label, value]], xp_text, xp_frac,
## level_up (text or ""), test (bool: a boss test, no rewards).
func show_over(data: Variant, title := "") -> void:
	if data is String:            # old callers
		data = {"title": title, "score": 0, "rows": [[data, ""]], "test": true}
	_clear(_overlay)
	_meter_box.visible = false
	_pause_btn.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.07, 0.1, 0.55)
	_overlay.add_child(_full(dim))
	var panel := UI.panel("panel_planks", 22)
	var v := _vbox(16)
	panel.add_child(v)
	var t := UI.label(data.get("title", "RUN OVER"), 70, Color.WHITE, 700, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if data.get("best", false):
		var rib := UI.panel("btn_red", 4)
		rib.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		rib.add_child(UI.label("NEW BEST!", 32))
		v.add_child(rib)
	if data.has("score"):
		var sc := UI.label(str(data["score"]), 100, UI.GOLD, 700, true)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sc)
	var rows := UI.panel("chip", 12)
	var rv := _vbox(8)
	rows.add_child(rv)
	for r in data.get("rows", []):
		var h := _hbox()
		var a := UI.label(r[0], 32, Color.WHITE, 600)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(a)
		h.add_child(UI.label(str(r[1]), 32, Color.WHITE, 600))
		rv.add_child(h)
	v.add_child(rows)
	if data.has("xp_text"):
		var xh := _hbox()
		var xl := UI.label(data["xp_text"], 28)
		xl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xh.add_child(xl)
		v.add_child(xh)
		var xb := UI.seg_bar(20, Vector2(20, 24), 4)
		UI.set_bar(xb, data.get("xp_frac", 0.0), Color("b06bff"))
		v.add_child(xb)
	if data.get("level_up", "") != "":
		var lu := UI.label(data["level_up"], 32, UI.GOLD)
		lu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(lu)
	var again := UI.button("RUN AGAIN", "green", 54, "play", 132)
	again.pressed.connect(func():
		_clear(_overlay)
		again_pressed.emit())
	v.add_child(again)
	var row := _hbox(12)
	for b in [["SKILLS", "stone", "skills"], ["SHOP", "gold", "shop"], ["MENU", "stone", "home"]]:
		var btn := UI.button(b[0], b[1], 32, "", 96)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func():
			_clear(_overlay)
			menu_pressed.emit()
			show_tab(b[2]))
		row.add_child(btn)
	v.add_child(row)
	_place(panel, _overlay, 40, 150, 40)
