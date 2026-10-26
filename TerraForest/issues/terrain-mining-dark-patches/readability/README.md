# Faint terrain readability — 2026-10-26

- Status: implemented and reproduced; latest visual result awaits player review.
- User decision: "Allow faint visibility even in enclosed caves."
- Parent: [terrain mining dark patches](../README.md); prior fixes remain intact.

## What changed

The terrain shader uses `max(0.12, sqrt(sky_visibility))` for its existing
texture-coloured fill. Only the lowest visibility values change; ordinary shading
at or above sky visibility 0.0144 is identical. This is not extra sunlight or GI.
Native baking/cache formats, density, real lights and canopy-shadow masks are
unchanged. No extra rays, render passes, textures or loading stages are added.
The material parameter `minimum_cave_fill=0` restores the previous appearance.

## Matched evidence

Hidden_Hills seed 1703, backup root; feet (986.9822, 38.99959, 1023.823), camera
(986.9822, 40.67959, 1023.823). The backup matches the report's camera and 41 stone /
11 topsoil inventory; the newer canonical root has further excavation and a
different player position. Source and packaged captures use copies and fresh
derived caches; all original root/sidecar hashes remain unchanged.

| Image | Meaning |
| --- | --- |
| [User report](images/reported.png) | Original pixels; reported build not independently recorded |
| [Before](images/before.png) | `86bf75b1`, headlamp off, backup reproduction |
| [After](images/after.png) | Installed package, faint fill, same density/camera, headlamp off |
| [Headlamp](images/torch.png) | Same package, real shadow-casting lamp on |
| [Sun mask disabled](images/sun-mask-disabled.png) | Black patch persists; not a cached-sun-only problem |
| [Unoccluded sky](images/unoccluded-sky.png) | Rejected: removing sky occlusion brightens the recess too much |
| [Native diffuse trial](images/diffuse-trial.png) | Rejected: local 4 m probes leave the central black patch |

[Pixel provenance](images/manifest.json). Different copied-slot HUD labels/counts
are expected. Terrain density SHA-256 is identical before, source-after and
packaged-after: `766626cab14deb7e34b019dd687047b706126612a637f333e23beb000ff0e027`.

## Checks and rejected work

- Baseline `1de6944dc52d4d29`, source `f38bb1da1fa54805`, package
  `32d0afbaeab14f1a`: diagnostic captures pass; exact serialized terrain unchanged.
- Zero-light GPU control: old fill is black; default floor is faint; ordinary
  shaded and open-sky pixels are unchanged. Native source/DLLs restored to baseline.
- Packaged contact mining passes 137 assertions. Rendered endurance passes 1,200
  mixed edits plus 16 large-volume commands: frame p99 17.084 ms, maximum 24.491 ms,
  zero runtime frames over 50 ms. Finite RTX 4050 laptop workload, not universal
  performance acceptance; all prior intermittent render/focus stalls remain open.
- Dense diagnostic: of 23 nearby zero-sky vertices, 18 also have zero visibility
  in 256 rays. More directions alone cannot provide missing indirect light.
- Native 27-point diffuse trials at 2 m / 4 m spacing (`9eaa3fd55e84449b` /
  `3d8561c55b634961`) were visually insufficient and fully reverted. Their harness
  passes are not visual acceptance. The trial thin-roof assertion failed; its
  purported roof used zero-density air samples. A corrected negative-layer
  fixture was not rerun before discarding the entire prototype. No claim of a
  passing diffuse implementation or established production leak is made.
- Initial diagnostic `a832022763d74e90` failed on restoring a default shader
  parameter (`Nil` assigned to `bool`), then timed out. It now preserves a Variant.
  Latest-root/old-camera `bb8315e622234c79` passed but is not the reported geometry.
- Full per-run results and retained failures: [qualification](qualification.json)
  and compressed `logs/`. Temporary private saves are not committed.

## Reproduce / remaining

```text
python tools/check_mining_darkness.py --slot Hidden_Hills --backup --pack
python tools/check_terrain_editing.py --pack --case terrain_cave_readability --case terrain_contact_mining --case terrain_tools_endurance
```

Requires the local save and a freshly exported matching package. `--backup` uses
the previous root with its content-addressed sidecars, never restores over the
player slot. F5 is not a permanent checkpoint: autosave/save-and-quit can supersede
it. This backup happened to retain the report; future saves may replace it.
`--camera-from <scene.json>` allows an explicit previous diagnostic camera, but
does not restore the terrain at that earlier moment; label such comparisons.

Native occlusion remains approximate, not bounced GI. The floor intentionally
makes sealed terrain faintly visible; it does not brighten characters or all
objects. User review and broader material/cave/hardware qualification remain open.
Return on another dark-face report with matched albedo/raw-sky/lamp captures,
checking this floor before adding more bake cost. Existing render/focus-stall
investigation remains separate and unresolved.
