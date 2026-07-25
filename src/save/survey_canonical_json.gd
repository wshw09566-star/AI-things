class_name SurveyCanonicalJson
extends RefCounted

# DESIGN.md section 6: the .svy file is human-readable strict JSON with a fixed
# (sorted) key order, LF endings and ASCII only, and header.checksum is FNV-1a 64
# over the canonical byte stream. Godot Dictionaries keep insertion order, so the
# writer below sorts keys at every level: two graphs with the same content always
# produce the same bytes and therefore the same checksum. Authoritative integers
# are written as decimal strings (SurveyIntCodec); the only JSON numbers in the
# envelope are the bounded centimetre/intensity values inside chunk point arrays.

static func encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_INT:
			return SurveyIntCodec.encode(int(value))
		TYPE_BOOL:
			return bool(value)
		TYPE_FLOAT:
			# JSON parsing returns every number as a float. Integral values are the
			# bounded point-array integers and must re-encode byte for byte.
			var number := float(value)
			if number == floor(number) and absf(number) < 9.0e15:
				return int(number)
			return number
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value)
		TYPE_VECTOR3I:
			var vector: Vector3i = value
			return [SurveyIntCodec.encode(vector.x), SurveyIntCodec.encode(vector.y), SurveyIntCodec.encode(vector.z)]
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var out := {}
			for key in source.keys():
				out[String(key) if typeof(key) != TYPE_INT else SurveyIntCodec.encode(int(key))] = encode(source[key])
			return out
		TYPE_ARRAY:
			var list: Array = []
			for item in value:
				list.append(encode(item))
			return list
		TYPE_PACKED_INT32_ARRAY:
			var packed: Array = []
			for item in value:
				packed.append(int(item))
			return packed
	return value

static func stringify(value: Variant, indent: String = "  ") -> String:
	return _write(value, indent, "")

static func _write(value: Variant, indent: String, current: String) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var number := float(value)
			if number == floor(number) and absf(number) < 9.0e15:
				return str(int(number))
			return str(number)
		TYPE_STRING, TYPE_STRING_NAME:
			return quote(String(value))
		TYPE_DICTIONARY:
			return _write_object(value, indent, current)
		TYPE_ARRAY:
			return _write_array(value, indent, current)
	return quote(str(value))

static func _write_object(source: Dictionary, indent: String, current: String) -> String:
	var keys: Array = []
	for key in source.keys():
		keys.append(String(key))
	keys.sort()
	if keys.is_empty():
		return "{}"
	var inner := current + indent
	var parts := PackedStringArray()
	for key in keys:
		parts.append("%s%s: %s" % [inner, quote(String(key)), _write(source[key], indent, inner)])
	return "{\n" + ",\n".join(parts) + "\n" + current + "}"

static func _write_array(source: Array, indent: String, current: String) -> String:
	if source.is_empty():
		return "[]"
	var inline := true
	for item in source:
		var kind := typeof(item)
		if kind != TYPE_INT and kind != TYPE_FLOAT and kind != TYPE_STRING and kind != TYPE_STRING_NAME and kind != TYPE_BOOL:
			inline = false
			break
	var parts := PackedStringArray()
	if inline:
		for item in source:
			parts.append(_write(item, indent, current))
		return "[" + ", ".join(parts) + "]"
	var inner := current + indent
	for item in source:
		parts.append(inner + _write(item, indent, inner))
	return "[\n" + ",\n".join(parts) + "\n" + current + "]"

static func quote(text: String) -> String:
	var out := "\""
	for index in text.length():
		var code := text.unicode_at(index)
		if code == 34:
			out += "\\\""
		elif code == 92:
			out += "\\\\"
		elif code == 10:
			out += "\\n"
		elif code == 13:
			out += "\\r"
		elif code == 9:
			out += "\\t"
		elif code < 32 or code > 126:
			out += "\\u%04x" % code
		else:
			out += char(code)
	return out + "\""

static func parse(text: String, errors: Array) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("PARSE_FAILED: line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	return json.data

# The M1 digest is the one FNV-1a 64 implementation in the project; M2 reuses it
# rather than growing a second checksum authority.
static func checksum(text: String) -> String:
	return M1StateHash.fnv1a_64(text)
