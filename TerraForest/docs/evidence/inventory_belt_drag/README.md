# Inventory and toolbelt drag access

2026-10-11. Removed the fullscreen inventory dimmer and made the fullscreen
layout root ignore mouse hit-testing. Panels retain their own input handling;
the existing native inventory transfer path now receives toolbelt drops.
Inventory-open belt clicks select the same underlying slot; dragging never
automatically equips a different slot. Moving/swapping the currently equipped
slot's contents updates the held tool normally. Selection styles clear on close.

Extended inventory_presentation: 22 checks, zero failures. Real mouse drags cover
belt to inventory, inventory to belt, empty destinations, occupied-slot swapping,
Shift-splitting and merging with conserved quantities. Earlier recipe checks
remain. Reward/claim UI also passes. Both use fullscreen 1920x1080; these are
functional checks, not sustained performance measurements. Screenshot inspected.
The first split test omitted the synthetic Shift event's logical keycode; fixing
the fixture to send both logical and physical Shift made the actual gesture pass.
