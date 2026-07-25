class_name SurveyIntCodec
extends RefCounted

# DESIGN.md section 6 demands strict JSON with exact integers, but JSON numbers
# are doubles. Every authoritative integer in a .svy envelope (ids, Morton
# cells, tick counts, accumulators, checksum-sensitive words) is therefore
# written as a canonical decimal string and parsed back without ever passing
# through a float. Canonical form: optional leading minus, no leading zeros, no
# plus sign, no negative zero, digits only.

static func encode(value: int) -> String:
	return str(value)

static func is_canonical(text: String) -> bool:
	if text.is_empty():
		return false
	var body := text
	if body.begins_with("-"):
		body = body.substr(1)
	if body.is_empty():
		return false
	for index in body.length():
		var code := body.unicode_at(index)
		if code < 48 or code > 57:
			return false
	if body.length() > 1 and body.begins_with("0"):
		return false
	if text.begins_with("-") and body == "0":
		return false
	return true

static func decode(value: Variant, field: String, errors: Array) -> int:
	if typeof(value) != TYPE_STRING:
		errors.append("%s: integer must be a decimal string" % field)
		return 0
	var text := String(value)
	if not is_canonical(text):
		errors.append("%s: non-canonical integer %s" % [field, text])
		return 0
	var negative := text.begins_with("-")
	var magnitude := text.substr(1) if negative else text
	var limit := "9223372036854775808" if negative else "9223372036854775807"
	if magnitude.length() > limit.length() or (magnitude.length() == limit.length() and magnitude > limit):
		errors.append("%s: integer is outside signed 64-bit range" % field)
		return 0
	return text.to_int()

static func decode_nonnegative(value: Variant, field: String, errors: Array) -> int:
	var parsed := decode(value, field, errors)
	if parsed < 0:
		errors.append("%s: must not be negative" % field)
		return 0
	return parsed
