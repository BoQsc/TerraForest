extends SceneTree

class Structures extends Node:
	var blocks: Node3D
class Fixture extends Node:
	var structures:=Structures.new()
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func legacy(blocks:Node3D)->Dictionary:
	var result:Dictionary={}
	var state:Dictionary=blocks.capture_storage_state()
	var keys:PackedInt32Array=state.unavailable_keys
	for index in keys.size()/3:
		result["%d,%d,%d"%[keys[index*3],keys[index*3+1],keys[index*3+2]]]=state.unavailable_checksums.slice(index*32,(index+1)*32).hex_encode()
	for region_x in 32:
		for region_y in 4:
			for region_z in 32:
				var key:="%d,%d,%d"%[region_x,region_y,region_z]
				if result.has(key):continue
				var packet:PackedByteArray=blocks.capture_region(Vector3i(region_x,region_y,region_z))
				if packet.size()>=100 and packet.decode_u32(32)>0:result[key]=packet.slice(packet.size()-32).hex_encode()
	return result
func run()->void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var task=load("res://addons/world_runtime/generate_world_task.gd").new()
	var game:=Fixture.new();game.structures.blocks=ClassDB.instantiate("NativeBlockWorld")
	var blocks:Node3D=game.structures.blocks
	check(task.block_signature(game)==legacy(blocks),"empty generation signature unchanged")
	var cells:=PackedInt32Array()
	for index in 32:
		cells.append_array(PackedInt32Array([index*64+1,10,65,1]))
	check(blocks.set_cells(cells),"author sparse generation fixture")
	var begin:=Time.get_ticks_usec();var old:Dictionary=legacy(blocks);var old_us:=Time.get_ticks_usec()-begin
	begin=Time.get_ticks_usec();var current:Dictionary=task.block_signature(game);var new_us:=Time.get_ticks_usec()-begin
	check(current==old and current.size()==32,"indexed signature matches every previous digest")
	var packet:PackedByteArray=blocks.capture_region(Vector3i(5,0,1))
	check(blocks.unload_region(packet) and task.block_signature(game)==current,"unloaded regions reuse authoritative checksum without disk reads")
	check(blocks.restore_region(packet,PackedByteArray()) and task.block_signature(game)==current,"resident and paged representations have same signature")
	blocks.set_cells(PackedInt32Array([1,10,65,2]))
	check(task.block_signature(game)!=current and task.block_signature(game)==legacy(blocks),"mutation changes only current authoritative signature")
	blocks.set_cells(PackedInt32Array([-65,10,0,1,65,300,0,1]))
	var extended:Dictionary=task.block_signature(game)
	check(extended.has("-2,0,0") and extended.has("1,4,0"),"index also covers authored regions outside old fixed scan box")
	print("GENERATION_BLOCK_SIGNATURE failures=",failures," old_us=",old_us," indexed_us=",new_us," calls=4096 -> 32")
	blocks.free();game.structures.free();game.free();task.free();quit(1 if failures else 0)
