# Matched building images

Captured in the populated seed-1703 worlds at 1920 × 1080, Godot 4.7.2 Forward+ on an RTX 4050 Laptop GPU. Each row uses matching cameras, lighting and original save. E2 is a candidate for approval. The images retain surrounding terrain and foliage defects. Neighbors change incrementally during the eight-lot pass; C1 uses the separate northern-district save. Full source paths, hashes, worlds and available camera coordinates are in [the manifest](images/manifest.json).

| Building / purpose | Approved R1 baseline | Proposed E2 |
| --- | --- | --- |
| Trader T1: aged brick, clay roof and timber ends | ![trader_t1 R1](images/trader_t1_R1.png) | ![trader_t1 E2](images/trader_t1_E2.png) |
| Town hall T1: finished coping, cornice and shallow hip canopy | ![town_hall_t1 R1](images/town_hall_t1_R1.png) | ![town_hall_t1 E2](images/town_hall_t1_E2.png) |
| Church C1: coursed limestone and slate from the street | ![church_c1 R1](images/church_c1_R1.png) | ![church_c1 E2](images/church_c1_E2.png) |
| School S2: lower library roof and complete taller-wall junction | ![school_s2 R1](images/school_s2_R1.png) | ![school_s2 E2](images/school_s2_E2.png) |
| Warehouse W1: continuous zinc on shell and gable slopes | ![warehouse_w1 R1](images/warehouse_w1_R1.png) | ![warehouse_w1 E2](images/warehouse_w1_E2.png) |
| Cottage A2: existing steps and silhouette with aged masonry and clay | ![cottage_a2 R1](images/cottage_a2_R1.png) | ![cottage_a2 E2](images/cottage_a2_E2.png) |
| Shop B2: slate thin roof and timber ends | ![shop_b2 R1](images/shop_b2_R1.png) | ![shop_b2 E2](images/shop_b2_E2.png) |
| Shop B1: all four existing hip directions preserved | ![shop_b1 R1](images/shop_b1_R1.png) | ![shop_b1 E2](images/shop_b1_E2.png) |
| House C1: preserved garage, balcony and cellar under aged brick/slate | ![house_c1 R1](images/house_c1_R1.png) | ![house_c1 E2](images/house_c1_E2.png) |

## Assembly, player travel and material detail

Final E2 cornice corner intact; coping runs continuously above it.

![Final E2 cornice corner intact; coping runs continuously above it.](images/corner_intact.png)

One independently addressable cornice corner removed; other cells remain.

![One independently addressable cornice corner removed; other cells remain.](images/corner_removed.png)

Exact styled corner restored by undo.

![Exact styled corner restored by undo.](images/corner_restored.png)

The school roof underside uses timber; slate remains on the upward faces.

![The school roof underside uses timber; slate remains on the upward faces.](images/school_underside.png)

C1 basement: preserved stairs, floor and partition doors.

![C1 basement: preserved stairs, floor and partition doors.](images/house_basement.png)

Trader clay roof at the 2 m comparison camera, 512-pixel runtime array.

![Trader clay roof at the 2 m comparison camera, 512-pixel runtime array.](images/roof_512.png)

Same clay roof and camera, 1024-pixel comparison array.

![Same clay roof and camera, 1024-pixel comparison array.](images/roof_1024.png)

Actual player at the start of the 221.22 m street traverse; no later teleport.

![Actual player at the start of the 221.22 m street traverse; no later teleport.](images/travel_far.png)

Actual player after the street traverse; no readiness holds or unsupported fall.

![Actual player after the street traverse; no readiness holds or unsupported fall.](images/travel_near.png)

Rejected E1 procedural art, preserved as historical evidence; not the current proposal.

![Rejected E1 procedural art, preserved as historical evidence; not the current proposal.](images/rejected_E1.png)

Searchable shape families with baked orientation and assembly previews; prior UI pass, unchanged behavior.

![Searchable shape families with baked orientation and assembly previews; prior UI pass, unchanged behavior.](images/palette.png)

The 20 m material-study cameras are obstructed by foliage and do not establish a distant-resolution benefit. The 2 m and 8 m views support retaining 512 pixels; the additional 1024 array costs 42.69 MiB while resident. Screenshot HUD FPS includes image-readback pauses and is not the frame-timing measurement.
