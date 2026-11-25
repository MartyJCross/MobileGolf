class_name Hud
extends CanvasLayer
## All on-screen UI, built in code. Emits intent signals; main.gd owns state.

signal swing_touch(kind: int, pos: Vector2)
signal controls_changed(scheme: int)
signal mark_toggled(on: bool)
signal shape_changed(value: float)
signal aim_drag(dx: float)
signal view_tapped
signal club_step(delta: int)
signal trajectory_changed(value: float)
signal next_pressed
signal retry_pressed
signal map_toggled
signal tempo_changed(value: float)
signal reset_stats_pressed

const SWING_ZONE_TOP := 0.62 # fraction of screen height

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
var carry_marker: Label
var club_label: Label
var club_sub: Label
var traj_slider: HSlider
var traj_label: Label
var swing_view: SwingView
var shape_slider: HSlider
var shape_label: Label
var result_panel: PanelContainer
var result_title: Label
var result_sub: Label
var result_body: Label
var settings_panel: PanelContainer
var tempo_slider: HSlider
var tempo_label: Label
var scheme_buttons: Array[Button] = []
var scheme_desc: Label
var mark_check: CheckButton
var toast: Label
var controls_bar: Control
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
	_build_controls()
	_build_swing_zone()
	_build_result()
	_build_settings()

	toast = Label.new()
	toast.set_anchors_preset(Control.PRESET_CENTER)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 34)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 8)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(toast)


# ------------------------------------------------------------------ build

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.03, 0.07, 0.05, 0.62)
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.1, 0.25, 0.16, 0.85)
	btn.set_corner_radius_all(14)
	btn.set_content_margin_all(12)
	var btn_p := btn.duplicate()
	btn_p.bg_color = Color(0.2, 0.45, 0.3, 0.95)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn)
	t.set_stylebox("pressed", "Button", btn_p)
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
	dist_label = _label("150 m", 52)
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
	pin_marker = _label("", 24, Color(1.0, 0.92, 0.3))
	pin_marker.add_theme_color_override("font_outline_color", Color.BLACK)
	pin_marker.add_theme_constant_override("outline_size", 6)
	pin_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(pin_marker)
	carry_marker = _label("", 20, Color(0.8, 0.95, 1.0))
	carry_marker.add_theme_color_override("font_outline_color", Color.BLACK)
	carry_marker.add_theme_constant_override("outline_size", 5)
	carry_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(carry_marker)


