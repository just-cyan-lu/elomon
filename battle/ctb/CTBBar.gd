extends Control

signal token_hovered(description: String)
signal token_hover_ended

const PREVIEW_COUNT := 6
const AXIS_PANEL_SIZE := Vector2(286, 44)
const BARS_PANEL_SIZE := Vector2(286, 44)
const TRACK_POS := Vector2(66, 8)
const TRACK_SIZE := Vector2(208, 28)
const TOKEN_SIZE := Vector2(18, 18)

enum ViewMode {
	BARS,
	AXIS
}

var _units: Array[Unit] = []
var _axis_tokens: Dictionary = {}
var _order_tokens: Array[Button] = []
var _active_unit: Unit = null
var _is_ctb_running: bool = false
var _view_mode: int = ViewMode.AXIS
var _bar_list: VBoxContainer
var _axis_track: Control
var _order_track: Control
var _toggle_button: Button
var _background_panel: PanelContainer

func _ready() -> void:
	_build_background_panel()
	_bar_list = $VBoxContainer
	_bar_list.visible = false
	_build_view_toggle()
	_build_axis_view()
	_build_order_view()
	_apply_view_mode()

func _build_background_panel() -> void:
	_background_panel = PanelContainer.new()
	_background_panel.position = Vector2(-4, -4)
	_background_panel.size = AXIS_PANEL_SIZE
	_background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.07, 0.80)
	style.border_color = Color(0.30, 0.36, 0.48, 0.45)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_background_panel.add_theme_stylebox_override("panel", style)
	add_child(_background_panel)
	move_child(_background_panel, 0)

func _build_view_toggle() -> void:
	_toggle_button = Button.new()
	_toggle_button.position = Vector2(4, 4)
	_toggle_button.custom_minimum_size = Vector2(58, 20)
	_toggle_button.add_theme_font_size_override("font_size", 7)
	_toggle_button.pressed.connect(_toggle_view_mode)
	add_child(_toggle_button)
	_bar_list.position = Vector2(4, 28)

func _build_axis_view() -> void:
	_axis_track = _make_track()
	add_child(_axis_track)

func _build_order_view() -> void:
	_order_track = _make_track()
	add_child(_order_track)
	for i in range(PREVIEW_COUNT):
		var token := _make_token()
		_order_track.add_child(token)
		_order_tokens.append(token)

func _make_track() -> Control:
	var track := Control.new()
	track.position = TRACK_POS
	track.size = TRACK_SIZE
	var line := ColorRect.new()
	line.position = Vector2(0, 13)
	line.size = Vector2(TRACK_SIZE.x, 2)
	line.color = Color(0.42, 0.48, 0.60, 0.75)
	track.add_child(line)
	var ready_mark := ColorRect.new()
	ready_mark.position = Vector2(TRACK_SIZE.x - 2, 6)
	ready_mark.size = Vector2(2, 16)
	ready_mark.color = Color(1.0, 0.82, 0.35, 0.95)
	track.add_child(ready_mark)
	return track

func _make_token() -> Button:
	var token := Button.new()
	token.custom_minimum_size = TOKEN_SIZE
	token.size = TOKEN_SIZE
	token.focus_mode = Control.FOCUS_NONE
	token.mouse_filter = Control.MOUSE_FILTER_STOP
	token.add_theme_font_size_override("font_size", 8)
	token.mouse_entered.connect(func(): _emit_token_hover(token))
	token.mouse_exited.connect(func(): emit_signal("token_hover_ended"))
	return token

func _toggle_view_mode() -> void:
	if _view_mode == ViewMode.BARS:
		_view_mode = ViewMode.AXIS
	else:
		_view_mode = ViewMode.BARS
	_apply_view_mode()

func _apply_view_mode() -> void:
	if _toggle_button != null:
		_toggle_button.text = "顺序" if _view_mode == ViewMode.BARS else "AP轴"
	if _background_panel != null:
		_background_panel.size = BARS_PANEL_SIZE if _view_mode == ViewMode.BARS else AXIS_PANEL_SIZE
	if _bar_list != null:
		_bar_list.visible = false
	if _axis_track != null:
		_axis_track.visible = _view_mode == ViewMode.AXIS
	if _order_track != null:
		_order_track.visible = _view_mode == ViewMode.BARS

func add_unit(unit: Unit) -> void:
	if unit in _units:
		return
	_units.append(unit)
	var token := _make_token()
	_axis_track.add_child(token)
	_axis_tokens[unit] = token
	_refresh_axis()
	_refresh_order()

func remove_unit(unit: Unit) -> void:
	_units.erase(unit)
	if _axis_tokens.has(unit):
		var token: Button = _axis_tokens[unit]
		if is_instance_valid(token):
			token.queue_free()
		_axis_tokens.erase(unit)
	if _active_unit == unit:
		_active_unit = null
	_refresh_axis()
	_refresh_order()

func set_ctb_state(is_running: bool, ready_unit: Unit = null) -> void:
	_is_ctb_running = is_running
	_active_unit = ready_unit
	_refresh_axis(_get_next_predicted_unit())
	_refresh_order()

func _process(_delta: float) -> void:
	var next_unit := _get_next_predicted_unit()
	_refresh_axis(next_unit)
	if _view_mode == ViewMode.AXIS:
		return
	_refresh_order()

