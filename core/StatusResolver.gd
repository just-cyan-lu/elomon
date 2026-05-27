class_name StatusResolver
extends RefCounted

const StatusInstanceUtil = preload("res://core/StatusInstance.gd")
const StatusTypeUtil = preload("res://core/StatusTypes.gd")

static func preview_status_from_effect(effect: Resource) -> Dictionary:
	if effect == null:
		return {}
	var status_id := int(effect.status_id)
	var value := float(effect.value)
	var stacks: int = max(int(effect.stacks), 1) if effect.get("stacks") != null else 1
	var metadata := {
		"status_id": status_id,
		"status_name": _get_status_name(status_id),
		"status_category": StatusTypeUtil.get_category(status_id),
		"dispellable": StatusTypeUtil.is_dispellable(status_id),
		"duration_type": int(effect.duration_type),
		"duration_text": StatusTypeUtil.get_duration_text(int(effect.duration_type)),
		"trigger_timing": StatusTypeUtil.get_trigger_timing(status_id),
		"stack_mode": int(effect.stack_mode),
		"stacks": stacks,
		"value": value
	}
	if status_id == StatusTypeUtil.StatusId.DEFENSE_MOD:
		metadata["defense_delta"] = int(round(value * float(stacks)))
	return metadata

static func apply_status_from_effect(effect: Resource, source, target) -> Dictionary:
	if effect == null or target == null or not is_instance_valid(target) or not target.is_alive():
		return {}
	var instance: Resource = StatusInstanceUtil.from_effect(effect, source)
	var applied_instance: Resource = target.add_status_instance(instance)
	var metadata: Dictionary = preview_status_from_effect(effect)
	metadata["applied"] = applied_instance != null
	if applied_instance != null:
		metadata["badge"] = applied_instance.get_badge()
		metadata["text"] = applied_instance.get_summary()
		metadata["stacks"] = applied_instance.stacks
		metadata["remaining_triggers"] = applied_instance.remaining_triggers
		metadata["source_name"] = applied_instance.source_name
	return metadata

static func trigger(unit, timing: int, context: Dictionary = {}) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if unit == null or not is_instance_valid(unit):
		return results
	var statuses: Array = unit.status_instances.duplicate()
	for status in statuses:
		if status == null or int(status.trigger_timing) != timing:
			continue
		var result := _apply_status_trigger(status, unit, timing, context)
		if not result.is_empty():
			results.append(result)
			_consume_if_needed(unit, status, timing)
	return results

static func _apply_status_trigger(status: Resource, unit, timing: int, context: Dictionary) -> Dictionary:
	match int(status.status_id):
		StatusTypeUtil.StatusId.DEFENSE_MOD:
			if timing != StatusTypeUtil.TriggerTiming.BEFORE_TAKE_DAMAGE:
				return {}
			var delta := int(round(status.get_total_value()))
			context["defense_delta"] = int(context.get("defense_delta", 0)) + delta
			return {
				"status_id": status.status_id,
				"status_name": _get_status_name(status.status_id),
				"trigger_timing": timing,
				"value": delta,
				"text": status.get_summary(),
				"source_name": status.source_name
			}
		_:
			return {}

static func _consume_if_needed(unit, status: Resource, timing: int) -> void:
	if not _should_consume(status, timing):
		return
	status.consume_trigger()
	if status.is_expired():
		unit.remove_status_instance(status)
	else:
		unit.refresh_status()

static func _should_consume(status: Resource, timing: int) -> bool:
	match int(status.duration_type):
		StatusTypeUtil.DurationType.NEXT_ACTION:
			return timing == StatusTypeUtil.TriggerTiming.ON_ACTION_END
		StatusTypeUtil.DurationType.NEXT_ATTACK:
			return timing == StatusTypeUtil.TriggerTiming.AFTER_DEAL_DAMAGE
		StatusTypeUtil.DurationType.NEXT_MOVE:
			return timing == StatusTypeUtil.TriggerTiming.AFTER_MOVE
		StatusTypeUtil.DurationType.NEXT_DAMAGE_TAKEN:
			return timing == StatusTypeUtil.TriggerTiming.BEFORE_TAKE_DAMAGE \
				or timing == StatusTypeUtil.TriggerTiming.AFTER_TAKE_DAMAGE
		StatusTypeUtil.DurationType.TRIGGER_COUNT:
			return timing == int(status.trigger_timing)
		_:
			return false

static func _get_status_name(status_id: int) -> String:
	return str(StatusTypeUtil.get_def(status_id).get("name", "状态"))
