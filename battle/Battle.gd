extends Node

signal resource_event_emitted(event: Dictionary)
signal action_preview_updated(preview: Dictionary)

const TypeChartUtil = preload("res://core/TypeChart.gd")
const CARD_RANGE := 3
const SUMMON_COST := 50
const RECALL_COST := 10
const EXTRACT_COST := 100
const BATTLE_LOG_LIMIT := 80
const RESOURCE_EVENT_LIMIT := 120
const NO_SKILL_AP_COST := 50.0
const SYNC_NATURAL_CAP := 100
const STARTING_POKEMON_LIMIT := 2
const POKEMON_IDS := ["fire", "grass", "water", "electric", "ice"]
const CARD_DEFS := {
	"haste": {"name": "高速组件", "cost": 30, "cooldown": 2, "effect": "目标宝可梦下一次移动距离 +2，移动后消耗。"},
	"shield": {"name": "小型护盾", "cost": 20, "cooldown": 2, "effect": "目标友方获得 30 护盾，护盾会抵消之后受到的伤害。"},
	"power": {"name": "火力插件", "cost": 25, "cooldown": 2, "effect": "目标宝可梦下一次攻击伤害提高 50%，攻击后消耗。"},
	"weak_mark": {"name": "弱点标记", "cost": 25, "cooldown": 2, "effect": "标记敌方目标，使其下次受到的伤害提高 50%，受击后消耗。"},
	"swap": {"name": "战术换位", "cost": 20, "cooldown": 2, "effect": "训练师与目标己方宝可梦交换位置。"},
	"calibrate": {"name": "属性校准", "cost": 25, "cooldown": 2, "effect": "目标宝可梦下一次攻击使用训练师当前提取属性结算克制，攻击后消耗。"},
}
const SUMMON_DEFS := {
	"fire": {"name": "召唤火狐兽", "reserve": "火狐兽", "short": "召火", "effect": "火属性输出型后备，擅长压制草/冰属性和打爆发。"},
	"grass": {"name": "召唤藤藤兽", "reserve": "藤藤兽", "short": "召藤", "effect": "草属性控制型后备，擅长牵制水/地属性和限制走位。"},
	"water": {"name": "召唤水跃兽", "reserve": "水跃兽", "short": "召水", "effect": "水属性支援型后备，能治疗友方并压制火/地属性。"},
	"electric": {"name": "召唤电花鼠", "reserve": "电花鼠", "short": "召电", "effect": "雷属性高速后备，擅长处理中远程水/飞属性目标。"},
	"ice": {"name": "召唤冰羽兽", "reserve": "冰羽兽", "short": "召冰", "effect": "冰属性压制型后备，擅长克制草/飞/地属性目标。"},
}
const EXTRACT_DEFS := {
	"fire": {"name": "提取火狐兽", "reserve": "火狐兽", "element_label": "火", "role": "输出", "skill_name": "火花", "skill_index": 0, "effect": "训练师切换为火属性，技能替换为火花；克制草/冰，被水/地属性压制。"},
	"grass": {"name": "提取藤藤兽", "reserve": "藤藤兽", "element_label": "草", "role": "控制", "skill_name": "缠绕", "skill_index": 1, "effect": "训练师切换为草属性，技能替换为缠绕；被火系克制，抵抗水系。"},
	"water": {"name": "提取水跃兽", "reserve": "水跃兽", "element_label": "水", "role": "治疗", "skill_name": "水愈", "skill_index": 1, "effect": "训练师切换为水属性，技能替换为水愈；抵抗火系，被草系克制。"},
	"electric": {"name": "提取电花鼠", "reserve": "电花鼠", "element_label": "雷", "role": "高速", "skill_name": "电弧", "skill_index": 0, "effect": "训练师切换为雷属性，技能替换为电弧；克制水/飞，被地属性压制。"},
	"ice": {"name": "提取冰羽兽", "reserve": "冰羽兽", "element_label": "冰", "role": "压制", "skill_name": "冰针", "skill_index": 0, "effect": "训练师切换为冰属性，技能替换为冰针；克制草/飞/地，被火属性压制。"},
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
var _pokemon_roster: Dictionary = {}
var _reserve_units: Dictionary = {}
var _trainer_extract_id: String = ""

var _sync_points: int = 100
var _selected_card_id: String = ""
var _selected_summon_id: String = ""
var _selected_skill_index: int = 0
var _sync_label: Label
var _sync_feedback_label: Label
var _tip_label: Label
var _prep_panel: PanelContainer
var _prep_message_label: Label
var _prep_start_button: Button
var _prep_extract_select: OptionButton
var _prep_pokemon_buttons := {}
var _prep_extract_ids: Array[String] = []
var _prep_selected_pokemon_ids: Array[String] = ["fire", "grass"]
var _prep_extract_id: String = "water"
var _enemy_threat_button: Button
var _preview_panel: PanelContainer
var _preview_label: Label
var _briefing_panel: PanelContainer
var _result_panel: PanelContainer
var _log_panel: PanelContainer
var _log_label: RichTextLabel
var _card_cooldowns := {}
var _selected_skill_target: Vector2i = Vector2i(-1, -1)
var _skill_preview_entries: Array[Dictionary] = []
var _skill_preview_markers: Array[Label] = []
var _battle_logs: Array[Dictionary] = []
var _pending_turn_logs: Array[Dictionary] = []
var _resource_events: Array[Dictionary] = []
var _current_action_preview := {}
var _log_sequence: int = 0
var _defeated_enemy_count: int = 0
var _enemy_threat_visible: bool = false
var _turn_start_pos: Vector2i = Vector2i(-1, -1)
var _turn_start_snapshot := {}
var _turn_has_support_action: bool = false
var _turn_ap_cost: float = NO_SKILL_AP_COST
var _extract_undo_available: bool = false
var _extract_undo_snapshot := {}
var _last_reversible_extract_log_index: int = -1

# 缓存当前高亮的格子（用于点击判断）
var _move_cells: Array[Vector2i] = []
var _attack_cells: Array[Vector2i] = []
var _card_cells: Array[Vector2i] = []

func _ready() -> void:
	result_label.visible = false
	_build_mvp_ui()
	grid_manager.setup_mvp_terrain()
	_connect_signals()
	_update_sync_ui()
	_build_prep_panel()

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

	_log_panel = PanelContainer.new()
	_log_panel.position = Vector2(430, 220)
	_log_panel.size = Vector2(204, 134)
	$UI.add_child(_log_panel)
	var log_box := VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 2)
	_log_panel.add_child(log_box)
	var log_title := Label.new()
	log_title.text = "行动日志"
	log_title.add_theme_font_size_override("font_size", 8)
	log_box.add_child(log_title)
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = false
	_log_label.scroll_following = true
	_log_label.custom_minimum_size = Vector2(194, 108)
	_log_label.add_theme_font_size_override("normal_font_size", 7)
	_log_label.add_theme_color_override("default_color", Color(0.86, 0.88, 0.9, 1.0))
	log_box.add_child(_log_label)

func _build_prep_panel() -> void:
	_prep_panel = PanelContainer.new()
	_prep_panel.position = Vector2(154, 42)
	_prep_panel.size = Vector2(332, 274)
	$UI.add_child(_prep_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_prep_panel.add_child(box)
	var title := Label.new()
	title.text = "战前准备"
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	var summary := Label.new()
	summary.text = "选择 2 只开局宝可梦，并为训练师选择默认提取形态。"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 8)
	box.add_child(summary)
	var pokemon_label := Label.new()
	pokemon_label.text = "开局上场"
	pokemon_label.add_theme_font_size_override("font_size", 9)
	box.add_child(pokemon_label)
	var pokemon_grid := GridContainer.new()
	pokemon_grid.columns = 2
	pokemon_grid.add_theme_constant_override("h_separation", 5)
	pokemon_grid.add_theme_constant_override("v_separation", 2)
	box.add_child(pokemon_grid)
	for pokemon_id in POKEMON_IDS:
		var current_id := str(pokemon_id)
		var check := CheckBox.new()
		check.text = _get_pokemon_prep_label(current_id)
		check.button_pressed = current_id in _prep_selected_pokemon_ids
		check.add_theme_font_size_override("font_size", 8)
		check.toggled.connect(func(pressed: bool): _on_prep_pokemon_toggled(current_id, pressed))
		pokemon_grid.add_child(check)
		_prep_pokemon_buttons[current_id] = check
	var extract_label := Label.new()
	extract_label.text = "训练师默认提取"
	extract_label.add_theme_font_size_override("font_size", 9)
	box.add_child(extract_label)
	_prep_extract_select = OptionButton.new()
	_prep_extract_select.add_theme_font_size_override("font_size", 8)
	box.add_child(_prep_extract_select)
	_populate_prep_extract_options()
	_prep_message_label = Label.new()
	_prep_message_label.custom_minimum_size = Vector2(300, 40)
	_prep_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prep_message_label.add_theme_font_size_override("font_size", 8)
	box.add_child(_prep_message_label)
	_prep_start_button = Button.new()
	_prep_start_button.text = "开始战斗"
	_prep_start_button.custom_minimum_size = Vector2(110, 22)
	_prep_start_button.add_theme_font_size_override("font_size", 9)
	_prep_start_button.pressed.connect(_start_battle_from_prep)
	box.add_child(_prep_start_button)
	_update_prep_message()

