# Temperate woodland sample

Original TerraForest authoring, 0BSD. No stock images, scanned assets, external
models or copied engine implementation are included in this set.

`woodland_mesh.gd` builds three shared assets at startup: a weathered stone,
seven-frond fern-like understory plant, and a 28-blade green/dry grass tuft.
`woodland.gdshader` supplies restrained vertex wind, leaf veins and lighting.
There is no per-instance script or animation node. The old `ground_mesh.gd`
remains the earlier prototype for comparisons, not the main-world asset source.

| Asset | Near triangles | Distant triangles |
| --- | ---: | ---: |
| Stone | 360 | 48 |
| Fern-like plant | 1512 | 392 |
| Grass tuft | 504 | 72 |

These costs are substantially higher than the prototypes. This is deliberate
visual development toward a representative workload, not a performance claim.
Keep actual final-asset density, GPU time and mixed-world qualification open.
This first sample is not final botanical art or full species/biome variety.

The stone colour and tangent-space normal maps are deterministic original
procedural textures. Regenerate with `python tools/bake_woodland_art.py` from
TerraForest. The `.trtex` files contain standard 256x256 RGB PNG data, loaded with
generated mipmaps, avoiding an editor-import requirement. Both maps together use
approximately 512 KiB of uncompressed RGB mipmap payload before backend format
padding/allocation. They are shared across stone instances.

Wind has a maximum local X displacement of0.012m and Z displacement of0.0066m,
weighted by height, with fixed roots. `custom_aabb` contains this deformation
inside the existing semantic interaction envelope. This keeps picking stable;
it is clump-envelope interaction, not per-leaf picking. Instance transforms scale
both the mesh and the envelope. No persistent data/schema changes are required.

Material wind defaults to1 and can be set to0 for deterministic image comparison.
The shader uses original vertex colours in linear space, opaque double-sided
geometry and modest backlighting; stone maps use sRGB colour and linear normals.
Plants/grass retain the existing disabled shadow-casting policy in ground cover.
Mesh LOD is selected by the engine per native draw page. No new density thinning,
manual LOD scheduler or custom renderer is introduced.

Next art decisions should follow a human view in the combined scene: silhouettes,
scale, colour, fine-blade aliasing, stone texture style, and useful species/shape
variants. The current population and coverage are not a finished forest floor.

The woodland mesh factory also authors three sparse flower colours, low bushes and
dry twig clusters. These are original 0BSD geometry; no external asset sources.
See `docs/evidence/woodland_accents` for interactions, rarity and save compatibility.
