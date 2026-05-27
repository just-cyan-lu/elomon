class_name StatusInstance
extends Resource

const StatusTypeUtil = preload("res://core/StatusTypes.gd")
const SCRIPT_PATH := "res://core/StatusInstance.gd"

var status_id: int = StatusTypeUtil.StatusId.DEFENSE_MOD
var value: float = 0.0
var stacks: int = 1
var max_stacks: int = 1
var duration_type: int = StatusTypeUtil.DurationType.NEXT_DAMAGE_TAKEN
var trigger_timing: int = StatusTypeUtil.TriggerTiming.BEFORE_TAKE_DAMAGE
var stack_mode: int = StatusTypeUtil.StackMode.REPLACE_STRONGER
var category: int = StatusTypeUtil.Category.STATUS
var dispellable: bool = true
var remaining_triggers: int = 1
var source_instance_id: int = 0
var source_name: String = ""
var tags: Array[String] = []

static func from_effect(effect: Resource, source) -> Resource:
	var instance = load(SCRIPT_PATH).new()
	instance.status_id = int(effect.status_id)
	instance.value = float(effect.value)
	instance.stacks = max(int(effect.get("stacks")), 1)
	instance.max_stacks = max(int(effect.get("max_stacks")), StatusTypeUtil.get_max_stacks(instance.status_id))
	instance.duration_type = int(effect.duration_type)
	instance.trigger_timing = StatusTypeUtil.get_trigger_timing(instance.status_id)
	instance.stack_mode = int(effect.stack_mode)
	instance.category = StatusTypeUtil.get_category(instance.status_id)
	instance.dispellable = StatusTypeUtil.is_dispellable(instance.status_id)
	instance.remaining_triggers = _get_initial_trigger_count(instance.duration_type, effect)
	if source != null and is_instance_valid(source):
		instance.source_instance_id = source.get_instance_id()
		instance.source_name = source.data.unit_name if source.data != null else ""
	return instance

static func from_snapshot(snapshot: Dictionary) -> Resource:
	var instance = load(SCRIPT_PATH).new()
	instance.status_id = int(snapshot.get("status_id", instance.status_id))
	instance.value = float(snapshot.get("value", instance.value))
	instance.stacks = int(snapshot.get("stacks", instance.stacks))
	instance.max_stacks = int(snapshot.get("max_stacks", instance.max_stacks))
	instance.duration_type = int(snapshot.get("duration_type", instance.duration_type))
	instance.trigger_timing = int(snapshot.get("trigger_timing", instance.trigger_timing))
	instance.stack_mode = int(snapshot.get("stack_mode", instance.stack_mode))
	instance.category = int(snapshot.get("category", instance.category))
	instance.dispellable = bool(snapshot.get("dispellable", instance.dispellable))
	instance.remaining_triggers = int(snapshot.get("remaining_triggers", instance.remaining_triggers))
	instance.source_instance_id = int(snapshot.get("source_instance_id", instance.source_instance_id))
	instance.source_name = str(snapshot.get("source_name", instance.source_name))
	var restored_tags: Array[String] = []
	for tag in snapshot.get("tags", []):
		restored_tags.append(str(tag))
	instance.tags = restored_tags
	return instance

static func _get_initial_trigger_count(duration: int, effect: Resource) -> int:
	if duration == StatusTypeUtil.DurationType.TRIGGER_COUNT:
		return max(int(effect.get("trigger_count")), 1)
	return 1

func to_snapshot() -> Dictionary:
	return {
		"status_id": status_id,
		"value": value,
		"stacks": stacks,
		"max_stacks": max_stacks,
		"duration_type": duration_type,
		"trigger_timing": trigger_timing,
		"stack_mode": stack_mode,
		"category": category,
		"dispellable": dispellable,
		"remaining_triggers": remaining_triggers,
		"source_instance_id": source_instance_id,
		"source_name": source_name,
		"tags": tags.duplicate()
	}

func can_merge(other: Resource) -> bool:
	if other == null:
		return false
	return status_id == int(other.status_id)

func merge_from(other: Resource) -> void:
	match stack_mode:
		StatusTypeUtil.StackMode.ADD_STACK:
			stacks = min(stacks + max(int(other.stacks), 1), max(max_stacks, int(other.max_stacks)))
			remaining_triggers = max(remaining_triggers, int(other.remaining_triggers))
		StatusTypeUtil.StackMode.REPLACE_STRONGER:
			if abs(float(other.value) * float(other.stacks)) >= abs(value * float(stacks)):
				_copy_runtime_values(other)
		StatusTypeUtil.StackMode.UNIQUE:
			remaining_triggers = max(remaining_triggers, int(other.remaining_triggers))
		_:
			_copy_runtime_values(other)

func _copy_runtime_values(other: Resource) -> void:
	value = float(other.value)
	stacks = int(other.stacks)
	max_stacks = int(other.max_stacks)
	duration_type = int(other.duration_type)
	trigger_timing = int(other.trigger_timing)
	stack_mode = int(other.stack_mode)
	category = int(other.category)
	dispellable = bool(other.dispellable)
	remaining_triggers = int(other.remaining_triggers)
	source_instance_id = int(other.source_instance_id)
	source_name = str(other.source_name)
	tags = other.tags.duplicate()

func consume_trigger() -> void:
	remaining_triggers -= 1

func is_expired() -> bool:
	return remaining_triggers <= 0

func get_total_value() -> float:
	return value * float(stacks)

func get_badge() -> String:
	match status_id:
		StatusTypeUtil.StatusId.DEFENSE_MOD:
			var sign := "+" if get_total_value() > 0.0 else "-"
			return "防%s%d" % [sign, abs(int(round(get_total_value())))]
		_:
			return str(StatusTypeUtil.get_def(status_id).get("short", "?"))

func get_summary() -> String:
	match status_id:
		StatusTypeUtil.StatusId.DEFENSE_MOD:
			var amount := int(round(get_total_value()))
			if amount < 0:
				return "防御-%d" % abs(amount)
			return "防御+%d" % amount
		_:
			return str(StatusTypeUtil.get_def(status_id).get("name", "状态"))

func get_details() -> String:
	var parts: Array[String] = [get_summary()]
	if stacks > 1:
		parts.append("%d层" % stacks)
	if remaining_triggers > 1:
		parts.append("剩余%d次" % remaining_triggers)
	if source_name != "":
		parts.append("来源：" + source_name)
	return "，".join(parts)

func to_entry() -> Dictionary:
	return StatusTypeUtil.make_entry(status_id, get_badge(), get_details())
