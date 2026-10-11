# Model ownership protection — 2026-10-11

`NativeStaticBatch.set_removal_protected(id, true)` reserves an existing placement
against destruction while an external owner retains contents. It accepts loaded
or unloaded reserved IDs, rejects unknown IDs and refuses changes during active
region transfer. Repeated enable/disable is idempotent.

`remove_instances` checks every requested ID before changing anything. Native
history uses that path, so failed erase/undo retains geometry and history.
Transform edits remain legal: contents follow the same identity. Bulk replacement,
snapshot replacement and metadata replacement reject while any ID is protected.
The combined native bootstrap and scene restore coordinator check protection
before mutating any blocks or model collections.

Streaming is not destruction. Synchronous and incremental retirement/admission
retain protection while allowing cold placement records and render/physics
residency to be released. Existing unloaded-ID reservation prevents ID theft.

## Ownership contract

Protection is an in-memory interlock, not a saved contents database. The content
owner must enable it before publishing a first deposit, keep it through travel,
and release it only after contents are empty or during an explicit whole-world
ownership handoff. On loading, restore protection against reserved model IDs
before exposing interactions. Handle failed reload without leaving existing
contents unprotected. No automatic protection is enabled in current gameplay.

This is a trusted local API, not a multiplayer authorization boundary. It does not
prevent trusted code from freeing the entire world or explicitly releasing a pin.
No per-item node or per-frame ownership scan is added; deletion uses set lookups.

## Verification

36 checks pass against debug and clean release DLLs. Includes atomic mixed removal,
undo/redo, transform edits, bulk/snapshot/metadata replacement, synchronous and
incremental region transfer, reserved IDs, startup reattachment, combined native
bootstrap and scene-level rejection before block mutation. Existing model-region
regression passes separately. Commands and native/source identities are retained.

The expanded incremental fixture first attempted retirement with eager render
pages still resident. Native retirement correctly rejected it; the subsequent
failure cascade is retained in `fixture_failure/`. The fixture now creates a cold,
collision-only collection. Production retirement conditions were not relaxed.

The contents store, saved ownership handoff, reach checks and transfer UI are
still missing. This does not certify playable containers or large-world storage.

Run `tools/run_godot_check.py model_removal_protection --headless --require MODEL_REMOVAL_PROTECTION`.
Release: `tools/test_native_release.py --addon structures --test model_removal_protection --godot <engine>`.