func _populate_prep_extract_options() -> void:
	_prep_extract_ids.clear()
	_prep_extract_select.clear()
	var selected_index := 0
	for pokemon_id in POKEMON_IDS:
		var current_id := str(pokemon_id)
		if not EXTRACT_DEFS.has(current_id):
			continue
		_prep_extract_ids.append(current_id)
		_prep_extract_select.add_item(_get_extract_option_label(current_id))
		if current_id == _prep_extract_id:
			selected_index = _prep_extract_ids.size() - 1
	_prep_extract_select.select(selected_index)
	if selected_index < _prep_extract_ids.size():
		_prep_extract_id = _prep_extract_ids[selected_index]
	_prep_extract_select.item_selected.connect(_on_prep_extract_selected)

func _on_prep_pokemon_toggled(pokemon_id: String, pressed: bool) -> void:
	if pressed:
		if pokemon_id in _prep_selected_pokemon_ids:
			_update_prep_message()
			return
		if _prep_selected_pokemon_ids.size() >= STARTING_POKEMON_LIMIT:
			var button := _prep_pokemon_buttons[pokemon_id] as CheckBox
			button.set_pressed_no_signal(false)
			_show_prep_message("开局最多选择 %d 只宝可梦。" % STARTING_POKEMON_LIMIT)
			return
		_prep_selected_pokemon_ids.append(pokemon_id)
	else:
		_prep_selected_pokemon_ids.erase(pokemon_id)
	_update_prep_message()

func _on_prep_extract_selected(index: int) -> void:
	if index >= 0 and index < _prep_extract_ids.size():
		_prep_extract_id = _prep_extract_ids[index]
	_update_prep_message()

func _update_prep_message() -> void:
	var valid := _is_prep_selection_valid()
	if _prep_start_button != null:
		_prep_start_button.disabled = not valid
	if _prep_selected_pokemon_ids.size() != STARTING_POKEMON_LIMIT:
		_show_prep_message("请选择 %d 只开局宝可梦。当前已选 %d 只。" % [STARTING_POKEMON_LIMIT, _prep_selected_pokemon_ids.size()])
		return
	if _prep_extract_id in _prep_selected_pokemon_ids:
		_show_prep_message("默认提取需要选择未上场的后备宝可梦。")
		return
	var names: Array[String] = []
	for pokemon_id in _prep_selected_pokemon_ids:
		names.append(_get_pokemon_name(pokemon_id))
	_show_prep_message("开局：训练师 + %s。默认提取：%s。" % [
		_join_strings(names, "、"),
		_get_extract_display_name(_prep_extract_id, true)
	])

func _show_prep_message(text: String) -> void:
	if is_instance_valid(_prep_message_label):
		_prep_message_label.text = text

func _is_prep_selection_valid() -> bool:
	return _prep_selected_pokemon_ids.size() == STARTING_POKEMON_LIMIT \
		and not (_prep_extract_id in _prep_selected_pokemon_ids)

func _start_battle_from_prep() -> void:
	if not _is_prep_selection_valid():
		_update_prep_message()
		return
	if is_instance_valid(_prep_panel):
		_prep_panel.queue_free()
	_spawn_units()
	ctb_system.register_units(_all_units)
	_update_sync_ui()
	_add_battle_log(
		"战斗开始。开局上场 %s，训练师默认提取 %s。" % [
			_get_selected_pokemon_names_text(),
			_get_extract_display_name(_prep_extract_id, true)
		],
		{
			"event_type": "battle_start",
			"starting_pokemon_ids": _prep_selected_pokemon_ids.duplicate(),
			"default_extract_id": _prep_extract_id
		}
	)
	_build_battle_briefing_panel()

func _build_battle_briefing_panel() -> void:
	if is_instance_valid(_briefing_panel):
		_briefing_panel.queue_free()
	_briefing_panel = PanelContainer.new()
	_briefing_panel.position = Vector2(126, 46)
	_briefing_panel.size = Vector2(388, 254)
	$UI.add_child(_briefing_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_briefing_panel.add_child(box)
	var title := Label.new()
	title.text = "第一场战斗"
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)
	var objective := Label.new()
	objective.text = "目标：击败全部敌人。"
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_font_size_override("font_size", 9)
	box.add_child(objective)
	var rules := Label.new()
	rules.text = _get_battle_briefing_text()
	rules.custom_minimum_size = Vector2(360, 130)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_font_size_override("font_size", 8)
	box.add_child(rules)
	var start_button := Button.new()
	start_button.text = "开始行动"
	start_button.custom_minimum_size = Vector2(112, 22)
	start_button.add_theme_font_size_override("font_size", 9)
	start_button.pressed.connect(_start_battle_after_briefing)
	box.add_child(start_button)

func _get_battle_briefing_text() -> String:
	var lines: Array[String] = [
		"关键规则",
		"1. 属性克制造成 2 倍伤害；确认攻击前会显示实际伤害。",
		"2. 同步率用于指令、提取、召唤；每个训练师回合最多 1 次。",
		"3. 指令卡可以强化移动/护盾/伤害，也能标记弱点、换位或校准属性。",
		"4. 默认形态：%s；对应后备会被同步占用。" % _get_extract_display_name(_prep_extract_id, true),
		"5. 可随时点“敌方范围”查看敌方全体威胁。"
	]
	return _join_strings(lines, "\n")

func _start_battle_after_briefing() -> void:
	if is_instance_valid(_briefing_panel):
		_briefing_panel.queue_free()
	_briefing_panel = null
	_show_tip("目标：击败全部敌人。用属性克制和同步率指令处理铁甲巨兽。")
	ctb_system.start()

func _get_selected_pokemon_names_text() -> String:
	var names: Array[String] = []
	for pokemon_id in _prep_selected_pokemon_ids:
		names.append(_get_pokemon_name(pokemon_id))
	return _join_strings(names, "、")

func _get_pokemon_name(pokemon_id: String) -> String:
	if SUMMON_DEFS.has(pokemon_id):
		return str(SUMMON_DEFS[pokemon_id]["reserve"])
	return pokemon_id

func _get_extract_summary(extract_id: String, include_skill: bool = true) -> String:
	if not EXTRACT_DEFS.has(extract_id):
		return "基础"
	var extract_def = EXTRACT_DEFS[extract_id]
	var parts: Array[String] = [
		str(extract_def["element_label"]),
		str(extract_def["role"])
	]
	if include_skill:
		parts.append(str(extract_def["skill_name"]))
	return _join_strings(parts, "/")

func _get_extract_display_name(extract_id: String, include_skill: bool = false) -> String:
	if not EXTRACT_DEFS.has(extract_id):
		return "基础"
	var extract_def = EXTRACT_DEFS[extract_id]
	return "%s（%s）" % [
		str(extract_def["reserve"]),
		_get_extract_summary(extract_id, include_skill)
	]

func _get_extract_option_label(extract_id: String) -> String:
	if not EXTRACT_DEFS.has(extract_id):
		return extract_id
	var extract_def = EXTRACT_DEFS[extract_id]
	return "%s / %s" % [
		str(extract_def["reserve"]),
		_get_extract_summary(extract_id, true)
	]

func _get_pokemon_prep_label(pokemon_id: String) -> String:
	if EXTRACT_DEFS.has(pokemon_id):
		return "%s  %s" % [
			_get_pokemon_name(pokemon_id),
			_get_extract_summary(pokemon_id, false)
		]
	return pokemon_id

