class_name SkillData
extends Resource

enum EffectType {
	DAMAGE,
	HEAL
}

@export var skill_name: String = "技能"
@export var damage: int = 30       # 基础伤害（不含攻击力加成）
@export var atk_range: int = 1         # 攻击射程，1=只打相邻格
@export var ap_cost: float = 100.0  # 行动 AP 消耗；可扣成负数，影响下次行动时间
@export var element_type: Enums.ElementType = Enums.ElementType.NONE
@export var stability_damage: int = 10  # 对稳定度的削减，捕捉系统使用
@export var is_control: bool = false
@export var area_radius: int = 0     # 0=单体；>0 时命中目标格周围菱形范围
@export var effect_type: EffectType = EffectType.DAMAGE
