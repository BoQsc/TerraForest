# Generated settlement supplies — 2026-10-18

District preparation now stocks generated chests through NativeContainerStore.
Sorted placement identities and the world seed determine modest wood/stone stocks,
plus plant material in housing or ore in the eastern service district. This is an
offline authoring operation; gameplay has no restocking timer or discovery scan.
Existing saves are not retroactively modified. Contents use normal persistence,
withdrawal and removal protection. Player inventory is never used as the source.

The preparation signature now includes chest_contents, closing a verification gap
where furniture identity was checked without comparing stored items. Failed
stocking restores the initial empty store and releases protection on touched chests.
Attempts to populate a nonempty store refuse without overwriting its contents.

Actual district creation and fresh-process reopen passed, publishing the named
world regional_supplies_20261018 (select it in Worlds.cmd). All 41 chests are stocked;
both phases compare exact saved contents along with the existing world components.
The 10 Python preparation orchestration tests also pass.

The targeted read-only integration test checks repeat-preparation refusal, unchanged
player inventory, all chest identities/removal protection, ordinary native withdrawal
and exact container serialization. Its initial run against the older empty world
passed in 19.82 seconds. The checked-in test additionally compares deterministic
repopulation when starting with an empty store. This is not a large-city performance
qualification, a loot balancing claim, or a human UI interaction test.

The first published-world check failed its 60-second loading deadline. An identical
retry with failure-only readiness logging passed in 20.24 seconds, including saved
contents/protection and withdrawal. Both results are retained. No loading fix was
made; intermittent startup readiness remains open. The new named world is available
in Worlds.cmd, but generated_world_v4 remains the default and is not overwritten.