func _spawn_units() -> void:
	var fire_skill := _make_skill("火花", 26, 2, 100, Enums.ElementType.FIRE, 20)
	var flame_line := _make_skill("火焰喷射", 42, 3, 120, Enums.ElementType.FIRE, 35, false, 1)
	var vine_skill := _make_skill("藤鞭", 24, 3, 100, Enums.ElementType.GRASS, 18, false)
	var snare_skill := _make_skill("缠绕", 14, 3, 100, Enums.ElementType.GRASS, 25, true)
	var water_skill := _make_skill("水泡", 20, 3, 100, Enums.ElementType.WATER, 14)
	var mend_skill := _make_skill("水愈", 22, 3, 100, Enums.ElementType.WATER, 0, false, 0, SkillData.EffectType.HEAL)
	var spark_skill := _make_skill("电弧", 22, 3, 100, Enums.ElementType.ELECTRIC, 16)
	var quick_skill := _make_skill("疾闪", 12, 2, 80, Enums.ElementType.ELECTRIC, 8)
	var ice_skill := _make_skill("冰针", 24, 3, 100, Enums.ElementType.ICE, 18)
	var frost_skill := _make_skill("霜缚", 16, 3, 120, Enums.ElementType.ICE, 24, true)
	var blade_skill := _make_skill("数据短刃", 14, 1, 100, Enums.ElementType.NONE, 8)
	var fire_bite_skill := _make_skill("火牙", 22, 1, 100, Enums.ElementType.FIRE, 10)
	var grass_bite_skill := _make_skill("叶咬", 22, 1, 100, Enums.ElementType.GRASS, 10)
	var water_dart_skill := _make_skill("水针", 18, 3, 100, Enums.ElementType.WATER, 10)
	var wind_skill := _make_skill("风刃", 20, 3, 100, Enums.ElementType.FLYING, 10)
	var ground_skill := _make_skill("地刺", 24, 2, 100, Enums.ElementType.GROUND, 12)
	var boss_skill := _make_skill("重踏", 10, 1, 100, Enums.ElementType.GRASS, 10)
	
	var fire_data := _make_unit_data("火狐兽", Enums.UnitType.PLAYER_POKEMON, 105, 18, 5, 58, 4, Color(0.95, 0.42, 0.18), Enums.ElementType.FIRE, [fire_skill, flame_line])
	var grass_data := _make_unit_data("藤藤兽", Enums.UnitType.PLAYER_POKEMON, 95, 15, 5, 48, 4, Color(0.25, 0.75, 0.36), Enums.ElementType.GRASS, [vine_skill, snare_skill])
	var water_data := _make_unit_data("水跃兽", Enums.UnitType.PLAYER_POKEMON, 88, 13, 4, 52, 4, Color(0.24, 0.58, 0.86), Enums.ElementType.WATER, [water_skill, mend_skill])
	var spark_data := _make_unit_data("电花鼠", Enums.UnitType.PLAYER_POKEMON, 76, 16, 3, 68, 5, Color(0.85, 0.78, 0.34), Enums.ElementType.ELECTRIC, [spark_skill, quick_skill])
	var ice_data := _make_unit_data("冰羽兽", Enums.UnitType.PLAYER_POKEMON, 82, 15, 4, 54, 4, Color(0.58, 0.82, 0.92), Enums.ElementType.ICE, [ice_skill, frost_skill])
	_pokemon_roster.clear()
	_pokemon_roster["fire"] = fire_data
	_pokemon_roster["grass"] = grass_data
	_pokemon_roster["water"] = water_data
	_pokemon_roster["electric"] = spark_data
	_pokemon_roster["ice"] = ice_data
	_reserve_units.clear()
	
	var unit_scene := preload("res://units/Unit.tscn")
	var trainer_data := _make_unit_data("训练师", Enums.UnitType.PLAYER, 90, 10, 4, 44, 4, Color(0.35, 0.85, 0.88), Enums.ElementType.NONE, [blade_skill])
	_spawn_unit(unit_scene, trainer_data, Vector2i(2, 5))
	var start_positions := [Vector2i(3, 5), Vector2i(2, 6)]
	for i in range(_prep_selected_pokemon_ids.size()):
		var pokemon_id := str(_prep_selected_pokemon_ids[i])
		if not _pokemon_roster.has(pokemon_id):
			continue
		var unit_data: UnitData = _pokemon_roster[pokemon_id]
		_spawn_unit(unit_scene, unit_data, start_positions[i])
	for pokemon_id in POKEMON_IDS:
		var current_id := str(pokemon_id)
		if current_id in _prep_selected_pokemon_ids:
			continue
		if _pokemon_roster.has(current_id):
			var reserve_data: UnitData = _pokemon_roster[current_id]
			_reserve_units[reserve_data.unit_name] = reserve_data
	_apply_trainer_extract(_prep_extract_id)
	_spawn_unit(unit_scene, _make_unit_data("火牙小怪", Enums.UnitType.ENEMY, 72, 13, 3, 36, 4, Color(0.92, 0.34, 0.32), Enums.ElementType.FIRE, [fire_bite_skill]), Vector2i(10, 4))
	_spawn_unit(unit_scene, _make_unit_data("叶咬小怪", Enums.UnitType.ENEMY, 72, 13, 3, 34, 4, Color(0.82, 0.36, 0.28), Enums.ElementType.GRASS, [grass_bite_skill]), Vector2i(10, 7))
	_spawn_unit(unit_scene, _make_unit_data("水针小怪", Enums.UnitType.ENEMY, 62, 11, 2, 40, 3, Color(0.34, 0.48, 0.82), Enums.ElementType.WATER, [water_dart_skill]), Vector2i(13, 5))
	_spawn_unit(unit_scene, _make_unit_data("飞羽小怪", Enums.UnitType.ENEMY, 58, 10, 2, 52, 5, Color(0.64, 0.66, 0.86), Enums.ElementType.FLYING, [wind_skill]), Vector2i(12, 2))
	_spawn_unit(unit_scene, _make_unit_data("地壳小怪", Enums.UnitType.ENEMY, 88, 12, 5, 28, 3, Color(0.62, 0.50, 0.34), Enums.ElementType.GROUND, [ground_skill]), Vector2i(12, 9))
	_spawn_unit(unit_scene, _make_unit_data("铁甲巨兽", Enums.UnitType.WILD_POKEMON, 280, 8, 8, 24, 2, Color(0.25, 0.65, 0.25), Enums.ElementType.GRASS, [boss_skill], 0, true, 3, 18, 5, 1), Vector2i(14, 9))

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
	_turn_ap_cost = NO_SKILL_AP_COST
	_save_turn_start_state(_active_unit)
	_turn_has_support_action = false
	_clear_extract_undo()
	_tick_card_cooldowns()
	_gain_sync(_get_natural_sync_gain_amount(), "自然回复", true)
	if not is_instance_valid(_active_unit) or not _active_unit.is_alive():
		if _battle_state != Enums.BattleState.BATTLE_OVER:
			ctb_system.resume()
		return
	
	if unit.is_enemy():
		_battle_state = Enums.BattleState.ENEMY_TURN
		action_menu.hide_menu()
		var enemy_logs: Array[Dictionary] = await UnitAI.run(unit, grid_manager, _all_units)
		for log_record in enemy_logs:
			_add_battle_log_record(log_record)
			_apply_log_ap_cost(log_record)
		_check_battle_over()
		if _battle_state == Enums.BattleState.BATTLE_OVER:
			return
		_end_turn()
	else:
		_battle_state = Enums.BattleState.PLAYER_TURN
		_action_state = Enums.ActionState.IDLE
		if _active_unit.data.unit_type == Enums.UnitType.PLAYER:
			_show_tip("轮到 %s。训练师回合可以提取后备能力、刷指令、召唤或回收。" % _active_unit.data.unit_name)
		elif _trainer_disabled:
			_show_tip("轮到 %s。训练师已倒下，无法再使用卡牌和切换宝可梦。" % _active_unit.data.unit_name)
		else:
			_show_tip("轮到 %s。" % _active_unit.data.unit_name)
		_show_action_menu()

# 回合结束：扣行动力，重置状态，恢复跑条
func _end_turn() -> void:
	if _battle_state == Enums.BattleState.BATTLE_OVER:
		return
	_commit_pending_turn_logs()
	if _active_unit and is_instance_valid(_active_unit):
		var ap_before := _active_unit.current_ap
		_active_unit.consume_ap(_turn_ap_cost)
		_emit_resource_event(
			"spend",
			"ap",
			-_turn_ap_cost,
			ap_before,
			_active_unit.current_ap,
			_get_action_ap_reason(),
			_active_unit,
			null,
			_with_action_timing_metadata({}, _turn_ap_cost)
		)
	_action_state = Enums.ActionState.IDLE
	_selected_card_id = ""
	_selected_summon_id = ""
	_selected_skill_index = 0
	_selected_skill_target = Vector2i(-1, -1)
	_turn_has_support_action = false
	_turn_ap_cost = NO_SKILL_AP_COST
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
	if _active_unit.has_acted:
		_show_tip("使用技能后不能再移动。")
		return
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
	var timing_text := _get_action_timing_text(skill.ap_cost)
	if timing_text != "":
		_show_tip("选择 %s 的目标。首次点击预览，确认后%s。" % [skill.skill_name, timing_text])
	else:
		_show_tip("选择 %s 的目标。首次点击预览，确认后发动。" % skill.skill_name)

func _on_wait_pressed() -> void:
	if _active_unit != null and is_instance_valid(_active_unit):
		_commit_pending_turn_logs()
		var timing_text := _get_action_timing_text(_turn_ap_cost)
		if _has_turn_activity():
			var end_log_text := "%s 结束行动。" % _active_unit.data.unit_name
			if not _active_unit.has_acted and timing_text != "":
				end_log_text = "%s 结束行动，%s。" % [_active_unit.data.unit_name, timing_text]
			_add_battle_log(
				end_log_text,
				_with_action_timing_metadata({
					"event_type": "end_action",
					"actor": _unit_log_data(_active_unit)
				}, _turn_ap_cost),
				[_unit_log_ref(_active_unit)]
			)
		else:
			_add_battle_log(
				"%s 待机，%s。" % [_active_unit.data.unit_name, timing_text],
				_with_action_timing_metadata({
					"event_type": "wait",
					"actor": _unit_log_data(_active_unit)
				}, _turn_ap_cost),
				[_unit_log_ref(_active_unit)]
			)
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
	_selected_summon_id = ""
	_selected_skill_index = 0
	_selected_skill_target = Vector2i(-1, -1)
	_move_cells.clear()
	_attack_cells.clear()
	_card_cells.clear()
	_clear_skill_preview()
	grid_manager.clear_highlights()
	_show_action_menu()
	_show_tip("已取消选择。")

func _on_summon_pressed(summon_id: String) -> void:
	if not _is_trainer_turn():
		_show_tip("只有训练师行动时可以召唤。")
		return
	if not _can_use_sync_action("召唤"):
		return
	if not SUMMON_DEFS.has(summon_id):
		return
	var summon_def = SUMMON_DEFS[summon_id]
	var reserve_name := str(summon_def["reserve"])
	if _is_summon_locked_by_extract(summon_id):
		_show_tip("%s 正在提供训练师当前同步形态，切换到别的提取形态后才能召唤。" % reserve_name)
		return
	if not _reserve_units.has(reserve_name):
		_show_tip("%s 不在后备中，不能召唤。" % reserve_name)
		return
	if _sync_points < SUMMON_COST:
		_show_tip("同步率不足，召唤需要 %d。" % SUMMON_COST)
		return
	_selected_summon_id = summon_id
	_action_state = Enums.ActionState.SELECTING_SUMMON
	_card_cells = _empty_cells_in_range(_trainer.grid_pos, CARD_RANGE)
	grid_manager.highlight_cells(_card_cells, GridManager.COLOR_MOVE)
	action_menu.hide_menu()
	_show_tip("选择训练师附近的空格召唤 %s。" % reserve_name)

