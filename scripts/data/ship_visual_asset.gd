class_name ShipVisualAsset
extends Resource

## Production contract for an authored ship scene and its runtime material pack.
## Authored assets remain opt-in: CombatShip falls back to its procedural builder
## whenever this resource or the instantiated scene fails validation.

@export_group("Identity")
@export var enabled: bool = false
@export var ship_id: StringName = &"ship"
@export var authored_dimensions_m: Vector3 = Vector3.ONE
@export_file("*.blend", "*.glb", "*.gltf") var source_file: String = ""
@export var model_scene: PackedScene
@export var model_scale: Vector3 = Vector3.ONE
@export var model_rotation_degrees: Vector3 = Vector3.ZERO

@export_group("Material Contract")
@export var replace_imported_materials: bool = false
@export var hull_material: ShipPbrMaterial
@export var accent_material: ShipPbrMaterial
@export var marking_material: ShipPbrMaterial
@export var emission_material: ShipPbrMaterial
@export var interior_material: ShipPbrMaterial

@export_group("Runtime Contract")
@export var required_sockets: Array[StringName] = []
@export_range(1, 500000, 1) var maximum_lod0_triangles: int = 100000
@export_range(1, 16, 1) var maximum_material_slots: int = 4
@export_multiline var authoring_notes: String = ""

const DIMENSION_TOLERANCE_RATIO := 0.03

func manifest_errors(expected_ship_id: StringName = &"", expected_dimensions_m: Vector3 = Vector3.ZERO) -> PackedStringArray:
	var errors := PackedStringArray()
	if ship_id == &"" or ship_id == &"ship":
		errors.append("ship_id must identify a production ship")
	if expected_ship_id != &"" and ship_id != expected_ship_id:
		errors.append("ship_id '%s' does not match expected '%s'" % [ship_id, expected_ship_id])
	if model_scene == null:
		errors.append("model_scene is required")
	if authored_dimensions_m.x <= 0.0 or authored_dimensions_m.y <= 0.0 or authored_dimensions_m.z <= 0.0:
		errors.append("authored_dimensions_m must be positive on every axis")
	if expected_dimensions_m != Vector3.ZERO and authored_dimensions_m.x > 0.0 and authored_dimensions_m.y > 0.0 and authored_dimensions_m.z > 0.0:
		for axis in 3:
			var expected: float = expected_dimensions_m[axis]
			var authored: float = authored_dimensions_m[axis] * absf(model_scale[axis])
			if expected > 0.0 and absf(authored - expected) / expected > DIMENSION_TOLERANCE_RATIO:
				errors.append("authored dimensions %s differ from expected %s by more than %.0f%%" % [authored_dimensions_m, expected_dimensions_m, DIMENSION_TOLERANCE_RATIO * 100.0])
				break
	if model_scale.x == 0.0 or model_scale.y == 0.0 or model_scale.z == 0.0:
		errors.append("model_scale cannot contain zero")
	if replace_imported_materials and hull_material == null:
		errors.append("hull_material is required when imported materials are replaced")
	if replace_imported_materials and hull_material != null:
		for material_error in hull_material.validation_errors():
			errors.append("hull material: %s" % material_error)
	if maximum_lod0_triangles <= 0:
		errors.append("maximum_lod0_triangles must be positive")
	if maximum_material_slots <= 0:
		errors.append("maximum_material_slots must be positive")
	return errors

func instantiate_model() -> Node3D:
	if model_scene == null:
		return null
	var instance := model_scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	var model := instance as Node3D
	model.name = "AuthoredVisual"
	model.scale = model_scale
	model.rotation_degrees = model_rotation_degrees
	return model

