class_name UnitAI
extends RefCounted   # 不是节点，是纯逻辑类

const TypeChartUtil = preload("res://core/TypeChart.gd")

# 执行 AI 行动，返回值用 await 等待（内部有延迟）
static func run(enemy: Unit, grid_manager: GridManager, all_units: Array[Unit]) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	if not enemy.pending_charge_cells.is_empty():
		await Engine.get_main_loop().create_timer(0.4).timeout
		logs.append_array(_resolve_charge_attack(enemy, grid_manager, all_units))
		return logs

	# 1. 优先反击上一次攻击自己的单位，否则找最近的我方单位
	var target := _find_target(enemy, all_units)
	if target == null:
		return logs

	enemy.ai_turn_count += 1
	if enemy.data.can_charge_attack \
	and enemy.ai_turn_count % enemy.data.charge_interval == 0 \
	and _distance(enemy.grid_pos, target.grid_pos) <= enemy.data.charge_range:
		await Engine.get_main_loop().create_timer(0.3).timeout
		_start_charge_attack(enemy, grid_manager, target)
		logs.append(_make_log_record(
			"%s 开始蓄力，预警 %s 周围。" % [enemy.data.unit_name, _format_grid_pos(target.grid_pos)],
			{
				"event_type": "enemy_charge_start",
				"actor": _unit_log_data(enemy),
				"target": _unit_log_data(target),
				"target_pos": _pos_log_data(target.grid_pos),
				"charge_range": enemy.data.charge_range,
				"charge_radius": enemy.data.charge_radius,
				"charge_damage": enemy.data.charge_damage
			},
			[_unit_log_ref(enemy), _unit_log_ref(target)]
		))
		return logs
	
	# 稍作延迟，模拟"思考"，同时让玩家看清楚发生了什么
	await Engine.get_main_loop().create_timer(0.4).timeout
	
	# 2. 计算移动范围，找最靠近目标的格子
	var move_cells: Array[Vector2i] = grid_manager.get_move_range(enemy.grid_pos, enemy.data.move_range)
	var best_cell := _find_best_move(move_cells, target.grid_pos, enemy.grid_pos)
	
	# 3. 移动
	if best_cell != enemy.grid_pos:
		var from_pos := enemy.grid_pos
		grid_manager.move_unit(enemy, enemy.grid_pos, best_cell)
		enemy.grid_pos = best_cell
		logs.append(_make_log_record(
			"%s 移动 %s -> %s。" % [
				enemy.data.unit_name,
				_format_grid_pos(from_pos),
				_format_grid_pos(best_cell)
			],
			{
				"event_type": "enemy_move",
				"actor": _unit_log_data(enemy),
				"from_pos": _pos_log_data(from_pos),
				"to_pos": _pos_log_data(best_cell)
			},
			[_unit_log_ref(enemy)]
		))
		await Engine.get_main_loop().create_timer(0.2).timeout
	
	# 4. 检查是否在攻击范围内
	if enemy.data.skills.is_empty():
		if logs.is_empty():
			logs.append(_make_wait_log(enemy))
		return logs
	var skill: SkillData = enemy.data.skills[0]
	var attack_cells: Array[Vector2i] = grid_manager.get_attack_range(enemy.grid_pos, skill.atk_range)
	
	if target.grid_pos in attack_cells:
		var damage := skill.damage + enemy.data.attack
		var actual := target.take_damage(damage, enemy, skill.element_type)
		var log_parts: Array[String] = [
			"%s 使用 %s -> %s" % [
				enemy.data.unit_name,
				skill.skill_name,
				target.data.unit_name
			]
		]
		var relation := _get_element_relation_text(skill.element_type, target.data.get_element_types())
		if relation != "":
			log_parts.append(relation)
		log_parts.append("伤害 %d" % actual)
		if target.current_hp <= 0:
			log_parts.append(_get_defeat_text(target))
		logs.append(_make_log_record(
			_join_strings(log_parts, "，") + "。",
			{
				"event_type": "enemy_skill_damage",
				"actor": _unit_log_data(enemy),
				"target": _unit_log_data(target),
				"skill_name": skill.skill_name,
				"element_type": skill.element_type,
				"target_pos": _pos_log_data(target.grid_pos),
				"raw_damage": damage,
				"hp_damage": actual,
				"target_hp_after": target.current_hp,
				"type_multiplier": TypeChartUtil.get_damage_multiplier(skill.element_type, target.data.get_element_types()),
				"type_relation_text": relation,
				"target_defeated": target.current_hp <= 0
			},
			[_unit_log_ref(enemy), _unit_log_ref(target)]
		))
	elif logs.is_empty():
		logs.append(_make_wait_log(enemy))
	return logs

static func _start_charge_attack(enemy: Unit, grid_manager: GridManager, target: Unit) -> void:
	enemy.set_pending_charge_cells(_get_charge_cells(target.grid_pos, enemy.data.charge_radius, grid_manager))
	grid_manager.set_warning_cells(enemy.pending_charge_cells)

