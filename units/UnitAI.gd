class_name UnitAI
extends RefCounted   # 不是节点，是纯逻辑类

const TypeChartUtil = preload("res://core/TypeChart.gd")
const CHARGE_ACTION_AP_COST := 100.0

# 执行 AI 行动，返回值用 await 等待（内部有延迟）
static func run(enemy: Unit, grid_manager: GridManager, all_units: Array[Unit]) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	if not enemy.pending_charge_cells.is_empty():
		await Engine.get_main_loop().create_timer(0.4).timeout
		logs.append_array(_resolve_charge_attack(enemy, grid_manager, all_units))
		return logs

	# 1. 评分选目标：保留反击倾向，同时考虑属性克制、血量和距离。
	var target := _find_target(enemy, all_units)
	if target == null:
		return logs

	enemy.ai_turn_count += 1
	if enemy.data.can_charge_attack \
	and enemy.ai_turn_count % enemy.data.charge_interval == 0 \
	and _distance(enemy.grid_pos, target.grid_pos) <= enemy.data.charge_range:
		target = _find_charge_target(enemy, all_units, target)
		await Engine.get_main_loop().create_timer(0.3).timeout
		_start_charge_attack(enemy, grid_manager, target)
		var charge_log_parts: Array[String] = [
			"%s 开始蓄力，预警 %s 周围" % [
				enemy.data.unit_name,
				_format_grid_pos(target.grid_pos)
			]
		]
		var charge_timing_text := _get_action_timing_text(CHARGE_ACTION_AP_COST)
		if charge_timing_text != "":
			charge_log_parts.append(charge_timing_text)
		logs.append(_make_log_record(
			_join_strings(charge_log_parts, "，") + "。",
			_with_action_timing_metadata({
				"event_type": "enemy_charge_start",
				"actor": _unit_log_data(enemy),
				"target": _unit_log_data(target),
				"target_pos": _pos_log_data(target.grid_pos),
				"charge_range": enemy.data.charge_range,
				"charge_radius": enemy.data.charge_radius,
				"charge_damage": enemy.data.charge_damage
			}, CHARGE_ACTION_AP_COST),
			[_unit_log_ref(enemy), _unit_log_ref(target)]
		))
		return logs
	
	# 稍作延迟，模拟"思考"，同时让玩家看清楚发生了什么
	await Engine.get_main_loop().create_timer(0.4).timeout
	
	# 2. 计算移动范围。近战逼近，远程尽量保持射程内距离。
	var skill: SkillData = null
	if not enemy.data.skills.is_empty():
		skill = enemy.data.skills[0]
	var move_cells: Array[Vector2i] = grid_manager.get_move_range(enemy.grid_pos, enemy.data.move_range)
	var best_cell := _find_best_move(enemy, move_cells, target, enemy.grid_pos, skill)
	
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
	if skill == null:
		if logs.is_empty():
			logs.append(_make_wait_log(enemy))
		return logs
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
		var enemy_skill_timing_text := _get_action_timing_text(skill.ap_cost)
		if enemy_skill_timing_text != "":
			log_parts.append(enemy_skill_timing_text)
		logs.append(_make_log_record(
			_join_strings(log_parts, "，") + "。",
			_with_action_timing_metadata({
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
				"targeting_hint": _get_targeting_hint(enemy, target),
				"target_defeated": target.current_hp <= 0
			}, skill.ap_cost),
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
			var charge_hit_timing_text := _get_action_timing_text(CHARGE_ACTION_AP_COST)
			if charge_hit_timing_text != "":
				log_parts.append(charge_hit_timing_text)
			logs.append(_make_log_record(
				_join_strings(log_parts, "，") + "。",
				_with_action_timing_metadata({
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
				}, CHARGE_ACTION_AP_COST),
				[_unit_log_ref(enemy), _unit_log_ref(unit)]
			))
	if logs.is_empty():
		var miss_parts: Array[String] = ["%s 蓄力攻击落空" % enemy.data.unit_name]
		var charge_miss_timing_text := _get_action_timing_text(CHARGE_ACTION_AP_COST)
		if charge_miss_timing_text != "":
			miss_parts.append(charge_miss_timing_text)
		logs.append(_make_log_record(
			_join_strings(miss_parts, "，") + "。",
			_with_action_timing_metadata({
				"event_type": "enemy_charge_miss",
				"actor": _unit_log_data(enemy)
			}, CHARGE_ACTION_AP_COST),
			[_unit_log_ref(enemy)]
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

# 评分选目标：按 AI profile 调整反击、克制、低血、斩杀和距离权重。
static func _find_target(enemy: Unit, all_units: Array[Unit]) -> Unit:
	var best_target: Unit = null
	var best_score := -INF
	for unit in all_units:
		if not unit.is_ally() or not unit.is_alive():
			continue
		var score := _score_target(enemy, unit)
		if score > best_score:
			best_score = score
			best_target = unit
	return best_target

static func _score_target(enemy: Unit, target: Unit) -> float:
	var weights := _get_profile_weights(enemy.data.ai_profile)
	var score := 0.0
	var dist := _distance(enemy.grid_pos, target.grid_pos)
	score -= float(dist) * float(weights["distance"])
	if enemy.last_attacker == target:
		score += float(weights["revenge"])
	var hp_ratio := 1.0
	if target.data.max_hp > 0:
		hp_ratio = float(target.current_hp) / float(target.data.max_hp)
	score += (1.0 - hp_ratio) * float(weights["low_hp"])
	if _estimate_damage(enemy, target) >= target.current_hp:
		score += float(weights["kill"])
	if target.data.unit_type == Enums.UnitType.PLAYER:
		score += float(weights["trainer"])
	if _is_support_target(target):
		score += float(weights["support"])
	if _has_tactical_status(target):
		score += float(weights["buffed"])
	var attack_type := _get_primary_attack_type(enemy)
	var type_multiplier := TypeChartUtil.get_damage_multiplier(attack_type, target.data.get_element_types())
	if type_multiplier > 1.0:
		score += float(weights["type_advantage"]) * type_multiplier
	elif type_multiplier < 1.0:
		score -= float(weights["type_resist"])
	score += _get_role_target_bonus(enemy, target) * float(weights["role_bonus_scale"])
	return score

static func _get_profile_weights(profile: int) -> Dictionary:
	match profile:
		Enums.AIProfile.HUNTER:
			return {
				"distance": 1.35,
				"revenge": 10.0,
				"low_hp": 42.0,
				"kill": 58.0,
				"type_advantage": 12.0,
				"type_resist": 8.0,
				"trainer": 8.0,
				"support": 14.0,
				"buffed": 8.0,
				"role_bonus_scale": 0.8,
				"area": 18.0
			}
		Enums.AIProfile.ELEMENTAL:
			return {
				"distance": 1.7,
				"revenge": 18.0,
				"low_hp": 12.0,
				"kill": 24.0,
				"type_advantage": 34.0,
				"type_resist": 18.0,
				"trainer": 2.0,
				"support": 4.0,
				"buffed": 4.0,
				"role_bonus_scale": 1.3,
				"area": 18.0
			}
		Enums.AIProfile.GUARDIAN:
			return {
				"distance": 3.3,
				"revenge": 12.0,
				"low_hp": 8.0,
				"kill": 18.0,
				"type_advantage": 16.0,
				"type_resist": 8.0,
				"trainer": 4.0,
				"support": 2.0,
				"buffed": 4.0,
				"role_bonus_scale": 0.7,
				"area": 22.0
			}
		Enums.AIProfile.SUPPRESSOR:
			return {
				"distance": 1.5,
				"revenge": 10.0,
				"low_hp": 18.0,
				"kill": 34.0,
				"type_advantage": 14.0,
				"type_resist": 8.0,
				"trainer": 24.0,
				"support": 22.0,
				"buffed": 18.0,
				"role_bonus_scale": 0.8,
				"area": 18.0
			}
		Enums.AIProfile.AREA:
			return {
				"distance": 1.4,
				"revenge": 10.0,
				"low_hp": 10.0,
				"kill": 22.0,
				"type_advantage": 14.0,
				"type_resist": 6.0,
				"trainer": 2.0,
				"support": 6.0,
				"buffed": 6.0,
				"role_bonus_scale": 0.7,
				"area": 42.0
			}
		_:
			return {
				"distance": 2.0,
				"revenge": 30.0,
				"low_hp": 18.0,
				"kill": 30.0,
				"type_advantage": 22.0,
				"type_resist": 10.0,
				"trainer": 4.0,
				"support": 6.0,
				"buffed": 6.0,
				"role_bonus_scale": 1.0,
				"area": 24.0
			}

static func _estimate_damage(enemy: Unit, target: Unit) -> int:
	if enemy.data.skills.is_empty():
		return 0
	var skill: SkillData = enemy.data.skills[0]
	var actual: int = max(skill.damage + enemy.data.attack - target.data.defense, 1)
	actual = TypeChartUtil.apply_damage_multiplier(actual, skill.element_type, target.data.get_element_types())
	if target.weak_marked:
		actual = max(int(round(float(actual) * 1.5)), 1)
	if target.shield > 0:
		actual = max(actual - target.shield, 0)
	return actual

static func _is_support_target(target: Unit) -> bool:
	if target.data.unit_type == Enums.UnitType.PLAYER:
		return true
	for skill_resource in target.data.skills:
		var skill: SkillData = skill_resource
		if skill.effect_type == SkillData.EffectType.HEAL:
			return true
	return false

static func _has_tactical_status(target: Unit) -> bool:
	return target.shield > 0 \
		or target.power_boost_next_attack \
		or target.calibrated_attack_type != Enums.ElementType.NONE \
		or target.bonus_move_range > 0

static func _get_role_target_bonus(enemy: Unit, target: Unit) -> float:
	var attack_type := _get_primary_attack_type(enemy)
	var target_types := target.data.get_element_types()
	match attack_type:
		Enums.ElementType.FIRE:
			if target_types.has(Enums.ElementType.GRASS) or target_types.has(Enums.ElementType.ICE):
				return 12.0
			return 0.0
		Enums.ElementType.WATER:
			if target_types.has(Enums.ElementType.FIRE) or target_types.has(Enums.ElementType.GROUND):
				return 12.0
			return 0.0
		Enums.ElementType.GRASS:
			if target_types.has(Enums.ElementType.WATER) or target_types.has(Enums.ElementType.GROUND):
				return 12.0
			return 0.0
		Enums.ElementType.FLYING:
			if target_types.has(Enums.ElementType.GRASS) or target_types.has(Enums.ElementType.GROUND):
				return 12.0
			if target.data.speed < enemy.data.speed:
				return 5.0
			return 0.0
		Enums.ElementType.GROUND:
			if target_types.has(Enums.ElementType.ELECTRIC) or target_types.has(Enums.ElementType.FIRE):
				return 14.0
			return 0.0
		_:
			return 0.0

static func _get_primary_attack_type(unit: Unit) -> int:
	if not unit.data.skills.is_empty():
		var skill: SkillData = unit.data.skills[0]
		return skill.element_type
	return unit.data.element_type

static func _get_targeting_hint(enemy: Unit, target: Unit) -> String:
	if _estimate_damage(enemy, target) >= target.current_hp:
		return "finisher"
	if enemy.last_attacker == target:
		return "retaliate"
	var attack_type := _get_primary_attack_type(enemy)
	var type_multiplier := TypeChartUtil.get_damage_multiplier(attack_type, target.data.get_element_types())
	if type_multiplier > 1.0:
		return "type_advantage"
	var hp_ratio := 1.0
	if target.data.max_hp > 0:
		hp_ratio = float(target.current_hp) / float(target.data.max_hp)
	if hp_ratio <= 0.35:
		return "low_hp"
	match enemy.data.ai_profile:
		Enums.AIProfile.GUARDIAN:
			return "nearest_guard"
		Enums.AIProfile.HUNTER:
			return "hunter_pressure"
		Enums.AIProfile.SUPPRESSOR:
			return "suppression"
		Enums.AIProfile.AREA:
			return "area_setup"
		_:
			return "nearest_pressure"

static func _find_charge_target(enemy: Unit, all_units: Array[Unit], fallback: Unit) -> Unit:
	var best_target := fallback
	var best_score := -INF
	var weights := _get_profile_weights(enemy.data.ai_profile)
	for unit in all_units:
		if not unit.is_ally() or not unit.is_alive():
			continue
		if _distance(enemy.grid_pos, unit.grid_pos) > enemy.data.charge_range:
			continue
		var score := float(_count_allies_in_radius(unit.grid_pos, enemy.data.charge_radius, all_units)) * float(weights["area"])
		score += _score_target(enemy, unit)
		if score > best_score:
			best_score = score
			best_target = unit
	return best_target

static func _count_allies_in_radius(center: Vector2i, radius: int, all_units: Array[Unit]) -> int:
	var count := 0
	for unit in all_units:
		if unit.is_ally() and unit.is_alive() and _distance(center, unit.grid_pos) <= radius:
			count += 1
	return count

static func _distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

static func _format_grid_pos(pos: Vector2i) -> String:
	return "(%d,%d)" % [pos.x, pos.y]

static func _get_element_relation_text(attack_type: int, target_types: Array[int]) -> String:
	return TypeChartUtil.get_multiplier_text(TypeChartUtil.get_damage_multiplier(attack_type, target_types))

static func _get_action_timing_percent(ap_cost: float) -> int:
	return int(round(abs(ap_cost - Enums.MAX_AP) / Enums.MAX_AP * 100.0))

static func _get_action_timing_direction(ap_cost: float) -> String:
	var percent := _get_action_timing_percent(ap_cost)
	if percent <= 0:
		return "standard"
	if ap_cost < Enums.MAX_AP:
		return "advance"
	return "delay"

static func _get_action_timing_text(ap_cost: float) -> String:
	var percent := _get_action_timing_percent(ap_cost)
	if percent <= 0:
		return ""
	if ap_cost < Enums.MAX_AP:
		return "下次行动提前%d%%" % percent
	return "下次行动推后%d%%" % percent

static func _with_action_timing_metadata(metadata: Dictionary, ap_cost: float) -> Dictionary:
	var result := metadata.duplicate(true)
	result["action_ap_cost"] = ap_cost
	result["action_timing_direction"] = _get_action_timing_direction(ap_cost)
	result["action_timing_percent"] = _get_action_timing_percent(ap_cost)
	result["action_timing_text"] = _get_action_timing_text(ap_cost)
	return result

static func _get_defeat_text(unit: Unit) -> String:
	if unit.data.unit_type == Enums.UnitType.PLAYER:
		return "%s倒下，训练师指挥离线" % unit.data.unit_name
	return "%s倒下" % unit.data.unit_name

static func _make_wait_log(unit: Unit) -> Dictionary:
	return _make_log_record(
		"%s 待机，%s。" % [unit.data.unit_name, _get_action_timing_text(50.0)],
		_with_action_timing_metadata({
			"event_type": "enemy_wait",
			"actor": _unit_log_data(unit)
		}, 50.0),
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

static func _find_best_move(enemy: Unit, move_cells: Array[Vector2i], target: Unit, current: Vector2i, skill: SkillData) -> Vector2i:
	if move_cells.is_empty():
		return current
	var best := current
	var best_score := _score_move_cell(enemy, current, target, skill)
	for cell in move_cells:
		var score := _score_move_cell(enemy, cell, target, skill)
		if score > best_score:
			best_score = score
			best = cell
	return best

static func _score_move_cell(enemy: Unit, cell: Vector2i, target: Unit, skill: SkillData) -> float:
	var dist := _distance(cell, target.grid_pos)
	if skill == null:
		return -float(dist)
	var score := 0.0
	if skill.atk_range >= 3:
		var desired_dist := skill.atk_range
		score -= float(abs(dist - desired_dist)) * 9.0
		if dist > 0 and dist <= skill.atk_range:
			score += 35.0
		if dist <= 1:
			score -= 18.0
	else:
		score -= float(dist) * 10.0
		if dist == 1:
			score += 28.0
	score -= float(abs(cell.x - enemy.grid_pos.x) + abs(cell.y - enemy.grid_pos.y)) * 0.2
	return score
