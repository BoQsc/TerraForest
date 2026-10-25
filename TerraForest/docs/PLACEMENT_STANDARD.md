# Terrain and building-grid standard

Accepted improvement/default, 2026-10-24. Improve the generated ground rather than deny
player construction. **Floating builds remain allowed.** The extra ground-contact
admission experiment and its ESC switch were removed following user clarification.
Do not reintroduce them as a solution to terrain/grid mismatch.

Current direction, 2026-10-25: generation must correct **both low and high ground**
toward the grid. Nearly hiding a cube to eliminate a small gap was explicitly
rejected. The current terrain and road generation preferences are independent and
default on for new worlds; existing saves are never silently regraded. Profiles
22/23 extend, rather than redefine, the previously accepted profiles 20/21.
Small residual height errors receive a smooth raise or cut toward the nearest
integer plus 8 cm. The road fitter preserves fixed entrance intervals and smooth
joins, uses sampled full-width earthwork budgets, and does no per-frame grading.

The separate session placement preference retains exact cells and a 60 cm safety
ceiling; a gap at most 10 cm never triggers deeper placement. It does not guarantee
shallow embedding, and user quality approval remains pending. Track both air gaps
and burial, not one at the expense of the other. No automatic foundations,
placement-triggered terrain mutation, hidden offsets, or bans on floating builds.
Current evidence and unfinished acceptance: `evidence/grid_preference/README.md`.
The following dated entries describe the earlier iterations.

User clarification, 2026-10-25: the near-level frontage-road preview was rejected
as a general solution; at most it is a future local town road type. Original
behavior is restored. The preferred next direction is some block submergence
rather than large floating gaps. This records a design preference, not approval
of a new global burial limit or an already implemented placement fix. Any future
comparison must keep the integer lattice and intentional floating builds, expose
the burial trade-off, and add neither automatic supports nor terrain fill.

Subsequent direction: try optional, gradually corrected road generation together
with a preference for submergence. A disabled-by-default native prototype now
compares the original, lower-cell targeting, and lower-cell targeting plus gentle
road cuts. Its provisional full-cube burial ceiling is 0.60 m, not an accepted
global setting. Plates, other shapes and objects retain their existing rules.
The normal world selector and generation remain unchanged; no save migration or
placement-triggered terrain edits. Evidence and remaining production gates are in
`evidence/road_burial_trial/README.md`.

## Coordinate and generation contract

### Feasibility and honest scope

For a block with integer base `b`, and ground heights `h_min` through `h_max`
over its footprint, maximum gap is `max(0, b - h_min)` and maximum burial is
`max(0, h_max - b)`. A base satisfying limits `G` and `B` exists only when
`ceil(h_max - B) <= floor(h_min + G)`. This is independent of targeting code.
At the current diagnostic G=0.10 m and B=0.25 m, flat ground halfway between
integer levels cannot fit. These thresholds remain diagnostic, not user approval
of 25 cm burial as universally acceptable.

A continuous rise between integer levels necessarily traverses the disallowed
height interval. Making the ramp longer does not remove it. With these limits,
the non-fitting height interval spans 0.65 m; a road grade capped at 20% requires
at least 3.25 m of horizontal transition to traverse it. Full block footprints
can make the unusable interval longer. Do not promise a perfect universal fit
from smooth normalization alone or manufacture success by excluding bad samples.

Consistent softening across final generated surfaces is still a valid unfinished
objective. Strict universal shallow contact would require a separately approved
design change: grid-aligned stepped surfaces, different vertical placement rules,
or suitable foundation shapes. The user has not authorized those as substitutes
for natural smooth terrain. Preserve the current lattice and player freedom.
Do not treat this limit as permission to ignore avoidable errors on otherwise
buildable ground. Validate the composed terrain, road beds/shoulders, yards and
entrances; shared algorithms alone do not prove final-surface contact quality.

### Preserved lattice

Generation-internal implementation, 2026-10-25: native terrain shaping and the
footprint road objective share `generation_contact.hpp`. Existing
terrain profiles remain byte-identical; recipe v4 / road_grid=3 selects the new
road objective. Following explicit user approval of the improvement, it is now
the default for new worlds when the road preference is enabled. It participates
in the existing native
grade solve before baking, with no final-world repair pass, placement-time edits
or additional loading stage. The reported shoulder still fails the diagnostic
limit; default approval is not a claim of universal contact. Full results and bounded
costs: `evidence/generation_contact_native/README.md`. This architectural progress
does not supersede the incomplete final-surface contract above.