func _on_recall_pressed() -> void:
	if not _is_trainer_turn():
		_show_tip("只有训练师行动时可以回收。")
		return
	if not _can_use_sync_action("回收"):
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
	if not _can_use_sync_action("指令"):
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
	if not _can_use_sync_action("提取"):
		return
	if not EXTRACT_DEFS.has(extract_id):
		return
	if _trainer_extract_id == extract_id:
		_show_tip("训练师已经处于%s状态。" % EXTRACT_DEFS[extract_id]["reserve"])
		return
	var extract_def = EXTRACT_DEFS[extract_id]
	var reserve_name := str(extract_def["reserve"])
	var extract_display := _get_extract_display_name(extract_id, true)
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
		_save_extract_undo_state()
	else:
		_clear_extract_undo(true)
	_spend_sync(EXTRACT_COST, "提取 %s" % reserve_name, _trainer, null, {
		"event_type": "extract",
		"extract_id": extract_id,
		"reserve_name": reserve_name
	})
	_turn_has_support_action = true
	_apply_trainer_extract(extract_id)
	_update_sync_ui()
	if can_undo_extract:
		var extract_log_index := _queue_battle_log(
			"训练师提取 %s，消耗同步率 %d。" % [extract_display, EXTRACT_COST],
			{
				"event_type": "extract",
				"actor": _unit_log_data(_trainer),
				"reserve_name": reserve_name,
				"extract_form": _get_extract_summary(extract_id, true),
				"extract_id": extract_id,
				"sync_cost": EXTRACT_COST,
				"unit_id_todo": "TODO: add stable ids for reserve units"
			},
			[_unit_log_ref(_trainer)]
		)
		_last_reversible_extract_log_index = extract_log_index
	else:
		_add_battle_log(
			"训练师提取 %s，消耗同步率 %d。" % [extract_display, EXTRACT_COST],
			{
				"event_type": "extract",
				"actor": _unit_log_data(_trainer),
				"reserve_name": reserve_name,
				"extract_form": _get_extract_summary(extract_id, true),
				"extract_id": extract_id,
				"sync_cost": EXTRACT_COST,
				"unit_id_todo": "TODO: add stable ids for reserve units"
			},
			[_unit_log_ref(_trainer)]
		)
	_show_action_menu()
	_show_tip("训练师提取了 %s：属性和技能已切换，直到下一次提取。" % extract_display)

func _can_use_sync_action(action_name: String) -> bool:
	if _turn_has_support_action:
		_show_tip("本回合已经使用过同步率操作，不能再%s。每个训练师回合只能在指令、提取、召唤或回收中选择 1 次。" % action_name)
		return false
	return true

func _on_cell_clicked(grid_pos: Vector2i) -> void:
	if _battle_state != Enums.BattleState.PLAYER_TURN: return
	
	match _action_state:
		Enums.ActionState.SELECTING_MOVE:
			if grid_pos in _move_cells:
				var can_undo_move := not _turn_has_support_action
				_clear_extract_undo(true)
				var from_pos := _active_unit.grid_pos
				grid_manager.move_unit(_active_unit, _active_unit.grid_pos, grid_pos)
				_active_unit.grid_pos = grid_pos
				_active_unit.has_moved = true
				_active_unit.consume_bonus_move()
				var move_record := _make_battle_log_record(
					"%s 移动 %s -> %s。" % [
						_active_unit.data.unit_name,
						_format_grid_pos(from_pos),
						_format_grid_pos(grid_pos)
					],
					{
						"event_type": "move",
						"actor": _unit_log_data(_active_unit),
						"from_pos": _pos_log_data(from_pos),
						"to_pos": _pos_log_data(grid_pos)
					},
					[_unit_log_ref(_active_unit)]
				)
				if can_undo_move:
					_pending_turn_logs.append(move_record)
				else:
					_add_battle_log_record(move_record)
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
				_summon_reserve(grid_pos)

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
	_current_action_preview = _build_action_preview(_active_unit, skill, entries, target_pos)
	emit_signal("action_preview_updated", _current_action_preview)
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
	_commit_pending_turn_logs()
	_clear_extract_undo(true)
	var skill: SkillData = _active_unit.data.skills[_selected_skill_index]
	_turn_ap_cost = skill.ap_cost
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
	if _is_trainer_turn():
		_update_enemy_threat_overlay()
		_show_action_menu()
		_show_tip("%s 已结算。训练师仍可使用指令、召唤、回收或结束行动。" % skill.skill_name)
	else:
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
	var timing_text := _get_action_timing_text(skill.ap_cost)
	if timing_text != "":
		_show_tip("选择 %s 的目标。首次点击预览，确认后%s。" % [skill.skill_name, timing_text])
	else:
		_show_tip("选择 %s 的目标。首次点击预览，确认后发动。" % skill.skill_name)

