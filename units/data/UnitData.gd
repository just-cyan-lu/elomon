class_name UnitData
extends Resource

@export var unit_name: String = "Unknown"
@export var role_label: String = ""  # UI 用的短定位，例如“火系爆发”“水系支援”
@export var battle_note: String = "" # 设计说明/悬停说明，不参与数值结算
@export var unit_type: Enums.UnitType = Enums.UnitType.ENEMY
@export var max_hp: int = 100
@export var attack: int = 20        # 攻击力，叠加在技能伤害上
@export var defense: int = 5        # 防御，减少受到的伤害
@export var speed: float = 50.0     # 速度，决定 AP 回复快慢
@export var move_range: int = 5     # 最大移动格数
@export var color: Color = Color.GRAY  # 占位色块颜色，有美术后替换
@export var skills: Array[Resource] = []  # 携带的 SkillData 列表
@export var element_type: Enums.ElementType = Enums.ElementType.NONE
@export var element_types: Array[int] = []  # 支持未来双属性；为空时回退到 element_type
@export var max_stability: int = 0   # 预留字段；当前 MVP 不展示也不参与结算
@export var ai_profile: Enums.AIProfile = Enums.AIProfile.BALANCED
@export var can_charge_attack: bool = false
@export var charge_interval: int = 3
@export var charge_damage: int = 16
@export var charge_range: int = 5
@export var charge_radius: int = 1

func set_element_types(types: Array[int]) -> void:
	element_types = []
	for element_type_value in types:
		if element_type_value == Enums.ElementType.NONE or element_types.has(element_type_value):
			continue
		element_types.append(element_type_value)
	element_type = element_types[0] if not element_types.is_empty() else Enums.ElementType.NONE

func get_element_types() -> Array[int]:
	if not element_types.is_empty():
		return element_types.duplicate()
	if element_type == Enums.ElementType.NONE:
		return []
	return [element_type]
