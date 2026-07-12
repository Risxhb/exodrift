class_name ModuleDefinition
extends Resource

@export var module_id: StringName = &"module"
@export var display_name: String = "Module"
@export_enum("weapon", "defense", "sensor", "support", "hangar") var slot_type: String = "support"
@export var capability_tags: Array[StringName] = []
@export var authored_modifiers: Dictionary = {}