func _execute_skill_preview(attacker: Unit, skill: SkillData, target_pos: Vector2i, entries: Array[Dictionary]) -> void:
	if skill.effect_type == SkillData.EffectType.HEAL:
		var total_heal := 0
		for entry in entries:
			var heal_target: Unit = entry["target"]
			if not is_instance_valid(heal_target) or not heal_target.is_alive():
				continue
			var actual_heal := heal_target.heal(entry["heal_amount"])
			total_heal += actual_heal
			var log_parts: Array[String] = [
				"%s 使用 %s -> %s" % [
					attacker.data.unit_name,
					skill.skill_name,
					heal_target.data.unit_name
				],
				"回复 %d" % actual_heal
			]
			var heal_timing_text := _get_action_timing_text(skill.ap_cost)
			if heal_timing_text != "":
				log_parts.append(heal_timing_text)
			_add_battle_log(
				_join_strings(log_parts, "，") + "。",
				_with_action_timing_metadata({
					"event_type": "skill_heal",
					"actor": _unit_log_data(attacker),
					"target": _unit_log_data(heal_target),
					"skill_name": skill.skill_name,
					"element_type": skill.element_type,
					"target_pos": _pos_log_data(heal_target.grid_pos),
					"heal_amount": actual_heal,
					"target_hp_after": heal_target.current_hp
				}, skill.ap_cost),
				[_unit_log_ref(attacker), _unit_log_ref(heal_target)]
			)
		_show_tip("%s 回复 %d 点 HP。" % [skill.skill_name, total_heal])
		return

	var total_damage := 0
	for entry in entries:
		var target: Unit = entry["target"]
		if not is_instance_valid(target) or not target.is_alive():
			continue
		var attack_type: int = int(entry.get("attack_type", _get_skill_attack_type(attacker, skill)))
		var weak_mark_consumed := target.weak_marked
		var calibrated_attack_consumed := attacker.calibrated_attack_type != Enums.ElementType.NONE
		var actual := target.take_damage(entry["raw_damage"], attacker, attack_type)
		total_damage += actual
		var log_parts: Array[String] = [
			"%s 使用 %s -> %s" % [
				attacker.data.unit_name,
				skill.skill_name,
				target.data.unit_name
			]
		]
		var relation := _get_element_relation_text(attack_type, target.data.get_element_types())
		if relation != "":
			log_parts.append(relation)
		if calibrated_attack_consumed:
			log_parts.append("属性校准%s" % TypeChartUtil.get_type_name(attack_type))
		if weak_mark_consumed:
			log_parts.append("弱点+50%")
		log_parts.append("伤害 %d" % actual)
		if target.current_hp <= 0:
			log_parts.append("%s倒下" % target.data.unit_name)
		var damage_timing_text := _get_action_timing_text(skill.ap_cost)
		if damage_timing_text != "":
			log_parts.append(damage_timing_text)
		_add_battle_log(
			_join_strings(log_parts, "，") + "。",
			_with_action_timing_metadata({
				"event_type": "skill_damage",
				"actor": _unit_log_data(attacker),
				"target": _unit_log_data(target),
				"skill_name": skill.skill_name,
				"element_type": attack_type,
				"base_element_type": skill.element_type,
				"target_pos": _pos_log_data(target.grid_pos),
				"raw_damage": entry["raw_damage"],
				"hp_damage": actual,
				"target_hp_after": target.current_hp,
				"type_multiplier": TypeChartUtil.get_damage_multiplier(attack_type, target.data.get_element_types()),
				"type_relation_text": relation,
				"weak_mark_consumed": weak_mark_consumed,
				"calibrated_attack_consumed": calibrated_attack_consumed,
				"calibrated_attack_type": attack_type if calibrated_attack_consumed else Enums.ElementType.NONE,
				"target_defeated": target.current_hp <= 0
			}, skill.ap_cost),
			[_unit_log_ref(attacker), _unit_log_ref(target)]
		)
	if attacker.power_boost_next_attack:
		attacker.set_power_boost(false)
	if attacker.calibrated_attack_type != Enums.ElementType.NONE:
		attacker.consume_calibrated_attack_type()
	if attacker.is_ally() and total_damage > 0:
		if attacker.data.unit_type == Enums.UnitType.PLAYER:
			_gain_sync(8, "训练师攻击")
		else:
			_gain_sync(5, "宝可梦攻击")
	_show_tip("%s 命中 %d 个目标，共造成 %d 伤害。" % [skill.skill_name, entries.size(), total_damage])
	_check_battle_over()

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
				_add_battle_log(
					"%s 使用指令 %s -> %s，消耗同步率 %d，移动+2。" % [
						_trainer.data.unit_name,
						CARD_DEFS["haste"]["name"],
						target.data.unit_name,
						CARD_DEFS["haste"]["cost"]
					],
					_build_card_log_metadata("haste", target, {"bonus_move": 2}),
					[_unit_log_ref(_trainer), _unit_log_ref(target)]
				)
				_finish_card("高速组件让 %s 下一次移动距离 +2。" % target.data.unit_name)
		"shield":
			if target != null and target.is_ally():
				_pay_card("shield")
				target.add_shield(30)
				_add_battle_log(
					"%s 使用指令 %s -> %s，消耗同步率 %d，护盾+30。" % [
						_trainer.data.unit_name,
						CARD_DEFS["shield"]["name"],
						target.data.unit_name,
						CARD_DEFS["shield"]["cost"]
					],
					_build_card_log_metadata("shield", target, {"shield_gain": 30}),
					[_unit_log_ref(_trainer), _unit_log_ref(target)]
				)
				_finish_card("%s 获得护盾。" % target.data.unit_name)
		"power":
			if target != null and target.is_ally() and target.data.unit_type != Enums.UnitType.PLAYER:
				_pay_card("power")
				target.set_power_boost(true)
				_add_battle_log(
					"%s 使用指令 %s -> %s，消耗同步率 %d，下次攻击强化。" % [
						_trainer.data.unit_name,
						CARD_DEFS["power"]["name"],
						target.data.unit_name,
						CARD_DEFS["power"]["cost"]
					],
					_build_card_log_metadata("power", target, {"next_attack_multiplier": 1.5}),
					[_unit_log_ref(_trainer), _unit_log_ref(target)]
				)
				_finish_card("%s 的下一次攻击被强化。" % target.data.unit_name)
		"weak_mark":
			if target != null and target.is_enemy():
				_pay_card("weak_mark")
				target.set_weak_marked(true)
				_add_battle_log(
					"%s 使用指令 %s -> %s，消耗同步率 %d，下次受伤+50%%。" % [
						_trainer.data.unit_name,
						CARD_DEFS["weak_mark"]["name"],
						target.data.unit_name,
						CARD_DEFS["weak_mark"]["cost"]
					],
					_build_card_log_metadata("weak_mark", target, {
						"weak_mark_multiplier": 1.5
					}),
					[_unit_log_ref(_trainer), _unit_log_ref(target)]
				)
				_finish_card("%s 被标记，下次受到伤害提高 50%%。" % target.data.unit_name)
			else:
				_show_tip("弱点标记只能选择敌方目标。")
		"swap":
			if target != null and target.is_ally() and target.data.unit_type != Enums.UnitType.PLAYER:
				var trainer_from := _trainer.grid_pos
				var target_from := target.grid_pos
				_pay_card("swap")
				grid_manager.remove_unit(trainer_from)
				grid_manager.remove_unit(target_from)
				grid_manager.place_unit(_trainer, target_from)
				grid_manager.place_unit(target, trainer_from)
				_trainer.grid_pos = target_from
				target.grid_pos = trainer_from
				_add_battle_log(
					"%s 使用指令 %s，与 %s 换位，消耗同步率 %d。" % [
						_trainer.data.unit_name,
						CARD_DEFS["swap"]["name"],
						target.data.unit_name,
						CARD_DEFS["swap"]["cost"]
					],
					_build_card_log_metadata("swap", target, {
						"trainer_from_pos": _pos_log_data(trainer_from),
						"trainer_to_pos": _pos_log_data(target_from),
						"target_from_pos": _pos_log_data(target_from),
						"target_to_pos": _pos_log_data(trainer_from)
					}),
					[_unit_log_ref(_trainer), _unit_log_ref(target)]
				)
				_update_enemy_threat_overlay()
				_finish_card("%s 与 %s 已换位。" % [_trainer.data.unit_name, target.data.unit_name])
			else:
				_show_tip("战术换位只能选择训练师附近的己方宝可梦。")
		"calibrate":
			if target != null and target.is_ally() and target.data.unit_type != Enums.UnitType.PLAYER:
				var calibration_type := _get_trainer_calibration_type()
				if calibration_type == Enums.ElementType.NONE:
					_show_tip("训练师当前没有提取属性，不能校准。")
					return
				_pay_card("calibrate")
				target.set_calibrated_attack_type(calibration_type)
				_add_battle_log(
					"%s 使用指令 %s -> %s，消耗同步率 %d，下次攻击改为%s属性。" % [
						_trainer.data.unit_name,
						CARD_DEFS["calibrate"]["name"],
						target.data.unit_name,
						CARD_DEFS["calibrate"]["cost"],
						TypeChartUtil.get_type_name(calibration_type)
					],
					_build_card_log_metadata("calibrate", target, {
						"calibrated_attack_type": calibration_type,
						"calibrated_attack_type_name": TypeChartUtil.get_type_name(calibration_type)
					}),
					[_unit_log_ref(_trainer), _unit_log_ref(target)]
				)
				_finish_card("%s 下一次攻击会按%s属性结算。" % [target.data.unit_name, TypeChartUtil.get_type_name(calibration_type)])
			else:
				_show_tip("属性校准只能选择训练师附近的己方宝可梦。")

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
	_spend_sync(RECALL_COST, "回收", _trainer, target, {"event_type": "recall"})
	_turn_has_support_action = true
	_commit_pending_turn_logs()
	_clear_extract_undo(true)
	_reserve_units[target.data.unit_name] = target.data
	var target_name := target.data.unit_name
	var target_log_data := _unit_log_data(target)
	var target_log_ref := _unit_log_ref(target)
	_remove_unit(target, false)
	_add_battle_log(
		"%s 回收 %s，消耗同步率 %d。" % [_trainer.data.unit_name, target_name, RECALL_COST],
		{
			"event_type": "recall",
			"actor": _unit_log_data(_trainer),
			"target": target_log_data,
			"sync_cost": RECALL_COST
		},
		[_unit_log_ref(_trainer), target_log_ref]
	)
	_finish_card("已回收 %s。" % target_name)

func _summon_reserve(grid_pos: Vector2i) -> void:
	if not SUMMON_DEFS.has(_selected_summon_id):
		return
	var reserve_name := str(SUMMON_DEFS[_selected_summon_id]["reserve"])
	if _is_summon_locked_by_extract(_selected_summon_id):
		_show_tip("%s 正在提供训练师当前同步形态，不能召唤。" % reserve_name)
		_selected_summon_id = ""
		_action_state = Enums.ActionState.IDLE
		grid_manager.clear_highlights()
		_show_action_menu()
		return
	if not _reserve_units.has(reserve_name):
		_show_tip("%s 不在后备中，不能召唤。" % reserve_name)
		return
	_spend_sync(SUMMON_COST, "召唤 %s" % reserve_name, _trainer, null, {
		"event_type": "summon",
		"summon_id": _selected_summon_id,
		"reserve_name": reserve_name
	})
	_turn_has_support_action = true
	_commit_pending_turn_logs()
	_clear_extract_undo(true)
	var unit_scene := preload("res://units/Unit.tscn")
	var unit_data: UnitData = _reserve_units[reserve_name]
	var unit := _spawn_unit(unit_scene, unit_data, grid_pos)
	ctb_system.add_unit(unit)
	_reserve_units.erase(reserve_name)
	unit.current_ap = 40
	_add_battle_log(
		"%s 召唤 %s 到 %s，消耗同步率 %d。" % [
			_trainer.data.unit_name,
			reserve_name,
			_format_grid_pos(grid_pos),
			SUMMON_COST
		],
		{
			"event_type": "summon",
			"actor": _unit_log_data(_trainer),
			"summoned_unit": _unit_log_data(unit),
			"summon_id": _selected_summon_id,
			"to_pos": _pos_log_data(grid_pos),
			"sync_cost": SUMMON_COST
		},
		[_unit_log_ref(_trainer), _unit_log_ref(unit)]
	)
	_selected_summon_id = ""
	_action_state = Enums.ActionState.IDLE
	grid_manager.clear_highlights()
	_update_enemy_threat_overlay()
	_update_sync_ui()
	_show_action_menu()
	_show_tip("%s 入场。同步率回复会因为多一只宝可梦而变慢。" % reserve_name)

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

func _get_trainer_calibration_type() -> int:
	if _trainer == null or not is_instance_valid(_trainer):
		return Enums.ElementType.NONE
	var element_types := _trainer.data.get_element_types()
	if element_types.is_empty():
		return Enums.ElementType.NONE
	return int(element_types[0])

func _save_extract_undo_state() -> void:
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
	_remove_reversible_extract_log()
	_clear_extract_undo()
	_cancel_to_action_menu("已取消本次能力提取，同步率已返还。")

func _clear_extract_undo(commit_pending_logs: bool = false) -> void:
	if commit_pending_logs:
		_commit_pending_turn_logs()
	_extract_undo_available = false
	_extract_undo_snapshot.clear()
	_last_reversible_extract_log_index = -1

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
	_commit_pending_turn_logs()
	_spend_sync(int(card_def["cost"]), str(card_def["name"]), _trainer, null, {
		"event_type": "card",
		"card_id": card_id,
		"card_name": str(card_def["name"])
	})
	_card_cooldowns[card_id] = card_def["cooldown"]
	_turn_has_support_action = true
	_clear_extract_undo(true)
	_update_sync_ui()

func _tick_card_cooldowns() -> void:
	for card_id in _card_cooldowns.keys():
		_card_cooldowns[card_id] = max(_card_cooldowns[card_id] - 1, 0)

