extends Control

signal move_pressed
signal skill_pressed
signal skill2_pressed
signal wait_pressed
signal card_pressed(card_id: String)
signal summon_pressed
signal recall_pressed

func _ready() -> void:
	$PanelContainer/VBoxContainer.add_theme_constant_override("separation", 1)
	$PanelContainer/VBoxContainer/BtnMove.pressed.connect(
		func(): emit_signal("move_pressed"))
	$PanelContainer/VBoxContainer/BtnSkill.pressed.connect(
		func(): emit_signal("skill_pressed"))
	$PanelContainer/VBoxContainer/BtnWait.pressed.connect(
		func(): emit_signal("wait_pressed"))
	_style_button($PanelContainer/VBoxContainer/BtnMove)
	_style_button($PanelContainer/VBoxContainer/BtnSkill)
	_style_button($PanelContainer/VBoxContainer/BtnWait)
	_add_button("技能2", func(): emit_signal("skill2_pressed"))
	_add_button("召唤", func(): emit_signal("summon_pressed"))
	_add_button("回收", func(): emit_signal("recall_pressed"))
	_add_button("卡:高速", func(): emit_signal("card_pressed", "haste"))
	_add_button("卡:护盾", func(): emit_signal("card_pressed", "shield"))
	_add_button("卡:火力", func(): emit_signal("card_pressed", "power"))
	_add_button("卡:草地", func(): emit_signal("card_pressed", "terrain"))
	_add_button("封印", func(): emit_signal("card_pressed", "capture"))
	visible = false   # 默认隐藏

func _add_button(label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	_style_button(button)
	button.pressed.connect(callback)
	$PanelContainer/VBoxContainer.add_child(button)

func _style_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(58, 18)
	button.add_theme_font_size_override("font_size", 7)

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
