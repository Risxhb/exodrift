"""Build EXODRIFT's Blender-authored combat VFX, sky accents, and Raptor craft.

Run from the project root with Blender 5.2 or newer:
  blender --background --python tools/vfx/create_combat_effects.py

The script deliberately exports geometry rather than baked simulations. Godot owns
timing, faction colors, pooling, and reduced-flash behavior; Blender owns the
silhouettes, faceting, layered rings, and authored motion reference.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path.cwd().resolve()
VFX_ROOT = ROOT / "assets" / "vfx" / "combat"
SKY_ROOT = ROOT / "assets" / "vfx" / "skybox"
RAPTOR_ROOT = ROOT / "assets" / "ships" / "raptor"
BUILD_ROOT = ROOT / "build"


def ensure_dirs() -> None:
    for path in (
        VFX_ROOT / "source",
        SKY_ROOT,
        RAPTOR_ROOT / "source",
        BUILD_ROOT,
    ):
        path.mkdir(parents=True, exist_ok=True)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name: str, color: tuple[float, float, float, float], emission: float = 0.0,
             metallic: float = 0.0, roughness: float = 0.45) -> bpy.types.Material:
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    mat.surface_render_method = "DITHERED" if color[3] < 0.999 else "DITHERED"
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = color[3]
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def apply_transform(obj: bpy.types.Object) -> bpy.types.Object:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)
    return obj


def assign(obj: bpy.types.Object, mat: bpy.types.Material) -> bpy.types.Object:
    if obj.data and hasattr(obj.data, "materials"):
        obj.data.materials.append(mat)
    return obj


def join(name: str, objects: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    # Godot's runtime library loader extracts the Mesh resource from the GLB
    # node. Bake the active object's translation too so no authored offsets are
    # lost when that node transform is intentionally discarded.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return objects[0]


def cube(name: str, location: tuple[float, float, float], scale: tuple[float, float, float],
         mat: bpy.types.Material, bevel: float = 0.0) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (scale[0] * 0.5, scale[1] * 0.5, scale[2] * 0.5)
    apply_transform(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("EdgeBreak", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return assign(obj, mat)


def cone(name: str, location: tuple[float, float, float], radius1: float, radius2: float,
         depth: float, vertices: int, mat: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2,
                                    depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    return assign(obj, mat)


def torus(name: str, major: float, minor: float, mat: bpy.types.Material,
          scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
          rotation: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                    major_segments=64, minor_segments=6,
                                    rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    return assign(obj, mat)


def custom_mesh(name: str, vertices: list[tuple[float, float, float]], faces: list[tuple[int, ...]],
                mat: bpy.types.Material) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    assign(obj, mat)
    return obj


def create_missile(mats: dict[str, bpy.types.Material], nuclear: bool = False) -> bpy.types.Object:
    radius = 0.92 if nuclear else 0.62
    length = 9.0 if nuclear else 6.8
    body = cone("Body", (0.0, 0.0, -length * 0.04), radius * 0.96, radius * 0.78, length * 0.58, 16,
                mats["nuclear_hull"] if nuclear else mats["missile_hull"])
    nose = cone("Nose", (0.0, 0.0, -length * 0.385), radius * 0.78, 0.0, length * 0.24, 16,
                mats["nuclear_core"] if nuclear else mats["missile_tip"])
    shoulder = cone("GuidanceCollar", (0.0, 0.0, -length * 0.245), radius * 1.03,
                    radius * 1.03, length * 0.055, 16, mats["accent"])
    aft = cone("AftCasing", (0.0, 0.0, length * 0.285), radius * 1.02,
               radius * 0.82, length * 0.16, 16, mats["nuclear_hull"] if nuclear else mats["missile_hull"])
    nozzle = cone("Nozzle", (0.0, 0.0, length * 0.405), radius * 0.74, radius * 0.48,
                  length * 0.105, 16, mats["dark"])
    nozzle_ring = cone("NozzleRing", (0.0, 0.0, length * 0.355), radius * 0.86,
                       radius * 0.86, length * 0.045, 16, mats["accent"])
    components = [body, nose, shoulder, aft, nozzle, nozzle_ring]
    for side in (-1.0, 1.0):
        fin_vertices = [
            (side * radius * 0.66, -0.07, length * 0.17),
            (side * radius * (1.9 if nuclear else 1.72), -0.05, length * 0.34),
            (side * radius * 0.68, -0.05, length * 0.41),
            (side * radius * 0.66, 0.07, length * 0.17),
            (side * radius * (1.9 if nuclear else 1.72), 0.05, length * 0.34),
            (side * radius * 0.68, 0.05, length * 0.41),
        ]
        fin_faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
        components.append(custom_mesh(f"FinX{side}", fin_vertices, fin_faces, mats["accent"]))
    for side in (-1.0, 1.0):
        fin = cube(f"FinY{side}", (0.0, side * radius * 1.02, length * 0.31),
                   (0.12, radius * 1.45, length * 0.28), mats["accent"], 0.03)
        components.append(fin)
    result = join("NuclearTorpedo" if nuclear else "GuidedMissile", components)
    result["forward_axis"] = "-Z"
    result["effect_role"] = "nuclear" if nuclear else "missile"
    return result


def create_exhaust(mats: dict[str, bpy.types.Material], nuclear: bool = False) -> bpy.types.Object:
    """Layered, tapered exhaust authored along +Z (the missile's aft axis)."""
    hot = mats["nuclear_core"] if nuclear else mats["exhaust_hot"]
    plume = mats["nuclear_wake"] if nuclear else mats["exhaust"]
    length = 14.0 if nuclear else 8.5
    radius = 1.0 if nuclear else 0.62
    parts = [
        cone("HotPlume", (0.0, 0.0, length * 0.23), radius, radius * 0.16,
             length * 0.46, 16, hot),
        cone("SoftPlume", (0.0, 0.0, length * 0.46), radius * 0.72, 0.02,
             length * 0.92, 16, plume),
    ]
    for offset, ring_radius in ((0.08, radius * 0.95), (length * 0.31, radius * 0.46)):
        ring = torus("ExhaustPulse", ring_radius, max(0.035, radius * 0.07), hot,
                     (1.0, 1.0, 0.72))
        ring.location.z = offset
        parts.append(ring)
    result = join("NuclearExhaust" if nuclear else "MissileExhaust", parts)
    result["effect_role"] = "nuclear_exhaust" if nuclear else "missile_exhaust"
    return result


def create_shield(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0)
    shell = bpy.context.object
    shell.name = "ShieldLattice"
    shell.scale = (1.0, 0.68, 1.0)
    apply_transform(shell)
    wire = shell.modifiers.new("HexLattice", "WIREFRAME")
    wire.thickness = 0.034
    wire.use_replace = True
    wire.use_even_offset = True
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.modifier_apply(modifier=wire.name)
    assign(shell, mats["shield"])
    rings = [shell]
    for radius, thickness, tilt in ((0.48, 0.035, 0.0), (0.72, 0.022, 0.18), (0.94, 0.012, -0.14)):
        pulse = torus("ShieldImpactPulse", radius, thickness, mats["shield_hot"],
                      (1.0, 0.68, 1.0), (tilt, tilt * 0.42, 0.0))
        pulse.location = (0.0, -0.27, -0.06)
        rings.append(pulse)
    return join("ShieldLattice", rings)


def create_nuclear_core(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0)
    obj = bpy.context.object
    obj.name = "NuclearCore"
    for vertex in obj.data.vertices:
        co = vertex.co
        modulation = 1.0 + 0.12 * math.sin(co.x * 13.0 + co.y * 7.0) * math.cos(co.z * 11.0)
        vertex.co = co * modulation
    assign(obj, mats["nuclear_core"])
    return obj


def create_blast_core(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0)
    shell = bpy.context.object
    shell.name = "BlastCore"
    for index, vertex in enumerate(shell.data.vertices):
        direction = vertex.co.normalized()
        vertex.co *= 0.82 + 0.2 * math.sin(index * 2.399)
        if index % 7 == 0:
            vertex.co += direction * 0.22
    assign(shell, mats["blast_core"])
    rays = [shell]
    for angle in range(0, 360, 60):
        direction = Vector((math.cos(math.radians(float(angle))), math.sin(math.radians(float(angle))), 0.0))
        ray = cone("BlastRay", (0.0, 0.0, 0.0), 0.16, 0.0, 1.45, 8, mats["blast_hot"])
        ray.location = direction * 0.62
        ray.rotation_euler = Vector((0.0, 0.0, 1.0)).rotation_difference(direction).to_euler()
        apply_transform(ray)
        rays.append(ray)
    return join("BlastCore", rays)


def create_shockwave(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    rings = []
    for radius, thickness, tilt in ((0.68, 0.022, -0.035), (0.84, 0.047, 0.0), (1.04, 0.014, 0.052)):
        rings.append(torus("ShockLayer", radius, thickness, mats["shock"],
                           (1.0, 0.82, 1.0), (tilt, tilt * 0.32, tilt * 0.4)))
    return join("ShockwaveRing", rings)


def create_debris(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    verts = [(-0.72, -0.22, -0.82), (0.62, -0.34, -0.45), (0.38, 0.26, -0.12),
             (-0.28, 0.42, 0.92), (-0.58, 0.02, 0.34), (0.72, 0.08, 0.48)]
    faces = [(0, 1, 2), (0, 2, 4), (2, 3, 4), (2, 5, 3), (1, 5, 2), (0, 4, 3, 5, 1)]
    shard = custom_mesh("ArmorShard", verts, faces, mats["debris"])
    bevel = shard.modifiers.new("TornEdges", "BEVEL")
    bevel.width = 0.035
    bevel.segments = 1
    bpy.context.view_layer.objects.active = shard
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    seam = custom_mesh("MoltenFracture", [(-0.46, 0.03, -0.42), (0.42, 0.08, -0.18),
                                           (0.22, 0.14, 0.08), (-0.33, 0.11, 0.14)],
                       [(0, 1, 2, 3)], mats["debris_hot"])
    return join("ArmorShard", [shard, seam])


def create_warp(mats: dict[str, bpy.types.Material]) -> tuple[bpy.types.Object, bpy.types.Object, bpy.types.Object]:
    rings = []
    for radius, thickness, tilt in ((0.76, 0.064, -0.07), (0.93, 0.032, 0.045), (1.1, 0.014, 0.12)):
        rings.append(torus("WarpArc", radius, thickness, mats["warp"],
                           (1.0, 1.32, 1.0), (tilt, tilt * 0.6, 0.0)))
    warp_ring = join("WarpRing", rings)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.72)
    warp_core = bpy.context.object
    warp_core.name = "WarpCore"
    # Portal plane is XY, with depth along Z. This keeps the aperture facing the
    # camera after Godot's look_at(), instead of becoming a bright side-on sliver.
    warp_core.scale = (1.0, 1.28, 0.13)
    apply_transform(warp_core)
    assign(warp_core, mats["warp_core"])

    wake_parts = []
    for index in range(4):
        depth = 1.8 + index * 0.7
        part = cone("WakeLayer", (0.0, 0.0, depth * 0.48 + index * 0.18),
                    0.7 - index * 0.09, 0.04, depth, 20, mats["warp_wake"])
        part.scale = (1.0, 1.28, 1.0)
        apply_transform(part)
        wake_parts.append(part)
    warp_wake = join("WarpWake", wake_parts)
    return warp_ring, warp_core, warp_wake


def create_sky_accents(mats: dict[str, bpy.types.Material]) -> list[bpy.types.Object]:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0)
    moon = bpy.context.object
    moon.name = "SkyDistantMoon"
    assign(moon, mats["moon"])
    ring = torus("MoonRing", 1.55, 0.18, mats["moon_ring"], (1.0, 0.36, 1.0), (0.25, 0.0, -0.18))
    moon_asset = join("SkyDistantMoon", [moon, ring])

    asteroid_parts = []
    for index, (location, scale) in enumerate((
        ((0.0, 0.0, 0.0), 1.0), ((1.35, 0.3, -0.6), 0.48),
        ((-1.05, -0.42, 0.55), 0.36), ((0.7, -0.85, 1.15), 0.28),
    )):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=scale, location=location)
        rock = bpy.context.object
        rock.name = f"Asteroid{index:02d}"
        rock.scale = (1.0 + index * 0.11, 0.72 + index * 0.04, 0.86)
        apply_transform(rock)
        for vertex in rock.data.vertices:
            length = vertex.co.length
            if length > 0.0:
                vertex.co *= 1.0 + 0.14 * math.sin(vertex.co.x * 9.0 + vertex.co.z * 6.0)
        assign(rock, mats["asteroid"])
        asteroid_parts.append(rock)
    asteroid_asset = join("SkyAsteroidCluster", asteroid_parts)

    ribbon_parts = []
    for index in range(5):
        radius = 1.0 + index * 0.16
        ribbon_parts.append(torus("NebulaRibbonLayer", radius, 0.11 - index * 0.012,
                                  mats["nebula"], (2.4, 0.72, 1.0),
                                  (0.18 + index * 0.025, 0.12, index * 0.08)))
    ribbon_asset = join("SkyNebulaRibbon", ribbon_parts)
    return [moon_asset, asteroid_asset, ribbon_asset]


