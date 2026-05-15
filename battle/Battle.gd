extends Node

const CARD_RANGE := 3
const SUMMON_COST := 50
const RECALL_COST := 10
const CARD_DEFS := {
	"haste": {"name": "高速组件", "cost": 30, "cooldown": 2},
	"shield": {"name": "小型护盾", "cost": 20, "cooldown": 2},
	"power": {"name": "火力插件", "cost": 25, "cooldown": 2},
	"terrain": {"name": "地形重构", "cost": 15, "cooldown": 1},
	"capture": {"name": "空白封印卡", "cost": 40, "cooldown": 3},
}

# 子节点引用（在 Battle.tscn 场景里赋值，名称必须一致）
@onready var grid_manager: GridManager = $Grid
@onready var ctb_system: CTBSystem = $CTBSystem
@onready var ctb_bar: Control = $UI/CTBBar
@onready var action_menu: Control = $UI/ActionMenu
@onready var result_label: Label = $UI/ResultLabel

# 状态
var _battle_state: Enums.BattleState = Enums.BattleState.WAITING
var _action_state: Enums.ActionState = Enums.ActionState.IDLE
var _active_unit: Unit = null
var _trainer: Unit = null
var _trainer_disabled: bool = false
var _all_units: Array[Unit] = []
var _reserve_grass_data: UnitData = null
var _captured_names: Array[String] = []

var _sync_points: int = 70
var _max_sync_points: int = 100
var _selected_card_id: String = ""
var _selected_skill_index: int = 0
var _sync_label: Label
var _sync_feedback_label: Label
var _tip_label: Label
var _card_cooldowns := {}

# 缓存当前高亮的格子（用于点击判断）
var _move_cells: Array[Vector2i] = []
var _attack_cells: Array[Vector2i] = []
var _card_cells: Array[Vector2i] = []

func _ready() -> void:
	result_label.visible = false
	_build_mvp_ui()
	grid_manager.setup_mvp_terrain()
	_spawn_units()
	_connect_signals()
	ctb_system.register_units(_all_units)
	_update_sync_ui()
	ctb_system.start()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_current_selection()

# ── 初始化 ──────────────────────────────────────────────────────

func _build_mvp_ui() -> void:
	_sync_label = Label.new()
	_sync_label.position = Vector2(218, 4)
	_sync_label.size = Vector2(220, 60)
	_sync_label.add_theme_font_size_override("font_size", 10)
	_sync_label.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0, 1.0))
	$UI.add_child(_sync_label)

	_sync_feedback_label = Label.new()
	_sync_feedback_label.position = Vector2(438, 6)
	_sync_feedback_label.size = Vector2(160, 24)
	_sync_feedback_label.add_theme_font_size_override("font_size", 11)
	_sync_feedback_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0, 1.0))
	_sync_feedback_label.visible = false
	$UI.add_child(_sync_feedback_label)

	_tip_label = Label.new()
	_tip_label.position = Vector2(220, 60)
	_tip_label.size = Vector2(380, 64)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.add_theme_font_size_override("font_size", 8)
	$UI.add_child(_tip_label)

