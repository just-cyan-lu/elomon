class_name SkillEffectData
extends Resource

const StatusTypeUtil = preload("res://core/StatusTypes.gd")

enum EffectType {
	DAMAGE,
	HEAL,
	ADD_STATUS,
	REMOVE_STATUS,
	AP_DELTA,
	MOVE_UNIT,
	SWAP,
	SUMMON
}

enum TargetKind {
	TARGET,
	SELF,
	ALLY,
	AREA
}

enum StackMode {
	REPLACE_STRONGER,
	ADD,
	REFRESH
}

const SCRIPT_PATH := "res://skills/SkillEffectData.gd"

@export var effect_type: EffectType = EffectType.ADD_STATUS
@export var target_kind: TargetKind = TargetKind.TARGET
@export var value: float = 0.0
@export var status_id: int = StatusTypeUtil.StatusId.MOVE_PENALTY
@export var duration_type: int = StatusTypeUtil.DurationType.NEXT_ACTION
@export var stack_mode: StackMode = StackMode.REPLACE_STRONGER
@export var chance: float = 1.0
@export var effect_note: String = ""

static func make_add_status(
	status: int,
	status_value: float,
	duration: int = StatusTypeUtil.DurationType.NEXT_ACTION,
	target: int = TargetKind.TARGET
) -> Resource:
	var effect = load(SCRIPT_PATH).new()
	effect.effect_type = EffectType.ADD_STATUS
	effect.target_kind = target
	effect.status_id = status
	effect.value = status_value
	effect.duration_type = duration
	return effect

static func make_ap_delta(ap_delta: float, target: int = TargetKind.TARGET) -> Resource:
	var effect = load(SCRIPT_PATH).new()
	effect.effect_type = EffectType.AP_DELTA
	effect.target_kind = target
	effect.value = ap_delta
	effect.duration_type = StatusTypeUtil.DurationType.PERMANENT
	return effect

func get_value_int() -> int:
	return int(round(value))

func get_percent_value() -> int:
	return int(round(abs(value) / Enums.MAX_AP * 100.0))

func get_summary() -> String:
	match effect_type:
		EffectType.ADD_STATUS:
			return _get_status_summary()
		EffectType.AP_DELTA:
			return _get_ap_delta_summary()
		_:
			return effect_note

func get_marker_text() -> String:
	match effect_type:
		EffectType.ADD_STATUS:
			if status_id == StatusTypeUtil.StatusId.MOVE_PENALTY:
				return "缚"
			return StatusTypeUtil.get_short(status_id)
		EffectType.AP_DELTA:
			var sign := "+" if value > 0.0 else "-"
			return "行%s%d%%" % [sign, get_percent_value()]
		_:
			return ""

func _get_status_summary() -> String:
	match status_id:
		StatusTypeUtil.StatusId.MOVE_PENALTY:
			return "目标下次行动移动-%d" % abs(get_value_int())
		StatusTypeUtil.StatusId.ATTACK_MOD:
			return "攻击%d" % get_value_int()
		StatusTypeUtil.StatusId.DEFENSE_MOD:
			return "防御%d" % get_value_int()
		StatusTypeUtil.StatusId.AP_REGEN_MOD:
			return "AP回复%d%%" % get_value_int()
		StatusTypeUtil.StatusId.POISON:
			return "中毒"
		_:
			return _get_status_name(status_id)

func _get_ap_delta_summary() -> String:
	var percent := get_percent_value()
	if percent <= 0:
		return ""
	if value < 0.0:
		return "目标行动条-%d%%" % percent
	return "目标行动条+%d%%" % percent

func _get_status_name(target_status_id: int) -> String:
	return str(StatusTypeUtil.get_def(target_status_id).get("name", "状态"))