func instance_errors(model: Node3D, socket_prefix_requirements: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	if model == null:
		errors.append("model scene did not instantiate as Node3D")
		return errors
	var sockets := collect_sockets(model)
	for required_name in required_sockets:
		var normalized := StringName(String(required_name).to_lower())
		if not sockets.has(normalized):
			errors.append("required socket '%s' is missing" % required_name)
	for prefix_value in socket_prefix_requirements:
		var prefix := String(prefix_value).to_lower()
		var expected_count := int(socket_prefix_requirements[prefix_value])
		var actual_count := 0
		for socket_name in sockets:
			if String(socket_name).begins_with(prefix):
				actual_count += 1
		if actual_count < expected_count:
			errors.append("socket prefix '%s' requires %d node(s), found %d" % [prefix, expected_count, actual_count])
	var metrics := model_metrics(model)
	if int(metrics.get("triangles", 0)) > maximum_lod0_triangles:
		errors.append("LOD0 contains %d triangles; budget is %d" % [metrics.get("triangles", 0), maximum_lod0_triangles])
	if int(metrics.get("material_slots", 0)) > maximum_material_slots:
		errors.append("model uses %d material slots; budget is %d" % [metrics.get("material_slots", 0), maximum_material_slots])
	var bounds_size := model_bounds_size(model)
	if bounds_size != Vector3.ZERO:
		for axis in 3:
			var expected: float = authored_dimensions_m[axis]
			if expected > 0.0 and absf(bounds_size[axis] - expected) / expected > DIMENSION_TOLERANCE_RATIO:
				errors.append("model bounds %s differ from authored_dimensions_m %s by more than %.0f%%" % [bounds_size, authored_dimensions_m, DIMENSION_TOLERANCE_RATIO * 100.0])
				break
	return errors

func collect_sockets(model: Node3D) -> Dictionary:
	var sockets: Dictionary = {}
	if model == null:
		return sockets
	var candidates: Array[Node] = [model]
	candidates.append_array(model.find_children("socket_*", "Node3D", true, false))
	for candidate in candidates:
		if candidate is Node3D and String(candidate.name).to_lower().begins_with("socket_"):
			sockets[StringName(String(candidate.name).to_lower())] = candidate
	return sockets

func apply_material_contract(model: Node3D) -> void:
	if not replace_imported_materials or model == null:
		return
	for candidate in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var imported := mesh_instance.mesh.surface_get_material(surface_index)
			var slot_name := String(imported.resource_name if imported != null else mesh_instance.name).to_lower()
			var replacement := _material_for_slot(slot_name)
			if replacement != null:
				mesh_instance.set_surface_override_material(surface_index, replacement.build_material())

func model_metrics(model: Node3D) -> Dictionary:
	var triangles := 0
	var material_slots := 0
	if model == null:
		return {"triangles": triangles, "material_slots": material_slots}
	for candidate in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		material_slots += mesh.get_surface_count()
		triangles += mesh.get_faces().size() / 3
	return {"triangles": triangles, "material_slots": material_slots}

func model_bounds_size(model: Node3D) -> Vector3:
	if model == null:
		return Vector3.ZERO
	var initialized := false
	var minimum := Vector3.ZERO
	var maximum := Vector3.ZERO
	for candidate in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local_transform := _relative_transform(mesh_instance, model)
		var bounds := mesh_instance.get_aabb()
		for corner_index in 8:
			var corner := bounds.position + Vector3(
				bounds.size.x if corner_index & 1 else 0.0,
				bounds.size.y if corner_index & 2 else 0.0,
				bounds.size.z if corner_index & 4 else 0.0
			)
			var point := local_transform * corner
			if not initialized:
				minimum = point
				maximum = point
				initialized = true
			else:
				minimum = minimum.min(point)
				maximum = maximum.max(point)
	return maximum - minimum if initialized else Vector3.ZERO

func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var chain: Array[Transform3D] = []
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			chain.append((current as Node3D).transform)
		current = current.get_parent()
	var result := Transform3D.IDENTITY
	for index in range(chain.size() - 1, -1, -1):
		result = result * chain[index]
	return result

func _material_for_slot(slot_name: String) -> ShipPbrMaterial:
	if ("emission" in slot_name or "engine" in slot_name or "light" in slot_name) and emission_material != null:
		return emission_material
	if ("interior" in slot_name or "hangar" in slot_name or "refractory" in slot_name) and interior_material != null:
		return interior_material
	if ("mark" in slot_name or "decal" in slot_name) and marking_material != null:
		return marking_material
	if "accent" in slot_name and accent_material != null:
		return accent_material
	return hull_material
