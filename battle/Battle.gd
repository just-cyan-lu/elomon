extends Node

const TypeChartUtil = preload("res://core/TypeChart.gd")
const CARD_RANGE := 3
const SUMMON_COST := 50
const RECALL_COST := 10
const EXTRACT_COST := 20
const CARD_DEFS := {
	"haste": {"name": "高速组件", "cost": 30, "cooldown": 2, "effect": "目标宝可梦下一次移动距离 +2，移动后消耗。"},
	"shield": {"name": "小型护盾", "cost": 20, "cooldown": 2, "effect": "目标友方获得 30 护盾，护盾会抵消之后受到的伤害。"},
	"power": {"name": "火力插件", "cost": 25, "cooldown": 2, "effect": "目标宝可梦下一次攻击伤害提高 50%，攻击后消耗。"},
	"capture": {"name": "空白封印卡", "cost": 40, "cooldown": 3, "effect": "封印稳定度归零且 HP 低于 40% 的野生宝可梦。"},
}
const EXTRACT_DEFS := {
	"grass": {"name": "提取藤藤兽", "reserve": "藤藤兽", "skill_index": 1, "effect": "训练师切换为草属性，技能替换为缠绕；被火系克制，抵抗水系。"},
	"water": {"name": "提取水跃兽", "reserve": "水跃兽", "skill_index": 1, "effect": "训练师切换为水属性，技能替换为水愈；抵抗火系，被草系克制。"},
	"spark": {"name": "提取电花鼠", "reserve": "电花鼠", "skill_index": 0, "effect": "训练师切换为无属性，技能替换为电弧；雷系尚未进入 MVP 克制表。"},
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
var _reserve_units: Dictionary = {}
var _trainer_extract_id: String = ""
var _captured_names: Array[String] = []

var _sync_points: int = 70
var _max_sync_points: int = 100
var _selected_card_id: String = ""
var _selected_skill_index: int = 0
var _sync_label: Label
var _sync_feedback_label: Label
var _tip_label: Label
var _enemy_threat_button: Button
var _preview_panel: PanelContainer
var _preview_label: Label
var _card_cooldowns := {}
var _selected_skill_target: Vector2i = Vector2i(-1, -1)
var _skill_preview_entries: Array[Dictionary] = []
var _skill_preview_markers: Array[Label] = []
var _enemy_threat_visible: bool = false
var _turn_start_pos: Vector2i = Vector2i(-1, -1)
var _turn_start_snapshot := {}
var _turn_has_support_action: bool = false
var _extract_undo_available: bool = false
var _extract_undo_snapshot := {}

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
	_sync_label.size = Vector2(260, 82)
	_sync_label.add_theme_font_size_override("font_size", 8)
	_sync_label.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0, 1.0))
	$UI.add_child(_sync_label)

	_sync_feedback_label = Label.new()
	_sync_feedback_label.position = Vector2(492, 6)
	_sync_feedback_label.size = Vector2(140, 24)
	_sync_feedback_label.add_theme_font_size_override("font_size", 11)
	_sync_feedback_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0, 1.0))
	_sync_feedback_label.visible = false
	$UI.add_child(_sync_feedback_label)

	_tip_label = Label.new()
	_tip_label.position = Vector2(220, 88)
	_tip_label.size = Vector2(380, 64)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.add_theme_font_size_override("font_size", 8)
	$UI.add_child(_tip_label)

	_enemy_threat_button = Button.new()
	_enemy_threat_button.position = Vector2(548, 34)
	_enemy_threat_button.size = Vector2(86, 20)
	_enemy_threat_button.text = "敌方范围"
	_enemy_threat_button.add_theme_font_size_override("font_size", 8)
	_enemy_threat_button.pressed.connect(_toggle_enemy_threat)
	$UI.add_child(_enemy_threat_button)

	_preview_panel = PanelContainer.new()
	_preview_panel.position = Vector2(418, 126)
	_preview_panel.size = Vector2(216, 170)
	_preview_panel.visible = false
	$UI.add_child(_preview_panel)
	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 3)
	_preview_panel.add_child(preview_box)
	_preview_label = Label.new()
	_preview_label.custom_minimum_size = Vector2(204, 118)
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.add_theme_font_size_override("font_size", 8)
	preview_box.add_child(_preview_label)
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 4)
	preview_box.add_child(button_row)
	var confirm_button := Button.new()
	confirm_button.text = "确认"
	confirm_button.custom_minimum_size = Vector2(72, 20)
	confirm_button.add_theme_font_size_override("font_size", 8)
	confirm_button.pressed.connect(_confirm_skill_preview)
	button_row.add_child(confirm_button)
	var cancel_button := Button.new()
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(72, 20)
	cancel_button.add_theme_font_size_override("font_size", 8)
	cancel_button.pressed.connect(_return_to_skill_selection)
	button_row.add_child(cancel_button)

