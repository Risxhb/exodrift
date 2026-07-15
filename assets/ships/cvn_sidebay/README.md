# CVN Sidebay authored source

`source/cvn_sidebay.blend` and `cvn_sidebay.glb` are rebuilt deterministically:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background `
  --python tools/ship_assets/create_sidebay_source.py
```

The current source is an authoring foundation: coherent dimensions, beveled
primary/secondary forms, UVs, four production material classes, studio lighting,
and every required runtime socket. It also contains one reusable twin-barrel
`PDW_FlakCannon` model linked into all ten flak sockets, allowing every visible
cannon to track the existing Godot flak director independently. The six drives
are recessed into two three-engine stern cassettes with armored cheeks, caps,
blast baffles, retaining rings, protected emitter cores, and a central isolation
keel; their sockets sit beyond the nozzle lips so runtime plumes do not clip the
armor. The manifest remains disabled until a visual review confirms that it is a
quality improvement at chase-camera distance.
