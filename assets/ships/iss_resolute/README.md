# ISS Resolute authored source

The Resolute is a Blender-authored 24 × 12 × 65 meter missile frigate. Its
silhouette combines a faceted spearhead bow, sacrificial broadside armor, a
ventral keel, a compact sensor crown, four armored drives, three flak batteries,
and a six-cell dorsal VLS bank.

Files:

- `source/iss_resolute.blend` — editable source, studio cameras, and animation.
- `iss_resolute.glb` — animated runtime model and socket hierarchy.
- `iss_resolute_visual_asset.tres` — enabled production manifest.
- `source/iss_resolute_preview_*.png` — rest, hatch-closeup, and salvo renders.
- `source/iss_resolute_report.json` — dimensions, budgets, sockets, and timing.

The Blender timeline contains the complete 205-frame, 24 fps ripple launch.
Each independent split hatch opens before ignition; its missile cold-clears
vertically, pitches toward the bow, and the bay reseals after clearance. The GLB
exports this as one `ISS Resolute — VLS Launch Demonstration` animation. At
runtime, `CombatShip` binds the six hatch pairs to the six missile sockets and
opens/reseals the matching cell for each gameplay launch.

Rebuild the asset deterministically:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background `
  --python tools/ship_assets/create_resolute_source.py
```