func _spawn_units() -> void:
	var fire_skill := _make_skill("火花", 26, 2, 30, Enums.ElementType.FIRE, 20)
	var flame_line := _make_skill("火焰喷射", 42, 3, 75, Enums.ElementType.FIRE, 35, false, 1)
	var vine_skill := _make_skill("藤鞭", 24, 3, 35, Enums.ElementType.GRASS, 18, false)
	var snare_skill := _make_skill("缠绕", 14, 3, 45, Enums.ElementType.GRASS, 25, true)
	var water_skill := _make_skill("水泡", 20, 3, 35, Enums.ElementType.WATER, 14)
	var mend_skill := _make_skill("水愈", 22, 3, 40, Enums.ElementType.WATER, 0, false, 0, SkillData.EffectType.HEAL)
	var spark_skill := _make_skill("电弧", 22, 3, 40, Enums.ElementType.NONE, 16)
	var quick_skill := _make_skill("疾闪", 12, 2, 30, Enums.ElementType.NONE, 8)
	var blade_skill := _make_skill("数据短刃", 14, 1, 25, Enums.ElementType.NONE, 8)
	var fire_bite_skill := _make_skill("火牙", 22, 1, 35, Enums.ElementType.FIRE, 10)
	var grass_bite_skill := _make_skill("叶咬", 22, 1, 35, Enums.ElementType.GRASS, 10)
	var water_dart_skill := _make_skill("水针", 18, 3, 45, Enums.ElementType.WATER, 10)
	var boss_skill := _make_skill("重踏", 10, 1, 60, Enums.ElementType.GRASS, 10)
	
	var grass_data := _make_unit_data("藤藤兽", Enums.UnitType.PLAYER_POKEMON, 95, 15, 5, 48, 4, Color(0.25, 0.75, 0.36), Enums.ElementType.GRASS, [vine_skill, snare_skill])
	var water_data := _make_unit_data("水跃兽", Enums.UnitType.PLAYER_POKEMON, 88, 13, 4, 52, 4, Color(0.24, 0.58, 0.86), Enums.ElementType.WATER, [water_skill, mend_skill])
	var spark_data := _make_unit_data("电花鼠", Enums.UnitType.PLAYER_POKEMON, 76, 16, 3, 68, 5, Color(0.85, 0.78, 0.34), Enums.ElementType.NONE, [spark_skill, quick_skill])
	_reserve_units.clear()
	_reserve_units[grass_data.unit_name] = grass_data
	_reserve_units[water_data.unit_name] = water_data
	_reserve_units[spark_data.unit_name] = spark_data
	
	var unit_scene := preload("res://units/Unit.tscn")
	var trainer_data := _make_unit_data("训练师", Enums.UnitType.PLAYER, 90, 10, 4, 44, 4, Color(0.35, 0.85, 0.88), Enums.ElementType.NONE, [blade_skill])
	_spawn_unit(unit_scene, trainer_data, Vector2i(2, 5))
	_spawn_unit(unit_scene, _make_unit_data("火狐兽", Enums.UnitType.PLAYER_POKEMON, 105, 18, 5, 58, 4, Color(0.95, 0.42, 0.18), Enums.ElementType.FIRE, [fire_skill, flame_line]), Vector2i(3, 5))
	_spawn_unit(unit_scene, _make_unit_data("火牙小怪", Enums.UnitType.ENEMY, 72, 13, 3, 36, 4, Color(0.92, 0.34, 0.32), Enums.ElementType.FIRE, [fire_bite_skill]), Vector2i(10, 4))
	_spawn_unit(unit_scene, _make_unit_data("叶咬小怪", Enums.UnitType.ENEMY, 72, 13, 3, 34, 4, Color(0.82, 0.36, 0.28), Enums.ElementType.GRASS, [grass_bite_skill]), Vector2i(10, 7))
	_spawn_unit(unit_scene, _make_unit_data("水针小怪", Enums.UnitType.ENEMY, 62, 11, 2, 40, 3, Color(0.34, 0.48, 0.82), Enums.ElementType.WATER, [water_dart_skill]), Vector2i(13, 5))
	_spawn_unit(unit_scene, _make_unit_data("铁甲巨兽", Enums.UnitType.WILD_POKEMON, 280, 8, 8, 24, 2, Color(0.25, 0.65, 0.25), Enums.ElementType.GRASS, [boss_skill], 110, true, 3, 18, 5, 1), Vector2i(14, 9))

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
	max_stability: int = 0,
	can_charge_attack: bool = false,
	charge_interval: int = 3,
	charge_damage: int = 16,
	charge_range: int = 5,
	charge_radius: int = 1
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
	var unit_element_types: Array[int] = []
	if element_type != Enums.ElementType.NONE:
		unit_element_types.append(element_type)
	data.set_element_types(unit_element_types)
	for skill in skills:
		data.skills.append(skill)
	data.max_stability = max_stability
	data.can_charge_attack = can_charge_attack
	data.charge_interval = charge_interval
	data.charge_damage = charge_damage
	data.charge_range = charge_range
	data.charge_radius = charge_radius
	return data

func _make_skill(
	skill_name: String,
	damage: int,
	atk_range: int,
	ap_cost: float,
	element_type: int,
	stability_damage: int,
	is_control: bool = false,
	area_radius: int = 0,
	effect_type: int = SkillData.EffectType.DAMAGE
) -> SkillData:
	var skill := SkillData.new()
	skill.skill_name = skill_name
	skill.damage = damage
	skill.atk_range = atk_range
	skill.ap_cost = ap_cost
	skill.element_type = element_type
	skill.stability_damage = stability_damage
	skill.is_control = is_control
	skill.area_radius = area_radius
	skill.effect_type = effect_type
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
	action_menu.extract_pressed.connect(_on_extract_pressed)
	action_menu.summon_pressed.connect(_on_summon_pressed)
	action_menu.recall_pressed.connect(_on_recall_pressed)
	action_menu.option_hovered.connect(_show_tip)

# ── CTB 流程 ────────────────────────────────────────────────────

