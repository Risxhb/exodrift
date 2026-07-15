# Texture-generation prompts

Use this base-color prompt with the built-in image generator, changing only the
faction material language. Generated output is a source—not a complete PBR set.
Run it through `tools/ship_assets/build_pbr_maps.py`, inspect the tile, then edit
or supply proper AO/roughness/metallic masks when the derived maps are not
physically convincing.

## Navy gunmetal base color

```text
Use case: stylized-concept
Asset type: seamless tileable game texture; spacecraft hull base-color source
Primary request: dark naval gunmetal armor panels for a massive military spacecraft
Style/medium: realistic hard-surface game material; flat diffuse albedo map
Composition/framing: orthographic square texture; broad modular plates at two scales; seamless on every edge
Color palette: charcoal blue-gray steel with restrained cool cyan identification paint
Materials/textures: subtle coating variation, recessed seams, sparse fasteners, restrained service wear, no corrosion
Constraints: no baked lighting; no directional highlights; no shadows; no perspective; no deep cavities; no text; no numbers; no logos; no emission; no watermark; no obvious focal element; no dense high-frequency noise; edges must tile seamlessly
Avoid: checkerboard repetition, photobashed machinery, random greeble soup, bright scratches, dramatic light, embossed lettering
```

Faction variants should preserve the same constraints:

- Acheron: welded iron armor, warmer oxidized undertone, rougher coating.
- Vesper: dark ceramic-metal facets, polished response, restrained magenta phase channels generated separately as an emission mask.
- Crucible: basalt composite carapace, broad fractured plates, violet alloy inclusions, no literal stone cracks at gameplay scale.