func _spawn_units() -> void:
	var fire_skill := _make_skill("火花", 26, 2, 30, Enums.ElementType.FIRE, 20, true)
	var flame_line := _make_skill("火焰喷射", 42, 3, 75, Enums.ElementType.FIRE, 35, true)
	var vine_skill := _make_skill("藤鞭", 24, 3, 35, Enums.ElementType.GRASS, 18, false)
	var snare_skill := _make_skill("缠绕", 14, 3, 45, Enums.ElementType.GRASS, 25, false, true)
	var blade_skill := _make_skill("数据短刃", 14, 1, 25, Enums.ElementType.NONE, 8)
	var bite_skill := _make_skill("撕咬", 22, 1, 35, Enums.ElementType.NONE, 8)
	var dart_skill := _make_skill("毒针", 18, 3, 45, Enums.ElementType.NONE, 8)
	var elite_skill := _make_skill("蛮力冲撞", 30, 2, 60, Enums.ElementType.GRASS, 10)
	
	_reserve_grass_data = _make_unit_data("藤藤兽", Enums.UnitType.PLAYER_POKEMON, 95, 15, 5, 48, 4, Color(0.25, 0.75, 0.36), Enums.ElementType.GRASS, [vine_skill, snare_skill])
	
	var unit_scene := preload("res://units/Unit.tscn")
	_spawn_unit(unit_scene, _make_unit_data("训练师", Enums.UnitType.PLAYER, 90, 10, 4, 44, 4, Color(0.35, 0.85, 0.88), Enums.ElementType.NONE, [blade_skill]), Vector2i(2, 5))
	_spawn_unit(unit_scene, _make_unit_data("火狐兽", Enums.UnitType.PLAYER_POKEMON, 105, 18, 5, 58, 4, Color(0.95, 0.42, 0.18), Enums.ElementType.FIRE, [fire_skill, flame_line]), Vector2i(3, 5))
	_spawn_unit(unit_scene, _make_unit_data("近战小怪A", Enums.UnitType.ENEMY, 72, 13, 3, 36, 4, Color(0.92, 0.34, 0.32), Enums.ElementType.NONE, [bite_skill]), Vector2i(10, 4))
	_spawn_unit(unit_scene, _make_unit_data("近战小怪B", Enums.UnitType.ENEMY, 72, 13, 3, 34, 4, Color(0.82, 0.26, 0.45), Enums.ElementType.NONE, [bite_skill]), Vector2i(10, 7))
	_spawn_unit(unit_scene, _make_unit_data("远程小怪", Enums.UnitType.ENEMY, 62, 11, 2, 40, 3, Color(0.58, 0.48, 0.92), Enums.ElementType.NONE, [dart_skill]), Vector2i(13, 5))
	_spawn_unit(unit_scene, _make_unit_data("可捕捉精英", Enums.UnitType.WILD_POKEMON, 140, 17, 6, 30, 3, Color(0.25, 0.65, 0.25), Enums.ElementType.GRASS, [elite_skill], 70), Vector2i(14, 9))

func _spawn_unit(unit_scene: PackedScene, unit_data: UnitData, spawn_pos: Vector2i) -> Unit:
	var unit: Unit = unit_scene.instantiate()
	add_child(unit)
	unit.setup(unit_data, spawn_pos)
	grid_manager.place_unit(unit, spawn_pos)
	unit.died.connect(_on_unit_died)
	unit.status_changed.connect(_on_unit_status_changed)
	ctb_bar.add_unit(unit)
	_all_units.append(unit)
	if unit.data.unit_type == Enums.UnitType.PLAYER:
		_trainer = unit
	return unit

func _make_unit_data(
	unit_name: String,
	unit_type: int,
	max_hp: int,
	attack: int,
	defense: int,
	speed: float,
	move_range: int,
	color: Color,
	element_type: int,
	skills: Array,
	max_stability: int = 0
) -> UnitData:
	var data := UnitData.new()
	data.unit_name = unit_name
	data.unit_type = unit_type
	data.max_hp = max_hp
	data.attack = attack
	data.defense = defense
	data.speed = speed
	data.move_range = move_range
	data.color = color
	data.element_type = element_type
	for skill in skills:
		data.skills.append(skill)
	data.max_stability = max_stability
	return data

func _make_skill(
	skill_name: String,
	damage: int,
	atk_range: int,
	ap_cost: float,
	element_type: int,
	stability_damage: int,
	can_ignite_grass: bool = false,
	is_control: bool = false
) -> SkillData:
	var skill := SkillData.new()
	skill.skill_name = skill_name
	skill.damage = damage
	skill.atk_range = atk_range
	skill.ap_cost = ap_cost
	skill.element_type = element_type
	skill.stability_damage = stability_damage
	skill.can_ignite_grass = can_ignite_grass
	skill.is_control = is_control
	return skill