func _on_unit_ready(unit: Unit) -> void:
	_active_unit = unit
	_active_unit.has_acted = false
	_active_unit.has_moved = false
	_capture_turn_start_state(_active_unit)
	_turn_has_support_action = false
	_clear_extract_undo()
	_tick_card_cooldowns()
	_gain_sync(max(1, 6 - _active_pokemon_count() * 2), "自然回复")
	_update_capture_marks()
	if not is_instance_valid(_active_unit) or not _active_unit.is_alive():
		if _battle_state != Enums.BattleState.BATTLE_OVER:
			ctb_system.resume()
		return
	
	if unit.is_enemy():
		_battle_state = Enums.BattleState.ENEMY_TURN
		action_menu.hide_menu()
		await UnitAI.run(unit, grid_manager, _all_units)
		_end_turn()
	else:
		_battle_state = Enums.BattleState.PLAYER_TURN
		_action_state = Enums.ActionState.IDLE
		if _active_unit.data.unit_type == Enums.UnitType.PLAYER:
			_show_tip("轮到 %s。训练师回合可以提取后备能力、刷卡、召唤、回收和封印。" % _active_unit.data.unit_name)
		elif _trainer_disabled:
			_show_tip("轮到 %s。训练师已倒下，无法再使用卡牌和切换宝可梦。" % _active_unit.data.unit_name)
		else:
			_show_tip("轮到 %s。" % _active_unit.data.unit_name)
		_show_action_menu()

# 回合结束：扣行动力，重置状态，恢复跑条
func _end_turn() -> void:
	if _battle_state == Enums.BattleState.BATTLE_OVER:
		return
	if _active_unit and is_instance_valid(_active_unit):
		_active_unit.consume_ap(Enums.MAX_AP)
	_action_state = Enums.ActionState.IDLE
	_selected_card_id = ""
	_selected_skill_index = 0
	_selected_skill_target = Vector2i(-1, -1)
	_turn_has_support_action = false
	_clear_extract_undo()
	_move_cells.clear()
	_attack_cells.clear()
	_card_cells.clear()
	_clear_skill_preview()
	grid_manager.clear_highlights()
	_update_enemy_threat_overlay()
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
	_highlight_move_with_attack_preview(_active_unit, _move_cells)
	action_menu.hide_menu()
	_show_tip("选择移动格。蓝色=可移动，红色=移动后最远技能覆盖范围。")

func _on_skill_pressed(skill_index: int) -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN: return
	if _active_unit.has_acted:
		_show_tip("本回合已经用过技能。")
		return
	if skill_index >= _active_unit.data.skills.size():
		_show_tip("这个单位没有技能 %d。" % (skill_index + 1))
		return
	_selected_skill_index = skill_index
	_selected_skill_target = Vector2i(-1, -1)
	_clear_skill_preview()
	_action_state = Enums.ActionState.SELECTING_SKILL
	var skill: SkillData = _active_unit.data.skills[_selected_skill_index]
	_attack_cells = grid_manager.get_attack_range(_active_unit.grid_pos, skill.atk_range)
	if skill.effect_type == SkillData.EffectType.HEAL:
		_attack_cells.append(_active_unit.grid_pos)
		grid_manager.highlight_cells(_attack_cells, GridManager.COLOR_MOVE)
	else:
		grid_manager.highlight_cells(_attack_cells, GridManager.COLOR_ATTACK)
	action_menu.hide_menu()
	_show_tip("选择 %s 的目标。技能不消耗 AP，每次行动最多使用一次。" % skill.skill_name)

func _on_wait_pressed() -> void:
	_end_turn()

func _cancel_current_selection() -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN:
		return
	if _action_state == Enums.ActionState.IDLE and _can_undo_trainer_extract():
		_undo_trainer_extract()
		return
	if _active_unit != null \
	and is_instance_valid(_active_unit) \
	and _active_unit.has_moved \
	and not _active_unit.has_acted:
		if _turn_has_support_action:
			if _action_state != Enums.ActionState.IDLE:
				_cancel_to_action_menu("已取消选择。")
			else:
				_show_tip("已经使用过提取、卡牌、召唤或回收，本回合不能撤回移动。")
			return
		if _action_state == Enums.ActionState.CONFIRMING_SKILL:
			_clear_skill_preview()
		_undo_active_unit_move()
		return
	if _action_state == Enums.ActionState.IDLE:
		return
	if _action_state == Enums.ActionState.CONFIRMING_SKILL:
		_return_to_skill_selection()
		return
	_action_state = Enums.ActionState.IDLE
	_selected_card_id = ""
	_selected_skill_index = 0
	_selected_skill_target = Vector2i(-1, -1)
	_move_cells.clear()
	_attack_cells.clear()
	_card_cells.clear()
	_clear_skill_preview()
	grid_manager.clear_highlights()
	_show_action_menu()
	_show_tip("已取消选择。")

func _on_summon_pressed() -> void:
	if not _is_trainer_turn():
		_show_tip("只有训练师行动时可以召唤。")
		return
	if not _reserve_units.has("藤藤兽"):
		_show_tip("藤藤兽不在后备中，暂时没有可召唤的宝可梦。")
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
	_card_cells = _cells_in_range(_trainer.grid_pos, CARD_RANGE)
	grid_manager.highlight_cells(_card_cells, GridManager.COLOR_ATTACK)
	action_menu.hide_menu()
	_show_tip("选择 %s 的目标。" % CARD_DEFS[card_id]["name"])

func _on_extract_pressed(extract_id: String) -> void:
	if not _is_trainer_turn():
		_show_tip("只有训练师行动时可以提取后备能力。")
		return
	if not EXTRACT_DEFS.has(extract_id):
		return
	if _trainer_extract_id == extract_id:
		_show_tip("训练师已经处于%s状态。" % EXTRACT_DEFS[extract_id]["reserve"])
		return
	var extract_def = EXTRACT_DEFS[extract_id]
	var reserve_name := str(extract_def["reserve"])
	if not _reserve_units.has(reserve_name):
		_show_tip("%s 不在后备中，不能提取它的能力。" % reserve_name)
		return
	if _sync_points < EXTRACT_COST:
		_show_tip("同步率不足，提取需要 %d。" % EXTRACT_COST)
		return
	var can_undo_extract := not _turn_has_support_action \
		and not _active_unit.has_moved \
		and not _active_unit.has_acted
	if can_undo_extract:
		_capture_extract_undo_state()
	else:
		_clear_extract_undo()
	_sync_points -= EXTRACT_COST
	_turn_has_support_action = true
	_apply_trainer_extract(extract_id)
	_update_sync_ui()
	_show_action_menu()
	_show_tip("训练师提取了 %s：属性和技能已切换，直到下一次提取。" % reserve_name)

