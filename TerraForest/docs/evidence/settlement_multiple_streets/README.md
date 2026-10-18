# Multiple street residents and safe reactivation — 2026-10-18

## World behavior

Actions > Development > **Add residents to nearby street** now permits two residents on a second prepared street even when other actors already exist. It preserves existing identities, positions and orders. It queries the existing native spatial store around the selected patrol area, including sleeping records; occupied or incompletely queried areas reject. Endpoint support, dry-ground, readiness and physical-overlap checks remain. The radius encloses the four endpoints with a 1 m margin. Selection stays within 32 m of a prepared street centre. This is explicit authoring, not automatic population or unrestricted crowd generation.

The persistent actor population still has 1,024 records, with 16 active bodies and 256 rendered records. No capacities, routing budgets or runtime tick rates were raised. The authoring-only script uses the existing native bounded query; native code owns simulation.

## Reactivation bug found and corrected

The actual-world test initially showed actor 2 jumping exactly 24 m after sleeping and reassigning pooled bodies, then falling between the test floors. The retained reactivation trace records the frame-by-frame discontinuity. Newly bound NativeEntityActor bodies now hold movement during their binding physics frame so the reassigned collision bodies synchronize before integration. This adds one physics-step activation delay without new bodies or continuous per-record work. The final test explicitly limits movement between observed physics frames to 0.2 m and verifies all four residents reach and reverse their own routes.

## Checks and limits

- `run_godot_check.py settlement_multiple_streets --timeout 80 --require "MULTIPLE_STREETS failures=0" -- --actors`: real world scene, real editor action and native block collision, normal world physics during walking; two separated authored test floors. Exact actor and order snapshots restore into fresh native owners. This is not a new fresh-process disk persistence qualification.
- `entity_activation` and `entity_actor`: headless native regressions pass, including synchronization hold, fixed body allocation, identity reuse, walls, readiness and authority correction.
- Zig builds of debug and release extensions succeeded against the existing prebuilt godot-cpp; zero SDK sources rebuilt. Runtime checks use the debug extension.
- Graphical run uses fullscreen 1920x1080. Reviewed screenshot shows four residents on both floors. This is a functional fixture, not a completed generated town. The screenshot HUD and earlier streaming stalls do not qualify sustained 60 FPS, actor scaling or older laptop thermals.
- An initial fixture used negative terrain coordinates; collision readiness correctly refused it. It was moved near actual spawn, with real readiness awaited. Failures and the reactivation trace are retained.
- Temporary world only; human saves untouched. Water and food/vitals remain deferred.
