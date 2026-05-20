class_name TypeChart
extends RefCounted

const ADVANTAGE_MULTIPLIER := 2.0
const RESIST_MULTIPLIER := 0.5

const MATCHUPS := {
	Enums.ElementType.FIRE: {
		Enums.ElementType.GRASS: ADVANTAGE_MULTIPLIER,
		Enums.ElementType.WATER: RESIST_MULTIPLIER,
	},
	Enums.ElementType.WATER: {
		Enums.ElementType.FIRE: ADVANTAGE_MULTIPLIER,
		Enums.ElementType.GRASS: RESIST_MULTIPLIER,
	},
	Enums.ElementType.GRASS: {
		Enums.ElementType.WATER: ADVANTAGE_MULTIPLIER,
		Enums.ElementType.FIRE: RESIST_MULTIPLIER,
	},
}

static func get_damage_multiplier(attack_type: int, target_types: Array[int]) -> float:
	if attack_type == Enums.ElementType.NONE:
		return 1.0
	var multiplier := 1.0
	for target_type in target_types:
		if target_type == Enums.ElementType.NONE:
			continue
		multiplier *= float(MATCHUPS.get(attack_type, {}).get(target_type, 1.0))
	return multiplier

static func apply_damage_multiplier(amount: int, attack_type: int, target_types: Array[int]) -> int:
	var multiplier := get_damage_multiplier(attack_type, target_types)
	return max(int(round(float(amount) * multiplier)), 1)

static func get_multiplier_text(multiplier: float) -> String:
	if is_equal_approx(multiplier, 1.0):
		return ""
	if multiplier > 1.0:
		return "克制x%s" % _format_multiplier(multiplier)
	return "抵抗x%s" % _format_multiplier(multiplier)

static func get_type_name(element_type: int) -> String:
	match element_type:
		Enums.ElementType.FIRE:
			return "火"
		Enums.ElementType.WATER:
			return "水"
		Enums.ElementType.GRASS:
			return "草"
		_:
			return "无"

static func get_type_names(element_types: Array[int]) -> String:
	var names: Array[String] = []
	for element_type in element_types:
		if element_type == Enums.ElementType.NONE:
			continue
		names.append(get_type_name(element_type))
	if names.is_empty():
		return "无"
	return "/".join(names)

static func _format_multiplier(multiplier: float) -> String:
	if is_equal_approx(multiplier, float(int(multiplier))):
		return str(int(multiplier))
	return "%.1f" % multiplier