func _on_cell_clicked(grid_pos: Vector2i) -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN: return
	
	match _action_state:
		Enums.ActionState.SELECTING_MOVE:
			if grid_pos in _move_cells:
				_clear_extract_undo()
				grid_manager.move_unit(_active_unit, _active_unit.grid_pos, grid_pos)
				_active_unit.grid_pos = grid_pos
				_active_unit.has_moved = true
				_active_unit.consume_bonus_move()
				_action_state = Enums.ActionState.IDLE
				grid_manager.clear_highlights()
				_update_enemy_threat_overlay()
				_show_action_menu()
		
		Enums.ActionState.SELECTING_SKILL:
			if grid_pos in _attack_cells:
				_show_skill_preview(grid_pos)

		Enums.ActionState.CONFIRMING_SKILL:
			if grid_pos == _selected_skill_target:
				_confirm_skill_preview()
			elif grid_pos in _attack_cells:
				_show_skill_preview(grid_pos)

		Enums.ActionState.SELECTING_CARD:
			if grid_pos in _card_cells:
				_resolve_card(grid_pos)

		Enums.ActionState.SELECTING_SUMMON:
			if grid_pos in _card_cells and not grid_manager.is_occupied(grid_pos):
				_summon_grass(grid_pos)

		Enums.ActionState.IDLE:
			var target := grid_manager.get_unit_at(grid_pos)
			if target != null and target.is_enemy():
				_preview_unit_ranges(target)
			else:
				grid_manager.clear_highlights()
				_show_action_menu()

func _show_skill_preview(target_pos: Vector2i) -> void:
	var skill: SkillData = _active_unit.data.skills[_selected_skill_index]
	var entries := _build_skill_preview(_active_unit, skill, target_pos)
	if entries.is_empty():
		if skill.effect_type == SkillData.EffectType.HEAL:
			_show_tip("这个位置没有可治疗的友方。")
		else:
			_show_tip("这个位置没有可命中的敌人。")
		return
	_action_state = Enums.ActionState.CONFIRMING_SKILL
	_selected_skill_target = target_pos
	_skill_preview_entries = entries
	_show_preview_area(skill, target_pos)
	_show_preview_panel(_active_unit, skill, entries)
	_show_preview_markers(entries)
	_show_tip("确认后发动 %s。可点其它范围内格子重新预览，Esc 返回选目标。" % skill.skill_name)

func _confirm_skill_preview() -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN:
		return
	if _action_state != Enums.ActionState.CONFIRMING_SKILL or _skill_preview_entries.is_empty():
		return
	var skill: SkillData = _active_unit.data.skills[_selected_skill_index]
	_execute_skill_preview(_active_unit, skill, _selected_skill_target, _skill_preview_entries)
	if _battle_state == Enums.BattleState.BATTLE_OVER:
		_clear_skill_preview()
		grid_manager.clear_highlights()
		action_menu.hide_menu()
		return
	_active_unit.has_acted = true
	_action_state = Enums.ActionState.IDLE
	_selected_skill_target = Vector2i(-1, -1)
	_skill_preview_entries.clear()
	_clear_skill_preview()
	grid_manager.clear_highlights()
	_end_turn()

func _return_to_skill_selection() -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN:
		return
	if _active_unit == null or not is_instance_valid(_active_unit):
		return
	_action_state = Enums.ActionState.SELECTING_SKILL
	_selected_skill_target = Vector2i(-1, -1)
	_skill_preview_entries.clear()
	_clear_skill_preview()
	var skill: SkillData = _active_unit.data.skills[_selected_skill_index]
	_attack_cells = grid_manager.get_attack_range(_active_unit.grid_pos, skill.atk_range)
	if skill.effect_type == SkillData.EffectType.HEAL:
		_attack_cells.append(_active_unit.grid_pos)
		grid_manager.highlight_cells(_attack_cells, GridManager.COLOR_MOVE)
	else:
		grid_manager.highlight_cells(_attack_cells, GridManager.COLOR_ATTACK)
	_show_tip("选择 %s 的目标。" % skill.skill_name)

func _execute_skill_preview(attacker: Unit, skill: SkillData, target_pos: Vector2i, entries: Array[Dictionary]) -> void:
	if skill.effect_type == SkillData.EffectType.HEAL:
		var total_heal := 0
		for entry in entries:
			var heal_target: Unit = entry["target"]
			if not is_instance_valid(heal_target) or not heal_target.is_alive():
				continue
			total_heal += heal_target.heal(entry["heal_amount"])
		_show_tip("%s 回复 %d 点 HP。" % [skill.skill_name, total_heal])
		return

	var total_damage := 0
	var depleted_count := 0
	for entry in entries:
		var target: Unit = entry["target"]
		if not is_instance_valid(target) or not target.is_alive():
			continue
		var was_stability_depleted := target.stability_depleted
		var actual := target.take_damage(entry["raw_damage"], attacker, skill.element_type)
		total_damage += actual
		if target.is_alive() and target.is_enemy() and target.data.max_stability > 0:
			target.damage_stability(entry["stability_damage"])
			if not was_stability_depleted and target.stability_depleted:
				depleted_count += 1
	if attacker.power_boost_next_attack:
		attacker.set_power_boost(false)
	if attacker.is_ally() and total_damage > 0:
		if attacker.data.unit_type == Enums.UnitType.PLAYER:
			_gain_sync(8, "训练师攻击")
		else:
			_gain_sync(5, "宝可梦攻击")
	for i in range(depleted_count):
		_gain_sync(12, "稳定归零")
	_show_tip("%s 命中 %d 个目标，共造成 %d 伤害。" % [skill.skill_name, entries.size(), total_damage])
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
		"capture":
			if target != null and target.is_capturable():
				_pay_card("capture")
				_capture_unit(target)
			else:
				_show_tip("目标必须稳定度归零、低血，且是野生宝可梦。")

