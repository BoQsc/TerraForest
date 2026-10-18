# Camera-aware distant vegetation coverage

2026-10-18. Native view selection retains nearby cover in every direction and extends the viewed cone up to248m when camera FOV narrows, capped at81 owners. Ordinary75-degree view retains exact original81-owner selection and124m fade range. Stable candidates/IDs, all16 layers, models, near cast shadows and byte/upload budgets unchanged. Native radius changes retain existing render pages instead of using the destructive renderer reconfiguration API.

Native tests check ordinary equivalence, invalid input, opposite headings, nearby retention and center/edge coverage across8 headings and3 FOVs. Stream regression and actual native render-page retention checks pass. Debug/release libraries built.

Readonly actual-world sequence75/35/75degrees passes after fixing a TEST synchronization error: the old settled predicate could observe the previous view before the cover coordinator consumed the new FOV. Final predicate waits for matching FOV and native pending pages. Retain initial failed log.

Final ranges124/248/124m; owners81/65/81. All visible pages fit configured budgets and saved edits remain unchanged. Zoomed image inspected; normal/return images retained for comparison. Timings labelled settle_ms in this capture include45 render frames and image readback:5.46/5.59/7.33seconds are phase elapsed values, not precise loading latency or runtime FPS. Immediate loading/turning continuity is not qualified.

This is camera-FOV integration, not a new player zoom control or binocular item. Forward ground coverage is bounded to2x normal range; vertical views fall back to local coverage. New view cells still load asynchronously. Further visibility/density acceptance and performance qualification remain open.
