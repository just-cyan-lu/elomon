class_name SkillData
extends Resource

const SkillEffectDataUtil = preload("res://skills/SkillEffectData.gd")
const StatusTypeUtil = preload("res://core/StatusTypes.gd")

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
@export var effects: Array[Resource] = [] # SkillEffectData 列表；附加效果统一从这里结算
@export var move_penalty: int = 0    # 旧兼容字段；新技能优先写入 effects
@export var target_ap_delay: float = 0.0 # 旧兼容字段；新技能优先写入 effects

func get_effects() -> Array:
	var result: Array = []
	for effect_resource in effects:
		if effect_resource != null and effect_resource.has_method("get_summary"):
			result.append(effect_resource)
	if result.is_empty():
		result.append_array(_build_legacy_effects())
	return result

func _build_legacy_effects() -> Array:
	var legacy: Array = []
	if move_penalty > 0:
		legacy.append(SkillEffectDataUtil.make_add_status(
			StatusTypeUtil.StatusId.MOVE_PENALTY,
			-float(move_penalty),
			StatusTypeUtil.DurationType.NEXT_ACTION
		))
	if target_ap_delay > 0.0:
		legacy.append(SkillEffectDataUtil.make_ap_delta(-target_ap_delay))
	return legacy
