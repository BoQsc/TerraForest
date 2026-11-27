# SPDX-License-Identifier: 0BSD
extends RefCounted
# Test-only bounded asynchronous readback. All RD access stays on the render
# thread; completed byte arrays cross to the main thread through deferred calls.
const REGION := Rect2i(1280,340,640,240)
const COUNT := 48
var capture_region := REGION
var frame_count := COUNT
var frames: Array[PackedByteArray] = []
var times: Array[int] = []
var context := PackedByteArray()
var received := 0
var ready := false
var errors: Array[String] = []
var source: RID
var cropped: RID

func _init() -> void:
	frames.resize(COUNT);times.resize(COUNT)

func begin(texture: RID, region: Rect2i = REGION, count: int = COUNT) -> void:
	capture_region = region
	frame_count = count; frames.resize(count); times.resize(count)
	RenderingServer.call_on_render_thread(_begin.bind(texture))

func _begin(texture: RID) -> void:
	var rd := RenderingServer.get_rendering_device()
	source=RenderingServer.texture_get_rd_texture(texture)
	if rd==null or not source.is_valid():_error.call_deferred("No source rendering-device texture");return
	var format := rd.texture_get_format(source)
	if format.width!=1920 or format.height!=1080 or format.format not in [RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB]:
		_error.call_deferred("Expected native 1080p RGBA8 viewport, got format "+str(format.format));return
	if not format.usage_bits&RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT:
		_error.call_deferred("Source viewport does not allow readback");return
	var target := RDTextureFormat.new()
	target.width=capture_region.size.x;target.height=capture_region.size.y;target.format=format.format
	target.usage_bits=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	cropped=rd.texture_create(target,RDTextureView.new())
	if not cropped.is_valid():_error.call_deferred("Cannot allocate bounded crop texture");return
	_set_ready.call_deferred()

func _set_ready() -> void:ready=true
func _error(message: String) -> void:errors.append(message)

func request(index: int) -> void:
	RenderingServer.call_on_render_thread(_request.bind(index))

func _request(index: int) -> void:
	var rd := RenderingServer.get_rendering_device()
	var stamp := Time.get_ticks_msec()
	var error := rd.texture_copy(source,cropped,Vector3(capture_region.position.x,capture_region.position.y,0),Vector3.ZERO,Vector3(capture_region.size.x,capture_region.size.y,1),0,0,0,0)
	if error!=OK:_error.call_deferred("Crop GPU copy failed: "+str(error));return
	error=rd.texture_get_data_async(cropped,0,_receive.bind(index,stamp))
	if error!=OK:_error.call_deferred("Asynchronous crop readback failed: "+str(error))
	if index==0:
		error=rd.texture_get_data_async(source,0,_receive_context)
		if error!=OK:_error.call_deferred("Asynchronous context readback failed: "+str(error))

func _receive(data: PackedByteArray,index: int,stamp: int) -> void:
	_store.call_deferred(data,index,stamp)

func _store(data: PackedByteArray,index: int,stamp: int) -> void:
	if index<0 or index>=frame_count or data.size()!=capture_region.size.x*capture_region.size.y*4 or not frames[index].is_empty():
		errors.append("Invalid, repeated or oversized crop readback");return
	frames[index]=data;times[index]=stamp;received+=1

func _receive_context(data: PackedByteArray) -> void:_store_context.call_deferred(data)
func _store_context(data: PackedByteArray) -> void:
	if data.size()!=1920*1080*4:errors.append("Invalid context readback size");return
	context=data

func dispose() -> void:RenderingServer.call_on_render_thread(_dispose)
func _dispose() -> void:
	if cropped.is_valid():RenderingServer.get_rendering_device().free_rid(cropped);cropped=RID()
