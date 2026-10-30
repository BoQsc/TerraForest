# World-building work

## Public-domain-first policy

Public-domain-first is a core project goal. Use **0BSD for new original code**
(including scripts, shaders, native code, tests and tools) and **CC0-1.0 for new
original assets** (including models, textures, audio, fonts, animations and
non-code authoring data). Follow [contribution and intake rules](CONTRIBUTING.md).
The policy covers human and AI-assisted work, copied snippets, vendored code,
embedded resources and material linked into distributed binaries.

Preserve inherited licenses and notices. Existing CC0 code and 0BSD assets retain
their terms; new defaults do not authorize rewriting their license declarations.
Keep copyright-bearing upstream portions identifiable when modifying them.

Before importing material, record its source/author, version or hash, exact terms,
affected paths and whether it is copied, linked, bundled or only used externally.
Prefer original work and verified default-compatible inputs. Missing license text,
"free", public availability or AI generation alone is not evidence of permission.
Do not copy an implementation and relabel it as original 0BSD/CC0 work.

Use [the license inventory](docs/LICENSE_INVENTORY.md) and
[`license_inventory.json`](license_inventory.json) for existing non-default terms
and provenance gaps. Listed existing use may continue within its recorded scope.
New or widened exceptions require a recorded proposal and an explicit maintainer
decision before admission; inventorying a proposal does not approve it. Routine
maintenance of listed use does not require renewed permission, but upgrades must
be checked for changed terms or new content.

Update provenance, inventory and applicable distribution notices together when
their scope changes. If a retained notice used by the credits viewer changes,
rebuild `assets/credits/notices.json` with `tools/build_credit_notices.py` and run
its `--check` mode. Do not claim a wholly 0BSD/CC0 distribution while exceptions,
unresolved provenance or binary-runtime coverage remain. Inventorying an exception
does not authorize dependency replacement; follow the current task's scope.

## Commit preference

User direction, 2026-10-25: commit completed, verified work by default rather
than waiting for another commit request. Keep commits focused, include matching
Godot UIDs, and document remaining work without claiming it is complete. Do not
include unrelated user changes. A later explicit no-commit instruction overrides
this preference. Committing does not authorize pushing; push only when requested.

## Godot identity files

Commit Godot `.uid` sidecars with their corresponding source files. They are
versioned resource identities, not disposable import cache. Let Godot generate
them for new resources, then include them when staging the source; check for
sidecars created by a later import before completing a commit.

This repository provides `.githooks/pre-commit` at the Git root to stage matching
UIDs automatically. Enable it per checkout with
`git config --local core.hooksPath .githooks` when no existing hook configuration
would be replaced. Do not add unrelated source changes or cache/report output
while collecting UID sidecars.

## Unfinished-work tracking

Never silently abandon unfinished work or report partial verification as completion.
Before switching milestones, record any remaining requirement in
`docs/WORLD_FOUNDATION_STATUS.md` (or link its dedicated contract from there).
Record what is missing, why it is deferred, its prerequisite or return trigger,
and the evidence required to close it. Keep failed and unreviewed checks visible.
When a prerequisite is completed, revisit dependent work; update the existing entry
instead of letting a newer progress note imply the old requirement is resolved.
Deferral is not completion. Do not expand excluded features to clear a backlog.

## Visual issue tracker

Use `issues/README.md` for player-visible bugs and partial fixes. Maintain one stable
`issues/<descriptive-name>/` folder per issue, following `issues/TEMPLATE.md`. Keep
status, remaining work, reproduction, code/commits, captioned images and provenance.
Preserve earlier/rejected comparisons. Distinguish scoped engineering verification
from universal resolution and user visual approval. Update the issue/index and
linked foundation status together. Link existing logs rather than moving them.
Keep tracker images out of Godot imports and game exports.

## Design and validation

For world generation, settlement, road, POI or landscape changes, read
`docs/WORLD_BUILDING_STANDARD.md` before choosing the implementation.

For entity navigation, traversal, pursuit or world-interaction changes, read
`docs/NAVIGATION_STANDARD.md` before choosing the implementation. Reuse the native
route core, declare movement capabilities and interaction permissions, keep one
body-integration owner, and retain explicit blocked/unavailable states and budgets.
Local steering and repeated local horizons do not qualify whole-world navigation.

Keep engineering verification separate from world-quality acceptance. Passing
generation, persistence, movement or performance checks does not override visible
design defects. Inspect relevant generated images before reporting visual success.
Report rejected and unreviewed requirements plainly; do not silently lower the
standard to match the current implementation.

The current northern single-pad district is a development draft, rejected for
terrain fit and visual variety. Prioritize a terrain-fitting block/lot layout over
decorating that rejected layout. Existing user saves must remain intact.

These rules do not prohibit development builds for diagnosis or require additional
user permission. Use short targeted checks, followed by integrated evidence where
the change affects the actual world. Preserve 0BSD and native runtime hot paths.
