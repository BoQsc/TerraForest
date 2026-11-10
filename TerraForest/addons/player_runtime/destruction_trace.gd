# SPDX-License-Identifier: 0BSD
extends RefCounted
## Diagnostic identities are world epoch + persisted barrel identity, not save state.
## Explicit clocks make deadline accounting testable without a running world.
const EVENT_LIMIT:=256
const TRANSITION_LIMIT:=2048
var enabled:=false
var events:Dictionary={}
var tickets:Dictionary={}
var transitions:Array[Dictionary]=[]
var dropped:=0
var missed:=0

func _record(event:Dictionary,phase:String,tick:int,at_us:int,details:Dictionary={})->void:
	if transitions.size()>=TRANSITION_LIMIT:
		dropped+=1
		return
	transitions.append({"event":event.id,"phase":phase,"tick":tick,"at_us":at_us,
		"trigger_tick":event.trigger_tick,"deadline_tick":event.deadline_tick,
		"age_us":maxi(0,at_us-int(event.trigger_us)),"details":details.duplicate(true)})

func trigger(epoch:int,barrel:int,tick:int,at_us:int)->String:
	if not enabled:return ""
	var identity:="%d:%d"%[epoch,barrel]
	if events.has(identity):return identity
	if events.size()>=EVENT_LIMIT:
		dropped+=1
		return ""
	var event:={"id":identity,"trigger_tick":tick,"deadline_tick":tick+1,
		"trigger_us":at_us,"blocks":false,"terrain":false,"missed":false}
	events[identity]=event
	_record(event,"trigger",tick,at_us)
	return identity

func admitted(identity:String,ticket:int,tick:int,at_us:int)->void:
	if not enabled or not events.has(identity):return
	if events[identity].has("ticket"):
		if int(events[identity].ticket)!=ticket:dropped+=1
		return
	if tickets.has(ticket):
		dropped+=1
		return
	events[identity].ticket=ticket
	tickets[ticket]=identity
	_record(events[identity],"admitted",tick,at_us,{"terrain_ticket":ticket})

func blocks_complete(identity:String,tick:int,at_us:int)->void:
	if not enabled or not events.has(identity):return
	events[identity].blocks=true
	events[identity].blocks_tick=tick
	_record(events[identity],"block_store_complete",tick,at_us)

func terrain_complete(ticket:int,tick:int,at_us:int,details:Dictionary)->void:
	if not enabled or not tickets.has(ticket):return
	var identity:String=tickets[ticket]
	tickets.erase(ticket)
	if not events.has(identity):return
	events[identity].terrain=true
	events[identity].terrain_tick=tick
	_record(events[identity],"terrain_published",tick,at_us,details)

func sample(tick:int,at_us:int)->Dictionary:
	if not enabled:return {}
	var finished:Array[String]=[]
	var oldest_age_us:=0
	for identity:String in events:
		var event:Dictionary=events[identity]
		oldest_age_us=maxi(oldest_age_us,maxi(0,at_us-int(event.trigger_us)))
		var completed_on_time:bool=event.blocks and event.terrain and int(event.blocks_tick)<=int(event.deadline_tick) and int(event.terrain_tick)<=int(event.deadline_tick)
		var overdue:bool=tick>=int(event.deadline_tick) and not completed_on_time
		if overdue and not event.missed:
			event.missed=true;missed+=1
			_record(event,"deadline_missed",tick,at_us)
		if event.blocks and event.terrain:
			_record(event,"first_draw_after_store_and_terrain",tick,at_us)
			finished.append(identity)
	for identity:String in finished:events.erase(identity)
	var output:={"transitions":transitions,"pending":events.size(),"oldest_age_us":oldest_age_us,
		"deadline_misses":missed,"dropped":dropped,
		"scope":"Trigger clock includes admission wait. Store/terrain completion is not proof of building-render or physics publication."}
	transitions=[]
	return output

func reset()->void:
	events.clear();tickets.clear();transitions.clear();dropped=0;missed=0
