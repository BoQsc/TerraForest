# Region-backed save interruption tests

The native region-world adapter was tested with abrupt termination of a real
Godot writer while a root publication temporary file existed. Three debug and
three clean-release trials passed. Each trial created its own isolated directory;
the harness terminates only the exact child process it started.

The writer commits revisions 0 and 1, then waits while another process verifies
that both its world-root lease and region-store lease reject competing owners.
After the parent permits more saves, the parent observes a live writer and a
`world.trw.pending.*` file, kills the writer without orderly shutdown, and starts
a fresh verification process.

Every observed trial left one pending root file. The fresh reader reconstructed
canonical revision 1 and backup revision 0. It checked complete 8 MiB terrain-marker
bytes, a water revision marker, two real native block-region records across signed
coordinates, and an actual static model's stable 64-bit ID and transform. These
values must all agree on one revision; independently valid but mixed component
versions fail the test. The test uses opaque terrain/water marker payloads to
isolate archive consistency; it does not simulate terrain or water gameplay.

The fresh process then saves revisions 2–4, exercising reconciliation of any
unreferenced checkpoint left by the interrupted publication, and verifies current
revision 4 and backup revision 3. It also checks that retained checkpoints return
to at most two. Neither pending root files nor orphan blobs are treated as committed
saves. The existing integrated persistence suite separately covers real terrain,
water providers, models, reload ordering and corrupt-save protection.

Run sequentially from the project directory:

```text
python tools/test_region_archive_process.py --godot PATH
python tools/test_region_archive_process.py --release --godot PATH
```

Release testing copies only the two required release extensions and test script
into a fresh project. No editor cache or debug DLL is used there. Reports are
retained in `docs/evidence/region_save_interruption`. Native binaries are unchanged
from the region-world integration; this change adds evidence and a reusable harness.

These observations cover process termination during the root-temporary phase.
They do not establish every possible interruption point, kernel/filesystem failure,
physical power-loss durability, multi-hour endurance or large-world throughput.
The filesystem may advance between observation and process termination, so the
test does not claim an exact interrupted instruction. Pending-file quota cleanup,
automatic region paging and delta capture remain unfinished.
