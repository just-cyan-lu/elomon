class_name Unit
extends Node2D

const TypeChartUtil = preload("res://core/TypeChart.gd")
const StatusTypeUtil = preload("res://core/StatusTypes.gd")

# 信号
signal died(unit: Unit)
signal hp_changed(current_hp: int, max_hp: int)
signal status_changed(unit: Unit)

# 静态数据引用
var data: UnitData

# 运行时状态（会随战斗变化）
var current_hp: int = 0
var current_ap: float = 0.0   # 当前行动力，由 CTBSystem 每帧更新
var grid_pos: Vector2i        # 当前所在格子坐标
var has_acted: bool = false   # 本回合是否已使用技能（每回合重置）
var has_moved: bool = false   # 本回合是否已移动（每回合重置）
var shield: int = 0
var current_stability: int = 0
var stability_depleted: bool = false
var power_boost_next_attack: bool = false
var weak_marked: bool = false
var calibrated_attack_type: int = Enums.ElementType.NONE
var bonus_move_range: int = 0
var move_penalty_next_action: int = 0
var last_attacker: Unit = null
var ai_turn_count: int = 0
var pending_charge_cells: Array[Vector2i] = []

# 视觉节点（代码动态创建）
var _body: ColorRect
var _label: Label
var _hp_back: ColorRect
var _hp_fill: ColorRect
var _status_bar: HBoxContainer

# 初始化：传入数据和初始格子位置
func setup(unit_data: UnitData, spawn_pos: Vector2i) -> void:
	data = unit_data
	current_hp = data.max_hp
	current_stability = data.max_stability
	grid_pos = spawn_pos
	_build_visuals()
	_update_label()

func _build_visuals() -> void:
	# 色块，居中对齐格子
	_body = ColorRect.new()
	var size := Enums.CELL_SIZE - 4
	_body.size = Vector2(size, size)
	_body.position = Vector2(-size * 0.5, -size * 0.5)
	_body.color = _get_side_color()
	add_child(_body)

	_hp_back = ColorRect.new()
	_hp_back.size = Vector2(size, 4)
	_hp_back.position = Vector2(-size * 0.5, size * 0.5 + 2)
	_hp_back.color = Color(0.08, 0.08, 0.08, 0.9)
	add_child(_hp_back)

	_hp_fill = ColorRect.new()
	_hp_fill.size = Vector2(size, 4)
	_hp_fill.position = _hp_back.position
	_hp_fill.color = Color(0.36, 0.72, 0.42, 1.0)
	add_child(_hp_fill)

	_status_bar = HBoxContainer.new()
	_status_bar.position = Vector2(-Enums.CELL_SIZE, size * 0.5 + 8)
	_status_bar.size = Vector2(Enums.CELL_SIZE * 2, 12)
	_status_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_bar.add_theme_constant_override("separation", 1)
	add_child(_status_bar)
	
	# 名字标签，显示在色块上方
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-Enums.CELL_SIZE, -Enums.CELL_SIZE - 2)
	_label.size = Vector2(Enums.CELL_SIZE * 2, 22)
	_label.add_theme_font_size_override("font_size", 5)  # 像素风小字
	add_child(_label)

# 由 CTBSystem 每帧调用，回复行动力
func regen_ap(delta: float) -> void:
	if current_ap < Enums.MAX_AP:
		current_ap = min(current_ap + data.speed * delta, Enums.MAX_AP)
		_update_label()

func is_ap_full() -> bool:
	return current_ap >= Enums.MAX_AP

# 行动结束后扣除行动力（不归零，快单位保留溢出优势）
func consume_ap(amount: float) -> void:
	current_ap -= amount
	_update_label()

func get_current_move_range() -> int:
	return max(data.move_range + bonus_move_range - move_penalty_next_action, 0)

func add_bonus_move(amount: int) -> void:
	bonus_move_range = max(bonus_move_range, amount)
	_update_label()
	emit_signal("status_changed", self)

func consume_bonus_move() -> void:
	if bonus_move_range <= 0:
		return
	bonus_move_range = 0
	_update_label()
	emit_signal("status_changed", self)

func add_move_penalty(amount: int) -> void:
	move_penalty_next_action = max(move_penalty_next_action, amount)
	_update_label()
	emit_signal("status_changed", self)

func clear_action_move_penalty() -> void:
	if move_penalty_next_action <= 0:
		return
	move_penalty_next_action = 0
	_update_label()
	emit_signal("status_changed", self)

func set_pending_charge_cells(cells: Array[Vector2i]) -> void:
	pending_charge_cells = cells.duplicate()
	_update_label()
	emit_signal("status_changed", self)

func clear_pending_charge_cells() -> void:
	pending_charge_cells.clear()
	_update_label()
	emit_signal("status_changed", self)

