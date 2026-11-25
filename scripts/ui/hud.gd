class_name Hud
extends CanvasLayer
## All on-screen UI, built in code. Emits intent signals; main.gd owns state.
##
## Layout (portrait): hole info at the top; the course in the middle (drag on
## it to move your landing target); shot panel at the bottom: club, height,
## spin ball and the HIT button.

signal target_drag(pos: Vector2, rel: Vector2) # screen position and movement
signal view_tapped
signal club_selected(idx: int)
signal height_selected(idx: int)
signal spin_changed(value: Vector2)
signal hit_pressed(error: float)
signal next_pressed
signal retry_pressed
signal map_toggled
signal meter_toggled(on: bool)
signal still_air_toggled(on: bool)
signal reset_stats_pressed

const PANEL_TOP := 0.655 # fraction of screen height where the shot panel starts

var root: Control
var view_area: Control
var hole_label: Label
var dist_label: Label
var elev_label: Label
var green_label: Label
var avg_label: Label
var wind_arrow: WindArrow
var wind_label: Label
var pin_marker: Label
var target_marker: Label
var shot_panel: PanelContainer
var club_buttons: Array[Button] = []
var height_buttons: Array[Button] = []
var spin_ball: SpinBall
var shot_info: Label
var profile: ProfileView
var hit_button: HitButton
var result_panel: PanelContainer
var result_title: Label
var result_sub: Label
var result_body: Label
var settings_panel: PanelContainer
var meter_check: CheckButton
var still_air_check: CheckButton
var toast: Label
var map_button: Button


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	view_area = Control.new()
	view_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	view_area.mouse_filter = Control.MOUSE_FILTER_STOP
	view_area.gui_input.connect(_on_view_input)
	root.add_child(view_area)

	_build_top()
	_build_markers()
	_build_shot_panel()
	_build_result()
	_build_settings()

	toast = Label.new()
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 34)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 8)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast)


# ------------------------------------------------------------------ build

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.03, 0.07, 0.05, 0.72)
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(14)
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.1, 0.25, 0.16, 0.9)
	btn.set_corner_radius_all(14)
	btn.set_content_margin_all(10)
	var btn_p := btn.duplicate()
	btn_p.bg_color = Color(0.25, 0.55, 0.35, 0.98)
	btn_p.border_color = Color(0.75, 1.0, 0.8)
	btn_p.set_border_width_all(2)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn)
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_stylebox("hover_pressed", "Button", btn_p)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Label", Color(0.96, 0.97, 0.94))
	return t


