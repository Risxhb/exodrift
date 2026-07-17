"""Build the Blender-authored ISS Resolute missile frigate.

The ship follows EXODRIFT's authored asset contract:
* Blender +Y is forward and +Z is up (GLTF export maps this to Godot -Z/+Y).
* Dimensions are exactly 24 m wide, 12 m high, and 65 m long at frame 1.
* Six VLS cells ripple fire through animated split blast doors.
* Six missile, three flak, four engine, and four damage sockets are exported.

Run with Blender 5.2 or newer:
    blender --background --python tools/ship_assets/create_resolute_source.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
ASSET_ROOT = ROOT / "assets" / "ships" / "iss_resolute"
SOURCE_ROOT = ASSET_ROOT / "source"
BLEND_PATH = SOURCE_ROOT / "iss_resolute.blend"
GLB_PATH = ASSET_ROOT / "iss_resolute.glb"
REPORT_PATH = SOURCE_ROOT / "iss_resolute_report.json"
PREVIEW_REST_PATH = SOURCE_ROOT / "iss_resolute_preview_rest.png"
PREVIEW_LAUNCH_PATH = SOURCE_ROOT / "iss_resolute_preview_vls_launch.png"
PREVIEW_SALVO_PATH = SOURCE_ROOT / "iss_resolute_preview_salvo.png"

SHIP_DIMENSIONS = (24.0, 65.0, 12.0)  # Blender X/Y/Z.
VLS_X = (-3.2, 3.2)
VLS_Y = (5.8, 11.3, 16.8)
VLS_START_FRAMES = (12, 38, 64, 90, 116, 142)
FRAME_END = 205


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(datablocks):
            datablocks.remove(block)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)


def make_collection(name: str, parent: bpy.types.Collection | None = None) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    if parent is None:
        bpy.context.scene.collection.children.link(collection)
    else:
        parent.children.link(collection)
    return collection


def move_to_collection(obj: bpy.types.Object, target: bpy.types.Collection) -> None:
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    target.objects.link(obj)


def material(
    name: str,
    color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color
    nodes = mat.node_tree.nodes
    principled = nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    metallic_input = principled.inputs.get("Metallic IOR Level") or principled.inputs.get("Metallic")
    if metallic_input is not None:
        metallic_input.default_value = metallic
    principled.inputs["Roughness"].default_value = roughness
    if emission_strength > 0.0:
        principled.inputs["Emission Color"].default_value = color
        principled.inputs["Emission Strength"].default_value = emission_strength
    return mat


def assign(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    obj.data.materials.append(mat)


def bevel(obj: bpy.types.Object, width: float, segments: int = 2) -> None:
    if width <= 0.0:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("EdgeChamfer", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    chamfer: float = 0.12,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    bevel(obj, min(chamfer, min(size) * 0.2), 2 if chamfer > 0.1 else 1)
    move_to_collection(obj, collection)
    return obj


def cylinder(
    name: str,
    radius: float,
    depth: float,
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 20,
    chamfer: float = 0.08,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    bevel(obj, min(chamfer, radius * 0.15), 1)
    move_to_collection(obj, collection)
    return obj


def cone(
    name: str,
    radius1: float,
    radius2: float,
    depth: float,
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 20,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    move_to_collection(obj, collection)
    return obj


def faceted_hull(
    name: str,
    sections: tuple[tuple[float, float, float], ...],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    chamfer: float = 0.24,
) -> bpy.types.Object:
    """Create an octagonal hull along Blender Y from (y, half width, half height)."""
    vertices: list[tuple[float, float, float]] = []
    for y, half_width, half_height in sections:
        corner_x = half_width * 0.70
        shoulder_z = half_height * 0.55
        vertices.extend(
            (
                (-corner_x, y, -half_height),
                (corner_x, y, -half_height),
                (half_width, y, -shoulder_z),
                (half_width, y, shoulder_z),
                (corner_x, y, half_height),
                (-corner_x, y, half_height),
                (-half_width, y, shoulder_z),
                (-half_width, y, -shoulder_z),
            )
        )
    faces: list[tuple[int, ...]] = []
    for section_index in range(len(sections) - 1):
        start = section_index * 8
        next_start = (section_index + 1) * 8
        for edge in range(8):
            next_edge = (edge + 1) % 8
            faces.append((start + edge, start + next_edge, next_start + next_edge, next_start + edge))
    faces.append(tuple(reversed(range(8))))
    last = (len(sections) - 1) * 8
    faces.append(tuple(last + index for index in range(8)))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign(obj, mat)
    bevel(obj, chamfer, 2)
    return obj


def tapered_prism(
    name: str,
    length: float,
    front_width: float,
    rear_width: float,
    height: float,
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    chamfer: float = 0.15,
) -> bpy.types.Object:
    """Create a Y-aligned wedge where front is local +Y."""
    half_l = length * 0.5
    half_h = height * 0.5
    fw = front_width * 0.5
    rw = rear_width * 0.5
    verts = [
        (-rw, -half_l, -half_h),
        (rw, -half_l, -half_h),
        (rw, -half_l, half_h),
        (-rw, -half_l, half_h),
        (-fw, half_l, -half_h),
        (fw, half_l, -half_h),
        (fw, half_l, half_h),
        (-fw, half_l, half_h),
    ]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (3, 2, 6, 7), (1, 5, 6, 2), (0, 3, 7, 4)]
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    collection.objects.link(obj)
    assign(obj, mat)
    bevel(obj, chamfer, 2)
    return obj


def parent_keep_transform(child: bpy.types.Object, parent: bpy.types.Object) -> None:
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def set_interpolation(obj: bpy.types.Object, mode: str) -> None:
    if obj.animation_data is None or obj.animation_data.action is None:
        return
    action = obj.animation_data.action
    if hasattr(action, "fcurves"):
        fcurves = action.fcurves
    else:
        # Blender 5 stores curves in layered Action channel bags.
        fcurves = [
            fcurve
            for layer in action.layers
            for strip in layer.strips
            for channelbag in strip.channelbags
            for fcurve in channelbag.fcurves
        ]
    for fcurve in fcurves:
        for point in fcurve.keyframe_points:
            point.interpolation = mode


def key_rotation(obj: bpy.types.Object, frame: int, rotation: tuple[float, float, float]) -> None:
    obj.rotation_euler = rotation
    obj.keyframe_insert(data_path="rotation_euler", frame=frame)


def key_location(obj: bpy.types.Object, frame: int, location: tuple[float, float, float]) -> None:
    obj.location = location
    obj.keyframe_insert(data_path="location", frame=frame)


def key_scale(obj: bpy.types.Object, frame: int, scale: tuple[float, float, float]) -> None:
    obj.scale = scale
    obj.keyframe_insert(data_path="scale", frame=frame)


def add_empty(name: str, location: tuple[float, float, float], collection: bpy.types.Collection, size: float = 0.5) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = size
    obj.location = location
    collection.objects.link(obj)
    return obj


def build_primary_hull(materials, geometry: bpy.types.Collection) -> list[bpy.types.Object]:
    hull, accent, marking, emission = materials
    objects: list[bpy.types.Object] = []
    objects.append(
        faceted_hull(
            "ResolutePressureHull",
            (
                (-32.5, 6.6, 3.6),
                (-27.0, 10.7, 4.7),
                (-18.0, 11.4, 4.8),
                (2.0, 10.8, 4.55),
                (18.0, 9.1, 3.95),
                (27.0, 5.8, 2.75),
                (32.5, 0.55, 0.65),
            ),
            hull,
            geometry,
            0.28,
        )
    )
    # Broadside sacrificial armor gives the frigate a hard, shield-like shoulder.
    for side_name, side in (("Port", -1.0), ("Starboard", 1.0)):
        objects.append(tapered_prism(f"{side_name}BroadsideArmor", 34.0, 2.8, 5.0, 4.2, (side * 9.15, -1.0, 0.1), hull, geometry, 0.22))
        objects[-1].rotation_euler.y = math.radians(side * 7.0)
        objects.append(box(f"{side_name}ArmorRail", (0.55, 31.0, 0.8), (side * 11.67, -1.5, 1.0), accent, geometry, 0.1))
        objects.append(box(f"{side_name}VentralRail", (0.5, 24.0, 0.65), (side * 11.2, -4.5, -2.15), accent, geometry, 0.09))
        # Three armored course breaks; these read as replaceable plates at game distance.
        for rib_index, y in enumerate((-12.0, -2.0, 8.0), start=1):
            objects.append(box(f"{side_name}ArmorRib{rib_index:02d}", (0.42, 0.7, 3.3), (side * 11.94, y, 0.05), marking if rib_index == 2 else accent, geometry, 0.06))
        # Recessed cyan hull telemetry strips.
        for strip_index, y in enumerate((-15.0, -8.0, -1.0, 6.0), start=1):
            objects.append(box(f"{side_name}TelemetryStrip{strip_index:02d}", (0.16, 3.4, 0.18), (side * 11.99, y, 0.55), emission, geometry, 0.025))

    # A hooked keel balances the tall sensor crown and protects the ventral battery.
    objects.append(tapered_prism("VentralKeel", 41.0, 2.0, 5.4, 1.65, (0.0, -2.5, -5.05), accent, geometry, 0.2))
    objects.append(tapered_prism("KeelArmorBlade", 26.0, 0.65, 2.3, 0.42, (0.0, 1.0, -5.78), marking, geometry, 0.08))
    objects.append(tapered_prism("ResoluteDorsalDeck", 36.0, 7.6, 12.8, 0.55, (0.0, 1.5, 4.45), accent, geometry, 0.16))

    # Low armored bow terraces keep the silhouette predatory rather than aircraft-like.
    objects.append(tapered_prism("BowArmorTerrace", 18.0, 1.2, 13.4, 0.9, (0.0, 22.6, 2.9), hull, geometry, 0.18))
    objects.append(tapered_prism("BowSensorBlade", 15.0, 0.35, 4.2, 0.38, (0.0, 24.5, 3.47), marking, geometry, 0.08))
    for side in (-1.0, 1.0):
        objects.append(box("BowRunningLight", (1.7, 0.18, 0.2), (side * 2.4, 31.35, 0.42), emission, geometry, 0.03))
        objects.append(tapered_prism("BowCheekArmor", 12.5, 0.7, 4.2, 1.15, (side * 4.9, 22.7, 0.8), hull, geometry, 0.14))

    # Identification bars are geometry so they survive the untextured compatibility renderer.
    objects.append(box("DorsalFleetStripe", (0.8, 20.0, 0.13), (0.0, -7.5, 4.87), marking, geometry, 0.03))
    for side in (-1.0, 1.0):
        objects.append(box("DorsalChevron", (2.8, 0.55, 0.13), (side * 2.25, -16.0, 4.89), marking, geometry, 0.04, (0.0, 0.0, math.radians(side * 28.0))))
    return objects


def build_command_citadel(materials, geometry: bpy.types.Collection) -> list[bpy.types.Object]:
    hull, accent, marking, emission = materials
    objects: list[bpy.types.Object] = []
    objects.append(tapered_prism("CommandCitadelLower", 10.0, 5.6, 8.4, 1.45, (0.0, -10.0, 4.45), hull, geometry, 0.18))
    objects.append(tapered_prism("CommandCitadelUpper", 7.5, 3.2, 5.8, 0.9, (0.0, -10.4, 5.15), accent, geometry, 0.13))
    # Bridge window band, split into facets.
    for x in (-1.8, -0.6, 0.6, 1.8):
        objects.append(box("BridgeWindow", (0.82, 0.2, 0.24), (x, -14.08, 5.25), emission, geometry, 0.04))
    # Sensor crown: short, sturdy, and intentionally asymmetric.
    objects.append(cylinder("SensorMast", 0.28, 1.2, (-0.9, -8.2, 5.25), accent, geometry, vertices=12, chamfer=0.04))
    objects.append(box("SensorCrossbar", (3.0, 0.25, 0.22), (-0.9, -8.2, 5.78), marking, geometry, 0.04))
    for x in (-2.25, 0.45):
        objects.append(cylinder("SensorPod", 0.24, 0.35, (x, -8.2, 5.78), emission, geometry, rotation=(math.radians(90.0), 0.0, 0.0), vertices=12, chamfer=0.03))
    objects.append(box("ResoluteRangefinder", (1.4, 0.35, 0.75), (1.45, -9.1, 5.4), hull, geometry, 0.09, (0.0, math.radians(-12.0), 0.0)))
    # Two formation lights define the ship's roll at long range.
    for side in (-1.0, 1.0):
        objects.append(box("FormationBeacon", (0.18, 0.7, 0.18), (side * 4.6, -12.0, 4.74), emission, geometry, 0.03))
    return objects


def build_engines(materials, geometry: bpy.types.Collection) -> list[bpy.types.Object]:
    hull, accent, marking, emission = materials
    objects: list[bpy.types.Object] = []
    engine_positions = ((-5.7, -2.1), (5.7, -2.1), (-5.7, 2.1), (5.7, 2.1))
    for index, (x, z) in enumerate(engine_positions, start=1):
        objects.append(box(f"EngineFirebreak{index:02d}", (4.8, 6.8, 3.35), (x, -27.5, z), hull, geometry, 0.32))
        objects.append(cylinder(f"EngineCollar{index:02d}", 1.62, 1.3, (x, -31.45, z), accent, geometry, rotation=(math.radians(90.0), 0.0, 0.0), vertices=24, chamfer=0.12))
        objects.append(cylinder(f"EngineEmitter{index:02d}", 1.22, 0.18, (x, -32.28, z), emission, geometry, rotation=(math.radians(90.0), 0.0, 0.0), vertices=24, chamfer=0.02))
        objects.append(cylinder(f"EngineCore{index:02d}", 0.5, 0.22, (x, -32.39, z), marking, geometry, rotation=(math.radians(90.0), 0.0, 0.0), vertices=16, chamfer=0.02))
    # Central armored power spine and reactor-status lights.
    objects.append(box("SternPowerSpine", (2.8, 8.0, 8.8), (0.0, -27.6, 0.0), accent, geometry, 0.28))
    for z in (-2.4, 0.0, 2.4):
        objects.append(box("ReactorStatusLight", (0.34, 0.18, 0.34), (0.0, -31.7, z), emission, geometry, 0.05))
    return objects


def build_flak_batteries(materials, geometry: bpy.types.Collection) -> list[bpy.types.Object]:
    hull, accent, marking, emission = materials
    objects: list[bpy.types.Object] = []
    mounts = ((-7.2, -3.8, 4.65, False), (7.2, -0.3, 4.55, False), (0.0, 3.0, -4.9, True))
    for index, (x, y, z, inverted) in enumerate(mounts, start=1):
        rot = (0.0, 0.0, 0.0) if not inverted else (math.pi, 0.0, 0.0)
        battery_name = f"ResoluteDorsalFlakBattery{index - 1:02d}" if not inverted else "ResoluteVentralFlakBattery"
        objects.append(cylinder(battery_name, 1.05, 0.52, (x, y, z), hull, geometry, rotation=rot, vertices=12, chamfer=0.1))
        cap_z = z + (-0.38 if inverted else 0.38)
        objects.append(box(f"FlakTurretCap{index:02d}", (1.6, 1.85, 0.62), (x, y, cap_z), accent, geometry, 0.13))
        barrel_z = cap_z + (-0.22 if inverted else 0.22)
        for barrel_x in (-0.35, 0.35):
            objects.append(cylinder(f"FlakBarrel{index:02d}", 0.11, 2.6, (x + barrel_x, y + 2.05, barrel_z), marking, geometry, rotation=(math.radians(90.0), 0.0, 0.0), vertices=10, chamfer=0.025))
        objects.append(box(f"FlakOptic{index:02d}", (0.32, 0.34, 0.25), (x, y + 0.7, barrel_z + (-0.25 if inverted else 0.25)), emission, geometry, 0.05))
    return objects


def build_vls_frames(materials, geometry: bpy.types.Collection) -> list[bpy.types.Object]:
    hull, accent, marking, emission = materials
    objects: list[bpy.types.Object] = []
    for cell_index, (y, x) in enumerate(((y, x) for y in VLS_Y for x in VLS_X), start=1):
        # Four frame rails surround a black launch well. The well remains visible when the doors open.
        objects.append(box(f"VLS{cell_index:02d}FramePort", (0.22, 4.35, 0.3), (x - 1.78, y, 4.73), hull, geometry, 0.045))
        objects.append(box(f"VLS{cell_index:02d}FrameStarboard", (0.22, 4.35, 0.3), (x + 1.78, y, 4.73), hull, geometry, 0.045))
        objects.append(box(f"VLS{cell_index:02d}FrameFore", (3.35, 0.22, 0.3), (x, y + 2.18, 4.73), hull, geometry, 0.045))
        objects.append(box(f"VLS{cell_index:02d}FrameAft", (3.35, 0.22, 0.3), (x, y - 2.18, 4.73), hull, geometry, 0.045))
        objects.append(box(f"ResoluteMissileCompartment{cell_index - 1:02d}", (3.25, 4.0, 0.18), (x, y, 4.53), hull, geometry, 0.035))
        for light_y in (-1.65, 1.65):
            objects.append(box(f"VLS{cell_index:02d}ReadyLight", (0.18, 0.5, 0.12), (x - 1.82, y + light_y, 4.92), emission, geometry, 0.025))
        # White cell index bars are a functional deck marking, not decoration-only detail.
        objects.append(box(f"VLS{cell_index:02d}IndexBar", (0.55, 0.16, 0.12), (x + 1.82, y - 1.5, 4.92), marking, geometry, 0.02))
    return objects


def build_vls_animation(materials, animated: bpy.types.Collection) -> tuple[list[bpy.types.Object], list[bpy.types.Object]]:
    hull, accent, marking, emission = materials
    animated_objects: list[bpy.types.Object] = []
    missile_roots: list[bpy.types.Object] = []
    cells = [(x, y) for y in VLS_Y for x in VLS_X]
    for cell_index, ((x, y), start) in enumerate(zip(cells, VLS_START_FRAMES), start=1):
        z = 4.91
        left_pivot = add_empty(f"VLS_{cell_index:02d}_DoorPort_Hinge", (x - 1.68, y, z), animated, 0.35)
        right_pivot = add_empty(f"VLS_{cell_index:02d}_DoorStarboard_Hinge", (x + 1.68, y, z), animated, 0.35)
        left_door = box(f"VLS_{cell_index:02d}_DoorPort", (1.58, 4.05, 0.2), (0.0, 0.0, 0.0), accent, animated, 0.08)
        right_door = box(f"VLS_{cell_index:02d}_DoorStarboard", (1.58, 4.05, 0.2), (0.0, 0.0, 0.0), accent, animated, 0.08)
        left_door.parent = left_pivot
        left_door.location = (0.82, 0.0, 0.0)
        right_door.parent = right_pivot
        right_door.location = (-0.82, 0.0, 0.0)
        # Reinforcing bars on each door make their motion legible from the hero camera.
        for side_name, door, local_x in (("Port", left_door, 0.82), ("Starboard", right_door, -0.82)):
            stripe = box(f"VLS_{cell_index:02d}_{side_name}_WarningStripe", (0.16, 3.15, 0.08), (0.0, 0.0, 0.0), marking, animated, 0.025)
            stripe.parent = door
            stripe.location = ((-0.28 if local_x > 0 else 0.28), 0.0, 0.135)
            animated_objects.append(stripe)
        # Closed -> open -> hold through ignition -> closed after missile clears.
        for pivot, open_angle in ((left_pivot, -math.radians(108.0)), (right_pivot, math.radians(108.0))):
            key_rotation(pivot, 1, (0.0, 0.0, 0.0))
            key_rotation(pivot, start, (0.0, 0.0, 0.0))
            key_rotation(pivot, start + 9, (0.0, open_angle, 0.0))
            key_rotation(pivot, start + 35, (0.0, open_angle, 0.0))
            key_rotation(pivot, start + 45, (0.0, 0.0, 0.0))
            if pivot.animation_data and pivot.animation_data.action:
                pivot.animation_data.action.name = f"VLS_Launch_Cell_{cell_index:02d}_{pivot.name.split('_')[-2]}"
            set_interpolation(pivot, "BEZIER")
        animated_objects.extend((left_pivot, right_pivot, left_door, right_door))

        # Missile root remains below the hatch until doors are fully open.
        root = add_empty(f"VLS_{cell_index:02d}_Missile_Root", (x, y, 1.85), animated, 0.55)
        root["launch_frame"] = start + 13
        root["vls_cell"] = cell_index
        missile_roots.append(root)
        body = cylinder(f"Missile_{cell_index:02d}_Body", 0.44, 3.05, (x, y, 1.85), hull, animated, vertices=20, chamfer=0.055)
        nose = cone(f"Missile_{cell_index:02d}_Nose", 0.44, 0.06, 1.18, (x, y, 3.96), marking, animated, vertices=20)
        motor = cylinder(f"Missile_{cell_index:02d}_Motor", 0.34, 0.5, (x, y, 0.08), accent, animated, vertices=16, chamfer=0.04)
        band = cylinder(f"Missile_{cell_index:02d}_GuidanceBand", 0.47, 0.28, (x, y, 2.65), emission, animated, vertices=20, chamfer=0.025)
        for component in (body, nose, motor, band):
            parent_keep_transform(component, root)
            animated_objects.append(component)
        for fin_index, angle in enumerate((0.0, 90.0, 180.0, 270.0), start=1):
            rad = math.radians(angle)
            fin = box(
                f"Missile_{cell_index:02d}_Fin{fin_index:02d}",
                (0.12, 0.8, 0.9),
                (x + math.cos(rad) * 0.55, y + math.sin(rad) * 0.55, 0.65),
                marking,
                animated,
                0.025,
                rotation=(0.0, 0.0, rad),
            )
            parent_keep_transform(fin, root)
            animated_objects.append(fin)
        flame = cone(f"Missile_{cell_index:02d}_Exhaust", 0.62, 0.12, 2.6, (x, y, -1.65), emission, animated, vertices=20)
        parent_keep_transform(flame, root)
        key_scale(flame, 1, (0.001, 0.001, 0.001))
        key_scale(flame, start + 11, (0.001, 0.001, 0.001))
        key_scale(flame, start + 13, (1.0, 1.0, 1.0))
        key_scale(flame, start + 36, (0.7, 0.7, 1.45))
        set_interpolation(flame, "LINEAR")
        animated_objects.append(flame)

        # Vertical cold-clear phase, then a visible pitch toward the bow.
        rest = (x, y, 1.85)
        key_location(root, 1, rest)
        key_location(root, start + 12, rest)
        key_location(root, start + 16, (x, y, 8.0))
        key_location(root, start + 27, (x, y + 1.5, 24.0))
        key_location(root, start + 43, (x, y + 17.0, 47.0))
        key_rotation(root, 1, (0.0, 0.0, 0.0))
        key_rotation(root, start + 18, (0.0, 0.0, 0.0))
        key_rotation(root, start + 43, (math.radians(-28.0), 0.0, 0.0))
        if root.animation_data and root.animation_data.action:
            root.animation_data.action.name = f"VLS_Launch_Cell_{cell_index:02d}_Missile"
        set_interpolation(root, "LINEAR")
        animated_objects.append(root)
    return animated_objects, missile_roots


def consolidate_static(objects: list[bpy.types.Object], collection: bpy.types.Collection) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    hull = bpy.context.object
    hull.name = "ISS_Resolute_Hull_LOD0"
    move_to_collection(hull, collection)

    old_materials = [slot.material for slot in hull.material_slots]
    polygon_materials = [old_materials[polygon.material_index] for polygon in hull.data.polygons]
    unique_materials: list[bpy.types.Material] = []
    for mat in old_materials:
        if mat not in unique_materials:
            unique_materials.append(mat)
    hull.data.materials.clear()
    for mat in unique_materials:
        hull.data.materials.append(mat)
    indices = {mat: index for index, mat in enumerate(unique_materials)}
    for polygon, mat in zip(hull.data.polygons, polygon_materials):
        polygon.material_index = indices[mat]
        polygon.use_smooth = False

    bpy.context.view_layer.objects.active = hull
    hull.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    hull.data.validate()
    hull.data.update()
    hull["ship_id"] = "iss_resolute"
    hull["lod"] = 0
    hull["role"] = "missile_frigate"
    hull["dimensions_m"] = "24 x 12 x 65"
    hull.select_set(False)
    return hull


def build_sockets(sockets: bpy.types.Collection) -> list[bpy.types.Object]:
    result: list[bpy.types.Object] = []
    cells = [(x, y) for y in VLS_Y for x in VLS_X]
    for index, (x, y) in enumerate(cells, start=1):
        socket = add_empty(f"socket_missile_{index:02d}", (x, y, 5.08), sockets, 0.75)
        socket["launch_axis"] = "+Z / Godot +Y"
        result.append(socket)
    for index, location in enumerate(((-7.2, -1.75, 5.1), (7.2, 1.75, 5.0), (0.0, 5.05, -5.55)), start=1):
        result.append(add_empty(f"socket_flak_{index:02d}", location, sockets, 0.7))
    for index, (x, z) in enumerate(((-5.7, -2.1), (5.7, -2.1), (-5.7, 2.1), (5.7, 2.1)), start=1):
        result.append(add_empty(f"socket_engine_{index:02d}", (x, -32.45, z), sockets, 0.7))
    for index, location in enumerate(((0.0, 25.0, 0.0), (-9.5, 2.0, 0.0), (8.5, -9.0, 0.0), (0.0, -25.0, 0.0)), start=1):
        result.append(add_empty(f"socket_damage_{index:02d}", location, sockets, 0.65))
    return result


def look_at(obj: bpy.types.Object, target=(0.0, 0.0, 0.0)) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def build_studio(materials, studio: bpy.types.Collection) -> tuple[bpy.types.Object, bpy.types.Object]:
    emission = materials[3]
    bpy.ops.object.camera_add(location=(58.0, 66.0, 39.0))
    hero_camera = bpy.context.object
    hero_camera.name = "Camera_Hero"
    hero_camera.data.lens = 55.0
    hero_camera.data.sensor_width = 36.0
    look_at(hero_camera, (0.0, 0.5, 0.5))
    move_to_collection(hero_camera, studio)

    bpy.ops.object.camera_add(location=(18.5, 12.5, 17.5))
    launch_camera = bpy.context.object
    launch_camera.name = "Camera_VLS_Closeup"
    launch_camera.data.lens = 58.0
    look_at(launch_camera, (0.0, 10.5, 4.6))
    move_to_collection(launch_camera, studio)

    for name, location, energy, color, size, target in (
        ("Key_Sunward", (25.0, 20.0, 45.0), 48000.0, (0.68, 0.82, 1.0), 18.0, (0.0, 4.0, 0.0)),
        ("Rim_Blue", (-32.0, -22.0, 18.0), 42000.0, (0.08, 0.38, 1.0), 16.0, (0.0, -8.0, 0.0)),
        ("Bow_Fill", (0.0, 45.0, -4.0), 14000.0, (0.35, 0.62, 1.0), 12.0, (0.0, 10.0, 0.0)),
        ("Camera_Fill", (48.0, 54.0, 30.0), 22000.0, (0.32, 0.54, 0.78), 24.0, (0.0, 0.0, 0.0)),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.color = color
        light.data.shape = "DISK"
        light.data.size = size
        look_at(light, target)
        move_to_collection(light, studio)

    # A restrained star volume is studio-only and never exported.
    star_mesh = bpy.data.meshes.new("StudioStarsMesh")
    star_vertices = []
    for index in range(96):
        angle = index * 2.399963
        radius = 52.0 + (index % 11) * 2.8
        star_vertices.append((math.cos(angle) * radius, math.sin(angle) * radius, ((index * 17) % 61) - 30.0))
    star_mesh.from_pydata(star_vertices, [], [])
    stars = bpy.data.objects.new("Studio_Starfield", star_mesh)
    studio.objects.link(stars)
    particle = stars.modifiers.new("StarNodes", "NODES")
    node_group = bpy.data.node_groups.new("StudioStarGeometry", "GeometryNodeTree")
    particle.node_group = node_group
    node_group.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    node_group.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    nodes = node_group.nodes
    links = node_group.links
    input_node = nodes.new("NodeGroupInput")
    output_node = nodes.new("NodeGroupOutput")
    ico = nodes.new("GeometryNodeMeshIcoSphere")
    ico.inputs["Radius"].default_value = 0.055
    ico.inputs["Subdivisions"].default_value = 1
    instance = nodes.new("GeometryNodeInstanceOnPoints")
    realize = nodes.new("GeometryNodeRealizeInstances")
    set_material = nodes.new("GeometryNodeSetMaterial")
    set_material.inputs["Material"].default_value = emission
    links.new(input_node.outputs["Geometry"], instance.inputs["Points"])
    links.new(ico.outputs["Mesh"], instance.inputs["Instance"])
    links.new(instance.outputs["Instances"], realize.inputs["Geometry"])
    links.new(realize.outputs["Geometry"], set_material.inputs["Geometry"])
    links.new(set_material.outputs["Geometry"], output_node.inputs["Geometry"])
    return hero_camera, launch_camera


def configure_scene() -> None:
    scene = bpy.context.scene
    scene.name = "ISS Resolute — VLS Launch Demonstration"
    scene.frame_start = 1
    scene.frame_end = FRAME_END
    scene.render.fps = 24
    # Blender 5.2 keeps the historic identifier even though the renderer is Eevee Next.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.55
    scene.render.image_settings.color_depth = "8"
    scene.world = bpy.data.worlds.new("EXODRIFT Deep Space")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.0015, 0.003, 0.008, 1.0)
    background.inputs["Strength"].default_value = 0.16
    scene["ship_id"] = "iss_resolute"
    scene["display_name"] = "ISS Resolute"
    scene["animation"] = "Six-cell VLS ripple launch"
    scene["coordinate_contract"] = "Blender +Y forward/+Z up; Godot -Z forward/+Y up"
    scene.timeline_markers.new("VLS_COLD", frame=1)
    for index, frame in enumerate(VLS_START_FRAMES, start=1):
        scene.timeline_markers.new(f"CELL_{index:02d}_DOORS", frame=frame)
        scene.timeline_markers.new(f"CELL_{index:02d}_LAUNCH", frame=frame + 13)


def add_blender_readme() -> None:
    text = bpy.data.texts.new("README_ISS_RESOLUTE.txt")
    text.write(
        "ISS RESOLUTE — BLENDER SOURCE\n"
        "================================\n\n"
        "24 m wide × 12 m high × 65 m long. Blender +Y is the bow; +Z is ship-up.\n"
        "The six-cell VLS ripple launch runs from frame 1 through 205 at 24 fps.\n"
        "Timeline markers identify every door-open and launch event.\n\n"
        "Collections:\n"
        "  MODEL/Geometry      joined static LOD0 hull\n"
        "  MODEL/Animated_VLS  split doors, missiles, and exhaust\n"
        "  MODEL/Sockets       runtime launch/weapon/VFX sockets\n"
        "  STUDIO              cameras, lights, and non-exported starfield\n\n"
        "Camera_Hero frames the complete ship. Camera_VLS_Closeup shows the mechanism.\n"
        "The GLB is exported with animation and without the STUDIO collection.\n"
    )


def model_bounds(model_objects: list[bpy.types.Object]) -> dict[str, list[float]]:
    scene = bpy.context.scene
    scene.frame_set(1)
    corners: list[Vector] = []
    for obj in model_objects:
        if obj.type != "MESH" or not obj.visible_get():
            continue
        corners.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    minimum = [min(corner[axis] for corner in corners) for axis in range(3)]
    maximum = [max(corner[axis] for corner in corners) for axis in range(3)]
    return {
        "min_blender_xyz": [round(value, 4) for value in minimum],
        "max_blender_xyz": [round(value, 4) for value in maximum],
        "size_blender_xyz": [round(maximum[axis] - minimum[axis], 4) for axis in range(3)],
    }


def mesh_triangles(obj: bpy.types.Object) -> int:
    return sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)


def export_and_report(model_collection: bpy.types.Collection, hull: bpy.types.Object, sockets: list[bpy.types.Object]) -> None:
    SOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

    bpy.ops.object.select_all(action="DESELECT")
    model_objects = list(model_collection.all_objects)
    for obj in model_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = hull
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_apply=True,
        export_extras=True,
        export_materials="EXPORT",
        export_animations=True,
        export_animation_mode="SCENE",
        export_anim_scene_split_object=False,
        export_nla_strips_merged_animation_name="VLS_Ripple_Launch",
    )
    mesh_objects = [obj for obj in model_objects if obj.type == "MESH"]
    report = {
        "ship_id": "iss_resolute",
        "display_name": "ISS Resolute",
        "role": "missile frigate",
        "blender_version": bpy.app.version_string,
        "blend": str(BLEND_PATH.relative_to(ROOT)),
        "glb": str(GLB_PATH.relative_to(ROOT)),
        "dimensions_contract_godot_xyz": [24.0, 12.0, 65.0],
        "bounds_frame_1": model_bounds(model_objects),
        "mesh_objects": len(mesh_objects),
        "vertices": sum(len(obj.data.vertices) for obj in mesh_objects),
        "polygons": sum(len(obj.data.polygons) for obj in mesh_objects),
        "triangles": sum(mesh_triangles(obj) for obj in mesh_objects),
        "materials": sorted({slot.material.name for obj in mesh_objects for slot in obj.material_slots if slot.material}),
        "animation": {
            "fps": scene.render.fps,
            "frame_start": scene.frame_start,
            "frame_end": scene.frame_end,
            "duration_seconds": round((scene.frame_end - scene.frame_start + 1) / scene.render.fps, 3),
            "vls_cells": 6,
            "door_type": "independent split armored hatch",
            "launch_order": list(range(1, 7)),
            "door_open_frames": list(VLS_START_FRAMES),
            "missile_ignition_frames": [frame + 13 for frame in VLS_START_FRAMES],
        },
        "sockets": sorted(socket.name for socket in sockets),
    }
    REPORT_PATH.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


def render_previews(hero_camera: bpy.types.Object, launch_camera: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.camera = hero_camera
    scene.frame_set(1)
    scene.render.filepath = str(PREVIEW_REST_PATH)
    bpy.ops.render.render(write_still=True)

    scene.camera = launch_camera
    scene.frame_set(VLS_START_FRAMES[0] + 14)
    scene.render.filepath = str(PREVIEW_LAUNCH_PATH)
    bpy.ops.render.render(write_still=True)

    scene.camera = hero_camera
    scene.frame_set(VLS_START_FRAMES[3] + 14)
    scene.render.filepath = str(PREVIEW_SALVO_PATH)
    bpy.ops.render.render(write_still=True)

    # Leave the source opening on the complete ship at its clean frame.
    scene.camera = hero_camera
    scene.frame_set(1)
    scene.render.filepath = ""
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))


def main() -> None:
    reset_scene()
    configure_scene()
    model = make_collection("MODEL")
    geometry = make_collection("Geometry", model)
    animated = make_collection("Animated_VLS", model)
    sockets_collection = make_collection("Sockets", model)
    studio = make_collection("STUDIO")
    materials = (
        material("Hull", (0.08, 0.125, 0.165, 1.0), 0.78, 0.34),
        material("Accent", (0.14, 0.27, 0.335, 1.0), 0.68, 0.28),
        material("Marking", (0.58, 0.72, 0.77, 1.0), 0.48, 0.3),
        material("Emission", (0.02, 0.58, 1.0, 1.0), 0.22, 0.2, 7.5),
    )
    static_parts: list[bpy.types.Object] = []
    primary_parts = build_primary_hull(materials, geometry)
    static_parts.extend(part for part in primary_parts if part.name != "ResoluteDorsalDeck")
    command_parts = build_command_citadel(materials, geometry)
    static_parts.extend(part for part in command_parts if part.name != "ResoluteRangefinder")
    static_parts.extend(build_engines(materials, geometry))
    vls_frame_parts = build_vls_frames(materials, geometry)
    static_parts.extend(part for part in vls_frame_parts if not part.name.startswith("ResoluteMissileCompartment"))
    hull = consolidate_static(static_parts, geometry)
    # Keep weapon assemblies named and separate for runtime recognition/tests.
    build_flak_batteries(materials, geometry)
    build_vls_animation(materials, animated)
    sockets = build_sockets(sockets_collection)
    hero_camera, launch_camera = build_studio(materials, studio)
    add_blender_readme()
    export_and_report(model, hull, sockets)
    render_previews(hero_camera, launch_camera)


if __name__ == "__main__":
    main()
