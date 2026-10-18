# Near-shadow camera travel

2026-10-18, production 4096 atlas, focused blended cascades, safe normal bias retained. Saved southern world readonly, fullscreen 1920x1080, cap 60 FPS. A 360-frame route translates 12 m while looking toward a fixed patch, moving vegetation across cascade distances. Wind frozen to isolate shadow projection.

Completed without script errors or rejected cover; persistent ground-cover state unchanged. Frame p95 19.057 ms, worst 23.751 ms, median GPU 10.246 ms. This fails strict 16.667 ms frame-budget qualification. Screenshots are a separate replay after measurement; the 6 FPS HUD in the final replay image includes readback stalls and is not the timed route result.

Start/middle/end images inspected. Nearby cast shadows remain present; no obvious spatial cascade seam or acne on this meadow in these samples. Sparse images cannot establish temporal shimmer stability. Hillsides, cliffs, other sun angles, wind-enabled movement and older-laptop thermals remain unverified. No production density/models/settings changed in this check.

Next visual work must preserve real nearby cast shadows and dense near cover while assessing distant continuity. Do not claim this evidence completes world vegetation or global shadow quality.
