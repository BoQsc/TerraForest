# Directional shadow bias comparison — 2026-10-18

Readonly northern_common_42_20261018, saved meadow, 1920x1080 fullscreen cap60.
`tests/vegetation_shadow_bias.gd` uses the integrated vegetation comparison fixture
and overrides every phase to the SAME selected casters (stone, fern, bush, twigs).
Phase suffixes are inherited labels, not changes in caster selection. Normal bias
sequence: 2.0, 0.5, 0.25, 2.0. Other sun settings remain unchanged.

Inspected the 0.5 and 0.25 images against the preceding daylight baseline. The
change does not convincingly solve the flat ground-cover appearance. Do not adopt
a lower global bias based on this meadow alone: the existing 2.0 value was installed
to suppress terrain shadow acne, and steep excavations are outside this check.
No production lighting change is made.

GPU medians 8.169, 7.460, 8.154, 7.460 ms show phase drift, not evidence that bias
reduces rendering cost. This is a rejected lighting adjustment, not a performance
qualification or completed art direction. Retain the committed fade/residency/mix
fixes. Next landscape work should address distribution and terrain/ground-cover
continuity while preserving accepted models and the user's human review.
