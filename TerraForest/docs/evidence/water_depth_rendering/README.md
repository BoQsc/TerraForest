# Water depth rendering check

The one regional runtime now uses depth-dependent alpha and preserves side normals. A single opaque-depth lookup reconstructs view-space depth with the inverse projection matrix; no screen-color copy or extra reflection render is requested. Procedural normal ripples leave volume geometry unchanged.

Actual-world mining, bucket, save and cached reload assertions passed. The close view is a diagnostic failure for overall visual acceptance: transparency exposes overlapping cell faces and grid seams. Shore geometry remains unfinished. No completed-water or 60 FPS claim follows from this check.

Paired hidden/visible/visible/hidden samples use the same camera, 1920x1080 fullscreen, with water simulation paused for render attribution. Each segment warms for 12 frames and measures 48. GPU medians: hidden 4.749/5.089 ms, visible 5.110/5.289 ms; difference of averaged medians approximately 0.281 ms. These short noisy samples cover one view on RTX 4050 Laptop GPU, not old-laptop thermals, worst-case overdraw, CPU simulation or sustained frame rate. The screenshot HUD reads 36 FPS; the GPU measurements do not explain that shortfall.

Depth reconstruction follows https://docs.godotengine.org/en/latest/tutorials/shaders/advanced_postprocessing.html . The authoritative executable, shader and native hashes are in run.json. No alternate water runtime was added.