func _connect_signals() -> void:
	ctb_system.unit_ready.connect(_on_unit_ready)
	ctb_system.running_changed.connect(ctb_bar.set_ctb_state)
	grid_manager.cell_clicked.connect(_on_cell_clicked)
	action_menu.move_pressed.connect(_on_move_pressed)
	action_menu.skill_pressed.connect(func(): _on_skill_pressed(0))
	action_menu.skill2_pressed.connect(func(): _on_skill_pressed(1))
	action_menu.wait_pressed.connect(_on_wait_pressed)
	action_menu.card_pressed.connect(_on_card_pressed)
	action_menu.summon_pressed.connect(_on_summon_pressed)
	action_menu.recall_pressed.connect(_on_recall_pressed)

# ── CTB 流程 ────────────────────────────────────────────────────

func _on_unit_ready(unit: Unit) -> void:
	_active_unit = unit
	_active_unit.has_acted = false
	_active_unit.has_moved = false
	_tick_card_cooldowns()
	_gain_sync(max(1, 6 - _active_pokemon_count() * 2), "自然回复")
	_apply_tile_effect(_active_unit)
	_update_capture_marks()
	if not is_instance_valid(_active_unit) or not _active_unit.is_alive():
		if _battle_state != Enums.BattleState.BATTLE_OVER:
			ctb_system.resume()
		return
	
	if unit.is_enemy():
		_battle_state = Enums.BattleState.ENEMY_TURN
		action_menu.hide_menu()
		await UnitAI.run(unit, grid_manager, _all_units)
		_apply_tile_effect(unit)
		_end_turn()
	else:
		_battle_state = Enums.BattleState.PLAYER_TURN
		_action_state = Enums.ActionState.IDLE
		if _active_unit.data.unit_type == Enums.UnitType.PLAYER:
			_show_tip("轮到 %s。训练师回合可以刷卡、召唤、回收和封印。" % _active_unit.data.unit_name)
		elif _trainer_disabled:
			_show_tip("轮到 %s。训练师已倒下，无法再使用卡牌和切换宝可梦。" % _active_unit.data.unit_name)
		else:
			_show_tip("轮到 %s。" % _active_unit.data.unit_name)
		action_menu.show_at(_active_unit.position)

# 回合结束：扣行动力，重置状态，恢复跑条
func _end_turn() -> void:
	if _battle_state == Enums.BattleState.BATTLE_OVER:
		return
	if _active_unit and is_instance_valid(_active_unit):
		_active_unit.consume_ap(Enums.MAX_AP)
	_action_state = Enums.ActionState.IDLE
	_selected_card_id = ""
	_selected_skill_index = 0
	_move_cells.clear()
	_attack_cells.clear()
	_card_cells.clear()
	grid_manager.clear_highlights()
	action_menu.hide_menu()
	_battle_state = Enums.BattleState.WAITING
	_update_sync_ui()
	ctb_system.resume()

# ── 玩家输入处理 ────────────────────────────────────────────────

func _on_move_pressed() -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN: return
	if _active_unit.has_moved:
		_show_tip("本回合已经移动过。")
		return
	_action_state = Enums.ActionState.SELECTING_MOVE
	_move_cells = grid_manager.get_move_range(
		_active_unit.grid_pos, _active_unit.get_current_move_range())
	grid_manager.highlight_cells(_move_cells, GridManager.COLOR_MOVE)
	action_menu.hide_menu()
	_show_tip("选择移动格。移动不消耗 AP；高速组件会提高下一次移动距离。")

