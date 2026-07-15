# Navy gunmetal reference material

`source/navy_gunmetal_source.svg` is the editable, seamless base-color source.
The PNG PBR pack in `runtime/` is generated with:

```powershell
godot --headless --path . --script tools/ship_assets/rasterize_texture.gd -- `
  --input=res://assets/ships/materials/navy/source/navy_gunmetal_source.svg `
  --output=res://assets/ships/materials/navy/source/navy_gunmetal_source.png

python tools/ship_assets/build_pbr_maps.py `
  --input assets/ships/materials/navy/source/navy_gunmetal_source.png `
  --output-dir assets/ships/materials/navy/runtime `
  --name navy_gunmetal --roughness 0.44 --metallic 0.66 --normal-strength 1.7
```

This is the reference plumbing material and a readable dark-space Navy baseline. A hero
ship may replace its derived normal/ORM maps with baked or hand-authored maps
without changing the runtime contract.
