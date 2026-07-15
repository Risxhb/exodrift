"""Render reproducible Sidebay engine and blast-door review views in Blender."""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path.cwd()
BUILD_ROOT = ROOT / "build"


def look_at(obj: bpy.types.Object, target) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def detail_light(name: str, location, target, energy: float, color, size: float) -> None:
    light = bpy.data.objects.get(name)
    if light is None:
        data = bpy.data.lights.new(name, "AREA")
        light = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(light)
    light.location = location
    light.data.energy = energy
    light.data.color = color
    light.data.shape = "DISK"
    light.data.size = size
    look_at(light, target)


def render_view(camera, filename: str, location, target, lens: float) -> None:
    camera.location = location
    camera.data.lens = lens
    camera.data.clip_end = 3000.0
    look_at(camera, target)
    scene = bpy.context.scene
    scene.render.filepath = str(BUILD_ROOT / filename)
    bpy.ops.render.render(write_still=True)


def set_blast_doors_closed(closed: bool) -> None:
    for side in ("port", "starboard"):
        for bay_index in range(1, 4):
            upper = bpy.data.objects.get(f"blastdoor_{side}_{bay_index:02d}_upper")
            lower = bpy.data.objects.get(f"blastdoor_{side}_{bay_index:02d}_lower")
            if upper is None or lower is None:
                continue
            if closed:
                upper.location.z = 3.0
                lower.location.z = -3.0
            else:
                upper.location.z = 10.25
                lower.location.z = -10.25


def main() -> None:
    BUILD_ROOT.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.exposure = -0.35
    if scene.world is not None and scene.world.use_nodes:
        background = scene.world.node_tree.nodes.get("Background")
        if background is not None:
            background.inputs["Color"].default_value = (0.045, 0.052, 0.058, 1.0)
            background.inputs["Strength"].default_value = 0.24
    camera = bpy.data.objects.get("AuthoringCamera")
    if camera is None:
        raise RuntimeError("AuthoringCamera is missing from the Sidebay source scene")

    for light_name, energy in (("Key", 520000.0), ("Rim", 310000.0)):
        light = bpy.data.objects.get(light_name)
        if light is not None and light.type == "LIGHT":
            light.data.energy = energy
    detail_light("SternDetailKey", (110.0, -255.0, 94.0), (0.0, -174.0, 0.0), 520000.0, (0.68, 0.82, 1.0), 54.0)
    detail_light("SternDetailFill", (-100.0, -235.0, -24.0), (0.0, -174.0, 0.0), 270000.0, (0.12, 0.42, 1.0), 44.0)
    detail_light("HangarDetailKey", (180.0, 15.0, 100.0), (37.0, 15.0, 0.0), 480000.0, (0.72, 0.86, 1.0), 58.0)
    for side_name, side in (("Port", -1.0), ("Starboard", 1.0)):
        for gallery_name, center_y, _length in (("Forward", 90.0, 68.0), ("Midship", 20.0, 68.0), ("Aft", -56.0, 74.0)):
            detail_light(
                f"{side_name}{gallery_name}InteriorLight",
                (side * 37.0, center_y, 6.0),
                (side * 37.0, center_y, -5.8),
                92000.0,
                (0.12, 0.5, 1.0),
                22.0,
            )

    set_blast_doors_closed(False)
    render_view(camera, "cvn_sidebay_reference_hero_0001.png", (-330.0, 480.0, 220.0), (0.0, -8.0, 0.0), 58.0)
    render_view(camera, "cvn_sidebay_reference_top_0001.png", (0.0, 0.0, 1200.0), (0.0, 0.0, 0.0), 60.0)
    render_view(camera, "cvn_sidebay_reference_side_0001.png", (740.0, 0.0, 42.0), (0.0, 0.0, 0.0), 62.0)
    render_view(camera, "cvn_sidebay_reference_bow_0001.png", (0.0, 430.0, 78.0), (0.0, 164.0, 0.0), 56.0)
    render_view(camera, "cvn_sidebay_reference_stern_0001.png", (0.0, -430.0, 78.0), (0.0, -174.0, 0.0), 56.0)
    render_view(camera, "cvn_sidebay_armored_engine_wall_0001.png", (132.0, -305.0, 82.0), (0.0, -174.0, 0.0), 64.0)
    render_view(camera, "cvn_sidebay_blast_doors_open_0001.png", (195.0, -125.0, 72.0), (37.0, -15.0, 0.0), 62.0)
    set_blast_doors_closed(True)
    render_view(camera, "cvn_sidebay_blast_doors_closed_0001.png", (195.0, -125.0, 72.0), (37.0, -15.0, 0.0), 62.0)
    set_blast_doors_closed(False)


if __name__ == "__main__":
    main()