func _refresh_axis(next_unit: Unit = null) -> void:
	var units := _get_alive_units()
	for i in range(units.size()):
		var unit := units[i]
		if not _axis_tokens.has(unit):
			continue
		var token: Button = _axis_tokens[unit]
		if not is_instance_valid(token):
			continue
		var ratio: float = clampf(float(unit.current_ap) / float(Enums.MAX_AP), 0.0, 1.0)
		var x: float = ratio * (TRACK_SIZE.x - TOKEN_SIZE.x)
		var y: float = 2.0 if i % 2 == 0 else 14.0
		token.position = Vector2(x, y)
		token.text = _avatar_letter(unit)
		token.set_meta("hover_text", _build_hover_text(unit, _get_prediction_index(unit)))
		_style_token(token, unit, unit == _active_unit, unit == next_unit)

func _refresh_order() -> void:
	var order := _predict_action_order(PREVIEW_COUNT)
	var denominator: float = max(1.0, float(PREVIEW_COUNT - 1))
	for i in range(_order_tokens.size()):
		var token: Button = _order_tokens[i]
		if i >= order.size():
			token.visible = false
			continue
		var unit: Unit = order[i]["unit"]
		token.visible = true
		var slot_ratio := 1.0 - float(i) / denominator
		token.position = Vector2(slot_ratio * (TRACK_SIZE.x - TOKEN_SIZE.x), 5.0)
		token.text = _avatar_letter(unit)
		token.set_meta("hover_text", _build_hover_text(unit, i + 1))
		_style_token(token, unit, i == 0 and unit == _active_unit, i == 0)

func _get_next_predicted_unit() -> Unit:
	if _active_unit != null and is_instance_valid(_active_unit):
		return _active_unit
	var order := _predict_action_order(1)
	if order.is_empty():
		return null
	return order[0]["unit"]

func _predict_action_order(count: int) -> Array[Dictionary]:
	var sim_units: Array[Unit] = []
	var sim_ap := {}
	for unit in _units:
		if is_instance_valid(unit) and unit.is_alive() and unit.data.speed > 0:
			sim_units.append(unit)
			sim_ap[unit] = unit.current_ap
	var result: Array[Dictionary] = []
	while result.size() < count and not sim_units.is_empty():
		var next_unit: Unit = null
		var next_time := INF
		for unit in sim_units:
			var ap_value: float = sim_ap[unit]
			var time_to_ready := 0.0
			if ap_value < Enums.MAX_AP:
				time_to_ready = (Enums.MAX_AP - ap_value) / unit.data.speed
			if time_to_ready < next_time:
				next_time = time_to_ready
				next_unit = unit
		if next_unit == null:
			break
		for unit in sim_units:
			sim_ap[unit] = min(float(sim_ap[unit]) + unit.data.speed * next_time, Enums.MAX_AP)
		result.append({"unit": next_unit, "time": next_time})
		sim_ap[next_unit] = max(float(sim_ap[next_unit]) - Enums.MAX_AP, 0.0)
	return result

func _get_prediction_index(unit: Unit) -> int:
	var order := _predict_action_order(PREVIEW_COUNT)
	for i in range(order.size()):
		if order[i]["unit"] == unit:
			return i + 1
	return -1

func _get_alive_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in _units:
		if is_instance_valid(unit) and unit.is_alive():
			result.append(unit)
	return result

func _style_token(token: Button, unit: Unit, active: bool = false, next: bool = false) -> void:
	var base_color := _get_unit_color(unit)
	var style := StyleBoxFlat.new()
	style.bg_color = base_color.darkened(0.18)
	style.border_color = Color(1.0, 0.88, 0.35, 1.0) if active else base_color.lightened(0.18)
	style.set_border_width_all(2 if active or next else 1)
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	token.add_theme_stylebox_override("normal", style)
	token.add_theme_stylebox_override("hover", style)
	token.add_theme_stylebox_override("pressed", style)
	token.add_theme_color_override("font_color", Color(0.05, 0.06, 0.08, 1.0))

func _emit_token_hover(token: Button) -> void:
	var description := str(token.get_meta("hover_text", ""))
	if description != "":
		emit_signal("token_hovered", description)

func _build_hover_text(unit: Unit, predicted_rank: int) -> String:
	var status := "行动中" if unit == _active_unit else ("暂停中" if not _is_ctb_running else "等待中")
	var rank_text := "预计较后行动"
	if predicted_rank > 0:
		rank_text = "预计第 %d 位行动" % predicted_rank
	return "%s（%s） AP %d/%d，速度 %d，%s，%s。" % [
		unit.data.unit_name,
		_get_unit_side_text(unit),
		int(round(unit.current_ap)),
		Enums.MAX_AP,
		int(round(unit.data.speed)),
		status,
		rank_text
	]

func _get_unit_side_text(unit: Unit) -> String:
	if unit.is_ally():
		return "我方"
	if unit.data.unit_type == Enums.UnitType.WILD_POKEMON:
		return "中立"
	return "敌方"

func _get_unit_color(unit: Unit) -> Color:
	if unit == _active_unit:
		return Color(1.0, 0.88, 0.35, 1.0)
	if unit.is_ally():
		return Color(0.55, 0.74, 1.0, 1.0)
	if unit.data.unit_type == Enums.UnitType.WILD_POKEMON:
		return Color(0.95, 0.82, 0.45, 1.0)
	return Color(1.0, 0.55, 0.55, 1.0)

func _avatar_letter(unit: Unit) -> String:
	var name := unit.data.unit_name
	if name.length() <= 1:
		return name
	return name.substr(0, 1)
