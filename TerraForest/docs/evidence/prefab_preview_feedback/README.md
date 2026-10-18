# Construction preview feedback - 2026-10-18

Furnished prefabs previously displayed green after checking only block occupancy and the player. Their models could still reject placement. The outline now displays amber for attachment or frontage checks that remain deferred until placement; red overrides amber for player, block or vehicle conflicts. Green means block space is clear, not that inventory or every placement constraint is satisfied. Construction selector tooltip and development HUD explain this distinction. Native transactional placement remains the authority and is unchanged.

The attachment classification is cached by selected resource, invalidated with the existing source/block change hook. Moving the aim does not repeatedly deep-copy attachment definitions. No speculative placement transaction or full model scan is added to the preview loop. Vehicle overlap uses the existing bounded vehicle protection query.

Actual-world graphical test uses a real camera ray against a disposable block fixture. It checks green block-only preview, amber furnished preview, red player overlap, byte-identical structure snapshots after preview and visible panel fit below 1080 pixels. Screenshot inspected at 1920x1080. Vehicle-specific preview colouring was not separately exercised by this test.

The older developer-belt fixture failed because it assumed gameplay at startup, enabled vegetation and text directly on item buttons. It now explicitly selects gameplay, enables its vegetation dependency and checks the actual item label. All 19 existing input/belt checks pass; retained stale_belt_fixture.log documents the two remaining stale assumptions after supplying the correct gameplay flag. No production input behavior was changed to make this pass.

Reproduce with tools/run_godot_check.py prefab_preview_feedback --timeout 65 --require 'PREFAB_PREVIEW_FEEDBACK failures=0' and developer_belt --timeout 65 --require 'failures=0'. Human saves and water unchanged. This improves truthful editor feedback; exact asynchronous model-conflict preview and general performance qualification remain open.
