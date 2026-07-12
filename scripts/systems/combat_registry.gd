extends Node

var _combat_entities: Dictionary = {}
var _projectiles: Dictionary = {}

func register_combat_entity(entity: Node) -> void:
	if is_instance_valid(entity):
		_combat_entities[entity.get_instance_id()] = weakref(entity)

func unregister_combat_entity(entity: Node) -> void:
	if entity != null:
		_combat_entities.erase(entity.get_instance_id())

func register_projectile(projectile: Node) -> void:
	if is_instance_valid(projectile):
		_projectiles[projectile.get_instance_id()] = weakref(projectile)

func unregister_projectile(projectile: Node) -> void:
	if projectile != null:
		_projectiles.erase(projectile.get_instance_id())

func active_combat_entities() -> Array[Node]:
	return _live_nodes(_combat_entities)

func active_projectiles() -> Array[Node]:
	return _live_nodes(_projectiles)

func resolve_combat_entity(entity_id: StringName) -> Node:
	for candidate in active_combat_entities():
		if "stable_entity_id" in candidate and candidate.stable_entity_id == entity_id:
			return candidate
	return null

func clear_invalid() -> void:
	_live_nodes(_combat_entities)
	_live_nodes(_projectiles)

func counts() -> Vector2i:
	return Vector2i(active_combat_entities().size(), active_projectiles().size())

func _live_nodes(source: Dictionary) -> Array[Node]:
	var result: Array[Node] = []
	var stale: Array = []
	for instance_id in source:
		var reference: WeakRef = source[instance_id]
		var node: Node = reference.get_ref() as Node
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			result.append(node)
		else:
			stale.append(instance_id)
	for instance_id in stale:
		source.erase(instance_id)
	return result