func _label(text: String, size: int = 26, color := Color(0.96, 0.97, 0.94)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_top() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 14
	panel.offset_right = -14
	panel.offset_top = 40
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)

	var row1 := HBoxContainer.new()
	v.add_child(row1)
	hole_label = _label("Hole 1", 26, Color(0.75, 0.85, 0.78))
	row1.add_child(hole_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(sp)
	avg_label = _label("", 24, Color(0.75, 0.85, 0.78))
	row1.add_child(avg_label)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	v.add_child(row2)
	dist_label = _label("60 m", 52)
	row2.add_child(dist_label)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	elev_label = _label("", 24)
	green_label = _label("", 24)
	col.add_child(elev_label)
	col.add_child(green_label)
	row2.add_child(col)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(sp2)
	var wind_box := VBoxContainer.new()
	wind_box.alignment = BoxContainer.ALIGNMENT_CENTER
	wind_arrow = WindArrow.new()
	wind_arrow.custom_minimum_size = Vector2(56, 56)
	wind_arrow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wind_box.add_child(wind_arrow)
	wind_label = _label("", 22)
	wind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wind_box.add_child(wind_label)
	row2.add_child(wind_box)

	var buttons := HBoxContainer.new()
	buttons.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	buttons.offset_top = 210
	buttons.offset_right = -14
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.add_theme_constant_override("separation", 10)
	root.add_child(buttons)
	map_button = Button.new()
	map_button.text = "Map"
	map_button.custom_minimum_size = Vector2(96, 64)
	map_button.pressed.connect(func(): map_toggled.emit())
	buttons.add_child(map_button)
	var gear := Button.new()
	gear.text = "Settings"
	gear.custom_minimum_size = Vector2(120, 64)
	gear.pressed.connect(func(): settings_panel.visible = not settings_panel.visible)
	buttons.add_child(gear)


func _build_markers() -> void:
	pin_marker = _marker(Color(1.0, 0.92, 0.3), 24)
	target_marker = _marker(Color(0.8, 0.95, 1.0), 22)


func _marker(c: Color, fs: int) -> Label:
	var l := _label("", fs, c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(l)
	return l


func _segment(names: Array, on_pick: Callable, fs := 24) -> Array[Button]:
	var group := ButtonGroup.new()
	var out: Array[Button] = []
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 58)
		b.add_theme_font_size_override("font_size", fs)
		var idx := i
		b.pressed.connect(func(): on_pick.call(idx))
		out.append(b)
	return out


func _build_shot_panel() -> void:
	shot_panel = PanelContainer.new()
	shot_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	shot_panel.anchor_top = PANEL_TOP
	shot_panel.offset_left = 10
	shot_panel.offset_right = -10
	shot_panel.offset_bottom = -12
	shot_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shot_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	shot_panel.add_child(v)

	var club_row := HBoxContainer.new()
	club_row.add_theme_constant_override("separation", 8)
	v.add_child(club_row)
	var names := []
	for c in Clubs.SET:
		names.append(c["name"].replace(" Wedge", ""))
	club_buttons = _segment(names, func(i): club_selected.emit(i), 26)
	for b in club_buttons:
		club_row.add_child(b)

	var h_row := HBoxContainer.new()
	h_row.add_theme_constant_override("separation", 8)
	v.add_child(h_row)
	var hn := []
	for h in ShotPlanner.HEIGHTS:
		hn.append(h["name"])
	height_buttons = _segment(hn, func(i): height_selected.emit(i), 22)
	for b in height_buttons:
		h_row.add_child(b)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bottom)
	spin_ball = SpinBall.new()
	spin_ball.custom_minimum_size = Vector2(250, 250)
	spin_ball.mouse_filter = Control.MOUSE_FILTER_STOP
	spin_ball.changed.connect(func(val): spin_changed.emit(val))
	bottom.add_child(spin_ball)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	bottom.add_child(right)
	profile = ProfileView.new()
	profile.custom_minimum_size = Vector2(0, 92)
	profile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(profile)
	shot_info = _label("", 19, Color(0.85, 0.93, 0.87))
	shot_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shot_info.custom_minimum_size = Vector2(0, 50)
	right.add_child(shot_info)
	hit_button = HitButton.new()
	hit_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hit_button.custom_minimum_size = Vector2(0, 110)
	hit_button.mouse_filter = Control.MOUSE_FILTER_STOP
	hit_button.hit.connect(func(err): hit_pressed.emit(err))
	right.add_child(hit_button)


