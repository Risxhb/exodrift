# Raptor strike craft

The production Raptor is a Blender-authored 6 × 2.2 × 8 meter strike craft.
Its local `-Z` axis is forward and `socket_engine_01` sits at the aft `+Z`
boundary. The runtime retains ownership of flight, weapons, collision, damage,
faction color trails, and loadouts.

Files:

- `source/raptor.blend` — editable source and studio camera.
- `raptor.glb` — runtime mesh used by `raptor_visual_asset.tres`.
- `raptor_visual_asset.tres` — enabled production manifest.
- `reference/raptor-studio.png` — Blender studio reference render.

Rebuild it together with the combat effects:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background `
  --python tools/vfx/create_combat_effects.py
```
