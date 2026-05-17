extends Control

signal move_pressed
signal skill_pressed
signal skill2_pressed
signal wait_pressed
signal card_pressed(card_id: String)
signal summon_pressed
signal recall_pressed
signal option_hovered(description: String)

var _btn_move: Button
var _btn_skill1: Button
var _btn_skill2: Button
var _btn_wait: Button
var _btn_summon: Button
var _btn_recall: Button
var _card_buttons := {}
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
	_btn_summon = _add_button("召唤", "summon", func(): emit_signal("summon_pressed"))
	_btn_recall = _add_button("回收", "recall", func(): emit_signal("recall_pressed"))
	_card_buttons["haste"] = _add_button("高速", "haste", func(): emit_signal("card_pressed", "haste"))
	_card_buttons["shield"] = _add_button("护盾", "shield", func(): emit_signal("card_pressed", "shield"))
	_card_buttons["power"] = _add_button("火力", "power", func(): emit_signal("card_pressed", "power"))
	_card_buttons["terrain"] = _add_button("草地", "terrain", func(): emit_signal("card_pressed", "terrain"))
	_card_buttons["capture"] = _add_button("封印", "capture", func(): emit_signal("card_pressed", "capture"))
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