func _finish_card(message: String) -> void:
	_action_state = Enums.ActionState.IDLE
	grid_manager.clear_highlights()
	_update_sync_ui()
	_show_action_menu()
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
	_turn_has_support_action = true
	_clear_extract_undo()
	_reserve_units[target.data.unit_name] = target.data
	var target_name := target.data.unit_name
	_remove_unit(target, false)
	_finish_card("已回收 %s。" % target_name)

func _summon_grass(grid_pos: Vector2i) -> void:
	_sync_points -= SUMMON_COST
	_turn_has_support_action = true
	_clear_extract_undo()
	var unit_scene := preload("res://units/Unit.tscn")
	var unit_data: UnitData = _reserve_units["藤藤兽"]
	var unit := _spawn_unit(unit_scene, unit_data, grid_pos)
	ctb_system.add_unit(unit)
	_reserve_units.erase("藤藤兽")
	unit.current_ap = 40
	_action_state = Enums.ActionState.IDLE
	grid_manager.clear_highlights()
	_update_enemy_threat_overlay()
	_update_sync_ui()
	_show_action_menu()
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

func _apply_trainer_extract(extract_id: String) -> void:
	if _trainer == null or not is_instance_valid(_trainer) or not EXTRACT_DEFS.has(extract_id):
		return
	var extract_def = EXTRACT_DEFS[extract_id]
	var reserve_name := str(extract_def["reserve"])
	if not _reserve_units.has(reserve_name):
		return
	var reserve_data: UnitData = _reserve_units[reserve_name]
	var skill_index := int(extract_def["skill_index"])
	if skill_index < 0 or skill_index >= reserve_data.skills.size():
		return
	_trainer_extract_id = extract_id
	_trainer.data.set_element_types(reserve_data.get_element_types())
	_trainer.data.skills.clear()
	_trainer.data.skills.append(reserve_data.skills[skill_index])
	_trainer.refresh_status()

func _capture_extract_undo_state() -> void:
	if _trainer == null or not is_instance_valid(_trainer):
		_clear_extract_undo()
		return
	_extract_undo_snapshot = {
		"sync_points": _sync_points,
		"extract_id": _trainer_extract_id,
		"element_types": _trainer.data.get_element_types(),
		"skills": _trainer.data.skills.duplicate()
	}
	_extract_undo_available = true

func _can_undo_trainer_extract() -> bool:
	return _extract_undo_available \
		and _active_unit != null \
		and is_instance_valid(_active_unit) \
		and _active_unit.data.unit_type == Enums.UnitType.PLAYER \
		and not _active_unit.has_moved \
		and not _active_unit.has_acted \
		and _extract_undo_snapshot.has("sync_points")

func _undo_trainer_extract() -> void:
	if _trainer == null or not is_instance_valid(_trainer):
		_clear_extract_undo()
		return
	_sync_points = int(_extract_undo_snapshot["sync_points"])
	_trainer_extract_id = str(_extract_undo_snapshot["extract_id"])
	var restored_element_types: Array[int] = []
	for element_type_value in _extract_undo_snapshot["element_types"]:
		restored_element_types.append(int(element_type_value))
	_trainer.data.set_element_types(restored_element_types)
	_trainer.data.skills.clear()
	for skill in _extract_undo_snapshot["skills"]:
		_trainer.data.skills.append(skill)
	_trainer.refresh_status()
	_turn_has_support_action = false
	_clear_extract_undo()
	_cancel_to_action_menu("已取消本次能力提取，同步率已返还。")

