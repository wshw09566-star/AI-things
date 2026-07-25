class_name SurveyCoverageBitset
extends RefCounted

# DESIGN.md section 3.1 coverage bitset: base64 ASCII, bit i is cell i of the
# region generation-time cell list, MSB first inside each byte, exactly
# ceil(cell_total / 8) bytes. Bits at or above cell_total must be zero, so the
# encoding of a coverage state is unique and hashable.

static func byte_length(cell_total: int) -> int:
	return (maxi(0, cell_total) + 7) / 8

static func empty(cell_total: int) -> String:
	var length := byte_length(cell_total)
	if length == 0:
		return ""
	var bytes := PackedByteArray()
	bytes.resize(length)
	bytes.fill(0)
	return Marshalls.raw_to_base64(bytes)

static func decode(text: String, cell_total: int, field: String, errors: Array) -> PackedByteArray:
	var expected := byte_length(cell_total)
	if expected == 0:
		if not text.is_empty():
			errors.append("%s: zero-cell coverage bitset must be empty" % field)
		return PackedByteArray()
	var bytes := Marshalls.base64_to_raw(text)
	if text != Marshalls.raw_to_base64(bytes):
		errors.append("%s: coverage bitset is not canonical base64" % field)
		return PackedByteArray()
	if bytes.size() != expected:
		errors.append("%s: coverage bitset is %d bytes, expected %d" % [field, bytes.size(), expected])
		return PackedByteArray()
	for index in range(maxi(0, cell_total), expected * 8):
		if bit_of(bytes, index):
			errors.append("%s: coverage bit %d is set above cell_total" % [field, index])
			return PackedByteArray()
	return bytes

static func bit_of(bytes: PackedByteArray, index: int) -> bool:
	var byte_index := index / 8
	if index < 0 or byte_index >= bytes.size():
		return false
	return ((int(bytes[byte_index]) >> (7 - (index % 8))) & 1) == 1

static func get_bit(text: String, index: int) -> bool:
	return bit_of(Marshalls.base64_to_raw(text), index)

static func set_bit(text: String, cell_total: int, index: int) -> String:
	if index < 0 or index >= cell_total:
		return text
	var bytes := Marshalls.base64_to_raw(text)
	if bytes.size() != byte_length(cell_total):
		var resized := PackedByteArray()
		resized.resize(byte_length(cell_total))
		resized.fill(0)
		for copy_index in mini(bytes.size(), resized.size()):
			resized[copy_index] = bytes[copy_index]
		bytes = resized
	bytes[index / 8] = int(bytes[index / 8]) | (1 << (7 - (index % 8)))
	return Marshalls.raw_to_base64(bytes)

static func popcount(text: String, cell_total: int) -> int:
	var bytes := Marshalls.base64_to_raw(text)
	var total := 0
	for index in maxi(0, cell_total):
		if bit_of(bytes, index):
			total += 1
	return total
