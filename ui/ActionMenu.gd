extends Control

signal move_pressed
signal skill_pressed
signal skill2_pressed
signal wait_pressed
signal card_pressed(card_id: String)
signal extract_pressed(extract_id: String)
signal summon_pressed(summon_id: String)
signal recall_pressed
signal option_hovered(description: String)

var _btn_move: Button
var _btn_skill1: Button
var _btn_skill2: Button
var _btn_wait: Button
var _btn_summon: Button
var _btn_recall: Button
var _card_buttons := {}
var _extract_buttons := {}
var _summon_buttons := {}
var _descriptions := {}

func _ready() -> void:
	$PanelContainer/VBoxContainer.add_theme_constant_override("separation", 1)
	_btn_move = $PanelContainer/VBoxContainer/BtnMove
	_btn_skill1 = $PanelContainer/VBoxContainer/BtnSkill
	_btn_wait = $PanelContainer/VBoxContainer/BtnWait
	_btn_move.pressed.connect(
		func(): emit_signal("move_pressed"))
	_btn_skill1.pressed.connect(
		func(): emit_signal("skill_pressed"))
	_btn_wait.pressed.connect(
		func(): emit_signal("wait_pressed"))
	_style_button(_btn_move)
	_style_button(_btn_skill1)
	_style_button(_btn_wait)
	_bind_hover(_btn_move, "move")
	_bind_hover(_btn_skill1, "skill1")
	_bind_hover(_btn_wait, "wait")
	_btn_skill2 = _add_button("技能2", "skill2", func(): emit_signal("skill2_pressed"))
	_btn_summon = _add_button("召藤", "summon_grass", func(): emit_signal("summon_pressed", "grass"))
	_btn_recall = _add_button("回收", "recall", func(): emit_signal("recall_pressed"))
	_summon_buttons["grass"] = _btn_summon
	_summon_buttons["water"] = _add_button("召水", "summon_water", func(): emit_signal("summon_pressed", "water"))
	_summon_buttons["electric"] = _add_button("召电", "summon_electric", func(): emit_signal("summon_pressed", "electric"))
	_summon_buttons["ice"] = _add_button("召冰", "summon_ice", func(): emit_signal("summon_pressed", "ice"))
	_card_buttons["haste"] = _add_button("高速", "haste", func(): emit_signal("card_pressed", "haste"))
	_card_buttons["shield"] = _add_button("护盾", "shield", func(): emit_signal("card_pressed", "shield"))
	_card_buttons["power"] = _add_button("火力", "power", func(): emit_signal("card_pressed", "power"))
	_card_buttons["capture"] = _add_button("封印", "capture", func(): emit_signal("card_pressed", "capture"))
	_extract_buttons["grass"] = _add_button("提藤", "extract_grass", func(): emit_signal("extract_pressed", "grass"))
	_extract_buttons["water"] = _add_button("提水", "extract_water", func(): emit_signal("extract_pressed", "water"))
	_extract_buttons["electric"] = _add_button("提电", "extract_electric", func(): emit_signal("extract_pressed", "electric"))
	_extract_buttons["ice"] = _add_button("提冰", "extract_ice", func(): emit_signal("extract_pressed", "ice"))
	visible = false   # 默认隐藏

func _add_button(label: String, key: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	_style_button(button)
	button.pressed.connect(callback)
	_bind_hover(button, key)
	$PanelContainer/VBoxContainer.add_child(button)
	return button

func _bind_hover(button: Button, key: String) -> void:
	button.mouse_entered.connect(func():
		if _descriptions.has(key):
			emit_signal("option_hovered", _descriptions[key])
	)

func _style_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(72, 18)
	button.add_theme_font_size_override("font_size", 7)

func set_skill_labels(skill_names: Array[String]) -> void:
	_btn_skill1.text = skill_names[0] if skill_names.size() > 0 else "技能1"
	_btn_skill1.disabled = skill_names.is_empty()
	_btn_skill2.text = skill_names[1] if skill_names.size() > 1 else "技能2"
	_btn_skill2.disabled = skill_names.size() <= 1

func set_card_labels(card_labels: Dictionary) -> void:
	for card_id in _card_buttons:
		if card_labels.has(card_id):
			_card_buttons[card_id].text = card_labels[card_id]

func set_summon_labels(summon_labels: Dictionary) -> void:
	for summon_id in _summon_buttons:
		if summon_labels.has(summon_id):
			_summon_buttons[summon_id].text = summon_labels[summon_id]

func set_extract_labels(extract_labels: Dictionary) -> void:
	for extract_id in _extract_buttons:
		if extract_labels.has(extract_id):
			_extract_buttons[extract_id].text = extract_labels[extract_id]

func set_option_descriptions(descriptions: Dictionary) -> void:
	_descriptions = descriptions.duplicate()

# 在指定像素位置显示菜单
func show_at(pixel_pos: Vector2) -> void:
	visible = true
	await get_tree().process_frame
	var panel_size: Vector2 = $PanelContainer.get_combined_minimum_size()
	var viewport_size: Vector2 = get_viewport_rect().size
	var desired := pixel_pos + Vector2(4, -20)
	var max_pos := viewport_size - panel_size - Vector2(4, 4)
	position = Vector2(
		clamp(desired.x, 4.0, max_pos.x),
		clamp(desired.y, 4.0, max_pos.y)
	)

func hide_menu() -> void:
	visible = false