func _clear_extract_undo() -> void:
	_extract_undo_available = false
	_extract_undo_snapshot.clear()

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
	_turn_has_support_action = true
	_clear_extract_undo()
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
	var trainer_form := "离线" if _trainer_disabled else _get_trainer_form_summary()
	_sync_label.text = "同步率 %d/%d\n形态 %s  宝%d 后备 %s\n获得: 自然+%d 训攻+8 宝攻+5 稳0+12 捕+18\n冷却 %s" % [
		_sync_points,
		_max_sync_points,
		trainer_form,
		_active_pokemon_count(),
		_get_reserve_summary(),
		max(1, 6 - _active_pokemon_count() * 2),
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
	_sync_feedback_label.position = Vector2(492, 6)
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

func _get_reserve_summary() -> String:
	if _reserve_units.is_empty():
		return "无"
	var names: Array[String] = []
	for reserve_name in _reserve_units.keys():
		names.append(str(reserve_name))
	names.sort()
	return _join_strings(names, "、")

func _get_trainer_form_summary() -> String:
	if _trainer_extract_id == "" or not EXTRACT_DEFS.has(_trainer_extract_id):
		return "基础"
	return str(EXTRACT_DEFS[_trainer_extract_id]["reserve"])

func _show_tip(text: String) -> void:
	if is_instance_valid(_tip_label):
		_tip_label.text = text

func _capture_turn_start_state(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		_turn_start_pos = Vector2i(-1, -1)
		_turn_start_snapshot.clear()
		return
	_turn_start_pos = unit.grid_pos
	_turn_start_snapshot = {
		"current_hp": unit.current_hp,
		"shield": unit.shield,
		"current_stability": unit.current_stability,
		"stability_depleted": unit.stability_depleted,
		"capture_ready": unit.capture_ready,
		"bonus_move_range": unit.bonus_move_range
	}

func _undo_active_unit_move() -> void:
	if _active_unit == null or not is_instance_valid(_active_unit):
		return
	if _turn_start_pos == Vector2i(-1, -1) or _active_unit.grid_pos == _turn_start_pos:
		return
	if grid_manager.is_occupied(_turn_start_pos):
		_show_tip("起始格已被占用，不能撤回移动。")
		return
	grid_manager.move_unit(_active_unit, _active_unit.grid_pos, _turn_start_pos)
	_active_unit.grid_pos = _turn_start_pos
	_active_unit.has_moved = false
	_active_unit.restore_turn_snapshot(_turn_start_snapshot)
	_cancel_to_action_menu("已撤回移动，回到本回合开始位置。")

func _cancel_to_action_menu(message: String) -> void:
	_action_state = Enums.ActionState.IDLE
	_selected_card_id = ""
	_selected_skill_index = 0
	_selected_skill_target = Vector2i(-1, -1)
	_move_cells.clear()
	_attack_cells.clear()
	_card_cells.clear()
	_clear_skill_preview()
	grid_manager.clear_highlights()
	_update_enemy_threat_overlay()
	_show_action_menu()
	_show_tip(message)

func _toggle_enemy_threat() -> void:
	_enemy_threat_visible = not _enemy_threat_visible
	_update_enemy_threat_overlay()

func _update_enemy_threat_overlay() -> void:
	if not is_instance_valid(grid_manager):
		return
	if not _enemy_threat_visible:
		grid_manager.clear_threat_cells()
		if is_instance_valid(_enemy_threat_button):
			_enemy_threat_button.text = "敌方范围"
		return
	grid_manager.set_threat_cells(_get_all_enemy_threat_cells())
	if is_instance_valid(_enemy_threat_button):
		_enemy_threat_button.text = "隐藏范围"

func _get_all_enemy_threat_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen := {}
	for unit in _all_units:
		if not is_instance_valid(unit) or not unit.is_enemy() or not unit.is_alive():
			continue
		var move_cells := grid_manager.get_move_range(unit.grid_pos, unit.get_current_move_range())
		for cell in _get_attack_preview_cells(unit, move_cells):
			if not seen.has(cell):
				seen[cell] = true
				result.append(cell)
	return result

func _show_action_menu() -> void:
	if _active_unit == null or not is_instance_valid(_active_unit):
		return
	_update_action_menu_content()
	action_menu.show_at(_active_unit.position)

func _update_action_menu_content() -> void:
	var skill_names: Array[String] = []
	for skill_resource in _active_unit.data.skills:
		var skill: SkillData = skill_resource
		skill_names.append(skill.skill_name)
	action_menu.set_skill_labels(skill_names)
	action_menu.set_card_labels(_build_card_labels())
	action_menu.set_extract_labels(_build_extract_labels())
	action_menu.set_option_descriptions(_build_action_descriptions())

func _build_card_labels() -> Dictionary:
	var labels := {}
	for card_id in CARD_DEFS:
		var left: int = _card_cooldowns.get(card_id, 0)
		if left > 0:
			labels[card_id] = "%sCD%d" % [_get_card_short_name(card_id), left]
		else:
			labels[card_id] = "%s%d" % [_get_card_short_name(card_id), CARD_DEFS[card_id]["cost"]]
	return labels

func _build_extract_labels() -> Dictionary:
	var labels := {}
	for extract_id in EXTRACT_DEFS:
		var label := _get_extract_short_name(extract_id)
		var reserve_name := str(EXTRACT_DEFS[extract_id]["reserve"])
		if _trainer_extract_id == extract_id:
			labels[extract_id] = label + "*"
		elif not _reserve_units.has(reserve_name):
			labels[extract_id] = label + "离"
		else:
			labels[extract_id] = "%s%d" % [label, EXTRACT_COST]
	return labels

func _build_action_descriptions() -> Dictionary:
	var descriptions := {}
	descriptions["move"] = "移动：最多 %d 格。移动后仍可使用技能；使用技能后会自动结束回合。" % _active_unit.get_current_move_range()
	descriptions["wait"] = "待机：不移动、不使用技能，直接结束当前单位行动。"
	for i in range(2):
		var key := "skill%d" % (i + 1)
		if i < _active_unit.data.skills.size():
			var skill: SkillData = _active_unit.data.skills[i]
			descriptions[key] = _describe_skill(skill)
		else:
			descriptions[key] = "这个单位没有技能 %d。" % (i + 1)
	descriptions["summon"] = "召唤：消耗 %d 同步率，在训练师 %d 格内召唤藤藤兽。召唤后藤藤兽以 40 AP 入场。" % [SUMMON_COST, CARD_RANGE]
	descriptions["recall"] = "回收：消耗 %d 同步率，收回训练师 %d 格内的己方宝可梦，保留 HP 和 AP 状态。" % [RECALL_COST, CARD_RANGE]
	for card_id in CARD_DEFS:
		descriptions[card_id] = _describe_card(card_id)
	for extract_id in EXTRACT_DEFS:
		descriptions["extract_" + extract_id] = _describe_extract(extract_id)
	return descriptions

func _describe_skill(skill: SkillData) -> String:
	var parts: Array[String] = []
	var target_text := "单体"
	if skill.area_radius > 0:
		target_text = "目标格周围 %d 格范围" % skill.area_radius
	parts.append("%s：射程 %d，%s。" % [skill.skill_name, skill.atk_range, target_text])
	if skill.effect_type == SkillData.EffectType.HEAL:
		parts.append("基础回复 %d + %s 攻击 %d；可选择自己或友方，确认后自动结束回合。" % [skill.damage, _active_unit.data.unit_name, _active_unit.data.attack])
	elif skill.stability_damage > 0:
		parts.append("基础伤害 %d + %s 攻击 %d；确认命中后自动结束回合。" % [skill.damage, _active_unit.data.unit_name, _active_unit.data.attack])
		parts.append("稳定度伤害 %d；属性克制时翻倍，控制技能会额外增加。" % skill.stability_damage)
	else:
		parts.append("基础伤害 %d + %s 攻击 %d；确认命中后自动结束回合。" % [skill.damage, _active_unit.data.unit_name, _active_unit.data.attack])
	if skill.is_control:
		parts.append("控制技能。")
	return _join_strings(parts, "\n")

func _describe_card(card_id: String) -> String:
	var card_def = CARD_DEFS[card_id]
	var left: int = _card_cooldowns.get(card_id, 0)
	var status := "可用"
	if left > 0:
		status = "冷却中，还需 %d 次行动" % left
	elif _sync_points < card_def["cost"]:
		status = "同步率不足"
	return "%s：消耗 %d，同步率当前 %d/%d，冷却 %d。%s\n状态：%s" % [
		card_def["name"],
		card_def["cost"],
		_sync_points,
		_max_sync_points,
		card_def["cooldown"],
		card_def["effect"],
		status
	]

func _describe_extract(extract_id: String) -> String:
	var extract_def = EXTRACT_DEFS[extract_id]
	var reserve_name := str(extract_def["reserve"])
	var status := "可用"
	if _trainer_extract_id == extract_id:
		status = "当前形态"
	elif not _reserve_units.has(reserve_name):
		status = "%s 不在后备" % reserve_name
	elif _sync_points < EXTRACT_COST:
		status = "同步率不足"
	return "%s：消耗 %d，同步率当前 %d/%d。%s\n状态：%s" % [
		extract_def["name"],
		EXTRACT_COST,
		_sync_points,
		_max_sync_points,
		extract_def["effect"],
		status
	]

func _get_card_short_name(card_id: String) -> String:
	match card_id:
		"haste":
			return "高速"
		"shield":
			return "护盾"
		"power":
			return "火力"
		"capture":
			return "封印"
		_:
			return str(card_id)

func _get_extract_short_name(extract_id: String) -> String:
	match extract_id:
		"grass":
			return "提藤"
		"water":
			return "提水"
		"spark":
			return "提电"
		_:
			return str(extract_id)

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

func _preview_unit_ranges(unit: Unit) -> void:
	var move_cells := grid_manager.get_move_range(unit.grid_pos, unit.get_current_move_range())
	var attack_cells := _get_attack_preview_cells(unit, move_cells)
	_highlight_ranges(move_cells, attack_cells)
	_show_tip("%s：蓝色=移动范围，红色=移动后最远攻击范围。" % unit.data.unit_name)

func _highlight_move_with_attack_preview(unit: Unit, move_cells: Array[Vector2i]) -> void:
	var attack_cells := _get_attack_preview_cells(unit, move_cells)
	_highlight_ranges(move_cells, attack_cells)

func _highlight_ranges(move_cells: Array[Vector2i], attack_cells: Array[Vector2i]) -> void:
	grid_manager.highlight_cells(attack_cells, GridManager.COLOR_ATTACK)
	grid_manager.highlight_cells(move_cells, GridManager.COLOR_MOVE, false)

func _get_attack_preview_cells(unit: Unit, move_cells: Array[Vector2i]) -> Array[Vector2i]:
	var max_range := _get_max_skill_range(unit)
	var result: Array[Vector2i] = []
	if max_range <= 0:
		return result
	var origins: Array[Vector2i] = [unit.grid_pos]
	for cell in move_cells:
		origins.append(cell)
	var seen := {}
	for origin in origins:
		for attack_cell in grid_manager.get_attack_range(origin, max_range):
			if not seen.has(attack_cell):
				seen[attack_cell] = true
				result.append(attack_cell)
	return result

func _get_max_skill_range(unit: Unit) -> int:
	var max_range := 0
	for skill_resource in unit.data.skills:
		var skill: SkillData = skill_resource
		if skill.effect_type == SkillData.EffectType.HEAL:
			continue
		max_range = max(max_range, skill.atk_range)
	return max_range

func _build_skill_preview(attacker: Unit, skill: SkillData, target_pos: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in _get_skill_area_cells(skill, target_pos):
		var target := grid_manager.get_unit_at(cell)
		if target == null or not target.is_alive():
			continue
		if skill.effect_type == SkillData.EffectType.HEAL:
			if not target.is_ally():
				continue
			var raw_heal := _get_raw_skill_heal(attacker, skill)
			var heal_amount: int = max(min(raw_heal, target.data.max_hp - target.current_hp), 0)
			result.append({
				"target": target,
				"heal_amount": heal_amount
			})
			continue
		if not target.is_enemy():
			continue
		var raw_damage := _get_raw_skill_damage(attacker, skill)
		var hp_damage := _get_expected_hp_damage(target, raw_damage, skill.element_type)
		var stability_damage := 0
		if target.data.max_stability > 0 and not target.stability_depleted:
			if target.current_hp - hp_damage > 0:
				stability_damage = _get_expected_stability_damage(skill, target)
		result.append({
			"target": target,
			"raw_damage": raw_damage,
			"hp_damage": hp_damage,
			"stability_damage": stability_damage
		})
	return result

func _get_skill_area_cells(skill: SkillData, target_pos: Vector2i) -> Array[Vector2i]:
	if skill.area_radius <= 0:
		return [target_pos]
	return _cells_in_range(target_pos, skill.area_radius)

func _get_raw_skill_damage(attacker: Unit, skill: SkillData) -> int:
	var raw_damage := skill.damage + attacker.data.attack
	if attacker.power_boost_next_attack:
		raw_damage = int(raw_damage * 1.5)
	return raw_damage

func _get_raw_skill_heal(attacker: Unit, skill: SkillData) -> int:
	return max(skill.damage + attacker.data.attack, 1)

func _get_expected_hp_damage(target: Unit, raw_damage: int, attack_type: int) -> int:
	var damage_after_defense: int = max(raw_damage - target.data.defense, 1)
	damage_after_defense = TypeChartUtil.apply_damage_multiplier(damage_after_defense, attack_type, target.data.get_element_types())
	return max(damage_after_defense - target.shield, 0)

func _get_expected_stability_damage(skill: SkillData, target: Unit) -> int:
	var stability_damage := skill.stability_damage
	var multiplier: float = TypeChartUtil.get_damage_multiplier(skill.element_type, target.data.get_element_types())
	if multiplier > 1.0:
		stability_damage *= int(multiplier)
	if skill.is_control:
		stability_damage += 8
	return stability_damage

func _show_preview_area(skill: SkillData, target_pos: Vector2i) -> void:
	var range_color := GridManager.COLOR_MOVE if skill.effect_type == SkillData.EffectType.HEAL else GridManager.COLOR_ATTACK
	grid_manager.highlight_cells(_attack_cells, range_color)
	grid_manager.highlight_cells(_get_skill_area_cells(skill, target_pos), GridManager.COLOR_CURSOR, false)

func _show_preview_panel(attacker: Unit, skill: SkillData, entries: Array[Dictionary]) -> void:
	var total_damage := 0
	var lines: Array[String] = []
	lines.append("%s -> %s" % [attacker.data.unit_name, skill.skill_name])
	if skill.area_radius > 0:
		lines.append("范围命中 %d 个目标" % entries.size())
	if skill.effect_type == SkillData.EffectType.HEAL:
		var total_heal := 0
		for entry in entries:
			var heal_target: Unit = entry["target"]
			var heal_amount: int = entry["heal_amount"]
			total_heal += heal_amount
			lines.append("%s HP %d>%d  回复%d" % [
				heal_target.data.unit_name,
				heal_target.current_hp,
				min(heal_target.current_hp + heal_amount, heal_target.data.max_hp),
				heal_amount
			])
		lines.append("总回复 %d" % total_heal)
		_preview_label.text = _join_strings(lines, "\n")
		_preview_panel.visible = true
		return
	for entry in entries:
		var target: Unit = entry["target"]
		var hp_damage: int = entry["hp_damage"]
		var stability_damage: int = entry["stability_damage"]
		total_damage += hp_damage
		var hp_after: int = max(target.current_hp - hp_damage, 0)
		var line := "%s HP %d>%d  伤%d" % [
			target.data.unit_name,
			target.current_hp,
			hp_after,
			hp_damage
		]
		if stability_damage > 0:
			line += " 稳-%d" % min(stability_damage, target.current_stability)
		var relation := _get_element_relation_text(skill.element_type, target.data.get_element_types())
		if relation != "":
			line += " " + relation
		if hp_damage == 0 and target.shield > 0:
			line += " 护盾吸收"
		lines.append(line)
	lines.append("总伤害 %d" % total_damage)
	if attacker.power_boost_next_attack:
		lines.append("火力插件已计入")
	_preview_label.text = _join_strings(lines, "\n")
	_preview_panel.visible = true

func _show_preview_markers(entries: Array[Dictionary]) -> void:
	_clear_preview_markers()
	for entry in entries:
		var target: Unit = entry["target"]
		var marker := Label.new()
		var marker_parts: Array[String] = []
		if entry.has("heal_amount"):
			marker_parts.append("+" + str(entry["heal_amount"]))
			marker.modulate = Color(0.38, 0.9, 0.58, 1.0)
		else:
			marker_parts.append("-" + str(entry["hp_damage"]))
			marker.modulate = Color(1.0, 0.82, 0.32, 1.0)
		if entry.has("stability_damage") and entry["stability_damage"] > 0:
			marker_parts.append("稳-" + str(min(int(entry["stability_damage"]), target.current_stability)))
		marker.text = _join_strings(marker_parts, "\n")
		marker.position = target.position + Vector2(-18, -42)
		marker.size = Vector2(48, 24)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.add_theme_font_size_override("font_size", 9)
		add_child(marker)
		_skill_preview_markers.append(marker)

func _clear_skill_preview() -> void:
	if is_instance_valid(_preview_panel):
		_preview_panel.visible = false
	_clear_preview_markers()

func _clear_preview_markers() -> void:
	for marker in _skill_preview_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_skill_preview_markers.clear()

func _get_element_relation_text(attack_type: int, target_types: Array[int]) -> String:
	return TypeChartUtil.get_multiplier_text(TypeChartUtil.get_damage_multiplier(attack_type, target_types))

func _update_capture_marks() -> void:
	for unit in _all_units:
		if is_instance_valid(unit):
			unit.set_capture_ready(unit.is_capturable())

func _remove_unit(unit: Unit, check_over: bool = true) -> void:
	if not is_instance_valid(unit):
		return
	if not unit.pending_charge_cells.is_empty():
		grid_manager.clear_warning_cells()
	grid_manager.remove_unit(unit.grid_pos)
	ctb_system.remove_unit(unit)
	ctb_bar.remove_unit(unit)
	_all_units.erase(unit)
	unit.queue_free()
	_update_enemy_threat_overlay()
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
