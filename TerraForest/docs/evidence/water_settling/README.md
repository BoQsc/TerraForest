# Event-budgeted hydrostatic settling component

2026-10-11. NativeWaterSettling is implemented as an independently usable native
component. It is not yet called by the playable world.73 checks pass in debug and
a clean release project; the existing shallow-water regression also passes.

## What is proven

Supplied storage curves and a verified binary basin hierarchy drive finite-volume
fill/spill/merge and withdrawal/split events. A dry raised sill keeps its neighbor
dry until overtopping. Overflow fills the receiver while the donor stays at the
sill; both then share the aggregate volume-to-level curve. Withdrawal consumes the
merged layer first and separates the branches below the connection. Nested trees,
unequal basin areas, arbitrary spill heights between profile anchors and tiny
millilitre quantities are covered.2000 deterministic commands match an independent
closed-form two-tank arithmetic oracle, including excess/unavailable water.

Every progress step preserves integer quantity: addition checks total+pending
against previous total+input, and withdrawal checks total+moved against previous
total. Maximum capacity leaves an explicit unaccepted remainder. Budget1 versus256
produces the same final distribution. New commands and settled-level inspection
are refused while work is in progress. A caller must retain external ownership of
unaccepted input and debit only moved quantities at eventual transaction commit;
the class does not yet implement the world/inventory atomic transaction boundary.

## Bounds and costs

A task accepts1..2048 events per advance call and retains its explicit stack between
calls. Each event visits at most the validated64-level ancestry. Limits:4096 leaves,
8191 nodes,256 shared storage anchors, depth64. Profiles use integer millilitres;
heights use millimetres. Curves interpolate linearly; spill capacities round down
to whole millilitres using128-bit intermediate multiplication, preventing overflow.
Merged level inspection never reports below its connection elevation. Quantization
and profile approximation must be included in the future geometry error budget.

The4096-leaf fixture reaches its expected13m equilibrium in8191 events over256 calls
at budget32, retains982,920 bytes of profile values, and then performs zero events.
Largest final measured call:8us debug,6us release, including API dispatch. An earlier
smaller test revision observed a2.044ms maximum at the same large fixture. That
value was transcribed from the initial report before it was overwritten; the
original run log/manifest are retained, but the initial timing JSON is not. These short headless timings are not a whole-game or
thermal guarantee. Tree configuration/aggregation is bounded but synchronous and
not included in those advance-call numbers. Memory figures exclude node/vector
allocation overhead. The maximum256-anchor configuration uses about16MiB just for
profiles; this must remain a per-region ceiling rather than a whole-world strategy.

## Remaining obligations

The inputs are analytic supplied profiles/topology, NOT a hierarchy extracted from
actual3D terrain. Submerged-passage evidence here establishes the communicating
basin equilibrium, not a pressure/velocity solve through rendered cave geometry.
Do not mark the full spatial-conservation gate complete. A terrain compiler must
produce terrain-clipped storage profiles, spill elevations and correct contact
entries, including stacked caves; it must have bounded work and approximation error.
Terrain edits need quantity-preserving remapping/displacement and atomic publication.
Canonical save/reopen, migration from static lakes, bucket ownership and replay-safe
world transactions are not connected. The hierarchy has no snapshot ABI yet.

This is bulk hydrostatic settling, with no simulated travel time, momentum, waves,
splashing or transient velocity field. It is intended to keep settled regions idle;
local active flow/presentation remains separate required work. No region eviction,
multiplayer, full-resolution visual or long-session performance claim is made.

Design reference: Barnes et al., Fill-Spill-Merge (2021),
https://esurf.copernicus.org/articles/9/105/2021/index.html . The paper concerns
surface hydrology; its existence does not prove3D cave support. All implementation
code here is original0BSD; no paper implementation/source dependency was imported.

The only failed attempted run in this turn was a GDScript inferred-type parse error
in the added oracle. It was corrected with explicit float declarations and retained
as fixture_parse_error. The native conservation expectations were not relaxed.
