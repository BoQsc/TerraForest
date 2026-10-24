# Accepted build-friendly terrain improvement, 2026-10-24

The user accepted this improvement and requested its commit and default promotion.
Native profiles 20/21 preserve the existing block lattice and player
building permissions. Details and open acceptance gates: `../../PLACEMENT_STANDARD.md`.
The old admission experiment in `../ground_contact/` is rejected and removed.

## Passed evidence

- `native_debug/`: 43 checks, four seeds, 26,244 sampled one-metre footprints.
- `native_release.json` and `.log`: the same 43 checks on the release DLL.
- `metrics.json`: close contact 2,953 -> 4,516 sites; average air gap
  0.3195 -> 0.2908 m; maximum sampled displacement 0.3522 m. Contact means highest
  support within 3 cm and greatest sampled gap at most 20 cm, for measurement only.
- `world_comparison/`: seed 1703, profiles 19/21, cell (800,50,1312), actual
  collision and paid placement. Greatest sampled gap 0.3216 -> 0.0874 m;
  highest support 49.7748 -> 50.0033 m. Native target and click agree; an aerial
  block-face attachment succeeds through the real placement handler.
- `generation_flow/`: 12 checks covering cancellation, generation, saved profile21,
  playing and return to selector in one native window. Isolated generated save:
  `window_generated_836c80e758d532fd`. Includes offline earthworks/water/cache logs.
- `world_browser/`: default-on option, opt-out, preview identity and coastal/inland
  command routing. Developer preset fixture requires `--developer-worlds`.
- `coast_regression/` and `placement_regression/`: preceding coast and original
  placement support tests, without the rejected admission flag.
- Build manifests identify both rebuilt terrain and world-runtime variants.
- `packaged_native/`: all 43 native checks run against the exported resources and
  external libraries. `pack_smoke.log` confirms exported startup with 14 libraries.
  Full graphical placement and generation checks used source resources.
- `browser_visual/`: creation controls fit 1920x1080; the default-on experimental
  checkbox and generation button were inspected in `buildable_create.png`.

The ground images for both profiles and profile21 landscape were inspected: the
old air strip beneath the cube is substantially closed, nearby vegetation remains
present, and this view retains connected rolling terrain. Some edge gap remains;
this is not airtight placement. The generated-playing image shows the ordinary
settlement entry and confirms presentation after generation, not settlement-quality
acceptance. Original profile19 overview is retained for comparison but not used as
an independent quality pass. UI performance counters in screenshots are not timing
benchmarks.

Release initialization was 3.9-4.7 ms in these four samples; the derived weight
field is 4,225 bytes per native World. These are scoped initialization figures,
not sustained frame-cost or hardware scalability results.

## Failed or incomplete evidence retained

- `failures/native_parse/`: test helper returned void where bool was required;
  corrected before the native passing run.
- `failures/browser_invocation/`: developer preset fixture run without its
  `--developer-worlds` flag; rerun with that flag passes.
- `failures/raw_inland/` and `failures/raw_inland_focused/`: raw profile17 did
  not become playable within the fixture's 50-second wait. Terrain reported ready;
  loading remained active. Forcing focus did not fix it. This raw-inland readiness
  cause is unresolved; passing profiles19/21 do not close it. Reproduce the stage
  on a raw inland launch before changing unrelated readiness gates.
- The first release harness invocation printed all 43 passing checks but lacked
  the summary file required by that harness. The test now writes that summary;
  rerun passes. The original harness console was not retained separately.
- `failures/package_report_path/`: all native checks passed, but report output
  attempted to write into read-only packed resources and then timed out. The
  fixture now accepts an external report directory and handles unwritable output;
  the rerun passes without changing game code.

Broader review across seeds, slopes, mining/placed-terrain changes and larger object
footprints remains ongoing, without negating acceptance of this improvement. The current
sampled improvement is limited: most arbitrary footprints still do not meet the
strict diagnostic close-contact definition. No globally flat world, automatic seam
enclosure, foundation-fill operation or new player restriction is claimed.
