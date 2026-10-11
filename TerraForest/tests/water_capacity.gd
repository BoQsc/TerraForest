# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var costs: Array=[]
func check(ok: bool,label: String):
    checks+=1
    if not ok: failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func basin(divide:=false,roof:=false,scale:=1.0):
    var lake=ClassDB.instantiate("NativeLakeVolume")
    lake.configure(Vector3.ZERO,Vector3i(8,6,8),scale,4.5*scale,Vector3(2.5,1.5,2.5)*scale)
    var field:=PackedFloat32Array()
    for z in 9:
        for y in 7:
            for x in 9:
                field.append(0.0 if x==0 or x==8 or z==0 or z==8 or y==0 or (divide and x==4) or (roof and y==3) else 1.0)
    check(lake.bake_density(field)==1,"analytic tank bakes")
    return lake
func measure(lake,budget:int):
    var task=ClassDB.instantiate("NativeWaterCapacity")
    check(task.begin(lake),"capacity measurement retains ready immutable source")
    var before: Dictionary=task.statistics()
    check(not task.step(0).ok and not task.step(2049).ok and task.statistics()==before,"invalid work budgets preserve progress")
    var bounded:=true;var calls:=0;var max_us:=0
    var start:=Time.get_ticks_usec()
    while task.statistics().status==0 and calls<300000:
        var begun:=Time.get_ticks_usec();var slice: Dictionary=task.step(budget)
        max_us=maxi(max_us,Time.get_ticks_usec()-begun)
        bounded=bounded and slice.work_cells<=budget and slice.work_cells>0
        if slice.status==0:bounded=bounded and slice.amount_ml==0
        calls+=1
    var result: Dictionary=task.statistics()
    check(bounded and result.status==1 and result.processed_cells==result.cells,"measurement resumes under declared cell budget without publishing partial quantity")
    check(task.step(budget).work_cells==0 and task.statistics()==result,"completed measurement does no further work")
    costs.append({"amount_ml":result.amount_ml,"m3":result.cubic_metres,"cells":result.cells,"budget":budget,"calls":calls,"total_us":Time.get_ticks_usec()-start,"max_call_us":max_us})
    return result
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var invalid=ClassDB.instantiate("NativeWaterCapacity")
    check(not invalid.begin(ClassDB.instantiate("NativeLakeVolume")) and not invalid.step(1).ok,"unfinished volume rejected")
    var lake=basin()
    var slow: Dictionary=measure(lake,1);var fast: Dictionary=measure(lake,2048)
    check(slow.amount_ml==276500000 and slow.cubic_metres==276.5,"sampled tank matches independent exact tetrahedral integral")
    check(slow==fast,"different scheduler budgets produce identical quantity")
    check(measure(basin(true),32).amount_ml==134500000,"disconnected basin contributes no quantity")
    check(measure(basin(false,true),32).amount_ml==175000000,"solid roof prevents counting disconnected air above it")
    check(measure(basin(false,false,2),32).amount_ml==2212000000,"scaled grid uses cubic physical units")
    # Curved sampled terrain exercises mixed-sign cuts. Independent point
    # integration checks measurement against the already-tested immersion query.
    var curved=ClassDB.instantiate("NativeLakeVolume")
    curved.configure(Vector3.ZERO,Vector3i(16,12,16),1,8,Vector3(8,4,8))
    var field:=PackedFloat32Array()
    for z in 17:
        for y in 13:
            for x in 17:field.append(y-(2.0+((x-8)*(x-8)+(z-8)*(z-8))/6.0))
    check(curved.bake_density(field)==1,"curved sampled terrain capacity fixture bakes")
    var amount: Dictionary=measure(curved,32)
    var wet:=0
    for z in 64:
        for y in 32:
            for x in 64:
                if curved.contains(Vector3((x+.5)*.25,(y+.5)*.25,(z+.5)*.25)):wet+=1
    var reference:=wet/64.0
    check(absf(amount.cubic_metres-reference)<reference*.005,"clipped tetrahedron volume agrees with independent quarter-metre point integration within 0.5 percent")
    var cache: PackedByteArray=curved.capture_bake("capacity".sha256_buffer())
    var restored=ClassDB.instantiate("NativeLakeVolume")
    check(restored.restore_bake(cache,"capacity".sha256_buffer()),"geometry cache restores")
    check(measure(restored,127)==amount,"restored connectivity and density reproduce quantity exactly")
    var quantities=ClassDB.instantiate("NativeWaterQuantity")
    var body: Dictionary=quantities.create(amount.amount_ml,amount.amount_ml,0)
    var bucket: Dictionary=quantities.create(10000,0,1)
    check(quantities.transfer(body.id,bucket.id,10000,2).ok and quantities.statistics().total_ml==amount.amount_ml,"measured terrain quantity initializes conserved scoop transaction")
    var big=ClassDB.instantiate("NativeLakeVolume")
    big.configure(Vector3.ZERO,Vector3i(64,64,64),1,48.5,Vector3(32,24,32))
    field=PackedFloat32Array()
    for z in 65:
        for y in 65:
            for x in 65:field.append(0.0 if x==0 or x==64 or z==0 or z==64 or y==0 else 1.0)
    check(big.bake_density(field)==1,"maximum-cell capacity fixture bakes")
    var large: Dictionary=measure(big,256)
    check(large.amount_ml==198544500000,"maximum-cell tank has exact geometric quantity")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_capacity.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"costs":costs,"curved_m3":amount.cubic_metres,"reference_m3":reference,"scope":"Resumable geometric volume measurement only, not flow or water-level response."},"  "));file.close()
    print("WATER_CAPACITY failures=",failures);quit(1 if failures else 0)
