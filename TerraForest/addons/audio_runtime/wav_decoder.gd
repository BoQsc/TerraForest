# SPDX-License-Identifier: 0BSD
extends RefCounted
## Decode Kaino's 24-bit PCM WAVs into the 16-bit streams Godot can play.

static func decode(path: String) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var channels := 0
	var rate := 0
	var bits := 0
	var data_offset := 0
	var data_size := 0
	var offset := 12
	while offset + 8 <= bytes.size():
		var chunk := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var size := int(bytes.decode_u32(offset + 4))
		var body := offset + 8
		if size < 0 or body + size > bytes.size(): break
		if chunk == "fmt ":
			channels = int(bytes.decode_u16(body + 2))
			rate = int(bytes.decode_u32(body + 4))
			bits = int(bytes.decode_u16(body + 14))
		elif chunk == "data":
			data_offset = body
			data_size = size
			break
		offset = body + size + (size & 1)
	if channels not in [1, 2] or rate <= 0 or data_size <= 0:
		return null
	var converted := PackedByteArray()
	if bits == 16:
		converted = bytes.slice(data_offset, data_offset + data_size)
	elif bits == 24:
		var samples := int(data_size / 3)
		converted.resize(samples * 2)
		for i in samples:
			var at := data_offset + i * 3
			var value := int(bytes[at]) | (int(bytes[at + 1]) << 8) | (int(bytes[at + 2]) << 16)
			if value & 0x800000: value -= 0x1000000
			converted.encode_s16(i * 2, clampi(value >> 8, -32768, 32767))
	else:
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels == 2
	stream.data = converted
	return stream
