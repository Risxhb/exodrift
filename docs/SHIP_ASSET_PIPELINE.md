# Authored ship asset pipeline

This pipeline replaces procedural ship visuals without coupling artwork to
weapons, collision, flight controls, or damage logic. A failed asset contract
always falls back to the existing model.

## Coordinate and scale contract

- Godot units are meters.
- `+Y` is up, `-Z` is the bow/forward direction, and `+Z` is aft.
- Place the model origin at the ship's center of mass.
- Apply transforms before export. Keep the manifest `model_scale` at `(1,1,1)`.
- Match `ShipDefinition.dimensions_m` within 3% on each axis.
- UV0 is the production material UV set. UV1 may be reserved for lightmaps.
- Export tangents, smooth/weighted normals, and named material slots.

## Per-ship layout

```text
assets/ships/cvn_sidebay/
  source/cvn_sidebay.blend
  source/texture-prompts.md
  textures/source/navy_gunmetal_source.png
  textures/runtime/navy_gunmetal_base_color.png
  textures/runtime/navy_gunmetal_normal.png
  textures/runtime/navy_gunmetal_orm.png
  textures/runtime/navy_gunmetal_material.json
  cvn_sidebay.glb
  cvn_sidebay_visual_asset.tres
```

The `.blend` source is recommended but not required by the runtime. The `.glb`,
runtime maps, and manifest are required.

## Geometry quality bar

Build detail in three readable scales:

1. Primary silhouette: bow, shoulders, flight galleries, engine mass, keel.
2. Secondary structure: armor courses, hangars, command island, weapon zones.
3. Tertiary surface: seams, vents, fasteners, restrained decals and wear.

Use real bevels or baked bevel normals on silhouette-facing edges. Join static
pieces where practical. Avoid coplanar layers, intersecting boxes that expose
z-fighting, and detail smaller than two pixels at the chase camera.

Starting budgets:

| Asset | LOD0 | Materials | LOD1 | LOD2 |
|---|---:|---:|---:|---:|
| Sidebay hero carrier | 100k triangles | 4 | 50% | 15% |
| Other capital ship | 60k triangles | 4 | 50% | 15% |
| Fighter or drone | 12k triangles | 3 | 50% | 15% |

Measure these in Godot; they are ceilings, not targets.

## Material contract

Name imported material slots so the manifest can replace them predictably:

- `Hull` — base armor.
- `Accent` — faction or ship-specific secondary plating.
- `Marking` — identification paint and decals.
- `Emission` — engines, windows, hangar and recognition lights.

`ShipPbrMaterial` uses these runtime maps:

- `_base_color.png`: sRGB color with no baked illumination.
- `_normal.png`: OpenGL tangent-space normal.
- `_orm.png`: red AO, green roughness, blue metallic.
- `_emission.png`: optional grayscale emission mask.

Keep texture sources and generation metadata. Generated color maps are design
inputs; normal, roughness, metallic, and AO must still be reviewed physically.

Build a baseline pack:

```powershell
python tools/ship_assets/build_pbr_maps.py `
  --input assets/ships/cvn_sidebay/textures/source/navy_gunmetal_source.png `
  --output-dir assets/ships/cvn_sidebay/textures/runtime `
  --name navy_gunmetal --roughness 0.40 --metallic 0.76
```

The exact image-generation prompt is in
[`assets/ships/_template/TEXTURE_PROMPTS.md`](../assets/ships/_template/TEXTURE_PROMPTS.md).

## Socket naming

Export empties as nodes whose names begin with `socket_`. Socket local `-Z`
points in the firing or launch direction; engine plumes extend toward local
`+Z`. Number repeated sockets with two digits so alphabetical order is stable.

Common sockets:

- `socket_engine_01`
- `socket_flak_01`
- `socket_missile_01`
- `socket_weapon_primary_01`
- `socket_damage_01`

Sidebay requires ten `socket_flak_` nodes, six `socket_engine_` nodes, three
`socket_bay_port_` nodes, three `socket_bay_starboard_` nodes, and one
`socket_bay_scout_` node. Resolute requires six `socket_missile_` and three
`socket_flak_` nodes. Fighters require one engine socket; Watcher drones require
two.

Each Sidebay `socket_flak_` node owns one linked instance of the reusable
twin-barrel `PDW_FlakCannon` mesh. Keep the cannon aimed along Blender local
`+Y` (Godot local `-Z`) so the existing flak director rotates the visible model.

The Sidebay's six drives are arranged as two armored three-engine stern banks.
Keep each `socket_engine_` just aft of its retaining ring and armored emitter
core so the runtime plume begins outside the blast collar. Engine armor must not
intersect the socket's exhaust axis.

## Activating a model

1. Export the GLB beside its manifest.
2. Copy `_template/ship_visual_asset.template.tres` and rename it.
3. Assign `model_scene`, exact dimensions, budgets, required socket names, and
   optional `ShipPbrMaterial` resources in the Godot inspector.
4. If `replace_imported_materials` is enabled, a complete hull PBR pack is
   mandatory. Imported slots are mapped by the names above.
5. Keep the manifest `enabled = false` during authoring. This allows validation
   and studio preview while the live game continues using the procedural fallback.
6. Validate before launching the game:

```powershell
godot --headless --path . --script tools/ship_assets/validate_ship_assets.gd
godot --headless --path . --script tests/run_ship_asset_pipeline_tests.gd
```

7. Check chase-camera, menu/archive, neutral studio, and combat-lighting renders.
8. Set `enabled = true` only after those reviews pass.
9. Re-run surface, readability, integration, menu, and performance suites.

Open the neutral Godot studio with `scenes/tools/ship_asset_studio.tscn`, or pass
`--asset=res://assets/ships/<id>/<id>_visual_asset.tres` after the Godot `--`
argument separator. The Sidebay Blender source can be rebuilt with:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background `
  --python tools/ship_assets/create_sidebay_source.py
```

## Acceptance checklist

- Silhouette remains recognizable at target and tactical-map distances.
- No texture seam, moire, z-fighting, inverted normal, or baked-light artifact.
- Dimensions, triangle/material budgets, and required sockets validate.
- Weapons, bays, engine trails, collision, damage VFX, menu, and archive work.
- Low/Medium/High profiles and the Web compatibility renderer remain readable.
- The procedural fallback still loads when the manifest is removed or rejected.
