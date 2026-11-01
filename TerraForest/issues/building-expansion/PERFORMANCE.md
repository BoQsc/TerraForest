# Measured expansion costs

These are matched, capped camera-approach measurements in the populated world. Each run has 90 warmup and 360 measured frames. Image capture is outside timing. Other desktop workload was uncontrolled. Values diagnose this scope; they do not establish sustained 60 FPS or a causal speedup. Native hashes, raw geometry/LOD/memory values and sources are retained in [measurements.json](measurements.json).

| Building | Frame p95 R1 → E2 ms | Worst R1 → E2 ms | CPU render p95 R1 → E2 ms | GPU render p95 R1 → E2 ms |
| --- | ---: | ---: | ---: | ---: |
| trader_t1 | 18.77 → 18.68 | 33.39 → 23.65 | 3.34 → 3.51 | 17.05 → 16.53 |
| town_hall_t1 | 18.20 → 18.04 | 33.08 → 23.18 | 4.48 → 4.62 | 17.00 → 16.65 |
| church_c1 | 18.03 → 18.40 | 18.69 → 25.24 | 4.50 → 4.59 | 15.55 → 15.56 |
| school_s2 | 18.21 → 18.41 | 19.51 → 27.50 | 4.45 → 4.56 | 17.06 → 17.04 |
| warehouse_w1 | 18.13 → 18.38 | 33.23 → 27.60 | 4.37 → 4.72 | 16.39 → 16.29 |
| cottage_a2 | 17.99 → 18.29 | 18.81 → 26.63 | 5.93 → 6.31 | 16.26 → 16.48 |
| shop_b2 | 18.02 → 18.37 | 33.38 → 27.76 | 5.87 → 6.13 | 16.47 → 16.40 |
| shop_b1 | 17.98 → 18.07 | 32.33 → 23.64 | 5.13 → 5.43 | 16.48 → 16.38 |
| house_c1 | 21.73 → 19.61 | 32.76 → 29.17 | 5.28 → 4.59 | 6.25 → 6.26 |

| Building | Draw calls R1 → E2 | Block triangles R1 → E2 | Video MiB R1 → E2 | E2 publication until collision ready ms |
| --- | ---: | ---: | ---: | ---: |
| trader_t1 | 1251 → 1251 | 25841 → 25647 | 1303.72 → 1314.37 | 351.16 |
| town_hall_t1 | 1476 → 1489 | 25841 → 27276 | 1270.28 → 1281.15 | 372.72 |
| church_c1 | 1554 → 1561 | 25841 → 26946 | 1270.44 → 1281.25 | 333.56 |
| school_s2 | 1718 → 1729 | 25841 → 26969 | 1269.94 → 1280.74 | 424.02 |
| warehouse_w1 | 1621 → 1627 | 25841 → 26609 | 1269.76 → 1280.51 | 281.91 |
| cottage_a2 | 3934 → 3937 | 12558 → 12230 | 1265.32 → 1275.93 | 111.56 |
| shop_b2 | 3802 → 3805 | 12558 → 12362 | 1265.48 → 1276.12 | 140.38 |
| shop_b1 | 3974 → 3977 | 12558 → 11550 | 1264.55 → 1275.02 | 162.36 |
| house_c1 | 1539 → 1539 | 19878 → 19636 | 1270.15 → 1249.18 | 282.31 |

Block counts include resident neighbors and incremental E2 replacements, rather than only the photographed building. Both phases use the final shared clipping fix. The 512 appearance array adds 10.69 MiB of measured texture allocation (8.00 MiB logical RGB mip data). The study adds a separate 1024 array costing 42.69 MiB (32.00 MiB logical). The larger array is not retained in normal play.

The actual-player traverse covers 221.22 m in R1 and E2, with zero collision-readiness holds and no unsupported fall. Distance screenshots taken by moving only the camera are separate from this evidence.
