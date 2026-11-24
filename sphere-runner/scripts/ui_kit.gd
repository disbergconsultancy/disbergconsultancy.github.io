class_name UI
extends RefCounted
## The block-pixel UI kit: Pixelify Sans, block buttons and panels (9-patch textures in
## assets/ui, made by a script from the agreed designs), 8x8 pixel icons and segmented bars.
## Layout is in the 720 x 1280 design space; one UI pixel is 6 px.

const INK := Color("1a1c22")
const U := 6
const GOLD := Color("ffd34a")
const HERO_ICONS := {"runner": "hero", "smasher": "hero", "jumper": "hero"}

static var _fonts := {}
static var click: Callable          # played on every button press (set by the game)
static var sound: Callable          # sound(name): plays a sound effect (set by the game)
static var _tex := {}


static func font(weight := 700) -> Font:
	# Pixelify Sans comes in 400, 600 and 700: other weights use the nearest one (a missing
	# file would fall back to the engine's smooth default font).
	weight = 400 if weight < 500 else (600 if weight < 650 else 700)
	if not _fonts.has(weight):
		var f: FontFile = load("res://assets/fonts/PixelifySans-%d.ttf" % weight)
		_fonts[weight] = f
	return _fonts[weight]


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://assets/ui/%s.png" % name)
	return _tex[name]


## A block box (9-patch): ink border, bevel, face. Panels with a textured face tile it.
static func box(name: String, pad := 18.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(name)
	sb.set_texture_margin_all(2 * U)
	sb.set_content_margin_all(2 * U + pad)
	if name in ["panel_stone", "panel_planks"]:
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


## Text with a hard pixel shadow (or a thick outline for big titles). Vertically centred,
## so it lines up with icons and the boxes it sits in.
static func label(text: String, size := 32, color := Color.WHITE, weight := 700, outline := false) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font(weight)
	ls.font_size = size
	ls.font_color = color
	ls.shadow_color = INK
	ls.shadow_size = 0
	var s := maxi(3, size / 12)
	ls.shadow_offset = Vector2(s, s)
	if outline:
		ls.outline_size = maxi(8, size / 6)
		ls.outline_color = INK
		ls.shadow_offset = Vector2(s + 2, s + 2)
		ls.shadow_size = ls.outline_size
	l.label_settings = ls
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Icon sizes snap to whole multiples of the 8 px source, so every icon pixel is the same size.
static func px(size: float) -> float:
	return maxf(8.0, round(size / 8.0) * 8.0)


## An 8x8 pixel icon, scaled up without smoothing and tinted.
static func icon(name: String, size := 40.0, color := Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex("icon_" + name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var s := px(size)
	t.custom_minimum_size = Vector2(s, s)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## A block button. kind: stone | green | gold | red | blue | off. Icon and text are one
## group, centred in the face (side by side, or stacked with vertical = true).
## Change them later with set_text() / set_icon_color() / disable().
static func button(text: String, kind := "stone", size := 34, icon_name := "", height := 96.0, vertical := false, icon_size := 0.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, height)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		if click.is_valid():
			click.call())
	style(b, kind)
	b.add_theme_stylebox_override("disabled", box("btn_off", 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var group: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	group.alignment = BoxContainer.ALIGNMENT_CENTER
	group.add_theme_constant_override("separation", 6 if vertical else 14)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(group)
	group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	group.offset_left = 2 * U
	group.offset_right = -2 * U
	if icon_name != "":
		var ic := icon(icon_name, icon_size if icon_size > 0.0 else size * (1.0 if text != "" else 1.4))
		group.add_child(ic)
		b.set_meta("icon", ic)
	if text != "":
		var l := label(text, size)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		group.add_child(l)
		b.set_meta("label", l)
	return b


static func style(b: Button, kind: String) -> void:
	b.add_theme_stylebox_override("normal", box("btn_" + kind, 6))
	b.add_theme_stylebox_override("hover", box("btn_" + kind, 6))
	b.add_theme_stylebox_override("pressed", box("btn_%s_down" % kind if kind != "off" else "btn_off", 6))


static func set_text(b: Button, text: String) -> void:
	if b.has_meta("label"):
		b.get_meta("label").text = text


static func get_text(b: Button) -> String:
	return b.get_meta("label").text if b.has_meta("label") else ""


static func set_icon_color(b: Button, c: Color) -> void:
	if b.has_meta("icon"):
		b.get_meta("icon").modulate = c


static func disable(b: Button, off: bool) -> void:
	b.disabled = off
	for k in ["label", "icon"]:
		if b.has_meta(k):
			b.get_meta(k).modulate.a = 0.45 if off else 1.0


## A small dark block holding a row of things (icon + text), centred. min: its smallest size.
static func chip(children: Array, kind := "chip", min := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(kind, 4))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = min
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	for c in children:
		row.add_child(c)
	return p


static func panel(kind := "panel", pad := 18.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(kind, pad))
	return p


## A segmented bar: `total` cells in an ink frame. Fill it with set_bar().
static func seg_bar(total: int, cell := Vector2(20, 24), gap := 4) -> PanelContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", gap)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in total:
		var c := ColorRect.new()
		c.custom_minimum_size = cell
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bevel(c, cell)
		bar.add_child(c)
	set_bar(bar, 0.0, Color.WHITE)
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = INK
	sb.set_content_margin_all(gap + 2)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(bar)
	frame.set_meta("bar", bar)
	return frame


## A pixel block bevel on a bar cell, like the buttons: light top and left edges, a darker
## bottom and right. Overlays, so the cell keeps its own colour.
static func _bevel(c: ColorRect, cell: Vector2) -> void:
	var e := maxf(2.0, round(cell.y / 6.0))       # edge thickness
	var parts := [
		[Color(1, 1, 1, 0.38), Control.PRESET_TOP_WIDE, Vector2(0, e)],
		[Color(1, 1, 1, 0.22), Control.PRESET_LEFT_WIDE, Vector2(e, 0)],
		[Color(0, 0, 0, 0.32), Control.PRESET_BOTTOM_WIDE, Vector2(0, e * 1.5)],
		[Color(0, 0, 0, 0.22), Control.PRESET_RIGHT_WIDE, Vector2(e, 0)]]
	for p in parts:
		var r := ColorRect.new()
		r.color = p[0]
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(r)
		r.set_anchors_and_offsets_preset(p[1])
		if p[2].y > 0.0:
			if p[1] == Control.PRESET_TOP_WIDE:
				r.offset_bottom = p[2].y
			else:
				r.offset_top = -p[2].y
		else:
			if p[1] == Control.PRESET_LEFT_WIDE:
				r.offset_right = p[2].x
			else:
				r.offset_left = -p[2].x


static func set_bar(frame_or_bar: Control, fraction: float, color: Color) -> void:
	var bar: HBoxContainer = frame_or_bar.get_meta("bar") if frame_or_bar.has_meta("bar") else frame_or_bar
	var n := bar.get_child_count()
	var lit := int(round(clampf(fraction, 0.0, 1.0) * n))
	for i in n:
		bar.get_child(i).color = color if i < lit else Color("2b2d36")


## A full-screen background of tiled dark rock.
static func backdrop() -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex("tile_dark")
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	return t
