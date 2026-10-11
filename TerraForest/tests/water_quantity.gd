# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String):
    checks+=1
    if not ok: failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func fresh(): return ClassDB.instantiate("NativeWaterQuantity")
func checksum(bytes: PackedByteArray):
    var value:=2166136261
    for i in range(16,bytes.size()): value=((value^bytes[i])*16777619)&0xffffffff
    bytes.encode_u32(12,value)
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var store=fresh()
    var lake: Dictionary=store.create(1000000000,500000000,0)
    var bucket: Dictionary=store.create(10000,0,1)
    check(lake.ok and bucket.ok,"finite lake and empty ten-litre container admitted")
    var before: PackedByteArray=store.capture_snapshot()
    check(not store.transfer(lake.id,bucket.id,10001,2).ok and before==store.capture_snapshot(),"overfull scoop is atomic rejection")
    check(store.transfer(lake.id,bucket.id,10000,2).ok and store.inspect(lake.id).amount_ml==499990000 and store.inspect(bucket.id).amount_ml==10000,"scoop subtracts exactly what container receives")
    before=store.capture_snapshot()
    check(not store.transfer(lake.id,bucket.id,10000,2).ok and store.capture_snapshot()==before,"replayed revision cannot duplicate water")
    check(not store.remove_empty(bucket.id,3).ok and store.capture_snapshot()==before,"filled container cannot discard its water")
    check(store.transfer(bucket.id,lake.id,4000,3).ok and store.inspect(bucket.id).amount_ml==6000,"partial pour retains container remainder")
    before=store.capture_snapshot()
    var rejected:=true
    for command in [[bucket.id,lake.id,6001],[bucket.id,bucket.id,1],[bucket.id,999,1],[bucket.id,lake.id,0],[bucket.id,lake.id,-1],[bucket.id,lake.id,9223372036854775807]]:
        rejected=rejected and not store.transfer(command[0],command[1],command[2],4).ok and before==store.capture_snapshot()
    check(rejected,"invalid transfers preserve both sides and revision")
    check(store.transfer(bucket.id,lake.id,6000,4).ok and store.remove_empty(bucket.id,5).ok,"empty container removal preserves lake quantity")
    check(store.create(10,0,6).id>bucket.id,"removed identities are not reused")
    var restored=fresh()
    check(restored.restore_snapshot(store.capture_snapshot()) and restored.capture_snapshot()==store.capture_snapshot(),"exact deterministic save and restore")
    check(not restored.restore_snapshot(before),"live ledger rejects save replay")
    # Independent integer oracle, many reservoirs and rejected transfers.
    var amounts: Array[int]=[];var ids: Array[int]=[];var capacities: Array[int]=[]
    var stress=fresh()
    for i in 64:
        capacities.append(10000+i*31);amounts.append(5000+i*7)
        ids.append(stress.create(capacities[i],amounts[i],i).id)
    var original_total: int=stress.statistics().total_ml
    var rng=RandomNumberGenerator.new();rng.seed=1703
    var correct:=true;var start:=Time.get_ticks_usec()
    for i in 20000:
        var a=rng.randi_range(0,63);var b=rng.randi_range(0,63);var n=rng.randi_range(1,15000)
        var accepted: bool=a!=b and amounts[a]>=n and capacities[b]-amounts[b]>=n
        var answer: Dictionary=stress.transfer(ids[a],ids[b],n,stress.statistics().revision)
        if accepted: amounts[a]-=n;amounts[b]+=n
        correct=correct and answer.ok==accepted and stress.inspect(ids[a]).amount_ml==amounts[a] and stress.inspect(ids[b]).amount_ml==amounts[b] and stress.statistics().total_ml==original_total
    var elapsed:=Time.get_ticks_usec()-start
    check(correct,"twenty thousand transfers match integer oracle with exact conservation")
    var saved: PackedByteArray=stress.capture_snapshot()
    restored=fresh()
    check(restored.restore_snapshot(saved) and restored.capture_snapshot()==saved,"stressed balances and identities persist exactly")
    var corrupt_ok:=true
    for offset in [0,4,8,12,16,24,32,40,44,48,saved.size()-1]:
        var corrupt:=saved.duplicate();corrupt[offset]^=1
        var target=fresh()
        corrupt_ok=corrupt_ok and not target.restore_snapshot(corrupt) and target.restore_snapshot(saved)
    check(corrupt_ok,"corrupt snapshots reject without poisoning fresh store")
    var forged:=saved.duplicate();forged.encode_u64(32,original_total+1);checksum(forged)
    check(not fresh().restore_snapshot(forged),"checksummed inconsistent total rejected")
    forged=saved.duplicate();forged.encode_u64(48+24,forged.decode_u64(48));checksum(forged)
    check(not fresh().restore_snapshot(forged),"checksummed duplicate identity rejected")
    forged=saved.duplicate();forged.encode_u64(48+8,forged.decode_u64(48+16)+1);checksum(forged)
    check(not fresh().restore_snapshot(forged),"checksummed over-capacity amount rejected")
    check(not fresh().restore_snapshot(saved.slice(0,saved.size()-1)),"truncated snapshot rejected")
    var full=fresh()
    var bounded:=true
    for i in 4096: bounded=bounded and full.create(1,0,i).ok
    before=full.capture_snapshot()
    check(bounded and not full.create(1,0,4096).ok and full.capture_snapshot()==before,"record cap rejects atomically at 4096")
    var extreme=fresh()
    check(extreme.create(9007199254740991,9007199254740991,0).ok and not extreme.create(1,1,1).ok,"aggregate quantity overflow rejected")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_quantity.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"stress_commands":20000,"stress_us_including_script_oracle":elapsed,"max_record_snapshot_bytes":before.size(),"scope":"Native finite-quantity transactions only; no spatial flow, bucket gameplay or world-save integration yet."},"  "));file.close()
    print("WATER_QUANTITY failures=",failures);quit(1 if failures else 0)
