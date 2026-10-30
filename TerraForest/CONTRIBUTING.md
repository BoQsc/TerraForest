# Contributing to TerraForest

TerraForest is a **public-domain-first project**, working toward 0BSD code and
CC0 assets. Existing third-party exceptions are retained and documented while we
work toward that goal. The current distribution is not entirely 0BSD/CC0.

## Terms for new original work

- Submit new original code under [0BSD](LICENSE.txt). This includes GDScript,
  shaders, C/C++, build tools and tests. Add `SPDX-License-Identifier: 0BSD` in the
  language's comment syntax for new standalone source files.
- Submit new original assets under [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/legalcode).
  This includes models, textures, audio, fonts, animations and non-code authoring
  data. Retain editable sources when available. For formats without comments,
  provide an adjacent notice or an asset-set manifest identifying exact paths,
  creator, source and CC0 dedication. Add the dedication only for rights you hold
  or are authorized to grant; a policy default is not proof of those rights.
- Confirm that you have the rights needed for your contribution. Disclose copied,
  adapted, generated or reference-derived material and its source. AI-assisted
  work follows the same intake requirements; retain relevant tool/prompt and
  reference provenance without committing credentials or private source material.

0BSD is a permissive software license; CC0 is a public-domain dedication with
fallback provisions. Neither label changes a third party's existing rights.
These prospective defaults do not replace existing grants, including retained
CC0 source code and 0BSD assets. Preserve their notices when making changes.

## Before importing or changing a dependency or asset

Record the following in the affected asset's notice/provenance file and, for an
exception or unresolved item, in the [license inventory](docs/LICENSE_INVENTORY.md):

1. Component/asset name, creator or rightsholder, and original source URL or
   supplied-package identity.
2. Exact upstream version/revision and a hash when practical. A file hash records
   identity; it does not establish licensing permission.
3. Exact license/dedication, retained text and attribution, and the evidence for
   its application to the particular files. Mark missing evidence `NOASSERTION`;
   do not infer public-domain status from availability or a nearby unrelated license.
4. Affected repository paths and derivatives, plus the relevant boundary: source
   archive, copied code, compiled/link-time code, game data, runtime distribution,
   or external build/authoring tool.
5. Any departure from the defaults, why it is needed, and its proposed future
   disposition or evidence needed to resolve it.

Prefer verified 0BSD code and CC0 assets. Any new or widened non-default or
unknown-license exception needs an explicit maintainer decision **before
admission**, recorded in the inventory with its scope and reason. Adding an
inventory entry alone does not approve an import. Existing recorded use may
continue within its scope; routine maintenance does not require renewed approval.
For upgrades, recheck terms, origins, copied files and binary contents and record
changes before expanding use.

Keep existing copyright statements, license texts and attribution. Do not remove
an upstream condition by changing a header. Future alternatives can include an
additional grant from the relevant rightsholders, an independently authored
replacement, or removal of an optional component. None is performed by this
policy change. Keep architecture boundaries clear where practical so later
replacement can be assessed independently.

## Source, tools and runnable distributions

The project-source/asset goal and a complete runnable distribution have different
boundaries. Godot is external engine infrastructure with MIT and other component
notices. godot-cpp and meshoptimizer contribute code to native libraries, so their
terms also matter when shipping those binaries. A source package can contain
third-party material even if it is unused by the main game.

Track build/authoring tools separately. Review any copied templates, embedded
resources, fonts, linked runtimes or other tool-supplied content in outputs;
using an external tool is not a blanket license grant for those outputs. Keep
actual artifact coverage and unresolved questions visible in the inventory.

## Review and validation

Keep changes focused. State the origin and terms of new material in the change
description. Update canonical notices, provenance, inventory and packaging when
their scope changes. If a source notice used by the offline credits bundle changes:

```text
python tools/build_credit_notices.py
python tools/build_credit_notices.py --check
```

Check that the relevant distribution actually includes the required notices.
Headers, file scans and the credits freshness check are evidence aids; they do
not prove ownership, complete binary coverage or an entirely 0BSD/CC0 release.
Automated admission enforcement is not added by this documentation change;
contributors and reviewers must apply these rules to each change.

Read [project agent and validation instructions](AGENTS.md). Preserve
matching Godot identity sidecars and unrelated working changes. The existing
exception inventory is an initial review, with remaining work explicitly listed.

Primary references: [0BSD text](https://opensource.org/license/0bsd),
[CC0 legal text](https://creativecommons.org/publicdomain/zero/1.0/legalcode), and
[Godot's distribution guidance](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).
