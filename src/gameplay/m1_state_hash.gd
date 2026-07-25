class_name M1StateHash
extends RefCounted

# M1 core, DESIGN.md sections 6 and 12. Canonical snapshot text plus an FNV-1a 64
# digest of it, which is the save to load to replay proof surface for M1. The
# digest is computed in two 32-bit lanes so the result is always a non-negative
# 16-character hex string, independent of platform integer signedness.

const OFFSET_HI := 0xcbf29ce4
const OFFSET_LO := 0x84222325
const PRIME_HI := 0x100
const PRIME_LO := 0x1b3
const MASK32 := 0xffffffff

static func fnv1a_64(text: String) -> String:
	var hi := OFFSET_HI
	var lo := OFFSET_LO
	for byte in text.to_utf8_buffer():
		lo ^= int(byte)
		var low_full := lo * PRIME_LO
		var mid := (hi * PRIME_LO + lo * PRIME_HI) & MASK32
		var carry := low_full >> 32
		lo = low_full & MASK32
		hi = (mid + carry) & MASK32
	return "%08x%08x" % [hi, lo]

static func snapshot_text(space: SurveySpace, scanner: ScannerCore, player: PlayerMotionState, patroller: EntityPatroller) -> String:
	var parts := PackedStringArray()
	parts.append("HOLLOW SURVEY M1 STATE v1")
	parts.append(space.canonical_text() if space != null else "space absent")
	parts.append(scanner.canonical_text() if scanner != null else "scanner absent")
	parts.append(player.canonical_text() if player != null else "player absent")
	parts.append(patroller.canonical_text() if patroller != null else "entity absent")
	return "\n".join(parts)

static func of(space: SurveySpace, scanner: ScannerCore, player: PlayerMotionState, patroller: EntityPatroller) -> String:
	return fnv1a_64(snapshot_text(space, scanner, player, patroller))