func _gain_sync(amount: int, reason: String = "", respects_natural_cap: bool = false) -> void:
	var before := _sync_points
	if respects_natural_cap and _sync_points >= SYNC_NATURAL_CAP:
		_sync_points = before
	elif respects_natural_cap:
		_sync_points = min(_sync_points + amount, SYNC_NATURAL_CAP)
	else:
		_sync_points += amount
	var gained := _sync_points - before
	_update_sync_ui()
	if gained > 0:
		var event_metadata := {
			"sync_gain": gained,
			"sync_requested": amount,
			"natural_cap": SYNC_NATURAL_CAP,
			"natural_cap_applied": respects_natural_cap
		}
		if respects_natural_cap and gained < amount:
			event_metadata["capped_by_natural_cap"] = true
		_emit_resource_event(
			"gain",
			"sync",
			gained,
			before,
			_sync_points,
			reason,
			_active_unit,
			null,
			event_metadata
		)
		_show_sync_feedback(gained, reason)

func _spend_sync(amount: int, reason: String, actor: Unit = null, target: Unit = null, metadata: Dictionary = {}) -> int:
	var before := _sync_points
	var spent: int = min(amount, _sync_points)
	_sync_points = max(_sync_points - amount, 0)
	_update_sync_ui()
	if spent > 0:
		var event_metadata := metadata.duplicate(true)
		event_metadata["sync_cost"] = amount
		_emit_resource_event(
			"spend",
			"sync",
			-spent,
			before,
			_sync_points,
			reason,
			actor,
			target,
			event_metadata
		)
		_show_sync_feedback(-spent, reason)
	return spent

func _emit_resource_event(
	event_type: String,
	resource_type: String,
	amount: float,
	before_value: float,
	after_value: float,
	reason: String = "",
	actor: Unit = null,
	target: Unit = null,
	metadata: Dictionary = {}
) -> Dictionary:
	var event := {
		"event_type": event_type,
		"resource_type": resource_type,
		"amount": amount,
		"before": before_value,
		"after": after_value,
		"reason": reason,
		"actor": _unit_log_data(actor),
		"target": _unit_log_data(target),
		"metadata": metadata.duplicate(true)
	}
	_resource_events.append(event)
	while _resource_events.size() > RESOURCE_EVENT_LIMIT:
		_resource_events.pop_front()
	emit_signal("resource_event_emitted", event)
	return event

func _get_action_ap_reason() -> String:
	if _active_unit != null and is_instance_valid(_active_unit) and _active_unit.has_acted:
		return "技能行动"
	return "未使用技能"

func _get_action_timing_percent(ap_cost: float) -> int:
	return int(round(abs(ap_cost - Enums.MAX_AP) / Enums.MAX_AP * 100.0))

func _get_action_timing_direction(ap_cost: float) -> String:
	var percent := _get_action_timing_percent(ap_cost)
	if percent <= 0:
		return "standard"
	if ap_cost < Enums.MAX_AP:
		return "advance"
	return "delay"

func _get_action_timing_text(ap_cost: float) -> String:
	var percent := _get_action_timing_percent(ap_cost)
	if percent <= 0:
		return ""
	if ap_cost < Enums.MAX_AP:
		return "下次行动提前%d%%" % percent
	return "下次行动推后%d%%" % percent

func _with_action_timing_metadata(metadata: Dictionary, ap_cost: float) -> Dictionary:
	var result := metadata.duplicate(true)
	result["action_ap_cost"] = ap_cost
	result["action_timing_direction"] = _get_action_timing_direction(ap_cost)
	result["action_timing_percent"] = _get_action_timing_percent(ap_cost)
	result["action_timing_text"] = _get_action_timing_text(ap_cost)
	return result

func _active_pokemon_count() -> int:
	var count := 0
	for unit in _all_units:
		if unit.is_ally() and unit.data.unit_type == Enums.UnitType.PLAYER_POKEMON:
			count += 1
	return count

func _get_natural_sync_gain_amount() -> int:
	return max(1, 6 - _active_pokemon_count() * 2)

func _apply_log_ap_cost(log_record: Dictionary) -> void:
	var metadata: Dictionary = log_record.get("metadata", {})
	if metadata.has("action_ap_cost"):
		_turn_ap_cost = float(metadata["action_ap_cost"])

func _has_turn_activity() -> bool:
	return _active_unit != null \
		and is_instance_valid(_active_unit) \
		and (_active_unit.has_moved or _active_unit.has_acted or _turn_has_support_action)

func _update_sync_ui() -> void:
	if not is_instance_valid(_sync_label):
		return
	var cooldown_text := []
	for card_id in CARD_DEFS:
		var left: int = _card_cooldowns.get(card_id, 0)
		if left > 0:
			cooldown_text.append("%s:%d" % [CARD_DEFS[card_id]["name"], left])
	var trainer_form := "离线" if _trainer_disabled else _get_trainer_form_summary()
	var natural_gain_text := "自然+%d" % _get_natural_sync_gain_amount()
	if _sync_points >= SYNC_NATURAL_CAP:
		natural_gain_text = "自然暂停"
	_sync_label.text = "同步率 %d  自然上限%d\n形态 %s  宝%d 后备 %s\n获得: %s 训攻+8 宝攻+5\n冷却 %s" % [
		_sync_points,
		SYNC_NATURAL_CAP,
		trainer_form,
		_active_pokemon_count(),
		_get_reserve_summary(),
		natural_gain_text,
		_join_strings(cooldown_text, "、") if cooldown_text.size() > 0 else "无"
	]

func _show_sync_feedback(amount: int, reason: String) -> void:
	if not is_instance_valid(_sync_feedback_label):
		return
	var reason_text := ""
	if reason != "":
		reason_text = " " + reason
	var sign := "+" if amount >= 0 else ""
	_sync_feedback_label.text = "%s%d 同步率%s" % [sign, amount, reason_text]
	if amount >= 0:
		_sync_feedback_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0, 1.0))
	else:
		_sync_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.5, 1.0))
	_sync_feedback_label.modulate.a = 1.0
	_sync_feedback_label.position = Vector2(492, 6)
	_sync_feedback_label.visible = true
	var tween := create_tween()
	tween.tween_property(_sync_feedback_label, "position:y", -8.0, 0.55)
	tween.parallel().tween_property(_sync_feedback_label, "modulate:a", 0.0, 0.55)
	tween.tween_callback(func(): _sync_feedback_label.visible = false)

func _add_battle_log(text: String, metadata: Dictionary = {}, unit_refs: Array[Dictionary] = []) -> int:
	return _add_battle_log_record(_make_battle_log_record(text, metadata, unit_refs))

func _queue_battle_log(text: String, metadata: Dictionary = {}, unit_refs: Array[Dictionary] = []) -> int:
	_pending_turn_logs.append(_make_battle_log_record(text, metadata, unit_refs))
	return _pending_turn_logs.size() - 1

func _make_battle_log_record(text: String, metadata: Dictionary = {}, unit_refs: Array[Dictionary] = []) -> Dictionary:
	return {
		"text": text,
		"metadata": metadata.duplicate(true),
		"unit_refs": unit_refs.duplicate(true)
	}

func _add_battle_log_record(record: Dictionary) -> int:
	_log_sequence += 1
	var stored_record := record.duplicate(true)
	stored_record["seq"] = _log_sequence
	if not stored_record.has("text"):
		stored_record["text"] = ""
	if not stored_record.has("metadata"):
		stored_record["metadata"] = {}
	if not stored_record.has("unit_refs"):
		stored_record["unit_refs"] = []
	if not stored_record.has("bbcode"):
		stored_record["bbcode"] = _render_log_text(str(stored_record["text"]), stored_record["unit_refs"])
	_battle_logs.append(stored_record)
	while _battle_logs.size() > BATTLE_LOG_LIMIT:
		_battle_logs.pop_front()
		if _last_reversible_extract_log_index >= 0:
			_last_reversible_extract_log_index -= 1
	_refresh_battle_log_ui()
	return _battle_logs.size() - 1

func _commit_pending_turn_logs() -> void:
	for record in _pending_turn_logs:
		_add_battle_log_record(record)
	_pending_turn_logs.clear()
	_last_reversible_extract_log_index = -1

func _discard_pending_turn_logs() -> void:
	_pending_turn_logs.clear()
	_last_reversible_extract_log_index = -1

func _remove_reversible_extract_log() -> void:
	if _last_reversible_extract_log_index < 0:
		return
	if _last_reversible_extract_log_index >= _pending_turn_logs.size():
		_last_reversible_extract_log_index = -1
		return
	_pending_turn_logs.remove_at(_last_reversible_extract_log_index)
	_last_reversible_extract_log_index = -1

func _refresh_battle_log_ui() -> void:
	if not is_instance_valid(_log_label):
		return
	var lines: Array[String] = []
	for record in _battle_logs:
		lines.append("[color=#8c95a3]%02d[/color]  %s" % [
			int(record["seq"]),
			str(record["bbcode"])
		])
	_log_label.clear()
	_log_label.append_text(_join_strings(lines, "\n"))

func _render_log_text(text: String, unit_refs: Array) -> String:
	var rendered := _escape_bbcode(text)
	for unit_ref in unit_refs:
		var ref: Dictionary = unit_ref
		if not ref.has("name"):
			continue
		var escaped_name := _escape_bbcode(str(ref["name"]))
		var color := _get_log_side_color(str(ref.get("side_key", "system")))
		rendered = rendered.replace(escaped_name, "[color=%s]%s[/color]" % [color, escaped_name])
	return rendered

func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")

