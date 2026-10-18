# Integrated mine access

The POI preparation path grades a six-metre asphalt access road from the eastern
arterial and a wider entrance yard before placing the mine prefab. It reuses native
terrain grading, persisted road anchors and asphalt vegetation-root rejection.
No global plant deletion or extra runtime exclusion scan was introduced.

Full 17-building world creation/save/reopen passes. The saved-world check confirms
three path/yard probes reject vegetation and an adjacent natural-ground probe stays
eligible. Exterior capture shows the paved yard clear. Actual player descent and
return pass after grading; the complete check takes 62 seconds including loading at
fullscreen 1920x1080/cap60. This is not travel/endurance/GPU qualification; logs retain
loading hitches. Road driving and access aesthetics remain unqualified.

Development slot: poi_access_20261018. Normal launchers remain unchanged. The entrance
is basic; this check closes access integration, not completed POI art or world scope.
