extends Control

var _bars: Dictionary = {}   # unit -> ProgressBar，动态追踪
var _labels: Dictionary = {} # unit -> Label
var _active_unit: Unit = null
var _is_ctb_running: bool = false

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
	
	$VBoxContainer.add_child(hbox)
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
	for unit in _bars:
		if is_instance_valid(unit) and is_instance_valid(_bars[unit]):
			_bars[unit].value = unit.current_ap
			if unit == _active_unit:
				_bars[unit].modulate = Color(1.0, 0.88, 0.35, 1.0)
			else:
				_bars[unit].modulate = Color.WHITE

func _refresh_labels() -> void:
	for unit in _labels:
		if not is_instance_valid(unit) or not is_instance_valid(_labels[unit]):
			continue
		var prefix := ""
		if unit == _active_unit:
			prefix = "READY "
		elif not _is_ctb_running:
			prefix = "WAIT "
		_labels[unit].text = prefix + unit.data.unit_name
