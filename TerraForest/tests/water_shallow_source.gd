# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func source(seed: Vector3,center_x:=8.0):
    var lake=ClassDB.instantiate("NativeLakeVolume")
    lake.configure(Vector3.ZERO,Vector3i(16,8,16),1,.12,seed)
    var field:=PackedFloat32Array()
    for z in 17:
        for y in 9:
            for x in 17:field.append(y-(.1+.1*((x-center_x)*(x-center_x)+(z-8)*(z-8))))
    var status: int=lake.bake_density(field)
    return {"lake":lake,"status":status}
func measure(lake):
    var task=ClassDB.instantiate("NativeWaterCapacity")
    if not task.begin(lake):return -1
    for i in 100:
        var result: Dictionary=task.step(32)
        if result.status==1:return result.amount_ml
    return -1
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var built: Dictionary=source(Vector3(8,.11,8))
    var lake=built.lake
    check(built.status==1 and lake.contains(Vector3(8,.11,8)),"shallow positive-density seed admits two-centimetre puddle")
    if built.status!=1:
        print("WATER_SHALLOW_SOURCE failures=",failures);quit(1);return
    check(lake.statistics().wet_cells==0,"puddle needs no completely air-filled cells")
    check(not lake.contains(Vector3(8,.09,8)) and not lake.contains(Vector3(8,.13,8)),"ground and air above water stay dry")
    var mesh: Array=lake.smooth_surface_arrays()
    check(not mesh[Mesh.ARRAY_INDEX].is_empty(),"partial-cell puddle has visible surface geometry")
    var amount: int=measure(lake)
    # Locally, sampled floor is .1 + .1*(abs(x-8)+abs(z-8)).
    # Diamond area .08m2 * .02m depth / 3 = .000533333m3 = 533.333ml.
    check(amount==533,"geometric partial-cell quantity is sub-litre and matches analytic integral")
    var identity="shallow-source".sha256_buffer()
    var saved: PackedByteArray=lake.capture_bake(identity)
    var restored=ClassDB.instantiate("NativeLakeVolume")
    check(not saved.is_empty() and restored.restore_bake(saved,identity),"cache admits connected volume with zero full cells")
    check(restored.contains(Vector3(8,.11,8)) and measure(restored)==amount and restored.capture_bake(identity)==saved,"shallow queries and quantity survive exact cache round trip")
    check(source(Vector3(8,.09,8)).status==-2,"seed inside terrain still rejected")
    var leaking: Dictionary=source(Vector3(.05,.115,8),0.0)
    check(leaking.status==-3 and not leaking.lake.contains(Vector3(.05,.115,8)),"partial-cell opening at domain edge rejects entire puddle")
    var quantities=ClassDB.instantiate("NativeWaterQuantity")
    var body: Dictionary=quantities.create(amount,amount,0)
    var bucket: Dictionary=quantities.create(10000,0,1)
    check(quantities.transfer(body.id,bucket.id,amount,2).ok and quantities.inspect(body.id).amount_ml==0 and quantities.inspect(bucket.id).amount_ml==amount,"sub-litre body quantity can transfer exactly to container ledger")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_shallow_source.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"amount_ml":amount,"scope":"Partial-cell admission/geometry/cache/quantity only; no live bucket, drainage or level response."},"  "));file.close()
    print("WATER_SHALLOW_SOURCE failures=",failures);quit(1 if failures else 0)
