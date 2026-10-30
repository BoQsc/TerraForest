# License exceptions and provenance inventory

Reviewed 2026-10-30. Policy: [CONTRIBUTING.md](../CONTRIBUTING.md).
Authoritative component records: [`license_inventory.json`](../license_inventory.json).
Paths in those records are relative to the inventory file's directory
(`TerraForest/` in this repository). Scope paths identify component use and review
boundaries; they do not assign one license to every file in a matching folder.
Canonical and more specific file notices remain authoritative; inventory entries
do not grant or change rights.

This initial review covers retained notices, both vendored meshoptimizer copies,
native build/link configuration, source-archive/export rules, asset authoring
notes and metadata from 32 tracked GLBs. It is not a complete file-by-file rights
audit or a certification of native-binary/runtime license coverage. A GLB's
generator field and an asset's file hash are not license grants.

## Current records

| ID | Material | Current terms / boundary | Disposition |
| --- | --- | --- | --- |
| EX-001 | Godot engine and bundled components | MIT plus build-specific component terms; external runtime | Retain engine notices; keep separate from project-source purity claims. |
| EX-002 | godot-cpp | MIT; pinned SDK statically linked into native addons | Retain notices; later assess binding boundaries or additional grants. |
| EX-003 | Legacy Godot C ABI declarations | MIT; retained source, legacy bridge excluded from the current terrain build | Preserve the engine notice even while code is inactive. |
| EX-004 | Runtime meshoptimizer 0.25 | MIT; vendored CPU simplifier compiled into structures | Preserve upstream notices and shipped MIT notice; replacement deferred. |
| EX-005 | Test/probe meshoptimizer 1.1 subset | MIT; separate pinned source copy in tests | Preserve header notice and manifest; source archives retain test dependencies too. |
| EX-006 | Godot splash/logo artwork | CC BY 4.0; original PNG and composite boot PNG | Preserve attribution and modification note; future CC0 branding is a separate decision. |
| GAP-001 | Inherited terrain textures | No established new license grant; source note only | Obtain original rights evidence or separately authorize replacement. |
| GAP-002 | Inherited character base and derivatives | CC0 stated for original/derivative work; inherited-source scope retained | Verify the original asset chain rather than treating the derivative notice as universal proof. |
| GAP-003 | Optional AK-47 comparison asset | No explicit grant found in retained asset/viewer readmes | Not loaded by the main-world integration, but retained in source; obtain rights evidence before expanding use. |
| LEG-001 | Original woodland sample assets | Existing 0BSD declaration | Keep 0BSD; any additional CC0 dedication requires the relevant rights and an explicit scoped declaration. |
| LEG-002 | Supplied vehicle model | Existing 0BSD author declaration | Keep its current grant; code already follows the code default. |
| LEG-003 | Original Zombie Lab source code | Existing CC0 dedication | Preserve CC0 source and file-specific notices; no blanket rewrite to the new code default. |
| GAP-004 | Optional image-generated grass detail textures | Prompt/tool provenance retained; CC0 scope not established separately | Review output/reference rights and declaration scope before claiming CC0 coverage. |
| INF-001 | Build/authoring tools and linked runtimes | External software plus unreviewed output/runtime coverage | Audit actual shipped artifacts and their notices; toolchain pins alone do not certify output licensing. |

`EX` records known non-default terms retained for existing use. `LEG` records
existing grants that differ from the new code/asset defaults. `GAP` records
unresolved evidence, not an assertion that an asset is unlicensed. `INF` records
infrastructure and artifact-review boundaries. Recording current use does not
approve new imports or certify redistribution rights where evidence is missing.

The initial retention decision is the maintainer's 2026-10-30 instruction to
inventory existing exceptions without replacing dependencies. It authorizes
recording and preserving existing scope, not relicensing or broader redistribution.

## Material already aligned with the defaults

- TerraForest-authored project code is declared 0BSD in the project license and
  applicable source headers. Separately identified inherited parts keep their terms.
- Supplied spruce derivatives retain a stated CC0 dedication and the source GLB
  hash in `addons/vegetation/ASSET_LICENSE.md`. This records the supplied declaration;
  it is not an independent investigation of every upstream right.
- Character assets have stated CC0 notices; GAP-002 records the inherited-rights
  verification still needed. These are separate from the optional GAP-003 asset.

## Admission and maintenance

Before a new import, follow the contribution intake requirements. For a new or
widened exception, add a proposed record with source/version, paths, terms, reason
and future disposition, obtain an explicit maintainer decision, then record that
decision. A proposal alone is not approval. Recheck terms on upgrades. Ordinary
maintenance of the listed existing use does not need repeated permission.

Keep component records current when source, versions, paths or distribution
boundaries change. Preserve canonical notices and keep any applicable offline
credit notices and distribution copies synchronized. A record may be closed only
with evidence that its issue has been resolved, including affected derivatives,
copies and compiled artifacts. Replacing a file in the latest build does not
retroactively change terms on historical releases.

## Remaining review and closure evidence

Dependency replacement is deliberately deferred by the current task. Revisit a
record on an explicit migration request, an upgrade, a scope expansion or new
rights evidence. Its `next_step` and `closure_evidence` fields identify the work
required; none is marked resolved by adding this inventory.

Still needed: a full source/asset-to-notice map, original evidence for the GAP
items, per-artifact linkage/runtime and notice verification, review of remaining
binary/authoring assets, and automated admission checks. The runtime credits list
is a display of retained notices and engine information, not a complete license
bill of materials. Godot's component list varies with the engine build.

Validation for this documentation change checks JSON structure, record IDs,
referenced local evidence/scopes, documentation links and unchanged credits
freshness. No dependencies, license grants, assets, binaries or runtime behavior
are changed by it.
