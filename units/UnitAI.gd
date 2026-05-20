class_name UnitAI
extends RefCounted   # 不是节点，是纯逻辑类

# 执行 AI 行动，返回值用 await 等待（内部有延迟）
static func run(enemy: Unit, grid_manager: GridManager, all_units: Array[Unit]) -> void:
	if not enemy.pending_charge_cells.is_empty():
		await Engine.get_main_loop().create_timer(0.4).timeout
		_resolve_charge_attack(enemy, grid_manager, all_units)
		return

	# 1. 优先反击上一次攻击自己的单位，否则找最近的我方单位
	var target := _find_target(enemy, all_units)
	if target == null:
		return

	enemy.ai_turn_count += 1
	if enemy.data.can_charge_attack \
	and enemy.ai_turn_count % enemy.data.charge_interval == 0 \
	and _distance(enemy.grid_pos, target.grid_pos) <= enemy.data.charge_range:
		await Engine.get_main_loop().create_timer(0.3).timeout
		_start_charge_attack(enemy, grid_manager, target)
		return
	
	# 稍作延迟，模拟"思考"，同时让玩家看清楚发生了什么
	await Engine.get_main_loop().create_timer(0.4).timeout
	
	# 2. 计算移动范围，找最靠近目标的格子
	var move_cells: Array[Vector2i] = grid_manager.get_move_range(enemy.grid_pos, enemy.data.move_range)
	var best_cell := _find_best_move(move_cells, target.grid_pos, enemy.grid_pos)
	
	# 3. 移动
	if best_cell != enemy.grid_pos:
		grid_manager.move_unit(enemy, enemy.grid_pos, best_cell)
		enemy.grid_pos = best_cell
		await Engine.get_main_loop().create_timer(0.2).timeout
	
	# 4. 检查是否在攻击范围内
	if enemy.data.skills.is_empty():
		return
	var skill: SkillData = enemy.data.skills[0]
	var attack_cells: Array[Vector2i] = grid_manager.get_attack_range(enemy.grid_pos, skill.atk_range)
	
	if target.grid_pos in attack_cells:
		var damage := skill.damage + enemy.data.attack
		target.take_damage(damage, enemy, skill.element_type)

static func _start_charge_attack(enemy: Unit, grid_manager: GridManager, target: Unit) -> void:
	enemy.set_pending_charge_cells(_get_charge_cells(target.grid_pos, enemy.data.charge_radius, grid_manager))
	grid_manager.set_warning_cells(enemy.pending_charge_cells)

static func _resolve_charge_attack(enemy: Unit, grid_manager: GridManager, all_units: Array[Unit]) -> void:
	for unit in all_units:
		if unit.is_ally() and unit.is_alive() and unit.grid_pos in enemy.pending_charge_cells:
			unit.take_damage(enemy.data.charge_damage, enemy, enemy.data.element_type)
	enemy.clear_pending_charge_cells()
	grid_manager.clear_warning_cells()

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