def export_selected(path: Path, objects: list[bpy.types.Object]) -> None:
    axis_matrix = Matrix.Rotation(math.pi / 2.0, 4, "X")
    for obj in objects:
        if obj.get("godot_axes_ready", False):
            continue
        if obj.type == "MESH":
            obj.data.transform(axis_matrix)
            obj.data.update()
        obj.location = axis_matrix @ obj.location
        obj["godot_axes_ready"] = True
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_render = False
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_cameras=False,
                              export_lights=False, export_animations=False)
    bpy.ops.object.select_all(action="DESELECT")


def set_key(obj: bpy.types.Object, frame: int, scale: tuple[float, float, float], hide: bool = False) -> None:
    obj.scale = scale
    obj.hide_render = hide
    obj.keyframe_insert("scale", frame=frame)
    obj.keyframe_insert("hide_render", frame=frame)


def duplicate_for_showcase(obj: bpy.types.Object, name: str, location: tuple[float, float, float]) -> bpy.types.Object:
    dup = obj.copy()
    dup.data = obj.data.copy()
    dup.name = name
    bpy.context.collection.objects.link(dup)
    dup.location = location
    return dup


def setup_render(camera_location: tuple[float, float, float], target: tuple[float, float, float],
                 output: Path, resolution: tuple[int, int] = (1280, 720)) -> bpy.types.Object:
    bpy.ops.object.camera_add(location=camera_location)
    camera = bpy.context.object
    camera.name = "ShowcaseCamera"
    camera.data.lens = 52
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    bpy.context.scene.render.engine = "BLENDER_EEVEE"
    bpy.context.scene.render.resolution_x = resolution[0]
    bpy.context.scene.render.resolution_y = resolution[1]
    bpy.context.scene.render.resolution_percentage = 100
    bpy.context.scene.render.image_settings.file_format = "PNG"
    bpy.context.scene.render.filepath = str(output)
    bpy.context.scene.render.film_transparent = False
    bpy.context.scene.world.color = (0.001, 0.003, 0.009)
    return camera


