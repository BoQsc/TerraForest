# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
    var feel=preload("res://addons/player_runtime/player_feel_trial.gd").new()
    feel.step(.016,Vector3(0,2,0),false,0,false)
    feel.step(.016,Vector3(0,-8,0),false,0,false)
    var landing:Transform3D=feel.step(.016,Vector3.ZERO,true,0,false)
    check(landing.origin.y<-.005,"a real airborne descent and landing produces a restrained dip")
    check(feel.step(.016,Vector3.ZERO,true,0,false).origin.y>landing.origin.y,"grounded follow-up recovers instead of retriggering landing")
    feel.reset();feel.shot(false)
    var hip:Transform3D=feel.step(.016,Vector3.ZERO,true,0,false)
    feel.reset();feel.shot(true)
    var aimed:Transform3D=feel.step(.016,Vector3.ZERO,true,0,true)
    check(aimed.origin.z>0 and aimed.origin.z<hip.origin.z,"aimed feedback is smaller than hip-fire feedback")
    for i in 600:
        feel.shot(false)
        var pose:Transform3D=feel.step(.016,Vector3(10,-12,-10),false,20,false)
        check(pose.origin.length()<.04 and absf(pose.basis.get_euler().z)<.02,"combined response stays bounded") if i==599 else 0
    for i in 180:feel.step(.016,Vector3.ZERO,true,0,false)
    check(feel.offset.length()<.0001 and feel.kick<.0001 and feel.pitch<.0001,"feedback settles at rest")
    feel.reset();check(feel.step(0,Vector3.ZERO,true,0,false)==Transform3D.IDENTITY and feel.fov_pulse==0,"reset exactly restores the baseline")
    print("PLAYER_FEEL_TRIAL failures=",failures);quit(1 if failures else 0)