func _build_result() -> void:
	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	result_panel.anchor_left = 0.0
	result_panel.anchor_right = 1.0
	result_panel.offset_left = 18
	result_panel.offset_right = -18
	result_panel.offset_bottom = -30
	result_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	result_panel.visible = false
	root.add_child(result_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	result_panel.add_child(v)
	result_title = _label("", 64, Color(1.0, 0.95, 0.6))
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(result_title)
	result_sub = _label("", 26, Color(0.8, 0.9, 0.82))
	result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(result_sub)
	result_body = _label("", 23)
	result_body.add_theme_constant_override("line_spacing", 2)
	v.add_child(result_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var retry := Button.new()
	retry.text = "Replay hole"
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry.custom_minimum_size = Vector2(0, 80)
	retry.pressed.connect(func(): retry_pressed.emit())
	row.add_child(retry)
	var nxt := Button.new()
	nxt.text = "Next hole"
	nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nxt.custom_minimum_size = Vector2(0, 80)
	nxt.add_theme_font_size_override("font_size", 30)
	nxt.pressed.connect(func(): next_pressed.emit())
	row.add_child(nxt)


func _build_settings() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	settings_panel.anchor_left = 0.0
	settings_panel.anchor_right = 1.0
	settings_panel.offset_left = 26
	settings_panel.offset_right = -26
	settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	settings_panel.visible = false
	var solid := StyleBoxFlat.new()
	solid.bg_color = Color(0.05, 0.1, 0.07, 0.98)
	solid.set_corner_radius_all(18)
	solid.set_content_margin_all(18)
	solid.border_color = Color(0.3, 0.5, 0.36)
	solid.set_border_width_all(2)
	settings_panel.add_theme_stylebox_override("panel", solid)
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(settings_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	settings_panel.add_child(v)
	v.add_child(_label("How to play", 34))
	var how := _label("1. Drag on the course to move your landing spot (the ring). The arc shows the flight, wind included: white is clear, red hits something.\n2. Pick a wedge and a height: Punch runs low under branches, Flop goes high over trees.\n3. Drag the dot on the ball: down for more backspin (stops, can spin back), up for a runner, left/right to draw or fade around things.\n4. Read the wind and the green (slopes, firmness), then HIT. Stop the needle in the green for a pure strike.", 21, Color(0.82, 0.92, 0.85))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(how)
	meter_check = CheckButton.new()
	meter_check.text = "Accuracy needle"
	meter_check.button_pressed = true
	meter_check.toggled.connect(func(on): meter_toggled.emit(on))
	v.add_child(meter_check)
	still_air_check = CheckButton.new()
	still_air_check.text = "Pro: plan in still air (read the wind yourself)"
	still_air_check.toggled.connect(func(on): still_air_toggled.emit(on))
	v.add_child(still_air_check)
	var reset := Button.new()
	reset.text = "Reset stats"
	reset.custom_minimum_size = Vector2(0, 64)
	reset.pressed.connect(func(): reset_stats_pressed.emit())
	v.add_child(reset)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 72)
	close.pressed.connect(func(): settings_panel.visible = false)
	v.add_child(close)


# ------------------------------------------------------------------ input

func _on_view_input(e: InputEvent) -> void:
	if e is InputEventScreenDrag:
		target_drag.emit(e.position, e.relative)
	elif e is InputEventScreenTouch and not e.pressed:
		view_tapped.emit()


# ------------------------------------------------------------------ updates

func show_toast(text: String) -> void:
	toast.text = text
	toast.reset_size()
	toast.position = Vector2((root.size.x - toast.size.x) * 0.5, root.size.y * 0.42)


func set_hole_info(hole_no: int, hole: HoleData, aim_yaw_deg: float) -> void:
	hole_label.text = "Hole %d" % hole_no
	dist_label.text = "%d m" % roundi(hole.distance)
	var e := hole.elevation
	if absf(e) < 0.75:
		elev_label.text = "Level"
	else:
		elev_label.text = ("Uphill %d m" if e > 0.0 else "Downhill %d m") % roundi(absf(e))
	green_label.text = "%s green" % hole.green_firmness_label()
	update_wind(hole, aim_yaw_deg)


func update_wind(hole: HoleData, aim_yaw_deg: float) -> void:
	var w := hole.wind_10m
	var spd := w.length()
	wind_label.text = "Calm" if spd < 0.5 else "%.1f m/s" % spd
	var fwd := LaunchModel.dir_from(aim_yaw_deg, 0.0)
	var right := fwd.cross(Vector3.UP)
	# Screen angle: 0 = blowing toward the target (up), positive = to the right.
	wind_arrow.angle = atan2(w.dot(right), w.dot(fwd))
	wind_arrow.strength = clampf(spd / 7.0, 0.0, 1.0)
	wind_arrow.visible = spd >= 0.5
	wind_arrow.queue_redraw()


func set_stats(stats: Stats) -> void:
	if stats.shots == 0:
		avg_label.text = "Avg to pin: –"
	else:
		avg_label.text = "Avg %.1f m  ·  last %d: %.1f m" % [stats.average(), stats.recent.size(), stats.recent_average()]


func set_selection(club_idx: int, height_idx: int) -> void:
	# Setting button_pressed keeps the ButtonGroup consistent; our handlers
	# listen to `pressed`, which only fires for real taps.
	club_buttons[club_idx].button_pressed = true
	height_buttons[height_idx].button_pressed = true


func set_shot_visible(v: bool) -> void:
	shot_panel.visible = v
	target_marker.visible = v


func place_marker(label: Label, cam: Camera3D, world: Vector3, text: String, lift_px := 40.0) -> void:
	if cam.is_position_behind(world):
		label.visible = false
		return
	var sp := cam.unproject_position(world)
	label.text = text
	label.reset_size()
	label.position = sp - Vector2(label.size.x * 0.5, label.size.y + lift_px)
	label.visible = true


func show_result(title: String, sub: String, body: String) -> void:
	result_title.text = title
	result_sub.text = sub
	result_body.text = body
	result_panel.visible = true


func hide_result() -> void:
	result_panel.visible = false


# ------------------------------------------------------------------ widgets

class WindArrow extends Control:
	var angle := 0.0
	var strength := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.45
		draw_circle(c, r, Color(1, 1, 1, 0.12))
		var col := Color(0.55, 0.85, 1.0).lerp(Color(1.0, 0.5, 0.35), strength)
		var d := Vector2(sin(angle), -cos(angle))
		var tip := c + d * r * 0.9
		var tail := c - d * r * 0.7
		var side := Vector2(-d.y, d.x)
		draw_line(tail, tip, col, 5.0)
		draw_colored_polygon(PackedVector2Array([tip, tip - d * r * 0.5 + side * r * 0.35, tip - d * r * 0.5 - side * r * 0.35]), col)