def build_vfx() -> dict[str, int]:
    clear_scene()
    mats = {
        "missile_hull": material("MissileHull", (0.07, 0.13, 0.17, 1.0), metallic=0.82, roughness=0.28),
        "missile_tip": material("MissileTip", (0.16, 0.58, 0.88, 1.0), emission=1.2, metallic=0.45, roughness=0.2),
        "nuclear_hull": material("NuclearHull", (0.06, 0.16, 0.2, 1.0), metallic=0.76, roughness=0.24),
        "nuclear_core": material("NuclearCore", (0.18, 0.82, 1.0, 0.94), emission=7.0, roughness=0.12),
        "accent": material("Accent", (0.2, 0.72, 0.94, 1.0), emission=1.6, metallic=0.38, roughness=0.22),
        "dark": material("Refractory", (0.018, 0.03, 0.04, 1.0), metallic=0.62, roughness=0.55),
        "exhaust_hot": material("ExhaustHot", (0.78, 0.94, 1.0, 0.92), emission=8.0, roughness=0.06),
        "exhaust": material("ExhaustPlume", (0.08, 0.5, 1.0, 0.34), emission=4.4, roughness=0.1),
        "nuclear_wake": material("NuclearWake", (0.05, 0.22, 1.0, 0.22), emission=4.8, roughness=0.1),
        "shield": material("ShieldField", (0.05, 0.52, 1.0, 0.38), emission=5.0, roughness=0.12),
        "shield_hot": material("ShieldImpact", (0.58, 0.94, 1.0, 0.72), emission=8.0, roughness=0.08),
        "shock": material("Shockwave", (0.22, 0.76, 1.0, 0.58), emission=6.0, roughness=0.1),
        "blast_core": material("BlastCore", (1.0, 0.34, 0.045, 0.86), emission=6.8, roughness=0.08),
        "blast_hot": material("BlastHot", (1.0, 0.9, 0.54, 0.96), emission=9.0, roughness=0.04),
        "debris": material("ArmorDebris", (0.12, 0.18, 0.21, 1.0), metallic=0.84, roughness=0.43),
        "debris_hot": material("ArmorFracture", (1.0, 0.22, 0.025, 0.92), emission=6.4, roughness=0.12),
        "warp": material("WarpAperture", (0.18, 0.72, 1.0, 0.64), emission=7.5, roughness=0.08),
        "warp_core": material("WarpCore", (0.72, 0.94, 1.0, 0.46), emission=9.0, roughness=0.04),
        "warp_wake": material("WarpWake", (0.08, 0.28, 0.92, 0.22), emission=4.2, roughness=0.12),
        "moon": material("Moon", (0.08, 0.13, 0.22, 1.0), emission=0.15, metallic=0.08, roughness=0.78),
        "moon_ring": material("MoonRing", (0.24, 0.42, 0.56, 0.58), emission=0.5, roughness=0.66),
        "asteroid": material("Asteroid", (0.09, 0.075, 0.07, 1.0), metallic=0.22, roughness=0.84),
        "nebula": material("NebulaRibbon", (0.22, 0.08, 0.46, 0.16), emission=2.4, roughness=0.18),
    }
    missile = create_missile(mats)
    nuke = create_missile(mats, True)
    missile_exhaust = create_exhaust(mats)
    nuclear_exhaust = create_exhaust(mats, True)
    shield = create_shield(mats)
    core = create_nuclear_core(mats)
    blast_core = create_blast_core(mats)
    shockwave = create_shockwave(mats)
    debris = create_debris(mats)
    warp_ring, warp_core, warp_wake = create_warp(mats)
    sky_objects = create_sky_accents(mats)
    vfx_objects = [missile, nuke, missile_exhaust, nuclear_exhaust, shield, core, blast_core,
                   shockwave, debris, warp_ring, warp_core, warp_wake]

    export_selected(VFX_ROOT / "combat_effects_library.glb", vfx_objects)
    export_selected(SKY_ROOT / "skybox_accents.glb", sky_objects)

    for obj in vfx_objects + sky_objects:
        obj.hide_render = True
    positions = {
        missile: (-5.2, 0.0, 1.4), nuke: (-2.0, 0.0, 1.2), shield: (1.6, 0.0, 1.1),
        core: (5.0, 0.0, 1.2), shockwave: (5.0, 0.0, 1.2), debris: (1.7, 0.0, -2.2),
        warp_ring: (-3.8, 0.0, -2.1), warp_core: (-3.8, 0.0, -2.1), warp_wake: (-3.8, 0.0, -2.1),
    }
    showcase = []
    for source, location in positions.items():
        dup = duplicate_for_showcase(source, f"ANIM_{source.name}", location)
        dup.hide_render = False
        showcase.append(dup)
    for obj in showcase:
        if "Shockwave" in obj.name:
            set_key(obj, 1, (0.08, 0.08, 0.08)); set_key(obj, 30, (2.0, 2.0, 2.0)); set_key(obj, 60, (3.4, 3.4, 3.4))
        elif "WarpRing" in obj.name:
            set_key(obj, 1, (0.05, 0.05, 0.05)); set_key(obj, 24, (2.0, 2.0, 2.0)); set_key(obj, 60, (0.12, 0.12, 0.12))
        elif "WarpCore" in obj.name:
            set_key(obj, 1, (0.05, 0.05, 0.05)); set_key(obj, 24, (1.4, 1.4, 1.4)); set_key(obj, 60, (0.04, 0.04, 0.04))
        elif "Shield" in obj.name:
            set_key(obj, 1, (0.25, 0.25, 0.25)); set_key(obj, 18, (1.6, 1.6, 1.6)); set_key(obj, 60, (2.15, 2.15, 2.15))
        elif "NuclearCore" in obj.name:
            set_key(obj, 1, (0.1, 0.1, 0.1)); set_key(obj, 22, (1.6, 1.6, 1.6)); set_key(obj, 60, (2.7, 2.7, 2.7))
    setup_render((0.0, -19.0, 2.8), (0.0, 0.0, -0.4), BUILD_ROOT / "authored-vfx-showcase.png")
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 60
    bpy.context.scene.frame_set(24)
    bpy.ops.wm.save_as_mainfile(filepath=str(VFX_ROOT / "source" / "combat_effects.blend"))
    bpy.ops.render.render(write_still=True)
    triangles = sum(max(0, len(poly.vertices) - 2) for obj in vfx_objects if obj.type == "MESH" for poly in obj.data.polygons)
    return {"vfx_triangles": triangles, "vfx_objects": len(vfx_objects), "sky_objects": len(sky_objects)}


