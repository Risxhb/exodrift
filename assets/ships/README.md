# EXODRIFT authored ship assets

Each production ship lives in `assets/ships/<ship_id>/` and is activated by one
file named `<ship_id>_visual_asset.tres`. Until that manifest exists and passes
validation, the game uses its current procedural model.

Copy the files in `_template/` to begin a ship. The complete modeling, texture,
socket, budget, preview, and validation contract is in
[`docs/SHIP_ASSET_PIPELINE.md`](../../docs/SHIP_ASSET_PIPELINE.md).

Do not commit generated Godot `.import` files by hand. Commit the source image,
runtime texture maps, `.glb`, manifest, and—when available—the `.blend` source.