func _on_skill_pressed(skill_index: int) -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN: return
	if _active_unit.has_acted:
		_show_tip("本回合已经用过技能。")
		return
	if skill_index >= _active_unit.data.skills.size():
		_show_tip("这个单位没有技能 %d。" % (skill_index + 1))
		return
	_selected_skill_index = skill_index
	_action_state = Enums.ActionState.SELECTING_SKILL
	var skill: SkillData = _active_unit.data.skills[_selected_skill_index]
	_attack_cells = grid_manager.get_attack_range(_active_unit.grid_pos, skill.atk_range)
	grid_manager.highlight_cells(_attack_cells, GridManager.COLOR_ATTACK)
	action_menu.hide_menu()
	_show_tip("选择 %s 的目标。技能不消耗 AP，每次行动最多使用一次。" % skill.skill_name)

func _on_wait_pressed() -> void:
	_end_turn()

func _cancel_current_selection() -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN:
		return
	if _action_state == Enums.ActionState.IDLE:
		return
	_action_state = Enums.ActionState.IDLE
	_selected_card_id = ""
	_selected_skill_index = 0
	_move_cells.clear()
	_attack_cells.clear()
	_card_cells.clear()
	grid_manager.clear_highlights()
	action_menu.show_at(_active_unit.position)
	_show_tip("已取消选择。")

func _on_summon_pressed() -> void:
	if not _is_trainer_turn():
		_show_tip("只有训练师行动时可以召唤。")
		return
	if _reserve_grass_data == null:
		_show_tip("没有可召唤的后备宝可梦。")
		return
	if _sync_points < SUMMON_COST:
		_show_tip("同步率不足，召唤需要 %d。" % SUMMON_COST)
		return
	_action_state = Enums.ActionState.SELECTING_SUMMON
	_card_cells = _empty_cells_in_range(_trainer.grid_pos, CARD_RANGE)
	grid_manager.highlight_cells(_card_cells, GridManager.COLOR_MOVE)
	action_menu.hide_menu()
	_show_tip("选择训练师附近的空格召唤藤藤兽。")

func _on_recall_pressed() -> void:
	if not _is_trainer_turn():
		_show_tip("只有训练师行动时可以回收。")
		return
	_selected_card_id = "recall"
	_action_state = Enums.ActionState.SELECTING_CARD
	_card_cells = _cells_in_range(_trainer.grid_pos, CARD_RANGE)
	grid_manager.highlight_cells(_card_cells, GridManager.COLOR_ATTACK)
	action_menu.hide_menu()
	_show_tip("选择训练师附近的己方宝可梦回收，保留当前状态。")

func _on_card_pressed(card_id: String) -> void:
	if not _is_trainer_turn():
		_show_tip("只有训练师行动时可以刷指令卡。")
		return
	if not _can_pay_card(card_id):
		return
	_selected_card_id = card_id
	_action_state = Enums.ActionState.SELECTING_CARD
	if card_id == "terrain":
		_card_cells = _cells_in_range(_trainer.grid_pos, 4)
	else:
		_card_cells = _cells_in_range(_trainer.grid_pos, CARD_RANGE)
	grid_manager.highlight_cells(_card_cells, GridManager.COLOR_ATTACK)
	action_menu.hide_menu()
	_show_tip("选择 %s 的目标。" % CARD_DEFS[card_id]["name"])

func _on_cell_clicked(grid_pos: Vector2i) -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN: return
	
	match _action_state:
		Enums.ActionState.SELECTING_MOVE:
			if grid_pos in _move_cells:
				grid_manager.move_unit(_active_unit, _active_unit.grid_pos, grid_pos)
				_active_unit.grid_pos = grid_pos
				_active_unit.has_moved = true
				_active_unit.consume_bonus_move()
				_apply_tile_effect(_active_unit)
				_action_state = Enums.ActionState.IDLE
				grid_manager.clear_highlights()
				action_menu.show_at(_active_unit.position)
		
		Enums.ActionState.SELECTING_SKILL:
			if grid_pos in _attack_cells:
				var target: Unit = grid_manager.get_unit_at(grid_pos)
				if target != null and target.is_enemy():
					var skill: SkillData = _active_unit.data.skills[_selected_skill_index]
					_use_skill(_active_unit, target, skill, grid_pos)
					_active_unit.has_acted = true
					_action_state = Enums.ActionState.IDLE
					grid_manager.clear_highlights()
					action_menu.show_at(_active_unit.position)

		Enums.ActionState.SELECTING_CARD:
			if grid_pos in _card_cells:
				_resolve_card(grid_pos)

		Enums.ActionState.SELECTING_SUMMON:
			if grid_pos in _card_cells and not grid_manager.is_occupied(grid_pos):
				_summon_grass(grid_pos)

		Enums.ActionState.IDLE:
			pass

