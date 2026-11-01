# Non-gameplay browser responsiveness — 2026-11-01

The initial source pass left the executable/PCK untouched during concurrent
native/content work. The coordinated export is now installed and passes packaged
browser/credits functional checks; exported startup timing remains unmeasured.

## Measured change

Three alternating rendered runs per variant, 299 existing saves, Godot 4.7.2
Steam, Forward+ Vulkan on an RTX 4050 Laptop GPU, 1920×1080. Medians:

| Measurement | Before | After |
| --- | ---: | ---: |
| Engine ticks to first browser frame | 1,749 ms | 1,243 ms |
| Browser script/scene load plus control setup | 564 ms | 155 ms |
| Saved-world filtering, 36 updates per variant | 45 ms | 2 ms |
| Engine ticks to populated list and selected photo | 1,749 ms | 1,376 ms |

See [raw samples and methodology](timings.json), `before_*.log`, `after_*.log`
and [the diagnostic probe](probe.gd.txt). The pre-change browser was preserved
before edits and loaded from an alternate scene; both variants used the same
active checkout's other resources. Filesystem/driver caches were not purged and
other project work was ongoing. These are source-run observations, not cold-boot
guarantees or timings of the Windows launcher. A preliminary cold-ish headless
sample was slower still (440 ms load + 1,177 ms setup); it is not mixed into the
rendered comparison.

## Implementation

- Saved-world enumeration, metadata reads and PNG decoding use one serial read
  worker. UI updates and thumbnail texture creation remain on the main thread.
- A revision rejects obsolete refreshes; selection changes coalesce to the latest
  request. An eight-entry LRU holds photos up to 760×400, preserving source PNGs.
- Cached filtering/reselection avoids disk work and chooses a stable photograph.
- The initial browser no longer preloads the regional planner/coordinator. Native
  script initializers still run on the owner thread when explicitly requested.
- Continue-last waits for enumeration. Existing save-selection integration tests
  wait for catalog readiness; their gameplay behavior is unchanged.
- Metadata uses its already-open bounded file instead of opening it twice.

## Verification

All listed checks passed with no engine/script diagnostics:

- `world_browser_responsiveness`: 42 checks covering asynchronous catalog/photo
  delivery, latest-selection wins, refresh invalidation, bounded cache, full-size
  source preservation, sorting, invalid paths, unchanged save bytes, joining on
  teardown, and the deferred native preview. See `responsiveness.log`/`.json`.
- `world_presentation`: save ordering, metadata, naming/path rejection, saved-byte
  preservation. See `world_presentation.log`/`.json`.
- Rendered `credits_licenses`, `world_browser_cancel`, `world_browser_progress`:
  existing dialogs, generation cancellation, compact progress and 720p/1080p
  layout checks. Runs used an offscreen window position; logs/commands retained.
- Actual `--continue-last --continue-report` resolves a saved world and exits
  without entering or writing it. See `continue.log`/`.json`.
- Godot editor import completed without diagnostics and generated the new UIDs.
- The browser screenshot was visually inspected; no layout redesign is claimed.

Run the new regression with:

```text
python tools/run_godot_check.py world_browser_responsiveness --headless --timeout 35 --require "WORLD_BROWSER_RESPONSIVENESS failures=0"
```

The four migrated full-world integration scripts pass Godot parse checks
(`integration_parse.json`) but were not run end to end in this pass.
Generation/gameplay assets and binaries were changing concurrently; the
focused cancellation and preview checks cover the changed lazy-loading paths.

## Coordinated installed-package verification

The expansion chat installed the matching export with browser commit `83f09d30`
and native/content milestone `cb0c9cc8`. PCK SHA-256:
`0c073b05501ae387f28d38e9cbf7b1c6cd781332283205a9d5838013eec8b889`.

- Packaged `world_browser_responsiveness`: all 42 checks pass, including deferred
  preview and asynchronous catalog/thumbnail behavior.
- Packaged `credits_licenses`: rendered check passes using an external writable
  screenshot folder and a window that does not take focus. The first unadapted
  headless run failed because it attempted to write under read-only `res://`;
  that failed harness run remains recorded, not counted as a pass.
- The expansion chat's normal source and packaged world flows each pass 76
  create/interaction/travel checks plus 15 fresh-process restore checks. This
  exercises the migrated exploration-world catalog wait; the other migrated
  full-world scripts retain their parse-only qualification from this pass.

See [package results and original report locations](package_validation.json),
[browser log](package_browser.log), [credits log](package_credits.log), and
[the integrated-world evidence](../../../issues/gameplay-expansion/watchtower-world-evidence.json).
These close the pending export installation and browser/credits functional checks.
They do not establish exported startup speed or user visual approval. No further
renderer or export was started by this chat while other work used the test window.

## Remaining scope and provenance

The Windows source launcher still runs its intentional icon dependency preflight.
Read-only `--check-only` took about 1.2 s and reported stale item/shape icons in the
active development checkout (expected exit 2; `icons.log`/`.json`). No bake was
triggered and no freshness guarantee was removed. Investigate a compatible faster
preflight separately if launcher delay remains noticeable after the next build.

Game-scene loading, regional planning duration, native initialization, GPU startup,
pause/inventory screens, cold machines and exported-pack timing are unqualified
by this browser measurement. Return after the concurrent build is stable for an
exported startup/filter/continue comparison and player review. No claim of instant
world loading or completed general UI optimization is made.

New worker, regression and probe code are original AI-assisted work for the user's
startup/UI request under 0BSD. No external implementation, dependency or asset was
imported. The screenshot depicts existing assets under their retained terms.
See the [issue](../../../issues/browser-responsiveness/README.md).
