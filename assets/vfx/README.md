# Blender-authored combat VFX

`combat/source/combat_effects.blend` is the editable source for the reusable
combat mesh library. Godot animates and pools these meshes so graphics quality,
faction palettes, and reduced-flash settings continue to work.

The library provides:

- guided missile and nuclear torpedo bodies;
- geodesic shield-hit lattice;
- layered conventional and nuclear shockwave rings;
- faceted blast core and torn armor/debris shard;
- distinct expanding warp-in and collapsing warp-out aperture/core/wake layers;
- a ringed moon, asteroid cluster, and nebula ribbon for the tiered skybox.

Coordinate contract: meters, `+Y` up, `-Z` forward. The generated VFX library
contains 11,548 triangles and the Raptor contains 546 triangles.

Rebuild:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background `
  --python tools/vfx/create_combat_effects.py
```

Preview renders are written to `build/authored-vfx-showcase.png` and
`build/raptor-studio.png`. The checked-in
`reference/authored-vfx-runtime.png` is the GL Compatibility runtime proof.
