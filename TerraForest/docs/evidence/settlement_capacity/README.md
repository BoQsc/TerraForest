# Settlement capacity preflight — 2026-10-15

NativeBlockPrefab.layout_counts reads source metadata and visits at most 1,024
building choices. It does not traverse/copy cells or create generated geometry.
The ordinal hash helper is shared with compose_frontage; row seeds retain uint32
wrap behavior. Counts are exact for block and attachment budgets, not an estimate
of rendering cost. Coordinate validity, source geometry overlap and site support
remain the existing composition/placement validators' responsibility.

Both the editor and prefab library check before dispatch. A rejected library
request starts no thread and creates no file. The editor keeps its dialog open.
Existing limits remain 262,144 blocks and 4,096 model attachments per prefab.

Nine count-versus-actual-generation cases cover seeds 0,1703,UINT32_MAX and one,
two,three streets. A 64-tower selection has 4,224 attachments and fails that limit
independently of block count. Oversized cottage counts and invalid arguments fail.
Preset UI regression passes including rejection without a generation signal.
The existing 26-check settlement network suite passes (roads, saved worker output,
catalog/persistence and atomic capacity rejection).

Debug and release DLLs rebuilt with pinned Zig/prebuilt godot-cpp; no SDK sources
rebuilt. Runtime checks used the debug DLL. No city-density, frame-time, release
runtime, larger-world storage or long-session qualification is claimed.
