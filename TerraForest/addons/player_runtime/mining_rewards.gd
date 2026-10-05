# SPDX-License-Identifier: 0BSD
extends RefCounted
# Bounded orchestration only: native terrain counts samples and the native
# inbox validates capacity/receipts. No voxel or world scan runs in script.
var terrain: Node
var hud: Node
var failed:=false
func attach(world: Node,player_hud: Node) -> bool:
	if terrain!=null or world.edit_admission.is_valid(): return false
	terrain=world;hud=player_hud
	terrain.edit_admission=admit
	terrain.require_published_shutdown=true
	terrain.region_changed.connect(published)
	return true
func admit(commands: Array) -> bool:
	if failed: return false
	for packet: PackedByteArray in commands:
		if packet.size()!=44 or packet.decode_u32(0)!=2 or packet.decode_u32(36)!=0:
			terrain.message_changed.emit("Gameplay terrain tools excavate only; filling and grading are editor tools")
			return false
	# A validated group has <=4 commands. Even removing the entire finite
	# 2001*2001*256 lattice four times is below this conservative per-item bound.
	var reserve:=PackedInt64Array([201,4101000000,202,4101000000,203,4101000000])
	if not hud.reward_inbox.can_accept(reserve,maxi(terrain.density_revision,hud.reward_inbox.get_last_receipt())+1).ok:
		terrain.message_changed.emit("Claim pending resources before mining; reward storage is near capacity")
		return false
	return true
func published(_bounds: AABB,_revision: int) -> void:
	var outcome: Dictionary=terrain.last_edit_outcome
	if failed or outcome.get("status")!="published" or outcome.get("epoch")!=terrain.epoch: return
	var receipt: int=outcome.get("revision",0)
	if receipt==hud.reward_inbox.get_last_receipt(): return
	var counts: PackedInt64Array=outcome.get("removed_samples",PackedInt64Array())
	if counts.size()!=16: _fail("Missing native excavation accounting");return
	var items:=PackedInt64Array()
	for entry in [[201,counts[0]+counts[1]],[202,counts[8]],[203,counts[9]]]:
		if entry[1]>0: items.append_array(PackedInt64Array(entry))
	if items.is_empty(): return
	var accepted: Dictionary=hud.reward_inbox.accept(items,receipt)
	if not accepted.ok: _fail("Excavation reward rejected: "+str(accepted.reason));return
	terrain.changed_since_save=true
	if not hud.slots.is_empty(): hud.refresh()
	terrain.message_changed.emit("Mined resources are available in inventory under Pending materials")
func _fail(reason: String) -> void:
	failed=true
	terrain.latest_error=reason
	terrain.backend.disable_snapshot_writes(reason)
	terrain.message_changed.emit(reason+"; previous save protected")