func _unit_log_ref(unit: Unit) -> Dictionary:
	if unit == null or not is_instance_valid(unit):
		return {}
	return {
		"name": unit.data.unit_name,
		"side_key": _get_unit_side_key(unit),
		"side": _get_unit_side_label(unit)
	}

func _unit_log_data(unit: Unit) -> Dictionary:
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

func _pos_log_data(pos: Vector2i) -> Dictionary:
	return {"x": pos.x, "y": pos.y, "text": _format_grid_pos(pos)}

func _build_card_log_metadata(card_id: String, target: Unit, extra: Dictionary = {}) -> Dictionary:
	var metadata := {
		"event_type": "card",
		"actor": _unit_log_data(_trainer),
		"target": _unit_log_data(target),
		"card_id": card_id,
		"card_name": str(CARD_DEFS[card_id]["name"]),
		"sync_cost": int(CARD_DEFS[card_id]["cost"]),
		"cooldown": int(CARD_DEFS[card_id]["cooldown"])
	}
	for key in extra:
		metadata[key] = extra[key]
	return metadata

func _get_unit_side_key(unit: Unit) -> String:
	if unit.is_ally():
		return "ally"
	if unit.data.unit_type == Enums.UnitType.WILD_POKEMON \
	or unit.data.unit_type == Enums.UnitType.NEUTRAL \
	or unit.data.unit_type == Enums.UnitType.NEUTRAL_POKEMON:
		return "neutral"
	if unit.is_enemy():
		return "enemy"
	return "system"

func _get_unit_side_label(unit: Unit) -> String:
	match _get_unit_side_key(unit):
		"ally":
			return "我方"
		"enemy":
			return "敌方"
		"neutral":
			return "中立"
		_:
			return "系统"

func _get_log_side_color(side_key: String) -> String:
	match side_key:
		"ally":
			return "#74b8ff"
		"enemy":
			return "#ff7b73"
		"neutral":
			return "#e4c766"
		_:
			return "#d7dbe2"

func _join_strings(parts: Array, delimiter: String) -> String:
	var text := ""
	for i in parts.size():
		if i > 0:
			text += delimiter
		text += str(parts[i])
	return text

func _format_grid_pos(pos: Vector2i) -> String:
	return "(%d,%d)" % [pos.x, pos.y]

func _is_summon_locked_by_extract(summon_id: String) -> bool:
	if _trainer_extract_id == "" \
	or not SUMMON_DEFS.has(summon_id) \
	or not EXTRACT_DEFS.has(_trainer_extract_id):
		return false
	return str(SUMMON_DEFS[summon_id]["reserve"]) == str(EXTRACT_DEFS[_trainer_extract_id]["reserve"])

func _get_reserve_summary() -> String:
	if _reserve_units.is_empty():
		return "无"
	var names: Array[String] = []
	for reserve_name in _reserve_units.keys():
		var display_name := str(reserve_name)
		if EXTRACT_DEFS.has(_trainer_extract_id) \
		and display_name == str(EXTRACT_DEFS[_trainer_extract_id]["reserve"]):
			display_name += "(同步)"
		names.append(display_name)
	names.sort()
	return _join_strings(names, "、")

func _get_trainer_form_summary() -> String:
	if _trainer_extract_id == "" or not EXTRACT_DEFS.has(_trainer_extract_id):
		return "基础"
	return _get_extract_display_name(_trainer_extract_id, false)

func _show_tip(text: String) -> void:
	if is_instance_valid(_tip_label):
		_tip_label.text = text

func _save_turn_start_state(unit: Unit) -> void:
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
	_discard_pending_turn_logs()
	_cancel_to_action_menu("已撤回移动，回到本回合开始位置。")

func _cancel_to_action_menu(message: String) -> void:
	_action_state = Enums.ActionState.IDLE
	_selected_card_id = ""
	_selected_summon_id = ""
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
	action_menu.set_context(_is_trainer_turn())
	action_menu.set_sync_action_used(_turn_has_support_action)
	action_menu.set_card_labels(_build_card_labels())
	action_menu.set_summon_labels(_build_summon_labels())
	action_menu.set_extract_labels(_build_extract_labels())
	action_menu.set_wait_label("结束" if _has_turn_activity() else "待机")
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

func _build_summon_labels() -> Dictionary:
	var labels := {}
	for summon_id in SUMMON_DEFS:
		var label := str(SUMMON_DEFS[summon_id]["short"])
		var reserve_name := str(SUMMON_DEFS[summon_id]["reserve"])
		if _is_summon_locked_by_extract(summon_id):
			labels[summon_id] = label + "同"
		elif not _reserve_units.has(reserve_name):
			labels[summon_id] = label + "离"
		else:
			labels[summon_id] = "%s%d" % [label, SUMMON_COST]
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
	descriptions["move"] = "移动：最多 %d 格。移动后仍可使用技能；使用技能后不能再移动。" % _active_unit.get_current_move_range()
	if _has_turn_activity():
		descriptions["wait"] = "结束：提交本回合尚未展示的移动/提取日志，并结束当前单位行动。"
		var timing_text := _get_action_timing_text(_turn_ap_cost)
		if timing_text != "":
			descriptions["wait"] += timing_text + "。"
	else:
		descriptions["wait"] = "待机：不移动、不使用技能，直接结束当前单位行动；%s。" % _get_action_timing_text(NO_SKILL_AP_COST)
	if _turn_has_support_action:
		descriptions["group_sync"] = "同步率：本回合已经使用过 1 次同步率操作。若刚提取且尚未行动，可按 Esc 撤销。"
	else:
		descriptions["group_sync"] = "同步率：本回合可在指令、提取、召唤或回收中选择 1 次。移动和技能不占用这次机会。"
	descriptions["group_cards"] = "指令：消耗同步率强化、保护、标记弱点、换位或校准属性。本回合与提取、召唤共享 1 次同步率操作。"
	descriptions["group_summon"] = "召唤：选择一只仍在后备、且没有提供当前同步形态的宝可梦入场。召唤会让对应提取暂时不可用，并占用本回合同步率操作。"
	descriptions["group_extract"] = "提取：切换训练师当前属性和技能，持续到下一次提取；占用本回合同步率操作。未行动前可按 Esc 撤销。"
	for i in range(2):
		var key := "skill%d" % (i + 1)
		if i < _active_unit.data.skills.size():
			var skill: SkillData = _active_unit.data.skills[i]
			descriptions[key] = _describe_skill(skill)
		else:
			descriptions[key] = "这个单位没有技能 %d。" % (i + 1)
	descriptions["recall"] = "回收：消耗 %d 同步率，收回训练师 %d 格内的己方宝可梦，保留 HP 和 AP 状态。" % [RECALL_COST, CARD_RANGE]
	for summon_id in SUMMON_DEFS:
		descriptions["summon_" + summon_id] = _describe_summon(summon_id)
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
	var finish_text := "确认后自动结束回合"
	if _is_trainer_turn():
		finish_text = "确认后仍可继续指挥，需手动结束行动"
	var summary := "%s：射程 %d，%s" % [
		skill.skill_name,
		skill.atk_range,
		target_text
	]
	var timing_text := _get_action_timing_text(skill.ap_cost)
	if timing_text != "":
		summary += "；" + timing_text
	summary += "。"
	parts.append(summary)
	if skill.effect_type == SkillData.EffectType.HEAL:
		parts.append("技能回复 %d；可选择自己或友方，%s。" % [skill.damage, finish_text])
	else:
		parts.append("技能伤害 %d；实际伤害以确认前预览为准，%s。" % [skill.damage, finish_text])
	return _join_strings(parts, "\n")

func _describe_card(card_id: String) -> String:
	var card_def = CARD_DEFS[card_id]
	var left: int = _card_cooldowns.get(card_id, 0)
	var status := "可用"
	if left > 0:
		status = "冷却中，还需 %d 次行动" % left
	elif _sync_points < card_def["cost"]:
		status = "同步率不足"
	elif card_id == "calibrate" and _get_trainer_calibration_type() == Enums.ElementType.NONE:
		status = "训练师没有同步属性"
	return "%s：消耗 %d，同步率当前 %d，自然上限 %d，冷却 %d。%s\n状态：%s" % [
		card_def["name"],
		card_def["cost"],
		_sync_points,
		SYNC_NATURAL_CAP,
		card_def["cooldown"],
		card_def["effect"],
		status
	]

func _describe_summon(summon_id: String) -> String:
	var summon_def = SUMMON_DEFS[summon_id]
	var reserve_name := str(summon_def["reserve"])
	var status := "可用"
	if _is_summon_locked_by_extract(summon_id):
		status = "%s 正在提供当前同步形态" % reserve_name
	elif not _reserve_units.has(reserve_name):
		status = "%s 不在后备" % reserve_name
	elif _sync_points < SUMMON_COST:
		status = "同步率不足"
	return "%s：消耗 %d，同步率当前 %d，自然上限 %d，在训练师 %d 格内召唤。%s\n状态：%s" % [
		summon_def["name"],
		SUMMON_COST,
		_sync_points,
		SYNC_NATURAL_CAP,
		CARD_RANGE,
		summon_def["effect"],
		status
	]

