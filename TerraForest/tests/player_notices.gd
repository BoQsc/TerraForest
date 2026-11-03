# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(1920,1080)
	var blocked:Dictionary={"value":true}
	var notices=preload("res://addons/player_runtime/player_notices.gd").new()
	notices.allowed=func():return not blocked.value
	notices.general_top=func():return 868.
	root.add_child(notices)
	check(not notices.is_processing(),"idle notices do no processing")
	notices.quest_added("A friendly face");notices.quest_added("A friendly face")
	notices._process(5)
	check(notices.queued.size()==1 and notices.shown==0 and not notices.toast.visible,"wake/loading/menu gating retains one unshown notice")
	blocked.value=false;notices._process(.3)
	check(notices.shown==1 and notices.toast.visible and notices.quest_title.text=="A friendly face","queued quest appears after release")
	check(notices.toast.modulate.a==1 and notices.toast.position.y==104,"quest animates below compass")
	check(notices.toast.size.y<120,"short quest notice remains compact instead of stretching down the screen")
	check(notices.toast.mouse_filter==Control.MOUSE_FILTER_IGNORE and notices.quest_title.mouse_filter==Control.MOUSE_FILTER_IGNORE,"notice never intercepts input")
	var age:float=notices.quest_age;blocked.value=true;notices._process(30)
	check(notices.quest_age==age and not notices.toast.visible,"opening another UI pauses rather than loses notice")
	blocked.value=false;notices._process(4)
	check(notices.current.is_empty() and not notices.toast.visible and not notices.is_processing(),"quest expires and returns to idle")
	notices.notify("World saved");notices.notify("Holding pickaxe");notices.notify("Block placed")
	check(not notices.is_processing() and notices.general.text.is_empty(),"routine saves, equipment and actions do not animate above the toolbelt")
	notices.notify("Quest complete","quest");notices._process(.2)
	check(notices.general.visible and notices.general.text=="Quest complete" and notices.general.position.y==868,"rare quest state notice remains above toolbar")
	notices._process(5)
	notices.observe_effects({});notices.observe_effects({1:180000});notices._process(.2)
	check(notices.general.text=="Well fed gained","new buff is announced")
	notices._process(5);notices.observe_effects({1:179000})
	check(not notices.is_processing(),"buff countdown does not repeat notices")
	notices.observe_effects({});notices._process(.2)
	check(notices.general.text=="Well fed ended","buff expiry is announced once")
	notices._process(5);check(not notices.general.visible and not notices.is_processing(),"rare notice expires")
	for index in 20:notices.quest_added("Quest "+str(index))
	check(notices.queued.size()==4,"quest backlog stays bounded")
	notices.free();print("PLAYER_NOTICES checks=",checks," failures=",failures);quit(1 if failures else 0)
