# World-building work

For world generation, settlement, road, POI or landscape changes, read
`docs/WORLD_BUILDING_STANDARD.md` before choosing the implementation.

Keep engineering verification separate from world-quality acceptance. Passing
generation, persistence, movement or performance checks does not override visible
design defects. Inspect relevant generated images before reporting visual success.
Report rejected and unreviewed requirements plainly; do not silently lower the
standard to match the current implementation.

The current northern single-pad district is a development draft, rejected for
terrain fit and visual variety. Prioritize a terrain-fitting block/lot layout over
decorating that rejected layout. Existing user saves must remain intact.

These rules do not prohibit development builds for diagnosis or require additional
user permission. Use short targeted checks, followed by integrated evidence where
the change affects the actual world. Preserve 0BSD and native runtime hot paths.
