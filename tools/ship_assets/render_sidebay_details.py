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
                upper.location.z = 2.35
                lower.location.z = -2.35
            else:
                upper.location.z = 8.0
                lower.location.z = -8.0


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
    detail_light("SternDetailKey", (75.0, -170.0, 72.0), (0.0, -106.0, 0.0), 420000.0, (0.68, 0.82, 1.0), 42.0)
    detail_light("SternDetailFill", (-72.0, -155.0, -18.0), (0.0, -106.0, 0.0), 220000.0, (0.12, 0.42, 1.0), 34.0)
    detail_light("HangarDetailKey", (135.0, 5.0, 82.0), (30.0, 12.0, 0.0), 390000.0, (0.72, 0.86, 1.0), 46.0)
    for side_name, side in (("Port", -1.0), ("Starboard", 1.0)):
        for gallery_name, center_y, _length in (("Forward", 43.5, 53.0), ("Aft", -20.0, 60.0)):
            detail_light(
                f"{side_name}{gallery_name}InteriorLight",
                (side * 30.0, center_y, 4.6),
                (side * 30.0, center_y, -4.2),
                75000.0,
                (0.12, 0.5, 1.0),
                18.0,
            )

    set_blast_doors_closed(False)
    render_view(camera, "cvn_sidebay_reference_hero_0001.png", (-220.0, 300.0, 142.0), (0.0, -5.0, 0.0), 60.0)
    render_view(camera, "cvn_sidebay_reference_top_0001.png", (0.0, 0.0, 720.0), (0.0, 0.0, 0.0), 60.0)
    render_view(camera, "cvn_sidebay_reference_side_0001.png", (430.0, 0.0, 24.0), (0.0, 0.0, 0.0), 62.0)
    render_view(camera, "cvn_sidebay_reference_bow_0001.png", (0.0, 285.0, 52.0), (0.0, 100.0, 0.0), 56.0)
    render_view(camera, "cvn_sidebay_reference_stern_0001.png", (0.0, -285.0, 52.0), (0.0, -104.0, 0.0), 56.0)
    render_view(camera, "cvn_sidebay_armored_engine_wall_0001.png", (92.0, -185.0, 58.0), (0.0, -105.0, 0.0), 64.0)
    render_view(camera, "cvn_sidebay_blast_doors_open_0001.png", (145.0, -105.0, 48.0), (30.0, 10.0, 0.0), 62.0)
    set_blast_doors_closed(True)
    render_view(camera, "cvn_sidebay_blast_doors_closed_0001.png", (145.0, -105.0, 48.0), (30.0, 10.0, 0.0), 62.0)
    set_blast_doors_closed(False)


if __name__ == "__main__":
    main()
