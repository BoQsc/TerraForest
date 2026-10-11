# SPDX-License-Identifier: 0BSD
# Required finite-water admission gate. Static full-cell seed policy fails this.
extends SceneTree
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var lake=ClassDB.instantiate("NativeLakeVolume")
    lake.configure(Vector3.ZERO,Vector3i(16,8,16),1,.12,Vector3(8,.11,8))
    var field:=PackedFloat32Array()
    for z in 17:
        for y in 9:
            for x in 17:field.append(y-(.1+.1*((x-8)*(x-8)+(z-8)*(z-8))))
    var status: int=lake.bake_density(field)
    var ok: bool=status==1 and lake.contains(Vector3(8,.11,8))
    print(("PASS " if ok else "FAIL ")+"shallow connected free-space seed admits finite pour source; status=",status)
    print("WATER_SHALLOW_SOURCE failures=",0 if ok else 1)
    quit(0 if ok else 1)
