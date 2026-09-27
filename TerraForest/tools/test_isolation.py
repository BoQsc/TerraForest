"""Prove each core addon starts in its own otherwise empty Godot project."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',default=os.environ.get('GODOT_EXE') or shutil.which('godot'))
args=p.parse_args()
if not args.godot:p.error('Specify --godot PATH')
engine=Path(args.godot)
direct=engine.parent/'godot.windows.opt.tools.64.exe'
if direct.exists():engine=direct
build=root/'.build'
build.mkdir(exist_ok=True)
reports=[]
tests={
    'structures': '''extends SceneTree
func _initialize():
    call_deferred("run")
func run():
    GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
    var world = ClassDB.instantiate("NativeBlockWorld")
    root.add_child(world)
    var success = world.set_cells(PackedInt32Array([0,0,0,1,1,0,0,1]))
    world.flush_bakes()
    success = success and world.stats().triangles == 12 and world.validate_snapshot(world.capture_snapshot())
    world.free()
    print("ISOLATION_OK" if success else "ISOLATION_FAIL")
    quit(0 if success else 1)
''',
    'volumetric_water': '''extends SceneTree
func _initialize():
    call_deferred("run")
func run():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var water = ClassDB.instantiate("NativeLakeVolume")
    var success = water.configure(Vector3.ZERO,Vector3i(8,8,8),1,4.5,Vector3(3,3,3))
    var density = PackedFloat32Array()
    for z in range(9):
        for y in range(9):
            for x in range(9):
                density.append(-1 if x==0 or z==0 or y==0 or x==8 or z==8 else 1)
    success = success and water.bake_density(density)==1 and water.contains(Vector3(3,3,3))
    water = null
    print("ISOLATION_OK" if success else "ISOLATION_FAIL")
    quit(0 if success else 1)
''',
    'volumetric_terrain': '''extends SceneTree
const Runtime = preload("res://addons/volumetric_terrain/terrain_world.gd")
var world = Runtime.new()
func _initialize():
    call_deferred("run")
func run():
    root.add_child(world)
    world.diagnostics_pause_streaming = true
    if world.start(null, true) != OK:
        quit(1)
        return
    var end = Time.get_ticks_msec() + 15000
    while not world.world_ready and Time.get_ticks_msec() < end:
        await process_frame
    var success = world.world_ready
    world.shutdown()
    world.free()
    print("ISOLATION_OK" if success else "ISOLATION_FAIL")
    quit(0 if success else 1)
''',
    'vegetation': '''extends SceneTree
const Runtime = preload("res://addons/vegetation/vegetation_world.gd")
func _initialize():
    call_deferred("run")
func run():
    var world = Runtime.new()
    root.add_child(world)
    var success = world.initialize() == OK
    var transforms: Array[Transform3D] = [Transform3D.IDENTITY]
    success = success and world.upsert_chunk("standalone", PackedInt64Array([1]), transforms)
    world.clear()
    world.free()
    print("ISOLATION_OK" if success else "ISOLATION_FAIL")
    quit(0 if success else 1)
'''
}
for addon,script in tests.items():
    with tempfile.TemporaryDirectory(prefix='isolation_',dir=build) as temporary:
        project=Path(temporary).resolve()
        # Verify the automatic recursive cleanup target is inside this build directory.
        assert build.resolve() in project.parents
        shutil.copytree(root/'addons'/addon,project/'addons'/addon)
        (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="TerraForest Isolation"\n',encoding='utf-8')
        (project/'test.gd').write_text(script,encoding='utf-8')
        run=subprocess.run([str(engine),'--headless','--path',str(project),'--script','res://test.gd'],capture_output=True,text=True,timeout=60)
        log=run.stdout+'\n'+run.stderr
        ok=run.returncode==0 and 'ISOLATION_OK' in log and 'ERROR:' not in log and 'instances leaked' not in log
        reports.append({'addon':addon,'pass':ok,'log':log})
        print(('PASS ' if ok else 'FAIL ')+addon+' isolated startup')
        if not ok:print(log)
(root/'reports').mkdir(exist_ok=True)
(root/'reports/isolation.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
raise SystemExit(0 if all(r['pass'] for r in reports) else 1)