# 受到伤害
func take_damage(raw_damage: int, attacker: Unit = null, attack_type: int = Enums.ElementType.NONE) -> int:
	var actual: int = max(raw_damage - data.defense, 1)
	actual = TypeChartUtil.apply_damage_multiplier(actual, attack_type, data.get_element_types())
	var consumed_status := false
	if weak_marked:
		actual = max(int(round(float(actual) * 1.5)), 1)
		weak_marked = false
		consumed_status = true
	if shield > 0:
		var blocked: int = min(shield, actual)
		shield -= blocked
		actual -= blocked
		consumed_status = true
	if actual <= 0:
		_update_label()
		_update_hp_bar()
		if consumed_status:
			emit_signal("status_changed", self)
		return 0
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker
	current_hp = max(current_hp - actual, 0)
	emit_signal("hp_changed", current_hp, data.max_hp)
	_update_hp_bar()
	_spawn_damage_number(actual)
	
	# 简单的受伤视觉反馈（色块闪白）
	_flash_hit()
	
	if current_hp <= 0:
		emit_signal("died", self)
	else:
		_update_label()
	if consumed_status:
		emit_signal("status_changed", self)
	return actual

func add_shield(amount: int) -> void:
	shield += amount
	_update_label()
	emit_signal("status_changed", self)

func heal(amount: int) -> int:
	if amount <= 0 or current_hp <= 0:
		return 0
	var before := current_hp
	current_hp = min(current_hp + amount, data.max_hp)
	var healed := current_hp - before
	if healed > 0:
		emit_signal("hp_changed", current_hp, data.max_hp)
		_update_hp_bar()
	_update_label()
	return healed

func refresh_status() -> void:
	_update_label()
	_update_hp_bar()
	emit_signal("status_changed", self)

func damage_stability(amount: int) -> void:
	if data.max_stability <= 0 or stability_depleted:
		return
	current_stability = max(current_stability - amount, 0)
	if current_stability <= 0:
		stability_depleted = true
	_update_label()
	emit_signal("status_changed", self)

func set_weak_marked(value: bool) -> void:
	weak_marked = value
	_update_label()
	emit_signal("status_changed", self)

func set_power_boost(value: bool) -> void:
	power_boost_next_attack = value
	_update_label()
	emit_signal("status_changed", self)

func set_calibrated_attack_type(element_type: int) -> void:
	calibrated_attack_type = element_type
	_update_label()
	emit_signal("status_changed", self)

func consume_calibrated_attack_type() -> void:
	if calibrated_attack_type == Enums.ElementType.NONE:
		return
	calibrated_attack_type = Enums.ElementType.NONE
	_update_label()
	emit_signal("status_changed", self)

func restore_turn_snapshot(snapshot: Dictionary) -> void:
	current_hp = snapshot["current_hp"]
	shield = snapshot["shield"]
	current_stability = snapshot["current_stability"]
	stability_depleted = snapshot["stability_depleted"]
	power_boost_next_attack = bool(snapshot.get("power_boost_next_attack", power_boost_next_attack))
	weak_marked = bool(snapshot.get("weak_marked", weak_marked))
	calibrated_attack_type = int(snapshot.get("calibrated_attack_type", calibrated_attack_type))
	bonus_move_range = snapshot["bonus_move_range"]
	move_penalty_next_action = int(snapshot.get("move_penalty_next_action", move_penalty_next_action))
	_update_hp_bar()
	_update_label()
	emit_signal("hp_changed", current_hp, data.max_hp)
	emit_signal("status_changed", self)

func _update_label() -> void:
	if is_instance_valid(_label):
		var parts: Array[String] = [data.unit_name, str(current_hp) + "/" + str(data.max_hp)]
		var type_text: String = TypeChartUtil.get_type_names(data.get_element_types())
		if type_text != "无":
			parts.append("属" + type_text)
		if shield > 0:
			parts.append("盾" + str(shield))
		_label.text = _join_strings(parts, "\n")
	_update_status_bar()

func get_status_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if shield > 0:
		entries.append(StatusTypeUtil.make_entry(
			StatusTypeUtil.StatusId.SHIELD,
			"盾",
			"剩余护盾 %d" % shield
		))
	if power_boost_next_attack:
		entries.append(StatusTypeUtil.make_entry(StatusTypeUtil.StatusId.POWER_BOOST))
	if weak_marked:
		entries.append(StatusTypeUtil.make_entry(StatusTypeUtil.StatusId.WEAK_MARK))
	if calibrated_attack_type != Enums.ElementType.NONE:
		entries.append(StatusTypeUtil.make_entry(
			StatusTypeUtil.StatusId.CALIBRATED_ATTACK,
			"校" + TypeChartUtil.get_type_name(calibrated_attack_type),
			"校准属性：" + TypeChartUtil.get_type_name(calibrated_attack_type)
		))
	if bonus_move_range > 0:
		entries.append(StatusTypeUtil.make_entry(
			StatusTypeUtil.StatusId.BONUS_MOVE,
			"移",
			"移动距离 +%d" % bonus_move_range
		))
	if move_penalty_next_action > 0:
		entries.append(StatusTypeUtil.make_entry(
			StatusTypeUtil.StatusId.MOVE_PENALTY,
			"缚",
			"下次行动移动距离 -%d" % move_penalty_next_action
		))
	if not pending_charge_cells.is_empty():
		entries.append(StatusTypeUtil.make_entry(StatusTypeUtil.StatusId.CHARGE_WARNING))
	return entries

