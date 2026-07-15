"""Create the production Sidebay Blender source and exportable GLB.

Run with Blender, not regular Python:
  blender --background --python tools/ship_assets/create_sidebay_source.py

Re-running this script deterministically rebuilds the source scene, socket
contract, UVs, material slots, GLB, and geometry report. Primary forms and
hangar structure are deliberately sized for the in-game chase camera rather
than relying on studio lighting or sub-pixel surface noise.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path.cwd()
SHIP_ROOT = ROOT / "assets" / "ships" / "cvn_sidebay"
SOURCE_ROOT = SHIP_ROOT / "source"
BLEND_PATH = SOURCE_ROOT / "cvn_sidebay.blend"
GLB_PATH = SHIP_ROOT / "cvn_sidebay.glb"
REPORT_PATH = SOURCE_ROOT / "cvn_sidebay_build_report.json"
TEXTURE_ROOT = ROOT / "assets" / "ships" / "materials" / "navy" / "runtime"
SHIP_DIMENSIONS = (76.0, 32.0, 220.0)
FLAK_POSITIONS = (
    (-27.5, 70.0, 10.8), (27.5, 70.0, 10.8),
    (-29.0, 42.0, 10.8), (29.0, 42.0, 10.8),
    (-28.0, 12.0, 10.8), (28.0, 12.0, 10.8),
    (-28.5, -27.0, 10.8), (28.5, -27.0, 10.8),
    (-26.5, -69.0, 13.05), (26.5, -69.0, 13.05),
)
ENGINE_POSITIONS = (
    (-22.5, -6.0), (0.0, -6.0), (22.5, -6.0),
    (-22.5, 6.0), (0.0, 6.0), (22.5, 6.0),
)
HANGAR_Y_POSITIONS = (56.0, 30.0, -20.0)
HANGAR_DOOR_LENGTHS = (25.0, 25.0, 58.0)
HANGAR_GALLERIES = (
    ("Forward", 43.5, 53.0),
    ("Aft", -20.0, 60.0),
)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["ship_id"] = "cvn_sidebay"
    scene["dimensions_m"] = SHIP_DIMENSIONS


def collection(name: str) -> bpy.types.Collection:
    result = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    return result


def set_principled(material: bpy.types.Material, name: str, value) -> None:
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled and name in principled.inputs:
        principled.inputs[name].default_value = value


def simple_material(name: str, color, metallic: float, roughness: float, emission_strength: float = 0.0) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (*color, 1.0)
    set_principled(material, "Base Color", (*color, 1.0))
    set_principled(material, "Metallic", metallic)
    set_principled(material, "Roughness", roughness)
    if emission_strength > 0.0:
        set_principled(material, "Emission Color", (*color, 1.0))
        set_principled(material, "Emission Strength", emission_strength)
    return material


def textured_hull_material() -> bpy.types.Material:
    material = simple_material("Hull", (0.12, 0.18, 0.22), 0.76, 0.4)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    base_path = TEXTURE_ROOT / "navy_gunmetal_base_color.png"
    normal_path = TEXTURE_ROOT / "navy_gunmetal_normal.png"
    orm_path = TEXTURE_ROOT / "navy_gunmetal_orm.png"
    if base_path.exists():
        base_node = nodes.new("ShaderNodeTexImage")
        base_node.name = "Navy Base Color"
        base_node.image = bpy.data.images.load(str(base_path), check_existing=True)
        links.new(base_node.outputs["Color"], principled.inputs["Base Color"])
    if normal_path.exists():
        normal_image = nodes.new("ShaderNodeTexImage")
        normal_image.name = "Navy Normal"
        normal_image.image = bpy.data.images.load(str(normal_path), check_existing=True)
        normal_image.image.colorspace_settings.name = "Non-Color"
        normal_node = nodes.new("ShaderNodeNormalMap")
        normal_node.inputs["Strength"].default_value = 0.85
        links.new(normal_image.outputs["Color"], normal_node.inputs["Color"])
        links.new(normal_node.outputs["Normal"], principled.inputs["Normal"])
    if orm_path.exists():
        orm_node = nodes.new("ShaderNodeTexImage")
        orm_node.name = "Navy ORM"
        orm_node.image = bpy.data.images.load(str(orm_path), check_existing=True)
        orm_node.image.colorspace_settings.name = "Non-Color"
        separate = nodes.new("ShaderNodeSeparateColor")
        links.new(orm_node.outputs["Color"], separate.inputs["Color"])
        links.new(separate.outputs["Green"], principled.inputs["Roughness"])
        links.new(separate.outputs["Blue"], principled.inputs["Metallic"])
    return material


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.append(material)


def apply_bevel(obj: bpy.types.Object, width: float, segments: int = 2) -> None:
    if width <= 0.0:
        return
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    modifier = obj.modifiers.new("ProductionBevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def box(name: str, size, location, material, geometry_collection, bevel: float = 0.35, rotation=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    # One broad chamfer reads better at gameplay distance and leaves the triangle
    # budget for silhouette-defining armor instead of invisible roundovers.
    apply_bevel(obj, min(bevel, min(size) * 0.22), 1)
    for parent_collection in list(obj.users_collection):
        parent_collection.objects.unlink(obj)
    geometry_collection.objects.link(obj)
    return obj


def tapered_box(name: str, length: float, front_width: float, back_width: float, height: float, location, material, geometry_collection, bevel: float = 0.45) -> bpy.types.Object:
    half_length = length * 0.5
    half_height = height * 0.5
    fw = front_width * 0.5
    bw = back_width * 0.5
    vertices = [
        (-bw, -half_length, -half_height), (bw, -half_length, -half_height),
        (bw, -half_length, half_height), (-bw, -half_length, half_height),
        (-fw, half_length, -half_height), (fw, half_length, -half_height),
        (fw, half_length, half_height), (-fw, half_length, half_height),
    ]
    faces = [
        (0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
        (3, 2, 6, 7), (1, 5, 6, 2), (0, 3, 7, 4),
    ]
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    geometry_collection.objects.link(obj)
    assign_material(obj, material)
    apply_bevel(obj, bevel)
    return obj


def faceted_hull(name: str, sections, material, geometry_collection, bevel: float = 0.45) -> bpy.types.Object:
    """Build a low octagonal armored volume from y/half-width/half-height sections."""
    vertices = []
    for y, half_width, half_height in sections:
        corner_x = half_width * 0.74
        shoulder_z = half_height * 0.58
        vertices.extend((
            (-corner_x, y, -half_height),
            (corner_x, y, -half_height),
            (half_width, y, -shoulder_z),
            (half_width, y, shoulder_z),
            (corner_x, y, half_height),
            (-corner_x, y, half_height),
            (-half_width, y, shoulder_z),
            (-half_width, y, -shoulder_z),
        ))
    faces = []
    for section_index in range(len(sections) - 1):
        start = section_index * 8
        next_start = (section_index + 1) * 8
        for edge in range(8):
            next_edge = (edge + 1) % 8
            faces.append((start + edge, start + next_edge, next_start + next_edge, next_start + edge))
    faces.append(tuple(reversed(range(8))))
    final_start = (len(sections) - 1) * 8
    faces.append(tuple(final_start + index for index in range(8)))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    geometry_collection.objects.link(obj)
    assign_material(obj, material)
    apply_bevel(obj, bevel)
    return obj


def cylinder(name: str, radius: float, depth: float, location, material, geometry_collection) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius, depth=depth, location=location, rotation=(math.radians(90.0), 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    apply_bevel(obj, 0.18, 2)
    for parent_collection in list(obj.users_collection):
        parent_collection.objects.unlink(obj)
    geometry_collection.objects.link(obj)
    return obj


def nozzle_frustum(name: str, front_radius: float, rear_radius: float, depth: float, location, material, geometry_collection) -> bpy.types.Object:
    """Create an aft-facing truncated engine bell along Blender local Y."""
    bpy.ops.mesh.primitive_cone_add(
        vertices=24,
        radius1=front_radius,
        radius2=rear_radius,
        depth=depth,
        location=location,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    apply_bevel(obj, 0.12, 2)
    for parent_collection in list(obj.users_collection):
        parent_collection.objects.unlink(obj)
    geometry_collection.objects.link(obj)
    return obj


def nozzle_ring(name: str, major_radius: float, minor_radius: float, location, material, geometry_collection) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=24,
        minor_segments=8,
        location=location,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    for parent_collection in list(obj.users_collection):
        parent_collection.objects.unlink(obj)
    geometry_collection.objects.link(obj)
    return obj


def vertical_cylinder(name: str, radius: float, depth: float, location, material, geometry_collection, vertices: int = 32) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    apply_bevel(obj, min(0.14, depth * 0.2), 2)
    for parent_collection in list(obj.users_collection):
        parent_collection.objects.unlink(obj)
    geometry_collection.objects.link(obj)
    return obj


def build_pdw_model(material: bpy.types.Material, geometry_collection) -> bpy.types.Object:
    """Build the one reusable twin-barrel flak/point-defense cannon mesh."""
    components: list[bpy.types.Object] = []
    components.append(vertical_cylinder("PDW_Base", 1.28, 0.42, (0.0, 0.0, 0.21), material, geometry_collection))
    components.append(vertical_cylinder("PDW_TraverseRing", 1.02, 0.34, (0.0, 0.0, 0.54), material, geometry_collection))
    components.append(box("PDW_RearHousing", (1.72, 1.58, 0.94), (0.0, -0.18, 1.02), material, geometry_collection, 0.18))
    components.append(tapered_box("PDW_ArmoredCradle", 1.85, 1.18, 1.72, 0.72, (0.0, 0.54, 1.34), material, geometry_collection, 0.16))
    for side in (-1.0, 1.0):
        x = side * 0.43
        components.append(box("PDW_Trunnion", (0.42, 0.76, 0.58), (x, 0.42, 1.55), material, geometry_collection, 0.11))
        components.append(cylinder("PDW_Barrel", 0.14, 3.65, (x, 2.34, 1.68), material, geometry_collection))
        components.append(cylinder("PDW_MuzzleBrake", 0.25, 0.52, (x, 4.16, 1.68), material, geometry_collection))
    components.append(box("PDW_SensorBrow", (0.62, 0.62, 0.42), (0.0, 0.36, 1.92), material, geometry_collection, 0.1))
    components.append(vertical_cylinder("PDW_SensorDish", 0.28, 0.16, (0.0, 0.38, 2.18), material, geometry_collection, 24))

    bpy.ops.object.select_all(action="DESELECT")
    for component in components:
        component.select_set(True)
    bpy.context.view_layer.objects.active = components[0]
    bpy.ops.object.join()
    model = bpy.context.object
    model.name = "PDW_FlakCannon_Model"
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    model.data.name = "PDW_FlakCannon_SharedMesh"
    model["weapon_role"] = "flak_point_defense"
    model["linked_asset"] = "PDW_FlakCannon"
    return model


def place_pdw_mounts(material: bpy.types.Material, geometry_collection, sockets: list[bpy.types.Object]) -> list[bpy.types.Object]:
    socket_lookup = {socket.name: socket for socket in sockets}
    prototype = build_pdw_model(material, geometry_collection)
    mounts: list[bpy.types.Object] = []
    for index, position in enumerate(FLAK_POSITIONS, start=1):
        mount = prototype if index == 1 else prototype.copy()
        if index > 1:
            mount.data = prototype.data
            geometry_collection.objects.link(mount)
        mount.name = f"PDW_FlakCannon_{index:02d}"
        mount["mount_index"] = index
        socket = socket_lookup[f"socket_flak_{index:02d}"]
        socket.rotation_euler.z = math.radians(-10.0 if position[0] < 0.0 else 10.0)
        mount.parent = socket
        mount.location = (0.0, 0.0, 0.0)
        mount.rotation_euler = (0.0, 0.0, 0.0)
        mounts.append(mount)
    return mounts


def build_armored_engines(materials, geometry_collection) -> list[bpy.types.Object]:
    """Build six recessed drives inside a compartmentalized armored stern wall."""
    hull, accent, _marking, emission = materials[:4]
    objects: list[bpy.types.Object] = []
    # A broad, deep stern citadel reproduces the reference wall while retaining
    # Sidebay's six-drive gameplay contract instead of inventing two new drives.
    objects.append(box("EngineCitadelRearBulkhead", (72.0, 2.4, 27.0), (0.0, -108.2, 0.0), hull, geometry_collection, 0.62))
    objects.append(box("EngineCitadelTopArmor", (76.0, 11.5, 2.2), (0.0, -104.8, 14.0), hull, geometry_collection, 0.5))
    objects.append(box("EngineCitadelBottomArmor", (76.0, 11.5, 2.2), (0.0, -104.8, -14.0), hull, geometry_collection, 0.5))
    objects.append(box("EngineCitadelPortArmor", (2.2, 11.5, 29.5), (-36.9, -104.8, 0.0), hull, geometry_collection, 0.52))
    objects.append(box("EngineCitadelStarboardArmor", (2.2, 11.5, 29.5), (36.9, -104.8, 0.0), hull, geometry_collection, 0.52))
    objects.append(tapered_box("EngineCitadelDorsalSpine", 15.0, 11.0, 15.0, 3.2, (0.0, -101.0, 13.25), hull, geometry_collection, 0.38))
    objects.append(tapered_box("EngineCitadelVentralKeel", 17.0, 12.0, 17.0, 3.2, (0.0, -100.0, -13.25), hull, geometry_collection, 0.38))

    # Full-depth dividers and a horizontal firebreak isolate each drive cell.
    for divider_index, x in enumerate((-11.25, 11.25), start=1):
        objects.append(box(f"EngineCellVerticalDivider{divider_index:02d}", (1.45, 10.0, 25.0), (x, -104.6, 0.0), hull, geometry_collection, 0.34))
    objects.append(box("EngineCellHorizontalFirebreak", (69.0, 10.0, 1.35), (0.0, -104.6, 0.0), hull, geometry_collection, 0.32))

    for engine_index, (x, z) in enumerate(ENGINE_POSITIONS, start=1):
        label = f"Engine_{engine_index:02d}"
        # A dark refractory cell behind the bell gives the drive real depth.
        objects.append(cylinder(f"{label}_RefractoryWell", 5.0, 0.92, (x, -109.0, z), accent, geometry_collection))
        objects.append(nozzle_frustum(f"{label}_Bell", 2.65, 4.05, 9.2, (x, -104.35, z), accent, geometry_collection))
        objects.append(cylinder(f"{label}_SacrificialBlastCollar", 4.75, 1.05, (x, -109.55, z), hull, geometry_collection))
        objects.append(nozzle_ring(f"{label}_GimbalRetainingRing", 3.75, 0.34, (x, -110.12, z), accent, geometry_collection))
        objects.append(nozzle_ring(f"{label}_CeramicThroatRing", 2.4, 0.22, (x, -109.94, z), emission, geometry_collection))
        objects.append(cylinder(f"{label}_Emitter", 1.68, 0.3, (x, -109.68, z), emission, geometry_collection))
        objects.append(cylinder(f"{label}_ArmoredInjector", 0.52, 0.34, (x, -110.18, z), hull, geometry_collection))
        for strut_index, rotation_z in enumerate((0.0, math.radians(90.0)), start=1):
            objects.append(box(
                f"{label}_InjectorBrace{strut_index:02d}",
                (0.28, 0.4, 4.2),
                (x, -110.26, z),
                hull,
                geometry_collection,
                0.04,
                rotation=(0.0, rotation_z, 0.0),
            ))

    # Small armored service trunks imply fuel, coolant, and power routing while
    # staying behind the blast plane rather than crossing exposed nozzles.
    for side_index, x in enumerate((-33.0, 33.0), start=1):
        objects.append(cylinder(f"EngineServiceTrunk{side_index:02d}", 0.75, 9.0, (x, -104.5, 0.0), accent, geometry_collection))
        for z in (-6.0, 6.0):
            objects.append(box(f"EngineServiceAccess_{side_index:02d}_{'L' if z < 0.0 else 'U'}", (2.8, 0.62, 2.0), (x, -109.95, z), hull, geometry_collection, 0.18))
    return objects


def build_hangar_blast_doors(materials, geometry_collection) -> list[bpy.types.Object]:
    """Create twelve animation-ready shutter halves across two large galleries."""
    hull, accent, marking, _emission = materials[:4]
    doors: list[bpy.types.Object] = []
    for bay_index, (y, door_length) in enumerate(zip(HANGAR_Y_POSITIONS, HANGAR_DOOR_LENGTHS), start=1):
        prototype_parts: list[bpy.types.Object] = []
        prototype_parts.append(box(
            f"BlastDoorPrototype{bay_index:02d}Panel",
            (0.88, door_length - 1.0, 4.55),
            (0.0, 0.0, 0.0),
            hull,
            geometry_collection,
            0.14,
        ))
        rib_count = max(4, int(door_length / 6.0))
        for rib_index in range(rib_count):
            rib_y = -door_length * 0.42 + door_length * 0.84 * rib_index / max(1, rib_count - 1)
            prototype_parts.append(box(
                f"BlastDoorPrototype{bay_index:02d}Rib",
                (0.16, 0.42, 4.7),
                (0.48, rib_y, 0.0),
                accent,
                geometry_collection,
                0.045,
            ))
        for band_z in (-1.45, 1.45):
            prototype_parts.append(box(
                f"BlastDoorPrototype{bay_index:02d}WarningBand",
                (0.17, door_length - 2.0, 0.16),
                (0.49, 0.0, band_z),
                marking,
                geometry_collection,
                0.03,
            ))
        bpy.ops.object.select_all(action="DESELECT")
        for part in prototype_parts:
            part.select_set(True)
        bpy.context.view_layer.objects.active = prototype_parts[0]
        bpy.ops.object.join()
        prototype = bpy.context.object
        prototype.name = f"blastdoor_port_{bay_index:02d}_upper"
        prototype.data.name = f"SidebayBlastDoor_{bay_index:02d}_SharedMesh"
        prototype["door_role"] = "hangar_blast_door"
        prototype["door_state"] = "open"

        door_copy_index = 0
        for side_name, side in (("port", -1.0), ("starboard", 1.0)):
            for half_name, z_offset in (("upper", 2.25), ("lower", -2.25)):
                door = prototype if door_copy_index == 0 else prototype.copy()
                if door_copy_index > 0:
                    door.data = prototype.data
                    geometry_collection.objects.link(door)
                door.name = f"blastdoor_{side_name}_{bay_index:02d}_{half_name}"
                door.location = (side * 37.35, y, 8.0 if half_name == "upper" else -8.0)
                door.rotation_euler.z = 0.0 if side > 0.0 else math.pi
                door["bay_side"] = side_name
                door["bay_index"] = bay_index
                door["door_half"] = half_name
                door["door_state"] = "open"
                doors.append(door)
                door_copy_index += 1
    return doors


def build_parked_fighter(name: str, side: float, x: float, y: float, z: float, materials, geometry_collection) -> list[bpy.types.Object]:
    """Create a dark, readable carrier-craft silhouette for a hangar parking spot."""
    hull, accent, marking, emission = materials[:4]
    objects: list[bpy.types.Object] = []
    rotation_z = math.radians(-90.0 if side > 0.0 else 90.0)
    body = tapered_box(f"{name}_Fuselage", 8.6, 0.72, 2.35, 0.72, (x, y, z), accent, geometry_collection, 0.12)
    body.rotation_euler.z = rotation_z
    objects.append(body)
    # Craft point outboard toward the launch aperture. Broad swept wings and a
    # tailplane are dark; only a narrow spine marking and canopy catch the eye.
    objects.append(box(f"{name}_MainWing", (3.8, 6.2, 0.28), (x - side * 0.55, y, z - 0.03), hull, geometry_collection, 0.07))
    objects.append(box(f"{name}_Tailplane", (1.65, 3.5, 0.22), (x - side * 3.0, y, z + 0.02), accent, geometry_collection, 0.06))
    objects.append(box(f"{name}_DorsalFin", (1.2, 0.22, 0.86), (x - side * 3.15, y, z + 0.5), hull, geometry_collection, 0.055))
    objects.append(box(f"{name}_Canopy", (1.25, 0.76, 0.3), (x + side * 1.45, y, z + 0.48), emission, geometry_collection, 0.05))
    return objects


def build_hangar_galleries(materials, geometry_collection) -> list[bpy.types.Object]:
    hull, accent, marking, emission = materials[:4]
    interior = materials[4]
    objects: list[bpy.types.Object] = []
    for side_name, side in (("Port", -1.0), ("Starboard", 1.0)):
        for gallery_index, (gallery_name, center_y, gallery_length) in enumerate(HANGAR_GALLERIES, start=1):
            prefix = f"{side_name}{gallery_name}Gallery"
            # Deep galleries are framed as armored voids. Their large beams and
            # chamfered shoulders remain legible from the normal chase camera.
            objects.append(box(f"{prefix}InnerBulkhead", (1.15, gallery_length, 11.5), (side * 22.8, center_y, 0.0), interior, geometry_collection, 0.2))
            objects.append(box(f"{prefix}FlightDeck", (15.8, gallery_length, 1.25), (side * 30.0, center_y, -5.75), interior, geometry_collection, 0.28))
            objects.append(box(f"{prefix}OverheadArmor", (15.8, gallery_length, 1.3), (side * 30.0, center_y, 6.0), interior, geometry_collection, 0.28))
            for end_index, end_y in enumerate((center_y - gallery_length * 0.5, center_y + gallery_length * 0.5), start=1):
                objects.append(box(f"{prefix}EndBulkhead{end_index:02d}", (15.9, 1.6, 13.2), (side * 30.0, end_y, 0.0), hull, geometry_collection, 0.36))
                objects.append(box(f"{prefix}OuterPillar{end_index:02d}", (2.8, 2.6, 15.2), (side * 36.4, end_y, 0.0), accent, geometry_collection, 0.34))
            objects.append(box(f"{prefix}OuterUpperBeam", (3.0, gallery_length + 2.2, 2.6), (side * 36.2, center_y, 6.9), accent, geometry_collection, 0.38))
            objects.append(box(f"{prefix}OuterLowerBeam", (3.0, gallery_length + 2.2, 2.6), (side * 36.2, center_y, -6.8), accent, geometry_collection, 0.38))
            objects.append(box(
                f"{prefix}SlopedArmorBrow",
                (5.4, gallery_length + 1.4, 2.2),
                (side * 34.5, center_y, 8.2),
                hull,
                geometry_collection,
                0.3,
                rotation=(0.0, math.radians(side * 18.0), 0.0),
            ))
            objects.append(box(
                f"{prefix}SlopedArmorSill",
                (5.4, gallery_length + 1.4, 2.2),
                (side * 34.5, center_y, -8.1),
                hull,
                geometry_collection,
                0.3,
                rotation=(0.0, math.radians(side * -18.0), 0.0),
            ))
            # Deep door coffers and guide rails carry the heavy shutters clear of
            # the opening during flight operations.
            objects.append(box(f"{prefix}UpperDoorCoffer", (2.0, gallery_length + 1.0, 4.7), (side * 37.0, center_y, 8.0), hull, geometry_collection, 0.28))
            objects.append(box(f"{prefix}LowerDoorCoffer", (2.0, gallery_length + 1.0, 4.7), (side * 37.0, center_y, -8.0), hull, geometry_collection, 0.28))
            objects.append(box(f"{prefix}UpperGuide", (1.2, gallery_length, 0.5), (side * 37.3, center_y, 5.75), accent, geometry_collection, 0.09))
            objects.append(box(f"{prefix}LowerGuide", (1.2, gallery_length, 0.5), (side * 37.3, center_y, -5.55), accent, geometry_collection, 0.09))

            for light_lane, lane_x in enumerate((25.8, 30.0, 34.2), start=1):
                objects.append(box(
                    f"{prefix}CeilingLight{light_lane:02d}",
                    (0.16, gallery_length - 4.0, 0.16),
                    (side * lane_x, center_y, 5.2),
                    emission,
                    geometry_collection,
                    0.025,
                ))
            for rail_lane, lane_x in enumerate((25.6, 30.0, 34.4), start=1):
                objects.append(box(
                    f"{prefix}DeckRail{rail_lane:02d}",
                    (0.18, gallery_length - 4.0, 0.12),
                    (side * lane_x, center_y, -5.02),
                    marking,
                    geometry_collection,
                    0.02,
                ))
            # Large parked craft and gantries establish scale; fewer, stronger
            # silhouettes read better than rows of sub-pixel miniatures.
            fighter_count = 2
            for fighter_index in range(fighter_count):
                fighter_y = center_y - gallery_length * 0.38 + gallery_length * 0.76 * fighter_index / max(1, fighter_count - 1)
                fighter_x = side * (27.8 + (fighter_index % 2) * 4.2)
                objects.append(box(
                    f"{prefix}OverheadPanel{fighter_index + 1:02d}",
                    (2.3, 1.35, 0.18),
                    (side * 30.0, fighter_y, 5.16),
                    emission,
                    geometry_collection,
                    0.03,
                ))
                objects.append(box(
                    f"{prefix}BulkheadLight{fighter_index + 1:02d}",
                    (0.18, 2.0, 0.5),
                    (side * 23.48, fighter_y, 2.4),
                    emission,
                    geometry_collection,
                    0.035,
                ))
                objects.extend(build_parked_fighter(
                    f"{prefix}Fighter{fighter_index + 1:02d}",
                    side,
                    fighter_x,
                    fighter_y,
                    -4.65,
                    materials,
                    geometry_collection,
                ))
            gantry_count = 4
            for gantry_index in range(gantry_count):
                gantry_y = center_y - gallery_length * 0.36 + gallery_length * 0.72 * gantry_index / max(1, gantry_count - 1)
                objects.append(box(
                    f"{prefix}CeilingGantry{gantry_index + 1:02d}",
                    (12.2, 0.48, 0.58),
                    (side * 29.6, gantry_y, 4.72),
                    accent,
                    geometry_collection,
                    0.08,
                ))
            for stripe_index, lane_x in enumerate((25.0, 35.0), start=1):
                objects.append(box(
                    f"{prefix}DeckEdgeMarking{stripe_index:02d}",
                    (0.32, gallery_length - 3.0, 0.12),
                    (side * lane_x, center_y, -5.02),
                    marking,
                    geometry_collection,
                    0.025,
                ))
    return objects


def build_command_citadel(materials, geometry_collection) -> list[bpy.types.Object]:
    hull, accent, _marking, emission = materials[:4]
    objects: list[bpy.types.Object] = []
    objects.append(tapered_box("CitadelLowerTerrace", 46.0, 25.0, 33.0, 2.8, (0.0, -23.0, 11.65), hull, geometry_collection, 0.46))
    objects.append(tapered_box("CitadelMiddleTerrace", 31.0, 18.5, 24.5, 2.4, (0.0, -24.5, 13.35), accent, geometry_collection, 0.4))
    objects.append(tapered_box("CitadelBridgeBlock", 17.0, 11.5, 15.5, 2.0, (0.0, -22.0, 14.65), hull, geometry_collection, 0.3))
    objects.append(box("CitadelForwardBridgeWindows", (11.6, 0.4, 0.58), (0.0, -13.45, 14.72), emission, geometry_collection, 0.06))
    for side_index, side in enumerate((-1.0, 1.0), start=1):
        objects.append(box(f"CitadelSideBridgeWindows{side_index:02d}", (0.38, 10.5, 0.54), (side * 7.1, -22.0, 14.72), emission, geometry_collection, 0.05))
        objects.append(box(
            f"CitadelArmoredCheek{side_index:02d}",
            (3.2, 22.0, 1.8),
            (side * 11.0, -24.0, 12.9),
            hull,
            geometry_collection,
            0.22,
            rotation=(0.0, math.radians(side * 12.0), 0.0),
        ))
        objects.append(vertical_cylinder(f"CitadelSensorDome{side_index:02d}", 0.95, 0.52, (side * 7.8, -31.0, 14.1), accent, geometry_collection, 24))
    objects.append(vertical_cylinder("CitadelMainMast", 0.42, 2.0, (0.0, -24.0, 14.9), hull, geometry_collection, 20))
    objects.append(vertical_cylinder("CitadelRadarCrown", 1.35, 0.42, (0.0, -24.0, 15.55), accent, geometry_collection, 28))
    objects.append(box("CitadelRadarArray", (5.2, 0.32, 0.42), (0.0, -24.0, 15.48), accent, geometry_collection, 0.08, rotation=(0.0, 0.0, math.radians(18.0))))
    for antenna_index, (x, y) in enumerate(((-2.5, -27.0), (2.5, -27.0), (-1.5, -20.0), (1.5, -20.0)), start=1):
        objects.append(vertical_cylinder(f"CitadelAntenna{antenna_index:02d}", 0.09, 1.35, (x, y, 15.25), hull, geometry_collection, 12))
    return objects


def build_armor_panel_language(materials, geometry_collection) -> list[bpy.types.Object]:
    hull, accent, _marking, emission = materials[:4]
    objects: list[bpy.types.Object] = []
    top_rows = (-91.0, -77.0, -63.0, -49.0, -35.0, -21.0, -7.0, 7.0, 28.0, 43.0, 58.0, 73.0, 86.0, 98.0)
    for row_index, y in enumerate(top_rows):
        if y < -55.0:
            half_width = 34.0
            surface_z = 13.12
        elif y <= 72.0:
            half_width = 34.5
            surface_z = 10.64
        else:
            progress = min(1.0, max(0.0, (y - 72.0) / 38.0))
            half_width = 34.0 * (1.0 - progress) + 9.0 * progress
            surface_z = 10.45 * (1.0 - progress) + 5.8 * progress
        lane_count = 4 if half_width > 25.0 else 2
        for lane_index in range(lane_count):
            fraction = (lane_index + 0.5) / lane_count
            x = -half_width + fraction * half_width * 2.0
            width = max(6.0, half_width * 2.0 / lane_count - 1.2)
            length = 11.0 + ((row_index + lane_index) % 3) * 1.1
            material = accent if (row_index * 3 + lane_index) % 7 == 0 else hull
            objects.append(box(
                f"DorsalArmorPanel_{row_index + 1:02d}_{lane_index + 1:02d}",
                (width, length, 0.26),
                (x, y, surface_z),
                material,
                geometry_collection,
                0.08,
            ))
            if (row_index + lane_index) % 5 == 0:
                objects.append(box(
                    f"DorsalServiceHatch_{row_index + 1:02d}_{lane_index + 1:02d}",
                    (max(1.8, width * 0.28), max(2.0, length * 0.24), 0.18),
                    (x + width * 0.18, y, surface_z + 0.2),
                    accent,
                    geometry_collection,
                    0.05,
                ))

    # Secondary hatches and vent clusters break the large armor fields into the
    # dense serviceable plate language visible throughout the reference sheet.
    for detail_index in range(20):
        y = -91.0 + (detail_index % 16) * 10.2
        row = detail_index // 16
        if y < -55.0:
            half_width = 31.5
            surface_z = 13.34
        elif y <= 72.0:
            half_width = 32.0
            surface_z = 10.86
        else:
            progress = min(1.0, max(0.0, (y - 72.0) / 38.0))
            half_width = 30.0 * (1.0 - progress) + 6.0 * progress
            surface_z = 10.65 * (1.0 - progress) + 5.9 * progress
        x_fraction = ((detail_index * 7 + row * 3) % 19) / 18.0
        x = -half_width + x_fraction * half_width * 2.0
        detail_width = 1.6 + (detail_index % 4) * 0.55
        detail_length = 2.2 + ((detail_index + 2) % 5) * 0.62
        objects.append(box(
            f"DorsalMicroArmor{detail_index + 1:02d}",
            (detail_width, detail_length, 0.2),
            (x, y, surface_z),
            accent,
            geometry_collection,
            0.05,
        ))
        if detail_index % 6 == 0:
            for vent_index in range(3):
                objects.append(box(
                    f"DorsalVent_{detail_index + 1:02d}_{vent_index + 1:02d}",
                    (0.28, detail_length * 0.85, 0.16),
                    (x - 0.48 + vent_index * 0.48, y, surface_z + 0.17),
                    hull,
                    geometry_collection,
                    0.025,
                ))

    for region_name, centers in (("Bow", (80.0, 92.0, 103.0)), ("Stern", (-69.0, -91.5))):
        for center_index, y in enumerate(centers, start=1):
            if region_name == "Bow":
                progress = min(1.0, max(0.0, (y - 72.0) / 38.0))
                half_width = 35.0 * (1.0 - progress) + 9.0 * progress
            else:
                half_width = 35.7
            for side_name, side in (("Port", -1.0), ("Starboard", 1.0)):
                levels = (-5.0, 0.0, 5.0) if region_name == "Bow" else (-4.25, 4.25)
                for level_index, z in enumerate(levels, start=1):
                    panel_length = 10.2 if region_name == "Bow" else 21.8
                    panel_height = 3.7 if region_name == "Bow" else 8.0
                    objects.append(box(
                        f"{region_name}{side_name}ArmorPanel_{center_index:02d}_{level_index:02d}",
                        (0.48, panel_length, panel_height),
                        (side * (half_width + 0.08), y, z),
                        hull if (center_index + level_index) % 3 else accent,
                        geometry_collection,
                        0.12,
                    ))

    for light_index, y in enumerate((-88.0, -66.0, -44.0, -18.0, 3.0, 25.0, 47.0, 67.0, 83.0), start=1):
        for side_name, side in (("Port", -1.0), ("Starboard", 1.0)):
            objects.append(box(
                f"{side_name}ArmorPinLight{light_index:02d}",
                (0.18, 1.25, 0.16),
                (side * 35.75, y, 10.35 if y > -55.0 else 12.6),
                emission,
                geometry_collection,
                0.025,
            ))
    return objects


def build_geometry(materials, geometry_collection) -> list[bpy.types.Object]:
    hull, accent, marking, emission = materials[:4]
    objects: list[bpy.types.Object] = []
    objects.append(faceted_hull("ArmoredInnerHull", ((-57.0, 27.0, 9.6), (10.0, 24.0, 9.2), (72.0, 27.0, 10.1)), hull, geometry_collection, 0.72))
    objects.append(faceted_hull("FacetedArmoredBow", ((70.0, 36.0, 10.4), (84.0, 32.0, 10.0), (99.0, 22.0, 8.2), (110.0, 8.5, 5.5)), hull, geometry_collection, 0.68))
    objects.append(faceted_hull("ArmoredSternCitadel", ((-110.0, 33.0, 13.0), (-94.0, 36.0, 13.0), (-55.0, 36.0, 11.2)), hull, geometry_collection, 0.74))
    # A narrower central roof and floor plus sloped shoulders replace the old
    # single rectangular slab. The silhouette now carries an armored chamfer
    # that survives the dark gameplay renderer.
    objects.append(box("ContinuousDorsalArmor", (63.5, 127.0, 3.6), (0.0, 7.5, 8.65), hull, geometry_collection, 0.82))
    objects.append(box("ContinuousVentralArmor", (63.5, 127.0, 3.6), (0.0, 7.5, -8.65), hull, geometry_collection, 0.82))
    objects.append(box("ArmoredMidshipPier", (74.0, 10.5, 21.0), (0.0, 15.0, 0.0), hull, geometry_collection, 0.72))
    objects.append(tapered_box("VentralKeel", 178.0, 9.0, 15.0, 4.6, (0.0, -7.0, -13.55), accent, geometry_collection, 0.48))
    for side_name, side in (("Port", -1.0), ("Starboard", 1.0)):
        objects.append(box(
            f"{side_name}DorsalShoulderArmor",
            (7.4, 127.0, 3.0),
            (side * 34.1, 7.5, 9.15),
            hull,
            geometry_collection,
            0.42,
            rotation=(0.0, math.radians(side * 20.0), 0.0),
        ))
        objects.append(box(
            f"{side_name}VentralShoulderArmor",
            (7.4, 127.0, 3.0),
            (side * 34.1, 7.5, -9.15),
            hull,
            geometry_collection,
            0.42,
            rotation=(0.0, math.radians(side * -20.0), 0.0),
        ))
        objects.append(box(f"{side_name}UpperSponsonRail", (2.4, 127.0, 2.2), (side * 36.7, 7.5, 6.4), accent, geometry_collection, 0.3))
        objects.append(box(f"{side_name}LowerSponsonRail", (2.4, 127.0, 2.2), (side * 36.7, 7.5, -6.4), accent, geometry_collection, 0.3))
    objects.extend(build_hangar_galleries(materials, geometry_collection))
    objects.extend(build_command_citadel(materials, geometry_collection))
    objects.extend(build_armor_panel_language(materials, geometry_collection))
    objects.extend(build_armored_engines(materials, geometry_collection))
    # Layered forward armor bands establish the reference's heavy, low bow face.
    for band_index, (y, width, z) in enumerate(((106.0, 20.0, -2.8), (105.2, 24.0, 0.0), (104.3, 28.0, 2.9)), start=1):
        objects.append(box(f"BowArmorBand{band_index:02d}", (width, 1.0, 2.0), (0.0, y, z), hull, geometry_collection, 0.18))
    for side_index, side in enumerate((-1.0, 1.0), start=1):
        objects.append(box(f"BowSensorSlit{side_index:02d}", (7.5, 0.45, 0.48), (side * 10.2, 106.7, 0.2), emission, geometry_collection, 0.06))
    return objects


def consolidate_geometry(objects: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    hull = bpy.context.object
    hull.name = "Hull_LOD0"

    old_materials = [slot.material for slot in hull.material_slots]
    polygon_materials = [old_materials[poly.material_index] for poly in hull.data.polygons]
    unique_materials = []
    for material in old_materials:
        if material not in unique_materials:
            unique_materials.append(material)
    hull.data.materials.clear()
    for material in unique_materials:
        hull.data.materials.append(material)
    material_indices = {material: index for index, material in enumerate(unique_materials)}
    for polygon, material in zip(hull.data.polygons, polygon_materials):
        polygon.material_index = material_indices[material]

    bpy.context.view_layer.objects.active = hull
    hull.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project()
    bpy.ops.object.mode_set(mode="OBJECT")
    hull.data.validate()
    hull.data.update()
    hull["lod"] = 0
    hull["design_status"] = "runtime_refined"
    return hull


def add_socket(socket_collection, name: str, location) -> bpy.types.Object:
    socket = bpy.data.objects.new(name, None)
    socket.empty_display_type = "ARROWS"
    socket.empty_display_size = 1.4
    socket.location = location
    socket_collection.objects.link(socket)
    return socket


def build_sockets(socket_collection) -> list[bpy.types.Object]:
    sockets = []
    for index, (x, z) in enumerate(ENGINE_POSITIONS, start=1):
        sockets.append(add_socket(socket_collection, f"socket_engine_{index:02d}", (x, -110.72, z)))
    for index, position in enumerate(FLAK_POSITIONS, start=1):
        sockets.append(add_socket(socket_collection, f"socket_flak_{index:02d}", position))
    for index, y in enumerate(HANGAR_Y_POSITIONS, start=1):
        sockets.append(add_socket(socket_collection, f"socket_bay_port_{index:02d}", (-38.2, y, 0.0)))
        sockets.append(add_socket(socket_collection, f"socket_bay_starboard_{index:02d}", (38.2, y, 0.0)))
    sockets.append(add_socket(socket_collection, "socket_bay_scout_01", (-5.0, 48.0, 11.0)))
    for index, position in enumerate(((-13.0, 50.0, 10.9), (13.0, 50.0, 10.9), (-13.0, -48.0, 12.9), (13.0, -48.0, 12.9)), start=1):
        sockets.append(add_socket(socket_collection, f"socket_missile_{index:02d}", position))
    for index, position in enumerate(((0.0, 84.0, 0.0), (-25.0, 32.0, 0.0), (25.0, -20.0, 0.0), (0.0, -82.0, 0.0)), start=1):
        sockets.append(add_socket(socket_collection, f"socket_damage_{index:02d}", position))
    return sockets


def look_at(obj: bpy.types.Object, target=(0.0, 0.0, 0.0)) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def build_studio(studio_collection) -> None:
    bpy.ops.object.camera_add(location=(205.0, -315.0, 152.0))
    camera = bpy.context.object
    camera.name = "AuthoringCamera"
    camera.data.lens = 58.0
    look_at(camera)
    for parent_collection in list(camera.users_collection):
        parent_collection.objects.unlink(camera)
    studio_collection.objects.link(camera)
    bpy.context.scene.camera = camera
    for name, location, energy, color, size in (
        ("Key", (95.0, 45.0, 145.0), 1650000.0, (0.72, 0.88, 1.0), 58.0),
        ("Rim", (-110.0, -70.0, 65.0), 950000.0, (0.18, 0.48, 1.0), 48.0),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.color = color
        light.data.shape = "DISK"
        light.data.size = size
        look_at(light)
        for parent_collection in list(light.users_collection):
            parent_collection.objects.unlink(light)
        studio_collection.objects.link(light)
    if bpy.context.scene.world is None:
        bpy.context.scene.world = bpy.data.worlds.new("EXODRIFT Studio World")
    bpy.context.scene.world.use_nodes = True
    background = bpy.context.scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.006, 0.01, 0.016, 1.0)
    background.inputs["Strength"].default_value = 0.22
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.view_settings.exposure = 1.0


def bounds(obj: bpy.types.Object) -> dict[str, list[float]]:
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = [min(corner[axis] for corner in corners) for axis in range(3)]
    maximum = [max(corner[axis] for corner in corners) for axis in range(3)]
    return {"min_blender_xyz": minimum, "max_blender_xyz": maximum}


def mesh_triangles(obj: bpy.types.Object) -> int:
    return sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)


def export(hull, sockets, pdw_mounts, blast_doors) -> None:
    SOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=False,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_apply=True,
        export_extras=True,
        export_materials="PLACEHOLDER",
    )
    report = {
        "ship_id": "cvn_sidebay",
        "blender_version": bpy.app.version_string,
        "blend": str(BLEND_PATH.relative_to(ROOT)),
        "glb": str(GLB_PATH.relative_to(ROOT)),
        "vertices": len(hull.data.vertices) + sum(len(obj.data.vertices) for obj in [*pdw_mounts, *blast_doors]),
        "polygons": len(hull.data.polygons) + sum(len(obj.data.polygons) for obj in [*pdw_mounts, *blast_doors]),
        "triangles": mesh_triangles(hull) + sum(mesh_triangles(obj) for obj in [*pdw_mounts, *blast_doors]),
        "material_slots": len(hull.data.materials) + sum(len(obj.data.materials) for obj in [*pdw_mounts, *blast_doors]),
        "materials": sorted({material.name for obj in [hull, *pdw_mounts, *blast_doors] for material in obj.data.materials}),
        "pdw_count": len(pdw_mounts),
        "pdw_shared_meshes": len({mount.data.as_pointer() for mount in pdw_mounts}),
        "engine_count": 6,
        "engine_layout": "three-by-two recessed drive wall",
        "engine_armor": "compartmentalized stern citadel with sacrificial collars and full-depth firebreaks",
        "hangar_blast_door_count": len(blast_doors),
        "hangar_blast_door_shared_meshes": len({door.data.as_pointer() for door in blast_doors}),
        "sockets": sorted(socket.name for socket in sockets),
        "bounds": bounds(hull),
    }
    REPORT_PATH.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


def main() -> None:
    reset_scene()
    geometry_collection = collection("Geometry")
    socket_collection = collection("Sockets")
    studio_collection = collection("Studio")
    materials = (
        textured_hull_material(),
        simple_material("Accent", (0.12, 0.19, 0.24), 0.56, 0.52),
        simple_material("Marking", (0.54, 0.7, 0.76), 0.24, 0.48),
        simple_material("Emission", (0.05, 0.72, 1.0), 0.08, 0.2, 5.0),
        simple_material("Interior", (0.08, 0.2, 0.3), 0.18, 0.66, 0.7),
    )
    sockets = build_sockets(socket_collection)
    hull = consolidate_geometry(build_geometry(materials, geometry_collection))
    blast_doors = build_hangar_blast_doors(materials, geometry_collection)
    pdw_mounts = place_pdw_mounts(materials[1], geometry_collection, sockets)
    build_studio(studio_collection)
    export(hull, sockets, pdw_mounts, blast_doors)


if __name__ == "__main__":
    main()
