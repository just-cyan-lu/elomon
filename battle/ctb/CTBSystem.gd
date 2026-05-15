class_name CTBSystem
extends Node

signal unit_ready(unit: Unit)   # 某单位 AP 满了，轮到它行动
signal running_changed(is_running: bool, ready_unit: Unit)

var _units: Array[Unit] = []
var _running: bool = false
var _ready_unit: Unit = null

func register_units(units: Array[Unit]) -> void:
	_units = units.duplicate()  # 复制数组，避免引用问题

func add_unit(unit: Unit) -> void:
	if not _units.has(unit):
		_units.append(unit)

func start() -> void:
	_ready_unit = null
	_set_running(true)

func stop() -> void:
	_ready_unit = null
	_set_running(false)

func resume() -> void:
	_ready_unit = null
	_set_running(true)

func remove_unit(unit: Unit) -> void:
	_units.erase(unit)
	if _ready_unit == unit:
		_ready_unit = null

func is_running() -> bool:
	return _running

func get_ready_unit() -> Unit:
	return _ready_unit

func _process(delta: float) -> void:
	if not _running:
		return
	
	for unit in _units:
		if not unit.is_alive():
			continue
		if unit.is_ap_full():
			_pause_for_ready_unit(unit)
			return
		unit.regen_ap(delta)
		
		if unit.is_ap_full():
			_pause_for_ready_unit(unit)
			return                 # 每帧只触发一个单位，防止同帧多个单位同时满

func _pause_for_ready_unit(unit: Unit) -> void:
	_ready_unit = unit
	_set_running(false)
	emit_signal("unit_ready", unit)

func _set_running(value: bool) -> void:
	if _running == value:
		emit_signal("running_changed", _running, _ready_unit)
		return
	_running = value
	emit_signal("running_changed", _running, _ready_unit)