def build_raptor() -> dict[str, int]:
    clear_scene()
    hull = material("Hull", (0.055, 0.11, 0.145, 1.0), metallic=0.78, roughness=0.34)
    accent = material("Accent", (0.12, 0.43, 0.62, 1.0), metallic=0.56, roughness=0.3)
    marking = material("Marking", (0.6, 0.82, 0.88, 1.0), emission=0.55, metallic=0.28, roughness=0.36)
    emission = material("Emission", (0.05, 0.64, 1.0, 1.0), emission=7.0, roughness=0.12)

    body_verts = [
        (-0.24, -0.36, -4.0), (0.24, -0.36, -4.0), (0.0, 0.12, -4.0),
        (-0.72, -0.52, 2.7), (0.72, -0.52, 2.7), (-0.58, 0.52, 2.7), (0.58, 0.52, 2.7),
        (-0.48, -0.38, 4.0), (0.48, -0.38, 4.0), (-0.4, 0.38, 4.0), (0.4, 0.38, 4.0),
    ]
    body_faces = [(0, 1, 2), (0, 3, 4, 1), (2, 6, 5), (0, 2, 5, 3), (1, 4, 6, 2),
                  (3, 5, 9, 7), (4, 8, 10, 6), (5, 6, 10, 9), (3, 7, 8, 4), (7, 9, 10, 8)]
    body = custom_mesh("FighterFuselage", body_verts, body_faces, hull)

    craft_objects = [body]
    for side, suffix in ((-1.0, "L"), (1.0, "R")):
        sx = side
        verts = [(sx * 0.42, -0.10, -1.0), (sx * 3.0, -0.08, 1.35), (sx * 2.1, -0.08, 2.45),
                 (sx * 0.56, -0.10, 2.65), (sx * 0.42, 0.10, -1.0), (sx * 3.0, 0.08, 1.35),
                 (sx * 2.1, 0.08, 2.45), (sx * 0.56, 0.10, 2.65)]
        faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        wing = custom_mesh("SweptWing" if side < 0 else "SweptWing_R", verts, faces, hull)
        craft_objects.append(wing)
        edge = cube("InterceptorLeadingEdge" if side < 0 else "InterceptorLeadingEdge_R",
                    (sx * 1.65, 0.13, 0.75), (2.45, 0.07, 0.18), marking, 0.02)
        edge.rotation_euler[1] = sx * math.radians(38.0)
        apply_transform(edge)
        craft_objects.append(edge)

    canopy_verts = [(-0.42, 0.48, -2.1), (0.42, 0.48, -2.1), (-0.55, 0.48, -0.35), (0.55, 0.48, -0.35),
                    (-0.22, 1.1, -1.65), (0.22, 1.1, -1.65), (-0.3, 0.92, -0.5), (0.3, 0.92, -0.5)]
    canopy_faces = [(0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5), (4, 5, 7, 6), (0, 2, 3, 1)]
    craft_objects.append(custom_mesh("CanopyOrSensorShroud", canopy_verts, canopy_faces, accent))
    craft_objects.append(cube("VentralKeel", (0.0, -0.83, 1.15), (0.34, 0.54, 3.2), hull, 0.06))
    craft_objects.append(cube("CraftRecognitionMark", (0.0, 0.58, 1.15), (0.18, 0.04, 2.1), marking, 0.015))
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.36, depth=0.22, location=(0.0, 0.0, 3.88))
    engine = bpy.context.object
    engine.name = "FighterEngine"
    assign(engine, emission)
    craft_objects.append(engine)

    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 4.0))
    socket = bpy.context.object
    socket.name = "socket_engine_01"
    socket.empty_display_size = 0.3
    craft_objects.append(socket)

    export_selected(RAPTOR_ROOT / "raptor.glb", craft_objects)
    for obj in craft_objects:
        obj.hide_render = False
    setup_render((10.5, -12.0, 6.5), (0.0, -0.3, 0.0), BUILD_ROOT / "raptor-studio.png", (960, 720))
    bpy.ops.object.light_add(type="AREA", location=(4.0, -6.0, 7.0))
    bpy.context.object.data.energy = 900
    bpy.context.object.data.color = (0.4, 0.68, 1.0)
    bpy.context.object.data.shape = "DISK"
    bpy.context.object.data.size = 7.0
    bpy.ops.object.light_add(type="AREA", location=(-5.0, -4.0, 1.0))
    bpy.context.object.data.energy = 650
    bpy.context.object.data.color = (0.18, 0.55, 1.0)
    bpy.context.object.data.size = 5.0
    bpy.ops.wm.save_as_mainfile(filepath=str(RAPTOR_ROOT / "source" / "raptor.blend"))
    bpy.ops.render.render(write_still=True)
    triangles = sum(max(0, len(poly.vertices) - 2) for obj in craft_objects if obj.type == "MESH" for poly in obj.data.polygons)
    return {"raptor_triangles": triangles, "raptor_objects": len(craft_objects)}


def main() -> None:
    ensure_dirs()
    bpy.context.preferences.filepaths.save_version = 0
    vfx_report = build_vfx()
    raptor_report = build_raptor()
    report = {
        "blender_version": bpy.app.version_string,
        "coordinate_contract": "+Y up, -Z forward, meters",
        **vfx_report,
        **raptor_report,
        "outputs": [
            str((VFX_ROOT / "source" / "combat_effects.blend").relative_to(ROOT)),
            str((VFX_ROOT / "combat_effects_library.glb").relative_to(ROOT)),
            str((SKY_ROOT / "skybox_accents.glb").relative_to(ROOT)),
            str((RAPTOR_ROOT / "source" / "raptor.blend").relative_to(ROOT)),
            str((RAPTOR_ROOT / "raptor.glb").relative_to(ROOT)),
        ],
    }
    (VFX_ROOT / "build_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("EXODRIFT_VFX_BUILD " + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
