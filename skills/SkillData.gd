class_name SkillData
extends Resource

enum EffectType {
	DAMAGE,
	HEAL
}

@export var skill_name: String = "技能"
@export var role_label: String = ""  # UI 用的短定位，例如“主攻”“快控”“范围重招”
@export var effect_note: String = "" # UI 用的额外效果说明，避免把技能说明写死在 Battle.gd
@export var damage: int = 30       # 基础伤害（不含攻击力加成）
@export var atk_range: int = 1         # 攻击射程，1=只打相邻格
@export var ap_cost: float = 100.0  # 内部行动条扣除值；玩家侧只展示非标准的提前/推后百分比
@export var element_type: Enums.ElementType = Enums.ElementType.NONE
@export var stability_damage: int = 10  # 预留字段；当前 MVP 不展示也不参与结算
@export var is_control: bool = false
@export var area_radius: int = 0     # 0=单体；>0 时命中目标格周围菱形范围
@export var effect_type: EffectType = EffectType.DAMAGE
@export var move_penalty: int = 0    # 命中后使目标下次行动移动距离减少，0=无
