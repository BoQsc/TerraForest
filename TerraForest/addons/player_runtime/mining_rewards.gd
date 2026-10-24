# SPDX-License-Identifier: 0BSD
extends RefCounted
# Bounded orchestration only: native terrain counts samples and the native
# inbox validates capacity/receipts. No voxel or world scan runs in script.
var terrain: Node
var hud: Node
var failed:=false
var enabled:=true
const TERRAIN_ITEMS={201:1,202:8,203:9,211:10}
var payment:Dictionary={}
var last_reward_ticket:=-1
var last_reward_epoch:=-1
func attach(world: Node,player_hud: Node) -> bool:
	if terrain!=null or world.edit_admission.is_valid(): return false
	terrain=world;hud=player_hud
	terrain.edit_admission=admit
	terrain.require_published_shutdown=true
	terrain.region_changed.connect(published)
	terrain.edit_resolved.connect(resolved)
	return true
func place(cell:Vector3i,item:int,slot:int) -> bool:
	if not enabled or failed or not payment.is_empty() or not TERRAIN_ITEMS.has(item) or terrain.pending_edit or not terrain.world_ready:return false
	hud.deliver_mining_rewards()
	if not hud.reward_inbox.get_pending().is_empty():return false
	var state:Dictionary=hud.inventory.snapshot()
	if slot<0 or slot>=32 or state.slots[slot].item!=item:return false
	var packet:PackedByteArray=terrain.Codec.command(38,[cell.x,cell.y,cell.z,TERRAIN_ITEMS[item]])
	if not hud.inventory.consume(slot,1,state.revision).ok:return false
	payment={"packet":packet,"item":item,"epoch":terrain.epoch,"ticket":terrain.edit_ticket+1}
	# The queued compound snapshot already includes the debit. Shutdown waits
	# for publication; rejected/no-op edits refund through the saved reward inbox.
	if not terrain.edit(packet,Vector3(cell),Vector3(cell)):
		refund();return false
	if not hud.slots.is_empty():hud.refresh()
	return true
func refund()->void:
	if payment.is_empty():return
	var item:int=payment.item;payment={}
	if not hud.reward_inbox.accept(PackedInt64Array([item,1]),hud.reward_inbox.get_last_receipt()+1).ok:
		_fail("Terrain placement refund could not be recorded");return
	hud.deliver_mining_rewards()
	if not hud.slots.is_empty():hud.refresh()
func resolved(outcome:Dictionary)->void:
	if payment.is_empty() or outcome.epoch!=payment.epoch or outcome.ticket!=payment.ticket:return
	if outcome.status in ["rejected","unchanged"]:
		refund();terrain.message_changed.emit("Terrain already filled or placement unavailable; material returned")
	elif outcome.status=="building":payment={}
func admit(commands: Array) -> bool:
	if not enabled:return true
	if failed: return false
	hud.deliver_mining_rewards()
	if not hud.reward_inbox.get_pending().is_empty():
		terrain.message_changed.emit("Inventory full; make room before mining again");return false
	for packet: PackedByteArray in commands:
		if commands.size()==1 and not payment.is_empty() and packet==payment.packet:continue
		if packet.size()!=44 or packet.decode_u32(0)!=2 or packet.decode_u32(36)!=0:
			terrain.message_changed.emit("Equip carried soil, stone or ore to fill terrain; grading requires development mode")
			return false
	# A validated group has <=4 commands. Even removing the entire finite
	# 2001*2001*256 lattice four times is below this conservative per-item bound.
	var reserve:=PackedInt64Array([201,4101000000,202,4101000000,203,4101000000,211,4101000000])
	if not hud.reward_inbox.can_accept(reserve,maxi(terrain.density_revision,hud.reward_inbox.get_last_receipt())+1).ok:
		terrain.message_changed.emit("Inventory overflow storage is full; make room before mining")
		return false
	return true
func published(_bounds: AABB,_revision: int) -> void:
	if not enabled:return
	var outcome: Dictionary=terrain.last_edit_outcome
	if failed or outcome.get("status")!="published" or outcome.get("epoch")!=terrain.epoch: return
	if last_reward_epoch==outcome.epoch and last_reward_ticket==outcome.ticket:return
	last_reward_epoch=outcome.epoch;last_reward_ticket=outcome.ticket
	var receipt: int=maxi(outcome.get("revision",0),hud.reward_inbox.get_last_receipt()+1)
	var counts: PackedInt64Array=outcome.get("removed_samples",PackedInt64Array())
	if counts.size()!=16: _fail("Missing native excavation accounting");return
	var items:=PackedInt64Array()
	for entry in [[201,counts[0]+counts[1]],[202,counts[8]],[203,counts[9]],[211,counts[10]]]:
		if entry[1]>0: items.append_array(PackedInt64Array(entry))
	if items.is_empty(): return
	var accepted: Dictionary=hud.reward_inbox.accept(items,receipt)
	if not accepted.ok: _fail("Excavation reward rejected: "+str(accepted.reason));return
	terrain.changed_since_save=true
	hud.deliver_mining_rewards()
	if not hud.slots.is_empty(): hud.refresh()
	terrain.message_changed.emit("Mined resources added to inventory" if hud.reward_inbox.get_pending().is_empty() else "Inventory full; remaining mined resources are saved and will enter automatically when space is available")
func _fail(reason: String) -> void:
	failed=true
	terrain.latest_error=reason
	terrain.backend.disable_snapshot_writes(reason)
	terrain.message_changed.emit(reason+"; previous save protected")
