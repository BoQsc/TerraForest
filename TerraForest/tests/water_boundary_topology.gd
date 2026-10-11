# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String):
    if not ok: failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var lake=ClassDB.instantiate("NativeLakeVolume")
    lake.configure(Vector3.ZERO,Vector3i(16,16,16),1,12.5,Vector3(4,10,8))
    var field:=PackedFloat32Array()
    for z in 17:
        for y in 17:
            for x in 17:
                var pocket:=minf(2.5-absf(x-4),minf(1.5-absf(y-4),2.5-absf(z-8)))
                var air:=maxf(y-8.5,pocket)
                air=minf(air,minf(x-0.5,minf(15.5-x,minf(z-0.5,15.5-z))))
                air=minf(air,absf(x-8)-0.6)
                field.append(air)
    check(lake.bake_density(field)==1,"sealed partial-cell lake bakes above closed chamber")
    var identity: PackedByteArray="boundary-topology-v2".sha256_buffer()
    var restored=ClassDB.instantiate("NativeLakeVolume")
    check(restored.restore_bake(lake.capture_bake(identity),identity),"boundary topology restores")
    for volume in [lake,restored]:
        check(volume.contains(Vector3(0.75,10,8)),"partial shoreline air is wet")
        check(not volume.contains(Vector3(0.25,10,8)),"partial shoreline solid is dry")
        check(not volume.contains(Vector3(4,4,8)) and not volume.submerges_root(Vector3(4,4,8)),"sealed chamber is dry for immersion and vegetation")
        check(not volume.contains(Vector3(12,10,8)) and not volume.contains(Vector3(8,10,8)),"thin dividing wall and disconnected basin are dry")
        check(volume.contains(Vector3(3.9999,10,8)) and volume.contains(Vector3(4,10,8)) and volume.contains(Vector3(4.0001,10,8)),"shared cell faces remain continuous")
        check(volume.contains(Vector3(4,12.499,8)) and not volume.contains(Vector3(4,12.5,8)) and not volume.contains(Vector3(4,12.501,8)),"fill boundary is strict")
        check(volume.submerges_root(Vector3(4,8.5,8)),"submerged ground contact excludes vegetation")
    var start:=Time.get_ticks_usec()
    var wet:=0
    for i in 100000:
        if lake.contains(Vector3(0.75,9.0+(i%30)*0.1,8)): wet+=1
    var elapsed:=Time.get_ticks_usec()-start
    check(wet==100000,"repeated partial-cell queries are stable")
    var result={"failures":failures,"queries":100000,"query_us_including_script_dispatch":elapsed,"statistics":lake.statistics()}
    var f=FileAccess.open("res://reports/water_boundary_topology.json",FileAccess.WRITE)
    f.store_string(JSON.stringify(result,"  "));f.close()
    print("WATER_BOUNDARY_TOPOLOGY failures=",failures)
    quit(1 if failures else 0)
