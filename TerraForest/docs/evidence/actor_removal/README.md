# Actor removal lifecycle — 2026-10-15

The existing actual-world identity fixture now wounds an actor before editor
deletion. Before the fix, its native durability record survived deletion. Combat
also failed to clear the authoring selection when killing the selected actor.

Both paths now call one world integration function resolving the current handle
from persistent identity. Successful despawn clears its order, durability key,
editor selection/marker and active presentation, then marks the world dirty.
Missing identities reject. Shared attack validates identity/handle before damage
or tool wear, so an already removed actor cannot leave a new orphan record.
Native stores retain ownership; the adapter runs only on explicit interactions.

Evidence: editor ray picking and actual remove-button handler pass after wounding;
combat removal clears selection/order/damage and preserves 80 coincident actor
records. A stale post-death hit rejects with exact unchanged inventory snapshot
and durability count. Tests run the normal world at 1920×1080, capped 60 FPS.

These are temporary-world interaction checks, not a new disk-restart proof or
population performance test. Existing orphan records in older saves are not
automatically migrated/pruned. Broader actor AI, animation and scaling remain open.
