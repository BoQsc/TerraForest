# Northern fitted lots — 2026-10-18

Production district preparation now uses twelve independently surveyed lots on
three streets crossing the existing arterial. Each lot gets its own supported
base elevation and native support/clearance placement transaction. Eight flat
seed-42 lots retain natural ground without foundation grading; four require edits.
Buildings share furnished two-, three- and four-storey native prefabs. This adds
no new runtime generator, renderer or per-building script processor.

Seed 42: maximum sampled lot fill 1.0734 m and cut 2.6566 m, compared with the
rejected old pad's 6.7471 m fill and 5.8557 m cut. Street core survey: fill 0.2002 m,
cut 0.3575 m. The already-paved arterial crossing is excluded from natural-root
sampling because that query rejects asphalt; traversal must validate the joins.
The survey does not certify every landscape shoulder or every future seed.

Native lot-fit checks pass for seeds 0, 1, 42, 50, 141, 1703 and 9999; seed 42 also
executes all grading edits and checks every lot's native foundation support.
Complete graphical generation and fresh-process reopen pass without diagnostics,
including saved blocks, furnishings, doors and other integrated world components.
New diagnostic/review slot: fitted_lots_42_20261018. Existing saves are untouched.

Overview and both ground images were inspected. The single large pad is removed.
World quality is still REJECTED: repeated facade family, no trees/public-space
landscape design, exposed cut at one end and raw road-end shoulders remain.
Height variation is progress, not enough to call this a designed neighborhood.
Further entrances, vehicle turning and ecological integration need validation.
Screenshot HUD FPS is contaminated by camera relocation and synchronous PNG
readback; stationary frame metrics precede captures and do not qualify travel or
long-run thermal performance. The graphical test's success marker checks data and
residency, not visual acceptance.

One intermediate creation was rejected by the runner despite a successful save:
new prefab registrations omitted dropdown reconfiguration. Production now uses
the existing composed-prefab registration path; final creation/reopen are clean.

Saved-world traversal passes all 11 street waypoints with ordinary W/Shift,
including all three streets and their arterial crossings. Movement p95 16.843 ms,
maximum 18.423 ms; 90.98 seconds total including loading. No per-entrance, vehicle,
long-run or thermal claim.
