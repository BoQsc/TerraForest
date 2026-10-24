# Rejected ground-contact admission experiment

This directory retains evidence for an approach rejected by the user's clarified
direction on 2026-10-24. It added placement restrictions rather than improving the
generated terrain. The extra native admission flag, player policy, ESC switch and
associated test changes were removed; structures source and binaries were restored
to their preceding state. These reports do not describe the current behavior.

Debug/release native checks passed for that rejected design. The retained packaged
failure used a stale target across an asynchronous screenshot; its later passing
rerun did not make the design acceptable. Do not reuse these passes as terrain
quality evidence. Current terrain-first work is documented in
`../buildable_terrain/README.md` and `../../PLACEMENT_STANDARD.md`.