func _use_skill(attacker: Unit, target: Unit, skill: SkillData, target_pos: Vector2i) -> void:
	var damage := skill.damage + attacker.data.attack
	if attacker.power_boost_next_attack:
		damage = int(damage * 1.5)
		attacker.set_power_boost(false)
	var actual := target.take_damage(damage)
	if attacker.is_ally():
		if attacker.data.unit_type == Enums.UnitType.PLAYER:
			_gain_sync(8, "训练师攻击")
		else:
			_gain_sync(5, "宝可梦攻击")
	if target.is_alive() and target.is_enemy() and target.data.max_stability > 0:
		var stability_damage := skill.stability_damage
		if _is_element_advantage(skill.element_type, target.data.element_type):
			stability_damage *= 2
		if skill.is_control:
			stability_damage += 8
		target.damage_stability(stability_damage)
		if target.is_broken:
			_gain_sync(12, "Break")
	if skill.can_ignite_grass and grid_manager.get_terrain(target_pos) == Enums.TerrainType.GRASS:
		grid_manager.set_terrain(target_pos, Enums.TerrainType.BURNING)
		_show_tip("%s 造成 %d 伤害，并点燃了草地。" % [skill.skill_name, actual])
	else:
		_show_tip("%s 造成 %d 伤害。" % [skill.skill_name, actual])
	_update_capture_marks()

func _resolve_card(grid_pos: Vector2i) -> void:
	if _selected_card_id == "recall":
		_resolve_recall(grid_pos)
		return
	var target := grid_manager.get_unit_at(grid_pos)
	match _selected_card_id:
		"haste":
			if target != null and target.is_ally() and target.data.unit_type != Enums.UnitType.PLAYER:
				_pay_card("haste")
				target.add_bonus_move(2)
				_finish_card("高速组件让 %s 下一次移动距离 +2。" % target.data.unit_name)
		"shield":
			if target != null and target.is_ally():
				_pay_card("shield")
				target.add_shield(30)
				_finish_card("%s 获得护盾。" % target.data.unit_name)
		"power":
			if target != null and target.is_ally() and target.data.unit_type != Enums.UnitType.PLAYER:
				_pay_card("power")
				target.set_power_boost(true)
				_finish_card("%s 的下一次攻击被强化。" % target.data.unit_name)
		"terrain":
			_pay_card("terrain")
			grid_manager.set_terrain(grid_pos, Enums.TerrainType.GRASS)
			_finish_card("目标格被重构为草地。")
		"capture":
			if target != null and target.is_capturable():
				_pay_card("capture")
				_capture_unit(target)
			else:
				_show_tip("目标必须是 Break 且低血的野生宝可梦。")

func _finish_card(message: String) -> void:
	_action_state = Enums.ActionState.IDLE
	grid_manager.clear_highlights()
	action_menu.show_at(_active_unit.position)
	_show_tip(message)

func _resolve_recall(grid_pos: Vector2i) -> void:
	var target := grid_manager.get_unit_at(grid_pos)
	if target == null or not target.is_ally() or target.data.unit_type == Enums.UnitType.PLAYER:
		_show_tip("只能回收训练师附近的己方宝可梦。")
		return
	if _sync_points < RECALL_COST:
		_show_tip("同步率不足，回收需要 %d。" % RECALL_COST)
		return
	_sync_points -= RECALL_COST
	if target.data.unit_name == "藤藤兽":
		_reserve_grass_data = target.data
	var target_name := target.data.unit_name
	_remove_unit(target, false)
	_finish_card("已回收 %s。" % target_name)

