# Vehicle packs — API 1

The host now uses the same adapter boundary for Ranger and external vehicles.
`world_vehicle.gd` owns identity, entry/exit, persistence and bounded activation;
each body has its own adapter and its own physics controller. Adapters need not
inherit DrivingCar. Hot-path physics may live in an installed native extension;
GDScript is the host/mod bridge, not a mandatory physics implementation.

## Install and trust

Restart the game after changing packs. No automatic folder discovery or hot reload.
Only enable code you trust: scripts and native extensions are **not sandboxed**.
Manifests alone do not make executable code safe.

Place exported Godot resource packs beneath `user://mods/`. Enable them explicitly
in `user://mods/enabled.cfg` (on Windows, beneath the game's app_userdata folder):

```ini
[modules]
trusted_packs=PackedStringArray("user://mods/example/vehicles.pck")
trusted_manifests=PackedStringArray("res://mods/example/vehicles.module.json")
```

Loose `user://mods/.../*.module.json` manifests are also supported. Their resources
must be loadable by Godot. PCK exports are preferable for imported models/textures.
Packs mount with replacement disabled; use a unique `res://mods/<pack>/` namespace.
Native DLL distribution, ABI selection and dependency installation are not handled
by this loader; existing compatible installed GDExtensions can be wrapped.

## Manifest

```json
{
  "api": 1,
  "id": "example.vehicles",
  "providers": [{
    "capability": "vehicle",
    "id": "example.cart.v1",
    "name": "Example cart",
    "scene": "res://mods/example/cart.tscn",
    "adapter": "res://mods/example/cart_adapter.gd"
  }]
}
```

IDs: 1–96 lowercase ASCII letters, digits, `.`, `_`, `-`. Manifests: at most
64 KiB, 32 providers, 32 modules. At most eight vehicle providers are admitted,
including the reserved built-in Ranger. Duplicate identities/API mismatches reject
registration atomically. Dev Spawner exposes installed vehicle choices; diagnostics
there report invalid registrations. No second discovery scan occurs during play.

## Adapter contract

Extend `res://addons/vehicle_runtime/vehicle_adapter.gd`; Ranger's implementation is
`ranger_adapter.gd`. The root must be a RigidBody3D (VehicleBody3D also qualifies).
One controller integrates that body; do not create a second movement authority.

| Method | Responsibility |
| --- | --- |
| `accepts(body)` / `install(body, world)` | Validate/bind the controller; return false on unsupported hosts. |
| `controls(body, enabled)` | Gate all driving input; never capture the OS cursor. |
| `restore_parked(body, pose)` | Reset transient motion, disable processing and freeze the pooled body. |
| `can_park(body, physics_frame)` | Confirm actual rest; readiness holds must not count as support. |
| `bounds(body)` / `collision(body)` | Supply the supported bounds and one parked chassis proxy. |
| `camera_update(body, camera, delta)` | Own the occupied camera without creating another game window. |
| `physics_rate()` | 60–120 Hz; the host restores the previous rate on exit. |
| `capture_state(body)` / `restore_state(body, bytes)` | Version the pack's opaque binary state; reset on empty defaults. |
| `status_text(body)` | Driving HUD without Ranger-specific field dependencies. |
| `update_focus(body, world)` | Default publishes position/velocity; Ranger leaves this to its existing streamer, preserving held motion during readiness pauses. |

API 1 retains the existing small-car placement/exit envelope (6.5 × 3 × 6.5 m,
3.25 m horizontal half-width), +Z vehicle forward, and one parked collision shape.
It is not yet an arbitrary-size truck/aircraft/boat admission contract. A custom
controller must enforce ready collision along its swept path, as Ranger does via
`bind_streamed_world`; the host publishes focus/velocity but does not replace a
pack's physics. Independent systems need their own travel and exit qualification.

Four live physics bodies total; pooling is type-specific. Nearby parked batches
are per provider, limited to 64 instances and 64 mesh parts per provider, within
128 m. The native render-only horizon now retains the other records throughout
the world, without a vehicle-distance cutoff. It uses 256 m spatial cells and
128-instance pages, sharing the provider's exact meshes/materials and their
existing imported LODs. Far pages have no collision or shadow casting. Near/body
handoffs exclude duplicates in the same frame; canonical state is unchanged.
Ordinary world launch enables fleet mode; known saved providers must finish
prototype preparation and initial render publication before play is allowed.

Native initial admission defaults to 128 records and three page uploads per
frame; live cross-cell changes publish source/donor/destination pages together.
Idle frames do not scan the fleet or upload unchanged transforms. Prototype
preparation uses a per-kind identity index, not a distance query. This removes
the old visual retirement, not the local physics limits. Camera clipping,
frustum culling, occlusion and atmosphere still apply.

There is no automatic cheap-LOD baker for arbitrary packs. Supply imported mesh
LODs; oversized/animated parked prototypes require a subsequent API extension,
not silent simplification. Ranger retains 32 mesh parts; dense real-car GPU cost,
near-handoff upload spikes and shadow-transition quality remain unqualified.
Custom vehicles currently spawn through Dev Spawner and persist in-world; their
inventory items/recipes/icons are not registered. Pickup refuses to convert a
custom vehicle into a Ranger item.

## Save compatibility

Default Ranger/empty-state fleets retain byte-compatible v2. Typed fleets use v3:
the existing 24-byte header and sorted 64-byte identity/pose rows, followed per row
by u16 type length, u16 state length, ASCII type and opaque state. Limits: 65,536
vehicles; 4 KiB state each; 32 MiB reserved metadata/state aggregate; 64 MiB packet.
No executable Variant deserialization. v1/v2 load; malformed v3 rejects atomically.
Missing packs retain their identities/state and never spawn substitute Rangers;
their vehicles cannot render or activate until the pack is restored.
`read_records(after, limit)` is bounded to 512 rows with revision/cursor metadata.

## Verification

`vehicle_modules`: mixed identities, unknown-pack roundtrip, malformed packets,
bounded queries, per-body adapters, custom entry/camera, state save/reload and pooling.
`vehicle_module_pack`: actual external PCK, independent scene/controller, explicit
enablement and host-resource replacement protection.
`world_vehicle`, `vehicle_exit_facing`, `developer_vehicle_spawn`: existing Ranger
behavior. `check_runtime_views.py world_overview --pack` also checks installed
Dev Spawner creation. These are engineering fixtures, not qualification of
arbitrary third-party vehicle physics or native ABI compatibility.

`vehicle_horizon`: rendered native ownership/buffer checks, bounded publication,
mutation/restore/teardown and 65,536-record pressure using **one box prototype**.
`vehicle_horizon_world`: four actual Rangers in the populated read-only fixture,
never-near preparation, near/far handoff, imported LOD retention and a second
world's production loading gate. Component binary injection is not compound-disk
save qualification or physical driving endurance. Both run against the installed
pack with `python tools/check_runtime_views.py <test> --pack`.
[Evidence and open costs](../issues/world-overview/vehicle-verification.json).
`vehicle_horizon_cost --pack` through the same runner records actual Ranger
1,024-car close views and 4,096-car world-wide views, draw calls and CPU/GPU/frame
timings. It is an isolated profiling baseline; functional PASS is not performance
acceptance or mixed-world driving qualification.
