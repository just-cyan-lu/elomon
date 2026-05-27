class_name StatusTypes
extends RefCounted

enum StatusId {
	SHIELD,
	POWER_BOOST,
	WEAK_MARK,
	CALIBRATED_ATTACK,
	BONUS_MOVE,
	MOVE_PENALTY,
	CHARGE_WARNING,
	POISON,
	BURN,
	ATTACK_MOD,
	DEFENSE_MOD,
	AP_REGEN_MOD
}

enum DurationType {
	PERMANENT,
	NEXT_ACTION,
	NEXT_ATTACK,
	NEXT_MOVE,
	NEXT_DAMAGE_TAKEN,
	UNTIL_SOURCE_NEXT_TURN
}

enum Polarity {
	BUFF,
	DEBUFF,
	NEUTRAL
}

const DEFS := {
	StatusId.SHIELD: {
		"name": "护盾",
		"short": "盾",
		"duration_type": DurationType.PERMANENT,
		"polarity": Polarity.BUFF,
		"description": "抵消之后受到的伤害，护盾值耗尽后消失。"
	},
	StatusId.POWER_BOOST: {
		"name": "火力插件",
		"short": "强",
		"duration_type": DurationType.NEXT_ATTACK,
		"polarity": Polarity.BUFF,
		"description": "下一次攻击伤害提高 50%，攻击后消耗。"
	},
	StatusId.WEAK_MARK: {
		"name": "弱点标记",
		"short": "弱",
		"duration_type": DurationType.NEXT_DAMAGE_TAKEN,
		"polarity": Polarity.DEBUFF,
		"description": "下次受到伤害提高 50%，受击后消耗。"
	},
	StatusId.CALIBRATED_ATTACK: {
		"name": "属性校准",
		"short": "校",
		"duration_type": DurationType.NEXT_ATTACK,
		"polarity": Polarity.BUFF,
		"description": "下一次攻击使用训练师当前提取属性结算克制，攻击后消耗。"
	},
	StatusId.BONUS_MOVE: {
		"name": "高速组件",
		"short": "移",
		"duration_type": DurationType.NEXT_MOVE,
		"polarity": Polarity.BUFF,
		"description": "下一次移动距离增加，移动后消耗。"
	},
	StatusId.MOVE_PENALTY: {
		"name": "移动压制",
		"short": "缚",
		"duration_type": DurationType.NEXT_ACTION,
		"polarity": Polarity.DEBUFF,
		"description": "下次行动时移动距离减少，行动结束后消失。"
	},
	StatusId.CHARGE_WARNING: {
		"name": "蓄力预警",
		"short": "蓄",
		"duration_type": DurationType.UNTIL_SOURCE_NEXT_TURN,
		"polarity": Polarity.NEUTRAL,
		"description": "释放者下次行动时结算预警范围。"
	},
	StatusId.POISON: {
		"name": "中毒",
		"short": "毒",
		"duration_type": DurationType.NEXT_ACTION,
		"polarity": Polarity.DEBUFF,
		"description": "行动后受到持续伤害。"
	},
	StatusId.BURN: {
		"name": "灼烧",
		"short": "灼",
		"duration_type": DurationType.NEXT_ACTION,
		"polarity": Polarity.DEBUFF,
		"description": "行动后受到持续伤害，后续可扩展为降低攻击。"
	},
	StatusId.ATTACK_MOD: {
		"name": "攻击变化",
		"short": "攻",
		"duration_type": DurationType.NEXT_ATTACK,
		"polarity": Polarity.NEUTRAL,
		"description": "临时改变攻击数值或造成伤害。"
	},
	StatusId.DEFENSE_MOD: {
		"name": "防御变化",
		"short": "防",
		"duration_type": DurationType.NEXT_DAMAGE_TAKEN,
		"polarity": Polarity.NEUTRAL,
		"description": "临时改变防御数值或承受伤害。"
	},
	StatusId.AP_REGEN_MOD: {
		"name": "AP回复变化",
		"short": "速",
		"duration_type": DurationType.NEXT_ACTION,
		"polarity": Polarity.NEUTRAL,
		"description": "临时改变行动条回复速度。"
	}
}

static func get_def(status_id: int) -> Dictionary:
	return DEFS.get(status_id, {})

static func get_name(status_id: int) -> String:
	return str(get_def(status_id).get("name", "状态"))

static func get_short(status_id: int) -> String:
	return str(get_def(status_id).get("short", "?"))

static func get_duration_type(status_id: int) -> int:
	return int(get_def(status_id).get("duration_type", DurationType.PERMANENT))

static func get_duration_text(duration_type: int) -> String:
	match duration_type:
		DurationType.PERMANENT:
			return "持续到被消耗或移除"
		DurationType.NEXT_ACTION:
			return "下次行动有效"
		DurationType.NEXT_ATTACK:
			return "下次攻击有效"
		DurationType.NEXT_MOVE:
			return "下次移动有效"
		DurationType.NEXT_DAMAGE_TAKEN:
			return "下次受伤有效"
		DurationType.UNTIL_SOURCE_NEXT_TURN:
			return "释放者下次行动前有效"
		_:
			return "持续时间未知"

static func get_description(status_id: int) -> String:
	return str(get_def(status_id).get("description", ""))

static func get_polarity(status_id: int) -> int:
	return int(get_def(status_id).get("polarity", Polarity.NEUTRAL))

static func get_color(status_id: int) -> Color:
	match get_polarity(status_id):
		Polarity.BUFF:
			return Color(0.28, 0.54, 0.86, 0.92)
		Polarity.DEBUFF:
			return Color(0.80, 0.28, 0.28, 0.92)
		_:
			return Color(0.78, 0.60, 0.24, 0.92)

static func make_entry(status_id: int, badge: String = "", details: String = "") -> Dictionary:
	var duration_type := get_duration_type(status_id)
	if badge == "":
		badge = get_short(status_id)
	return {
		"id": status_id,
		"name": get_name(status_id),
		"badge": badge,
		"duration_type": duration_type,
		"duration_text": get_duration_text(duration_type),
		"description": get_description(status_id),
		"details": details,
		"color": get_color(status_id)
	}

static func format_tooltip(entry: Dictionary) -> String:
	var parts: Array[String] = [
		str(entry.get("name", "状态")),
		str(entry.get("duration_text", ""))
	]
	var details := str(entry.get("details", ""))
	if details != "":
		parts.append(details)
	var description := str(entry.get("description", ""))
	if description != "":
		parts.append(description)
	return "\n".join(parts)