func _describe_extract(extract_id: String) -> String:
	var extract_def = EXTRACT_DEFS[extract_id]
	var reserve_name := str(extract_def["reserve"])
	var form_text := "%s / %s" % [
		reserve_name,
		_get_extract_summary(extract_id, true)
	]
	var status := "可用"
	if _trainer_extract_id == extract_id:
		status = "当前形态"
	elif not _reserve_units.has(reserve_name):
		status = "%s 不在后备" % reserve_name
	elif _sync_points < EXTRACT_COST:
		status = "同步率不足"
	return "%s：消耗 %d，同步率当前 %d，自然上限 %d。\n同步形态：%s。\n%s\n状态：%s" % [
		extract_def["name"],
		EXTRACT_COST,
		_sync_points,
		SYNC_NATURAL_CAP,
		form_text,
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
		"weak_mark":
			return "标记"
		"swap":
			return "换位"
		"calibrate":
			return "校准"
		_:
			return str(card_id)

func _get_extract_short_name(extract_id: String) -> String:
	match extract_id:
		"fire":
			return "提火"
		"grass":
			return "提藤"
		"water":
			return "提水"
		"electric":
			return "提电"
		"ice":
			return "提冰"
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
		var attack_type := _get_skill_attack_type(attacker, skill)
		var hp_damage := _get_expected_hp_damage(target, raw_damage, attack_type)
		result.append({
			"target": target,
			"raw_damage": raw_damage,
			"hp_damage": hp_damage,
			"attack_type": attack_type
		})
	return result

func _get_skill_area_cells(skill: SkillData, target_pos: Vector2i) -> Array[Vector2i]:
	if skill.area_radius <= 0:
		return [target_pos]
	return _cells_in_range(target_pos, skill.area_radius)

func _build_action_preview(attacker: Unit, skill: SkillData, entries: Array[Dictionary], target_pos: Vector2i) -> Dictionary:
	var targets: Array[Dictionary] = []
	for entry in entries:
		var target: Unit = entry["target"]
		var target_preview := {
			"target": _unit_log_data(target),
			"target_pos": _pos_log_data(target.grid_pos)
		}
		if entry.has("heal_amount"):
			target_preview["heal_amount"] = int(entry["heal_amount"])
			target_preview["hp_after"] = min(target.current_hp + int(entry["heal_amount"]), target.data.max_hp)
		else:
			target_preview["hp_damage"] = int(entry["hp_damage"])
			target_preview["hp_after"] = max(target.current_hp - int(entry["hp_damage"]), 0)
			var attack_type: int = int(entry.get("attack_type", skill.element_type))
			target_preview["attack_type"] = attack_type
			target_preview["type_multiplier"] = TypeChartUtil.get_damage_multiplier(attack_type, target.data.get_element_types())
		targets.append(target_preview)
	return {
		"event_type": "skill_action_preview",
		"actor": _unit_log_data(attacker),
		"skill_name": skill.skill_name,
		"target_pos": _pos_log_data(target_pos),
		"resources": {
			"ap": {
				"before": attacker.current_ap,
				"after": attacker.current_ap - skill.ap_cost,
				"cost": skill.ap_cost,
				"timing_direction": _get_action_timing_direction(skill.ap_cost),
				"timing_percent": _get_action_timing_percent(skill.ap_cost),
				"timing_text": _get_action_timing_text(skill.ap_cost)
			},
			"sync": {
				"before": _sync_points,
				"after": _sync_points,
				"delta": 0
			}
		},
		"targets": targets
	}

func _get_raw_skill_damage(attacker: Unit, skill: SkillData) -> int:
	var raw_damage := skill.damage + attacker.data.attack
	if attacker.power_boost_next_attack:
		raw_damage = int(raw_damage * 1.5)
	return raw_damage

func _get_raw_skill_heal(attacker: Unit, skill: SkillData) -> int:
	return max(skill.damage + attacker.data.attack, 1)

func _get_skill_attack_type(attacker: Unit, skill: SkillData) -> int:
	if skill.effect_type == SkillData.EffectType.DAMAGE \
	and attacker != null \
	and is_instance_valid(attacker) \
	and attacker.calibrated_attack_type != Enums.ElementType.NONE:
		return attacker.calibrated_attack_type
	return skill.element_type

func _get_expected_hp_damage(target: Unit, raw_damage: int, attack_type: int) -> int:
	var damage_after_defense: int = max(raw_damage - target.data.defense, 1)
	damage_after_defense = TypeChartUtil.apply_damage_multiplier(damage_after_defense, attack_type, target.data.get_element_types())
	if target.weak_marked:
		damage_after_defense = max(int(round(float(damage_after_defense) * 1.5)), 1)
	return max(damage_after_defense - target.shield, 0)

func _show_preview_area(skill: SkillData, target_pos: Vector2i) -> void:
	var range_color := GridManager.COLOR_MOVE if skill.effect_type == SkillData.EffectType.HEAL else GridManager.COLOR_ATTACK
	grid_manager.highlight_cells(_attack_cells, range_color)
	grid_manager.highlight_cells(_get_skill_area_cells(skill, target_pos), GridManager.COLOR_CURSOR, false)

func _show_preview_panel(attacker: Unit, skill: SkillData, entries: Array[Dictionary]) -> void:
	if is_instance_valid(_log_panel):
		_log_panel.visible = false
	var total_damage := 0
	var lines: Array[String] = []
	lines.append("%s -> %s" % [attacker.data.unit_name, skill.skill_name])
	var timing_text := _get_action_timing_text(skill.ap_cost)
	if timing_text != "":
		lines.append(timing_text)
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
		var attack_type: int = int(entry.get("attack_type", _get_skill_attack_type(attacker, skill)))
		total_damage += hp_damage
		var hp_after: int = max(target.current_hp - hp_damage, 0)
		var modifiers: Array[String] = []
		var relation := _get_element_relation_text(attack_type, target.data.get_element_types())
		if relation != "":
			modifiers.append(relation)
		if attacker.calibrated_attack_type != Enums.ElementType.NONE:
			modifiers.append("校" + TypeChartUtil.get_type_name(attack_type))
		if target.weak_marked:
			modifiers.append("弱点+50%")
		if hp_damage == 0 and target.shield > 0:
			modifiers.append("护盾吸收")
		var modifier_text := ""
		if not modifiers.is_empty():
			modifier_text = _join_strings(modifiers, " ") + " "
		var line := "%s HP %d>%d  %s伤%d" % [
			target.data.unit_name,
			target.current_hp,
			hp_after,
			modifier_text,
			hp_damage
		]
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
	if is_instance_valid(_log_panel):
		_log_panel.visible = true
	_clear_preview_markers()
	_current_action_preview.clear()
	emit_signal("action_preview_updated", _current_action_preview)

func _clear_preview_markers() -> void:
	for marker in _skill_preview_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_skill_preview_markers.clear()

func _get_element_relation_text(attack_type: int, target_types: Array[int]) -> String:
	return TypeChartUtil.get_multiplier_text(TypeChartUtil.get_damage_multiplier(attack_type, target_types))

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
	pass

# ── 胜负判断 ────────────────────────────────────────────────────

func _on_unit_died(unit: Unit) -> void:
	if unit.data.unit_type == Enums.UnitType.PLAYER:
		_trainer_disabled = true
		_trainer = null
		_remove_unit(unit, false)
		_show_tip("训练师倒下：对局继续，但无法再刷指令、召唤或回收。")
		_update_sync_ui()
		return
	if unit.is_enemy():
		_defeated_enemy_count += 1
	_remove_unit(unit, false)

func _check_battle_over() -> void:
	if _battle_state == Enums.BattleState.BATTLE_OVER:
		return
	var has_ally := _all_units.any(func(u): return u.is_ally() and u.is_alive())
	var has_enemy := _all_units.any(func(u): return u.is_enemy() and u.is_alive())
	
	if not has_ally:
		_end_battle(false)
	elif not has_enemy:
		_end_battle(true)

func _end_battle(victory: bool) -> void:
	_battle_state = Enums.BattleState.BATTLE_OVER
	ctb_system.stop()
	action_menu.hide_menu()
	_clear_skill_preview()
	grid_manager.clear_highlights()
	_enemy_threat_visible = false
	_update_enemy_threat_overlay()
	result_label.visible = false
	_show_result_panel(victory)

func _show_result_panel(victory: bool) -> void:
	if is_instance_valid(_result_panel):
		_result_panel.queue_free()
	_result_panel = PanelContainer.new()
	_result_panel.position = Vector2(142, 54)
	_result_panel.size = Vector2(356, 244)
	$UI.add_child(_result_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_result_panel.add_child(box)
	var title := Label.new()
	title.text = "胜利" if victory else "失败"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var summary := Label.new()
	summary.text = _get_battle_result_summary(victory)
	summary.custom_minimum_size = Vector2(328, 154)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 9)
	box.add_child(summary)
	var note := Label.new()
	note.text = "行动日志保留在右下角，可用来回看关键操作。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 8)
	box.add_child(note)

func _get_battle_result_summary(victory: bool) -> String:
	var trainer_text := "倒下" if _trainer_disabled else "存活"
	var goal_text := "目标达成：敌方已清空。"
	if not victory:
		goal_text = "目标失败：己方全体倒下。"
	var lines: Array[String] = [
		goal_text,
		"击败敌人：%d" % _defeated_enemy_count,
		"同步率操作：%d" % _count_sync_action_logs(),
		"训练师：%s" % trainer_text,
		"剩余同步率：%d" % _sync_points
	]
	return _join_strings(lines, "\n")

func _count_sync_action_logs() -> int:
	var count := 0
	var sync_event_types := {
		"card": true,
		"extract": true,
		"summon": true,
		"recall": true
	}
	for record in _battle_logs:
		if not record.has("metadata"):
			continue
		var metadata: Dictionary = record["metadata"]
		var event_type := str(metadata.get("event_type", ""))
		if sync_event_types.has(event_type):
			count += 1
	return count
