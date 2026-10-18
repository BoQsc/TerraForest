# Mixed regional recipe admission

The eight-building central district previously chose all cottages for seed 50 and
all towers for seed 141, violating its own post-placement mixed-content check.
Preparation now uses native layout_counts to select a deterministic building-layout
seed containing both source types before composition or terrain placement. Terrain
seed is unchanged. Candidate search is bounded to 16 adjacent layout seeds followed
by a validated recipe fallback. The chosen seed is recorded in the checkpoint report.
Native mesh/runtime algorithms and existing saved content are unchanged.

Actual native composition passes for 13 seeds including 50, 141 and 2147483647:
eight doors and between one and seven towers each. Existing reviewed seeds 42 and
1703 retain their exact layout seed. This is a recipe check, not a fresh full-world
bake or performance qualification for all those seeds. Preparation script parse
check also passes. This prevents this particular late generation failure; it does
not guarantee every possible seed passes terrain surveys and other bake gates.
