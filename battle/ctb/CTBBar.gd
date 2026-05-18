extends Control

const PREVIEW_COUNT := 6

enum ViewMode {
	BARS,
	AXIS
}

var _bars: Dictionary = {}   # unit -> ProgressBar，动态追踪
var _labels: Dictionary = {} # unit -> Label
var _active_unit: Unit = null
var _is_ctb_running: bool = false
var _view_mode: int = ViewMode.BARS
var _bar_list: VBoxContainer
var _axis_list: HBoxContainer
var _toggle_button: Button
var _axis_labels: Array[Label] = []

func _ready() -> void:
	_bar_list = $VBoxContainer
	_build_view_toggle()
	_build_axis_view()
	_apply_view_mode()

func _build_view_toggle() -> void:
	_toggle_button = Button.new()
	_toggle_button.custom_minimum_size = Vector2(96, 18)
	_toggle_button.add_theme_font_size_override("font_size", 7)
	_toggle_button.pressed.connect(_toggle_view_mode)
	add_child(_toggle_button)
	move_child(_toggle_button, 0)
	_bar_list.position = Vector2(0, 20)

func _build_axis_view() -> void:
	_axis_list = HBoxContainer.new()
	_axis_list.position = Vector2(0, 22)
	_axis_list.add_theme_constant_override("separation", 2)
	add_child(_axis_list)
	for i in range(PREVIEW_COUNT):
		var label := Label.new()
		label.custom_minimum_size = Vector2(34, 32)
		label.add_theme_font_size_override("font_size", 6)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_axis_list.add_child(label)
		_axis_labels.append(label)

func _toggle_view_mode() -> void:
	if _view_mode == ViewMode.BARS:
		_view_mode = ViewMode.AXIS
	else:
		_view_mode = ViewMode.BARS
	_apply_view_mode()

func _apply_view_mode() -> void:
	if _toggle_button != null:
		_toggle_button.text = "视图:跑条" if _view_mode == ViewMode.BARS else "视图:行动轴"
	if _bar_list != null:
		_bar_list.visible = _view_mode == ViewMode.BARS
	if _axis_list != null:
		_axis_list.visible = _view_mode == ViewMode.AXIS

func add_unit(unit: Unit) -> void:
	var hbox := HBoxContainer.new()
	
	var label := Label.new()
	label.text = unit.data.unit_name
	label.custom_minimum_size.x = 52
	label.add_theme_font_size_override("font_size", 6)
	hbox.add_child(label)
	
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = Enums.MAX_AP
	bar.value = 0
	bar.custom_minimum_size = Vector2(60, 8)
	bar.show_percentage = false
	hbox.add_child(bar)
	
	_bar_list.add_child(hbox)
	_bars[unit] = bar
	_labels[unit] = label

func remove_unit(unit: Unit) -> void:
	if _bars.has(unit):
		_bars[unit].get_parent().queue_free()
		_bars.erase(unit)
	_labels.erase(unit)
	if _active_unit == unit:
		_active_unit = null

func set_ctb_state(is_running: bool, ready_unit: Unit = null) -> void:
	_is_ctb_running = is_running
	_active_unit = ready_unit
	_refresh_labels()

func _process(_delta: float) -> void:
	var next_unit := _get_next_predicted_unit()
	for unit in _bars:
		if is_instance_valid(unit) and is_instance_valid(_bars[unit]):
			_bars[unit].value = unit.current_ap
			if unit == _active_unit:
				_bars[unit].modulate = Color(1.0, 0.88, 0.35, 1.0)
			elif unit == next_unit:
				_bars[unit].modulate = Color(0.7, 1.0, 0.65, 1.0)
			else:
				_bars[unit].modulate = Color.WHITE
	_refresh_labels()
	if _view_mode == ViewMode.AXIS:
		_refresh_axis()

func _refresh_labels() -> void:
	for unit in _labels:
		if not is_instance_valid(unit) or not is_instance_valid(_labels[unit]):
			continue
		var prefix := ""
		if unit == _active_unit:
			prefix = "READY "
		elif unit == _get_next_predicted_unit():
			prefix = "NEXT "
		elif not _is_ctb_running:
			prefix = "WAIT "
		_labels[unit].text = prefix + unit.data.unit_name

func _refresh_axis() -> void:
	var order := _predict_action_order(PREVIEW_COUNT)
	for i in range(_axis_labels.size()):
		var label := _axis_labels[i]
		if i >= order.size():
			label.text = ""
			label.modulate = Color(1.0, 1.0, 1.0, 0.25)
			continue
		var unit: Unit = order[i]["unit"]
		var prefix := str(i + 1)
		if i == 0 and unit == _active_unit:
			prefix = "动"
		elif i == 0:
			prefix = "下"
		label.text = "%s\n%s" % [prefix, _short_unit_name(unit)]
		label.modulate = _get_unit_color(unit)

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
	for unit in _bars:
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

func _get_unit_color(unit: Unit) -> Color:
	if unit == _active_unit:
		return Color(1.0, 0.88, 0.35, 1.0)
	if unit.is_ally():
		return Color(0.55, 0.74, 1.0, 1.0)
	if unit.data.unit_type == Enums.UnitType.WILD_POKEMON:
		return Color(0.95, 0.82, 0.45, 1.0)
	return Color(1.0, 0.55, 0.55, 1.0)

func _short_unit_name(unit: Unit) -> String:
	var name := unit.data.unit_name
	if name.length() <= 2:
		return name
	return name.substr(0, 2)