One world unit is one metre. Blocks retain their exact integer-metre lattice and
shared faces; do not introduce per-block offsets, deform blocks, or silently grade
terrain when the player places one. Existing clearance, inventory and collision
readiness checks stay unchanged. Generated settlements still obey
`WORLD_BUILDING_STANDARD.md`; its supported-foundation requirement is not a ban on
intentional player overhangs or floating structures.

The previously accepted **Build-friendly terrain** selected immutable native
profile 20 (inland) or 21 (surrounding coast). The current preference selects 22/23.
Disabling
it selects the preceding profiles 17/19. It applies only to new worlds. Existing
saves retain their profile, terrain edits and constructions; there is no migration.
Preview, generation, binary save/restore, cache identity and water use the same
selected profile. A saved build-friendly world retains that profile when reopened.

## Native terrain shaping

During world initialization, derive a 65 by 65 byte eligibility field at 32 m
spacing. Each node samples a local 3 by 3 raw-height footprint; low-gradient,
low-altitude regions receive stronger shaping. Smooth interpolation avoids cell
boundaries. Lake margins, the existing coastal band and steep/high terrain are
excluded or faded out, rather than globally flattening the landscape.

Eligible ground forms wider levels at integer height plus 0.08 m, connected by
continuous smooth ramps. The slight overlap accommodates meshed terrain without
changing the block grid or the existing burial allowance. The transformation is
continuous across integer elevations, with displacement bounded below 0.36 m.
It reduces common fractional-height gaps, not every possible gap on every slope.

The derived field occupies 4,225 bytes per native World and is reconstructed from
seed/profile, not serialized. Each height query interpolates four bytes; native
worker ownership, binary density edits and existing region caches remain in use.
No per-frame GDScript terrain shaping, physics readback or placement-triggered
terrain mutation is added. Excavation and subsequent terrain edits remain possible.

## Verification and remaining acceptance

Four-seed native sampling covers 26,244 one-metre footprints. Close-fitting sites
increase from 2,953 to 4,516 (11.25% to 17.21%); mean sampled air gap decreases from
0.3195 m to 0.2908 m. This is a modest absolute improvement, not universal buildable
terrain. The diagnostic contact thresholds are test measurements, not admission
rules. Maximum observed height displacement is 0.3522 m.

Native debug/release checks cover determinism, cache identity, binary restoration,
unchanged coast/lake interiors, mining and edited-region restoration. A graphical
comparison places a paid brick at the same natural site under profiles 19 and 21:
maximum sampled gap falls from 0.3216 m to 0.0874 m. It also exercises the actual
placement handler to extend an unsupported floating block. Inspected ground and
overview images support this local improvement; they do not establish world-wide
visual acceptance. Generation/cancellation/play/save/return-to-selector also pass.

The user accepted this as an improvement and requested it as the default. Keep
reviewing multiple seeds, slopes, edited ground and larger block/object footprints
in normal play. Return to tuning if reviews show distracting terraces or insufficient
ground contact; retain exact block alignment and player freedom. Sustained travel
performance and lower-end hardware remain unqualified. Automatic seam enclosure,
foundation fill, arbitrary-object contact guarantees and existing settlement-quality
defects are not solved here. See [evidence and retained failures](evidence/buildable_terrain/README.md).

The user accepted the topsoil/targeting baseline and resumed road work on
2026-10-24. New settlement plans now select integer street-node heights within
the existing earthworks budgets and connect different heights with smooth terrain
ramps. Flat roadside strips use native 1 m square upper-quarter plates, whose tops
meet the next block cell exactly. They remain independently destructible and use
normal player placement/payment, not a special terrain-altering building rule.
Existing worlds are not migrated. Regional connecting roads remain smooth editable
terrain; arbitrary slopes are not guaranteed to fit every block footprint.
Verification and remaining review scope are tracked in `WORLD_FOUNDATION_STATUS.md`.

New-world road preference now selects footprint-aware native grading (road_grid=3,
32-byte recipe v4). Road_grid=2 retains connected grading and its v3 identity.
Road_grid=1 retains the prior segment normalizer and its
32-byte v2 identity; the five-field legacy recipe remains 28-byte v1. Jointly
bounded heights/tangents replace independent endpoint-fixed correction. Adjustable
roads survey cut/fill before baking and can request an alternate native corridor;
exhaustion fails explicitly rather than accepting the failed road unchanged.
The road option stays independent of terrain shaping, and both remain toggleable.
This improves measured footprint coverage without changing placement rules, but
does not guarantee shallow contact everywhere. See
`evidence/connected_grid_roads/README.md` for remaining failures and comparisons.