func _summon_grass(grid_pos: Vector2i) -> void:
	_sync_points -= SUMMON_COST
	var unit_scene := preload("res://units/Unit.tscn")
	var unit := _spawn_unit(unit_scene, _reserve_grass_data, grid_pos)
	ctb_system.add_unit(unit)
	_reserve_grass_data = null
	unit.current_ap = 40
	_action_state = Enums.ActionState.IDLE
	grid_manager.clear_highlights()
	action_menu.show_at(_active_unit.position)
	_update_sync_ui()
	_show_tip("藤藤兽入场。同步率回复会因为多一只宝可梦而变慢。")

func _capture_unit(unit: Unit) -> void:
	_captured_names.append(unit.data.unit_name)
	_gain_sync(18, "捕捉")
	_remove_unit(unit, false)
	_finish_card("封印成功，获得 %s。" % _captured_names.back())
	_check_battle_over()

# ── 资源、地形与工具 ────────────────────────────────────────────

func _is_trainer_turn() -> bool:
	return _active_unit != null \
		and is_instance_valid(_active_unit) \
		and _active_unit.data.unit_type == Enums.UnitType.PLAYER \
		and not _trainer_disabled

func _can_pay_card(card_id: String) -> bool:
	var card_def = CARD_DEFS[card_id]
	if _sync_points < card_def["cost"]:
		_show_tip("同步率不足，%s 需要 %d。" % [card_def["name"], card_def["cost"]])
		return false
	if _card_cooldowns.get(card_id, 0) > 0:
		_show_tip("%s 冷却中，还需 %d 次行动。" % [card_def["name"], _card_cooldowns[card_id]])
		return false
	return true

func _pay_card(card_id: String) -> void:
	var card_def = CARD_DEFS[card_id]
	_sync_points -= card_def["cost"]
	_card_cooldowns[card_id] = card_def["cooldown"]
	_update_sync_ui()

func _tick_card_cooldowns() -> void:
	for card_id in _card_cooldowns.keys():
		_card_cooldowns[card_id] = max(_card_cooldowns[card_id] - 1, 0)

func _gain_sync(amount: int, reason: String = "") -> void:
	var before := _sync_points
	_sync_points = min(_sync_points + amount, _max_sync_points)
	var gained := _sync_points - before
	_update_sync_ui()
	if gained > 0:
		_show_sync_feedback(gained, reason)

func _active_pokemon_count() -> int:
	var count := 0
	for unit in _all_units:
		if unit.is_ally() and unit.data.unit_type == Enums.UnitType.PLAYER_POKEMON:
			count += 1
	return count

func _update_sync_ui() -> void:
	if not is_instance_valid(_sync_label):
		return
	var cooldown_text := []
	for card_id in CARD_DEFS:
		var left: int = _card_cooldowns.get(card_id, 0)
		if left > 0:
			cooldown_text.append("%s:%d" % [CARD_DEFS[card_id]["name"], left])
	var trainer_state := "离线" if _trainer_disabled else "在线"
	_sync_label.text = "同步率 %d/%d\n训练师 %s  场上宝可梦 %d\n冷却 %s" % [
		_sync_points,
		_max_sync_points,
		trainer_state,
		_active_pokemon_count(),
		_join_strings(cooldown_text, "、") if cooldown_text.size() > 0 else "无"
	]

