# TerraForest repository instructions

## Public-domain-first policy

TerraForest's goal is freely reusable project code and assets: **0BSD for new
original code and CC0-1.0 for new original assets**. Read [contribution and intake
rules](CONTRIBUTING.md) before adding or importing material. This policy applies
to human and AI-assisted contributions throughout the repository.
Admission defaults cover material copied into, linked into or distributed with
project work. Track external development tools separately; existing tools may
continue to be used under their terms.

Preserve existing licenses, authorship, notices and provenance. The defaults are
prospective; they do not relicense inherited work or third-party components.
Existing exceptions and unresolved evidence are recorded in
[the inventory](TerraForest/docs/LICENSE_INVENTORY.md) and its
[machine-readable records](TerraForest/license_inventory.json).

Do not add or silently widen a non-default or unknown-license exception. Record
its exact source/version, affected paths, terms, purpose and proposed disposition
for an explicit maintainer decision before admission. Existing listed use may
continue within its recorded scope; normal maintenance does not require renewed
permission for that existing use. Recheck provenance and terms on upgrades.

For changes inside `TerraForest/`, also follow `TerraForest/AGENTS.md`, including
its focused-commit, identity-file and verification rules.

## Branch workflow

- `master` is the current development integration, not a production-release claim.
- Develop directly on `master` by default, using focused commits and relevant tests.
- Do not create feature branches or worktrees unless the user requests them.
- Coordinate parallel chats before overlapping edits, native builds or exports;
  serialize conflicting work rather than silently creating another branch.
- Tag approved playtest/release milestones. Keep known limitations explicit.
- Audit unique commits and worktree ownership before retiring old branches; do not
  rewrite published history or force-push as part of routine integration.

## Generated storage

- Use the existing main checkout for routine work. A test label is not a reason
  to create a worktree, source copy, full export or new saved world.
- Follow `TerraForest/docs/DEVELOPMENT_RETENTION.md`. Developer captures and
  isolated builds must pass `tools/development_storage.py` admission before
  allocating output, and use receipt-owned retention after the process exits.
- New launchers must declare planned output and an archival lifecycle. Reuse a
  fixture/build by hash when it is unchanged; keep at most two ordinary ready
  copies per test family unless a documented `.retain`/`RETAIN_READY` pin applies.
- Never silently raise a storage budget or evict saves/regression evidence to
  run another test. Restore archived evidence into a new inspection directory
  when needed; a cold archived artifact is not a missing or discarded result.
- Keep tool responses compact: report summaries and artifact paths instead of
  dumping whole traces, inventories, embedded image data or long logs into chat.
  Preserve full evidence in the bounded artifact lifecycle.
