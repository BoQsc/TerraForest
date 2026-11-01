# Original seated and lying sleeper animations

Six original R4-compatible clips, authored 2026-11-01. Status: animation asset
checkpoint, not playable sleeper/POI integration or user visual approval.

| Clip | Seconds | Exit |
| --- | ---: | --- |
| Zombie_Sleep_Seated | 4.0 | Loop |
| Zombie_Sleep_Lying | 4.0 | Loop |
| Zombie_Wake_Seated | 3.2 | Original standing idle |
| Zombie_Wake_Lying | 4.2 | Original standing idle |
| Zombie_Wake_Seated_Crawl | 2.8 | Original crawling idle |
| Zombie_Wake_Lying_Crawl | 2.6 | Original crawling idle |

The seated wake lifts the head, leans forward, brings the feet underneath and
rises. The lying wake rolls toward its hands, tucks a knee and rises. The seated
crawl exit swings the legs around instead of interpolating them through the floor;
the lying crawl exit raises/repositions its palms before entering the existing
prone idle. These are authored poses/IK trajectories, not reversed death clips.
The standing/crawling endpoints deliberately match the inherited idle pose exactly.

The editable blend retains the source rig and character geometry. The intermediate
GLB exports only a minimal skin map and six actions; the compact runtime AnimationLibrary
contains pose data and seven neutral morph-reset tracks, not a duplicate model.
The converter validates all 59 rest bones, reduces keys, and bakes actual native
skinned bounds at 60 samples/second into padded 12-Hz groups. The table is for the
forthcoming bounded physical-clearance handshake; it is not itself a collision
test or permission to stand through ceilings. The animation cannot move the world root.

Rebuild from TerraForest, using the existing external Blender installation:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --disable-autoexec addons/characters/ZombieLab/source/Zombie.r4.blend --python tools/author_zombie_sleepers.py
python tools/check_zombie_sleepers.py import
python tools/check_zombie_sleepers.py poses
python tools/check_zombie_sleepers.py review
python tools/check_zombie_sleepers.py review --missing shin_l
python tools/check_zombie_sleepers.py review --missing forearm_l
python tools/check_zombie_sleepers.py review --motion
```

The review runner prints its report directory. For its optional 480-frame video:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --factory-startup --python tools/encode_zombie_sleepers_review.py -- --frames '<reported-directory>/frames'
```

Add `--pack` to pose/review commands after a matching export. All runners use
off-screen, nonactivating windows and disable pointer capture. Screenshots/encoding
are not frame-pacing benchmarks. Tests inspect every 60-Hz pose, flat-floor skin
clearance, root immobility, endpoint continuity, neutral morphs and baked bounds.
They do not qualify slopes, live hits/amputation during waking, moving obstacles,
sleep persistence or the native awareness-to-animation-to-body handshake.

Original contributions are CC0-1.0; authoring tools are 0BSD. Retained character
provenance is unchanged; see [the exact asset notice](../runtime/assets/Zombie.sleepers.LICENSE.txt)
and [the original character notice](../LICENSE.txt).
