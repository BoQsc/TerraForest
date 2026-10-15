# Actor development controls, 2026-10-15

Enter development mode with ~ and choose toolbelt slot 9 (Actors). The persistent
HUD provides place, select/send, stop, remove and save buttons. Aim first, hold
Alt to click the action, then release Alt to look around. If simulation is off,
the panel offers Enable actor simulation; this activation is session-local.
Existing actor storage/orders keep their normal world-save behavior. Local
walking limits remain unchanged. This is development authoring, not an NPC
conversation, allegiance, job or combat-AI system.

Editor selection/removal now takes the exact native hit body's validated handle,
matching the attack path, rather than searching nearby positions with a capped
query. The main-world test deliberately places 80 dormant records at the same
position as one active proxy. The old lookup is incomplete; UI button selection,
stop and removal now succeed for the exact hit, clear selection and preserve all
80 other records. The test calls actual Button.pressed signals and physics rays;
it does not automate OS mouse clicks. The screenshot was visually inspected at
1920x1080. This fixture floats the actor above the world to isolate hit identity;
it does not test grounded placement or travel (covered by separate tests).

Command: python tools/run_godot_check.py actor_attack_identity --timeout 65
--require 'ACTOR_AUTHORING_UI failures=0' -- --authoring

The first test called an unbound C++ helper; the second incorrectly expected an
empty dictionary instead of the public API's present=false field. Both test
failures are retained alongside the corrected passing result. Runtime errors
were not suppressed. Temporary world; canonical saves untouched. No native
runtime, water or persistence-format changes.