func _build_controls() -> void:
	controls_bar = PanelContainer.new()
	controls_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	controls_bar.anchor_top = SWING_ZONE_TOP
	controls_bar.anchor_bottom = SWING_ZONE_TOP
	controls_bar.offset_left = 14
	controls_bar.offset_right = -14
	controls_bar.offset_top = -196
	controls_bar.offset_bottom = -8
	controls_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(controls_bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	controls_bar.add_child(v)

	var club_row := HBoxContainer.new()
	v.add_child(club_row)
	var prev := Button.new()
	prev.text = "  <  "
	prev.custom_minimum_size = Vector2(90, 58)
	prev.pressed.connect(func(): club_step.emit(-1)) # toward longer clubs
	club_row.add_child(prev)
	var club_col := VBoxContainer.new()
	club_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	club_col.add_theme_constant_override("separation", -6)
	club_label = _label("7 Iron", 32)
	club_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	club_sub = _label("", 20, Color(0.75, 0.85, 0.78))
	club_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	club_col.add_child(club_label)
	club_col.add_child(club_sub)
	club_row.add_child(club_col)
	var nxt := Button.new()
	nxt.text = "  >  "
	nxt.custom_minimum_size = Vector2(90, 58)
	nxt.pressed.connect(func(): club_step.emit(1)) # toward shorter clubs
	club_row.add_child(nxt)

	var traj_row := HBoxContainer.new()
	traj_row.add_theme_constant_override("separation", 10)
	v.add_child(traj_row)
	traj_row.add_child(_label("Low", 22))
	traj_slider = HSlider.new()
	traj_slider.min_value = -1.0
	traj_slider.max_value = 1.0
	traj_slider.step = 0.25
	traj_slider.value = 0.0
	traj_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	traj_slider.custom_minimum_size = Vector2(0, 44)
	traj_slider.value_changed.connect(func(val): trajectory_changed.emit(val))
	traj_row.add_child(traj_slider)
	traj_row.add_child(_label("High", 22))
	traj_label = _label("Stock", 22, Color(0.75, 0.85, 0.78))
	traj_label.custom_minimum_size = Vector2(110, 0)
	traj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	traj_row.add_child(traj_label)

	var shape_row := HBoxContainer.new()
	shape_row.add_theme_constant_override("separation", 10)
	v.add_child(shape_row)
	shape_row.add_child(_label("Draw", 22))
	shape_slider = HSlider.new()
	shape_slider.min_value = -1.0
	shape_slider.max_value = 1.0
	shape_slider.step = 0.5
	shape_slider.value = 0.0
	shape_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_slider.custom_minimum_size = Vector2(0, 44)
	shape_slider.value_changed.connect(func(val):
		shape_label.text = _shape_text(val)
		shape_changed.emit(val))
	shape_row.add_child(shape_slider)
	shape_row.add_child(_label("Fade", 22))
	shape_label = _label("Straight", 22, Color(0.75, 0.85, 0.78))
	shape_label.custom_minimum_size = Vector2(110, 0)
	shape_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shape_row.add_child(shape_label)


func _build_swing_zone() -> void:
	swing_view = SwingView.new()
	swing_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	swing_view.anchor_top = SWING_ZONE_TOP
	swing_view.mouse_filter = Control.MOUSE_FILTER_STOP
	swing_view.touch.connect(func(kind, pos): swing_touch.emit(kind, pos))
	root.add_child(swing_view)


static func _shape_text(v: float) -> String:
	if v <= -0.99:
		return "Draw"
	if v < -0.01:
		return "Slight draw"
	if v >= 0.99:
		return "Fade"
	if v > 0.01:
		return "Slight fade"
	return "Straight"


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
	settings_panel.offset_left = 30
	settings_panel.offset_right = -30
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
	v.add_child(_label("Settings", 36))
	v.add_child(_label("Downswing speed on screen. Slower is easier to time; real speed is the full challenge.", 21, Color(0.8, 0.9, 0.82)))
	v.get_child(1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	v.add_child(row)
	tempo_slider = HSlider.new()
	tempo_slider.min_value = 0.3
	tempo_slider.max_value = 1.0
	tempo_slider.step = 0.05
	tempo_slider.value = 0.55
	tempo_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tempo_slider.custom_minimum_size = Vector2(0, 50)
	tempo_slider.value_changed.connect(func(val):
		tempo_label.text = tempo_text(val)
		tempo_changed.emit(val))
	row.add_child(tempo_slider)
	tempo_label = _label(tempo_text(0.55), 24)
	tempo_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(tempo_label)
	v.add_child(_label("Controls", 28))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var group := ButtonGroup.new()
	for i in SwingControls.NAMES.size():
		var b := Button.new()
		b.text = SwingControls.NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 64)
		var idx := i
		b.pressed.connect(func():
			scheme_desc.text = SwingControls.DESCRIPTIONS[idx]
			controls_changed.emit(idx))
		grid.add_child(b)
		scheme_buttons.append(b)
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.25, 0.55, 0.35, 0.95)
	pressed_style.set_corner_radius_all(14)
	pressed_style.set_content_margin_all(12)
	for b in scheme_buttons:
		b.add_theme_stylebox_override("pressed", pressed_style)
		b.add_theme_stylebox_override("hover_pressed", pressed_style)
	scheme_desc = _label("", 22, Color(0.8, 0.9, 0.82))
	scheme_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(scheme_desc)
	mark_check = CheckButton.new()
	mark_check.text = "Show release line (green)"
	mark_check.button_pressed = true
	mark_check.toggled.connect(func(on): mark_toggled.emit(on))
	v.add_child(mark_check)
	var how := _label("Release on time for full speed and a square face. Early: the club flips past your hands (higher, closed face, pulls and hooks). Late: still lagging (lower, open face, pushes and slices). No release: your wrists give way late on their own.", 21, Color(0.8, 0.9, 0.82))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(how)
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
		aim_drag.emit(e.relative.x)
	elif e is InputEventScreenTouch and not e.pressed:
		view_tapped.emit()


static func tempo_text(v: float) -> String:
	if v >= 0.99:
		return "Real speed"
	return "%d%% speed" % roundi(v * 100.0)


# ------------------------------------------------------------------ updates

func show_toast(text: String) -> void:
	toast.text = text
	toast.position = Vector2((root.size.x - toast.size.x) * 0.5, root.size.y * 0.42)


func set_hole_info(hole_no: int, hole: HoleData, aim_yaw_deg: float) -> void:
	hole_label.text = "Hole %d  ·  Par 3" % hole_no
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
	wind_arrow.strength = clampf(spd / 9.0, 0.0, 1.0)
	wind_arrow.visible = spd >= 0.5
	wind_arrow.queue_redraw()


func set_stats(stats: Stats) -> void:
	if stats.shots == 0:
		avg_label.text = "Avg to pin: –"
	else:
		avg_label.text = "Avg %.1f m  ·  last %d: %.1f m" % [stats.average(), stats.recent.size(), stats.recent_average()]


func set_club(club: Dictionary, stock_carry: float, traj: float) -> void:
	club_label.text = club["name"]
	club_sub.text = "Full swing carries ~%d m (no wind)" % roundi(stock_carry)
	traj_label.text = "Stock" if absf(traj) < 0.01 else ("High %+.2f" % traj if traj > 0 else "Low %.2f" % traj)


func set_controls(scheme: int, show_mark: bool) -> void:
	scheme_buttons[scheme].button_pressed = true
	scheme_desc.text = SwingControls.DESCRIPTIONS[scheme]
	mark_check.set_pressed_no_signal(show_mark)


func set_aiming_visible(v: bool) -> void:
	controls_bar.visible = v
	carry_marker.visible = v


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
