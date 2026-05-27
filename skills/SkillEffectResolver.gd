class_name SkillEffectResolver
extends RefCounted

const SkillEffectDataUtil = preload("res://skills/SkillEffectData.gd")
const StatusResolverUtil = preload("res://core/StatusResolver.gd")
const StatusTypeUtil = preload("res://core/StatusTypes.gd")

static func preview_effect(effect: Resource) -> Dictionary:
	if effect == null:
		return {}
	var metadata := {
		"effect_type": effect.effect_type,
		"target_kind": effect.target_kind,
		"value": effect.value,
		"text": effect.get_summary()
	}
	match effect.effect_type:
		SkillEffectDataUtil.EffectType.ADD_STATUS:
			var status_metadata := StatusResolverUtil.preview_status_from_effect(effect)
			for key in status_metadata:
				metadata[key] = status_metadata[key]
			if effect.status_id == StatusTypeUtil.StatusId.MOVE_PENALTY:
				metadata["move_penalty"] = abs(effect.get_value_int())
		SkillEffectDataUtil.EffectType.AP_DELTA:
			metadata["ap_delta"] = effect.value
			metadata["ap_delta_percent"] = effect.get_percent_value()
	return metadata

static func apply_effect_to_target(effect: Resource, source: Unit, target: Unit) -> Dictionary:
	if effect == null or target == null or not is_instance_valid(target) or not target.is_alive():
		return {}
	var metadata := preview_effect(effect)
	if metadata.is_empty():
		return {}
	metadata["applied"] = false
	match effect.effect_type:
		SkillEffectDataUtil.EffectType.ADD_STATUS:
			var status_metadata := _apply_status_effect(effect, source, target)
			for key in status_metadata:
				metadata[key] = status_metadata[key]
			metadata["applied"] = bool(status_metadata.get("applied", false))
		SkillEffectDataUtil.EffectType.AP_DELTA:
			var before := target.current_ap
			target.consume_ap(-effect.value)
			metadata["applied"] = true
			metadata["ap_before"] = before
			metadata["ap_after"] = target.current_ap
			metadata["source_name"] = source.data.unit_name if source != null and is_instance_valid(source) else ""
	return metadata

static func apply_effects_to_target(effects: Array, source: Unit, target: Unit) -> Array[Dictionary]:
	var applied: Array[Dictionary] = []
	for effect in effects:
		var metadata := apply_effect_to_target(effect, source, target)
		if not metadata.is_empty() and bool(metadata.get("applied", false)):
			applied.append(metadata)
	return applied

static func preview_effects(effects: Array) -> Array[Dictionary]:
	var previews: Array[Dictionary] = []
	for effect in effects:
		var metadata := preview_effect(effect)
		if not metadata.is_empty():
			previews.append(metadata)
	return previews

static func _apply_status_effect(effect: Resource, source: Unit, target: Unit) -> Dictionary:
	match effect.status_id:
		StatusTypeUtil.StatusId.MOVE_PENALTY:
			target.add_move_penalty(abs(effect.get_value_int()))
			return {
				"applied": true,
				"badge": "缚",
				"text": effect.get_summary()
			}
		_:
			return StatusResolverUtil.apply_status_from_effect(effect, source, target)