func _show_sync_feedback(amount: int, reason: String) -> void:
	if not is_instance_valid(_sync_feedback_label):
		return
	var reason_text := ""
	if reason != "":
		reason_text = " " + reason
	_sync_feedback_label.text = "+%d 同步率%s" % [amount, reason_text]
	_sync_feedback_label.modulate.a = 1.0
	_sync_feedback_label.position = Vector2(438, 6)
	_sync_feedback_label.visible = true
	var tween := create_tween()
	tween.tween_property(_sync_feedback_label, "position:y", -8.0, 0.55)
	tween.parallel().tween_property(_sync_feedback_label, "modulate:a", 0.0, 0.55)
	tween.tween_callback(func(): _sync_feedback_label.visible = false)

func _join_strings(parts: Array, delimiter: String) -> String:
	var text := ""
	for i in parts.size():
		if i > 0:
			text += delimiter
		text += str(parts[i])
	return text

func _show_tip(text: String) -> void:
	if is_instance_valid(_tip_label):
		_tip_label.text = text

func _cells_in_range(origin: Vector2i, range_value: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-range_value, range_value + 1):
		for dx in range(-range_value, range_value + 1):
			var pos := origin + Vector2i(dx, dy)
			if abs(dx) + abs(dy) <= range_value and grid_manager.is_valid(pos):
				result.append(pos)
	return result

func _empty_cells_in_range(origin: Vector2i, range_value: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _cells_in_range(origin, range_value):
		if cell != origin and not grid_manager.is_occupied(cell):
			result.append(cell)
	return result

func _is_element_advantage(attack_type: int, target_type: int) -> bool:
	return (attack_type == Enums.ElementType.FIRE and target_type == Enums.ElementType.GRASS) \
		or (attack_type == Enums.ElementType.GRASS and target_type == Enums.ElementType.WATER) \
		or (attack_type == Enums.ElementType.WATER and target_type == Enums.ElementType.FIRE)

func _apply_tile_effect(unit: Unit) -> void:
	if not is_instance_valid(unit) or not unit.is_alive():
		return
	if grid_manager.get_terrain(unit.grid_pos) == Enums.TerrainType.BURNING \
	and unit.data.element_type != Enums.ElementType.FIRE:
		unit.take_damage(8)
		_show_tip("%s 被燃烧地面灼伤。" % unit.data.unit_name)

func _update_capture_marks() -> void:
	for unit in _all_units:
		if is_instance_valid(unit):
			unit.set_capture_ready(unit.is_capturable())

func _remove_unit(unit: Unit, check_over: bool = true) -> void:
	if not is_instance_valid(unit):
		return
	grid_manager.remove_unit(unit.grid_pos)
	ctb_system.remove_unit(unit)
	ctb_bar.remove_unit(unit)
	_all_units.erase(unit)
	unit.queue_free()
	if check_over:
		_check_battle_over()

func _on_unit_status_changed(_unit: Unit) -> void:
	_update_capture_marks()

# ── 胜负判断 ────────────────────────────────────────────────────

func _on_unit_died(unit: Unit) -> void:
	if unit.data.unit_type == Enums.UnitType.PLAYER:
		_trainer_disabled = true
		_trainer = null
		_remove_unit(unit, false)
		_show_tip("训练师倒下：对局继续，但无法再刷卡、召唤、回收或封印。")
		_update_sync_ui()
		_check_battle_over()
		return
	_remove_unit(unit)

func _check_battle_over() -> void:
	if _battle_state == Enums.BattleState.BATTLE_OVER:
		return
	var has_ally := _all_units.any(func(u): return u.is_ally() and u.is_alive())
	var has_enemy := _all_units.any(func(u): return u.is_enemy() and u.is_alive())
	
	if not has_ally:
		_end_battle("失败：全体倒下")
	elif not has_enemy:
		var suffix := ""
		if _captured_names.size() > 0:
			suffix = "\n捕捉：" + _join_strings(_captured_names, "、")
		_end_battle("胜利！" + suffix)

func _end_battle(text: String) -> void:
	_battle_state = Enums.BattleState.BATTLE_OVER
	ctb_system.stop()
	action_menu.hide_menu()
	result_label.text = text
	result_label.visible = true