static func _resolve_charge_attack(enemy: Unit, grid_manager: GridManager, all_units: Array[Unit]) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	for unit in all_units:
		if unit.is_ally() and unit.is_alive() and unit.grid_pos in enemy.pending_charge_cells:
			var actual := unit.take_damage(enemy.data.charge_damage, enemy, enemy.data.element_type)
			var log_parts: Array[String] = [
				"%s 蓄力攻击 -> %s" % [
					enemy.data.unit_name,
					unit.data.unit_name
				]
			]
			var relation := _get_element_relation_text(enemy.data.element_type, unit.data.get_element_types())
			if relation != "":
				log_parts.append(relation)
			log_parts.append("伤害 %d" % actual)
			if unit.current_hp <= 0:
				log_parts.append(_get_defeat_text(unit))
			logs.append(_make_log_record(
				_join_strings(log_parts, "，") + "。",
				{
					"event_type": "enemy_charge_damage",
					"actor": _unit_log_data(enemy),
					"target": _unit_log_data(unit),
					"target_pos": _pos_log_data(unit.grid_pos),
					"raw_damage": enemy.data.charge_damage,
					"hp_damage": actual,
					"target_hp_after": unit.current_hp,
					"type_multiplier": TypeChartUtil.get_damage_multiplier(enemy.data.element_type, unit.data.get_element_types()),
					"type_relation_text": relation,
					"target_defeated": unit.current_hp <= 0
				},
				[_unit_log_ref(enemy), _unit_log_ref(unit)]
			))
	enemy.clear_pending_charge_cells()
	grid_manager.clear_warning_cells()
	return logs

static func _get_charge_cells(center: Vector2i, radius: int, grid_manager: GridManager) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var pos := center + Vector2i(dx, dy)
			if abs(dx) + abs(dy) <= radius and grid_manager.is_valid(pos):
				result.append(pos)
	return result

# 优先反击上一次攻击自己的单位；没有可用仇恨目标时，找最近的我方单位。
static func _find_target(enemy: Unit, all_units: Array[Unit]) -> Unit:
	if enemy.last_attacker != null \
	and is_instance_valid(enemy.last_attacker) \
	and enemy.last_attacker.is_alive() \
	and enemy.last_attacker.is_ally():
		return enemy.last_attacker
	return _find_nearest_ally(enemy, all_units)

static func _find_nearest_ally(enemy: Unit, all_units: Array[Unit]) -> Unit:
	var nearest: Unit = null
	var min_dist := INF
	for unit in all_units:
		if unit.is_ally() and unit.is_alive():
			var dist: int = abs(unit.grid_pos.x - enemy.grid_pos.x) \
					  + abs(unit.grid_pos.y - enemy.grid_pos.y)
			if dist < min_dist:
				min_dist = dist
				nearest = unit
	return nearest

static func _distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

static func _format_grid_pos(pos: Vector2i) -> String:
	return "(%d,%d)" % [pos.x, pos.y]

static func _get_element_relation_text(attack_type: int, target_types: Array[int]) -> String:
	return TypeChartUtil.get_multiplier_text(TypeChartUtil.get_damage_multiplier(attack_type, target_types))

static func _get_defeat_text(unit: Unit) -> String:
	if unit.data.unit_type == Enums.UnitType.PLAYER:
		return "%s倒下，训练师指挥离线" % unit.data.unit_name
	return "%s倒下" % unit.data.unit_name

static func _make_wait_log(unit: Unit) -> Dictionary:
	return _make_log_record(
		"%s 待机。" % unit.data.unit_name,
		{
			"event_type": "enemy_wait",
			"actor": _unit_log_data(unit)
		},
		[_unit_log_ref(unit)]
	)

static func _make_log_record(text: String, metadata: Dictionary, unit_refs: Array[Dictionary]) -> Dictionary:
	return {
		"text": text,
		"metadata": metadata,
		"unit_refs": unit_refs
	}

static func _unit_log_ref(unit: Unit) -> Dictionary:
	if unit == null or not is_instance_valid(unit):
		return {}
	return {
		"name": unit.data.unit_name,
		"side_key": _get_unit_side_key(unit),
		"side": _get_unit_side_label(unit)
	}

static func _unit_log_data(unit: Unit) -> Dictionary:
	if unit == null or not is_instance_valid(unit):
		return {}
	return {
		"unit_id": "TODO: add stable runtime unit id",
		"name": unit.data.unit_name,
		"side_key": _get_unit_side_key(unit),
		"side": _get_unit_side_label(unit),
		"unit_type": unit.data.unit_type,
		"element_types": unit.data.get_element_types(),
		"grid_pos": _pos_log_data(unit.grid_pos),
		"hp": unit.current_hp,
		"max_hp": unit.data.max_hp,
		"ap": unit.current_ap
	}

static func _pos_log_data(pos: Vector2i) -> Dictionary:
	return {"x": pos.x, "y": pos.y, "text": _format_grid_pos(pos)}

static func _get_unit_side_key(unit: Unit) -> String:
	if unit.is_ally():
		return "ally"
	if unit.data.unit_type == Enums.UnitType.WILD_POKEMON \
	or unit.data.unit_type == Enums.UnitType.NEUTRAL \
	or unit.data.unit_type == Enums.UnitType.NEUTRAL_POKEMON:
		return "neutral"
	if unit.is_enemy():
		return "enemy"
	return "system"

static func _get_unit_side_label(unit: Unit) -> String:
	match _get_unit_side_key(unit):
		"ally":
			return "我方"
		"enemy":
			return "敌方"
		"neutral":
			return "中立"
		_:
			return "系统"

static func _join_strings(parts: Array, delimiter: String) -> String:
	var text := ""
	for i in parts.size():
		if i > 0:
			text += delimiter
		text += str(parts[i])
	return text

# 在可移动格子里找最靠近目标的一格
static func _find_best_move(move_cells: Array[Vector2i], target: Vector2i, current: Vector2i) -> Vector2i:
	if move_cells.is_empty():
		return current
	var best := current
	var min_dist: int = abs(current.x - target.x) + abs(current.y - target.y)
	for cell in move_cells:
		var dist: int = abs(cell.x - target.x) + abs(cell.y - target.y)
		if dist < min_dist:
			min_dist = dist
			best = cell
	return best
