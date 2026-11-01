# Startup and saved-world browser latency

- Status: Improved-partial / installed, source and package functional checks pass.
- Updated: 2026-11-01. Fix: `83f09d30`; coordinated export with `cb0c9cc8`.
- User review: Pending.
- Symptom: Startup waits for save/photo work; filtering or changing worlds hitches.

## Images

![Saved-world browser after background reads](images/browser.png)

After: 1920×1080 source browser, Forward+, 299 existing saves. Selected photograph
is the existing Exploration_1703_596a160e preview. UI layout and thumbnail were
inspected; a still image does not demonstrate latency. Source/hash and retained
asset provenance are in [the manifest](images/manifest.json).

## Changes and verification

One read worker handles the catalog and thumbnail decoding; an eight-entry cache
avoids repeat reads. Stale refresh/selection results cannot replace current UI.
Generation scripts load on demand on the owner thread. Continue-last waits for
the catalog. Save files and full-resolution photographs remain intact.

Three alternating rendered source comparisons: median first browser frame
1.75 → 1.24 s, filter update 45 → 2 ms. See [timings, commands, passing checks and
limitations](../../docs/evidence/browser_responsiveness/README.md).

The matching installed package passes all 42 browser assertions and the rendered
credits check. Normal source/package exploration-world create and restore checks
also pass. Exported startup timings have not been compared; the numbers above
remain source-run observations.

## Remaining / resume here

The source launcher's required icon freshness preflight remains (read-only check
found stale icons while other content was being edited). Full native/GPU startup,
game-scene loading, general pause/inventory responsiveness and exported build
timing are separate work. The coordinated export is installed and functionally
checked. Resume with exported startup/filter/continue timing when the shared test
window is available, then obtain player review. Functional passes do not establish
exported performance or user approval.

## Reproduce / history

Open My worlds with a substantial save library, type in the filter, switch worlds,
refresh and use Continue last. The regression uses a unique disposable fixture
and checks saved bytes. Source benchmarks read the existing library without
opening worlds; no player save is overwritten.