func _update_status_bar() -> void:
	if not is_instance_valid(_status_bar):
		return
	for child in _status_bar.get_children():
		child.queue_free()
	var entries := get_status_entries()
	var max_visible := 4
	for i in range(min(entries.size(), max_visible)):
		_status_bar.add_child(_make_status_badge(entries[i]))
	if entries.size() > max_visible:
		var hidden_count := entries.size() - max_visible
		_status_bar.add_child(_make_status_badge({
			"badge": "+" + str(hidden_count),
			"name": "更多状态",
			"duration_text": "",
			"description": "还有 %d 个状态。" % hidden_count,
			"details": "",
			"color": Color(0.42, 0.44, 0.50, 0.92)
		}))

func _make_status_badge(entry: Dictionary) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(17, 10)
	badge.tooltip_text = StatusTypeUtil.format_tooltip(entry)
	var style := StyleBoxFlat.new()
	style.bg_color = entry.get("color", Color(0.42, 0.44, 0.50, 0.92))
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	badge.add_theme_stylebox_override("panel", style)
	var text := Label.new()
	text.text = str(entry.get("badge", "?"))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 5)
	text.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0, 1.0))
	badge.add_child(text)
	return badge

func _update_hp_bar() -> void:
	if not is_instance_valid(_hp_fill):
		return
	var hp_ratio := 0.0
	if data.max_hp > 0:
		hp_ratio = float(current_hp) / float(data.max_hp)
	_hp_fill.size.x = (Enums.CELL_SIZE - 4) * clamp(hp_ratio, 0.0, 1.0)
	if hp_ratio <= 0.3:
		_hp_fill.color = Color(0.82, 0.28, 0.24, 1.0)
	elif hp_ratio <= 0.6:
		_hp_fill.color = Color(0.86, 0.66, 0.28, 1.0)
	else:
		_hp_fill.color = Color(0.36, 0.72, 0.42, 1.0)

func _spawn_damage_number(amount: int) -> void:
	var damage_label := Label.new()
	damage_label.text = "-" + str(amount)
	damage_label.position = Vector2(-Enums.CELL_SIZE * 0.5, -Enums.CELL_SIZE * 1.2)
	damage_label.size = Vector2(Enums.CELL_SIZE, 10)
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.add_theme_font_size_override("font_size", 8)
	damage_label.modulate = Color(0.92, 0.28, 0.24, 1.0)
	add_child(damage_label)
	var tween := create_tween()
	tween.tween_property(damage_label, "position:y", damage_label.position.y - 10, 0.45)
	tween.parallel().tween_property(damage_label, "modulate:a", 0.0, 0.45)
	tween.tween_callback(damage_label.queue_free)

func _get_side_color() -> Color:
	match data.unit_type:
		Enums.UnitType.PLAYER, Enums.UnitType.PLAYER_POKEMON, Enums.UnitType.ALLY, Enums.UnitType.ALLY_POKEMON:
			return Color(0.30, 0.50, 0.78, 1.0)
		Enums.UnitType.ENEMY, Enums.UnitType.ENEMY_POKEMON:
			return Color(0.76, 0.34, 0.34, 1.0)
		Enums.UnitType.NEUTRAL, Enums.UnitType.NEUTRAL_POKEMON, Enums.UnitType.WILD_POKEMON:
			return Color(0.78, 0.68, 0.36, 1.0)
		_:
			return Color(0.55, 0.55, 0.55, 1.0)

func _join_strings(parts: Array[String], delimiter: String) -> String:
	var text := ""
	for i in parts.size():
		if i > 0:
			text += delimiter
		text += parts[i]
	return text

func _flash_hit() -> void:
	_body.color = Color.WHITE
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(_body):
		_body.color = _get_side_color()

# 工具方法
func is_alive() -> bool:
	return current_hp > 0

func is_enemy() -> bool:
	return data.unit_type == Enums.UnitType.ENEMY \
		or data.unit_type == Enums.UnitType.ENEMY_POKEMON \
		or data.unit_type == Enums.UnitType.WILD_POKEMON

func is_ally() -> bool:
	return data.unit_type == Enums.UnitType.PLAYER \
		or data.unit_type == Enums.UnitType.PLAYER_POKEMON \
		or data.unit_type == Enums.UnitType.ALLY \
		or data.unit_type == Enums.UnitType.ALLY_POKEMON
