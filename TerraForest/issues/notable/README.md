<!-- SPDX-License-Identifier: CC0-1.0 -->
# ★ Notable investigations

Unusual, difficult or broadly useful investigations worth keeping visible for
future contributors. A star means there is something to learn; each case keeps
its actual verification and human-review status.

The original issue folder remains the source of truth for reproduction, code,
status and evidence. This index links to it so the history stays together.

| Case | Why retain it | Current status | Lessons |
| --- | --- | --- | --- |
| [★ Vegetation flicker and invalid shader colours](../vegetation-lod/README.md) | A distance symptom hid a shared shader-domain fault; a subsequent stone proxy also lost its per-instance depth transform | Previous flicker fix human-approved. Stone transition/fade pass causal and physical gameplay checks; stone and near-fade snapshots approved for commit/push; detailed near-handoff visual feedback, broader coverage and earlier GPU-tail target remain open | [Validated flicker case study](../vegetation-lod/LESSONS.md), [transition investigation](../vegetation-lod/TRANSITIONS.md), [near handoffs and camera-control lesson](../vegetation-lod/NEAR_HANDOFFS.md) |

## Adding and maintaining a case

1. Keep one stable issue folder and add a star and a link here to its README.
2. Record the symptom, misleading hypotheses, failed or rejected approaches,
   decisive controls, correction, regression checks and remaining uncertainty.
   Link existing evidence rather than copying logs or moving captures.
3. Label unfinished lessons as a draft. Record human feedback with its date,
   tested source/build and scope. A visual case becomes a validated lesson only
   after the user's playtest confirms the relevant result; unresolved requirements
   remain explicit. Preserve rejection and recurrence as part of the lesson.
4. Keep the index entry after resolution. Update the existing case when new
   evidence changes the explanation, instead of replacing its history.

This index is open to rendering, gameplay, persistence, performance, tooling and
other investigations with transferable lessons. It is a curated reading list;
the ordinary issue tracker continues to hold the complete backlog.
