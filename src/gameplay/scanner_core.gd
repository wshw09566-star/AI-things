class_name ScannerCore
extends RefCounted

# M1 core, DESIGN.md section 2. Charge economy plus deterministic point capture.
# No ray casting yet: the caller supplies quantized centimetre hit samples, which
# keeps the M1 tests independent of physics and of the renderer.

const CHARGE_MAX_TENTHS := 1000
const BURST_COST_TENTHS := 250
const RECHARGE_TENTHS_PER_SECOND := 50
const TICKS_PER_SECOND := 60
const INTENSITY_FLOOR := 96
const INTENSITY_SPAN := 160

var charge_tenths := 0
var charge_accumulator := 0
var burst_count := 0
var sample_count := 0
var seed_value := 0
var last_error := ""

var _rng := RandomNumberGenerator.new()

func _init(p_seed: int = 19790417) -> void:
	seed_value = p_seed
	_rng.seed = p_seed

func charge_percent_tenths() -> int:
	return charge_tenths

func can_burst() -> bool:
	return charge_tenths >= BURST_COST_TENTHS

# One 60 Hz tick of charge-up. Charge accrues only while the tripod is deployed
# and the surveyor is stationary beside it, using an integer accumulator so the
# rate is exactly 5.0 per second and never frame-rate dependent.
func tick_charge(deployed: bool, stationary: bool) -> int:
	if not deployed or not stationary:
		charge_accumulator = 0
		return charge_tenths
	charge_accumulator += RECHARGE_TENTHS_PER_SECOND
	var gain := charge_accumulator / TICKS_PER_SECOND
	charge_accumulator -= gain * TICKS_PER_SECOND
	charge_tenths = mini(CHARGE_MAX_TENTHS, charge_tenths + gain)
	return charge_tenths

func charge_for_ticks(ticks: int, deployed: bool = true, stationary: bool = true) -> int:
	for tick_index in maxi(0, ticks):
		tick_charge(deployed, stationary)
	return charge_tenths

# Fires one burst of quantized samples (x,y,z centimetre triples) into region_id.
# Charge is spent whenever the burst fires, even when every sample is a duplicate
# or is refused by a cap, and the cap outcome is reported explicitly.
func burst(space: SurveySpace, region_id: int, samples_cm: PackedInt32Array) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"charge_tenths": charge_tenths,
		"received": 0,
		"stored": 0,
		"duplicates": 0,
		"region_capped": 0,
		"global_capped": 0,
		"at_cap": false,
	}
	if space == null:
		result["reason"] = "NO_SURVEY_SPACE"
		last_error = result["reason"]
		return result
	if samples_cm.size() % 3 != 0:
		result["reason"] = "INVALID_SAMPLES"
		last_error = result["reason"]
		return result
	if not can_burst():
		result["reason"] = "INSUFFICIENT_CHARGE"
		last_error = result["reason"]
		return result
	charge_tenths -= BURST_COST_TENTHS
	burst_count += 1
	var count := samples_cm.size() / 3
	sample_count += count
	var quads := PackedInt32Array()
	for index in count:
		var base := index * 3
		quads.append(samples_cm[base])
		quads.append(samples_cm[base + 1])
		quads.append(samples_cm[base + 2])
		quads.append(INTENSITY_FLOOR + int(_rng.randi() % INTENSITY_SPAN))
	var stored := space.store_points(region_id, quads)
	if not bool(stored["ok"]):
		result["reason"] = "STORE_REJECTED"
		result["charge_tenths"] = charge_tenths
		last_error = String(space.last_error)
		return result
	result["ok"] = true
	result["reason"] = "STORED"
	result["charge_tenths"] = charge_tenths
	result["received"] = int(stored["received"])
	result["stored"] = int(stored["stored"])
	result["duplicates"] = int(stored["duplicates"])
	result["region_capped"] = int(stored["region_capped"])
	result["global_capped"] = int(stored["global_capped"])
	result["at_cap"] = bool(stored["at_cap"])
	return result

func canonical_text() -> String:
	return "scanner seed=%d charge=%d acc=%d bursts=%d samples=%d rng=%d" % [seed_value, charge_tenths, charge_accumulator, burst_count, sample_count, _rng.state]

func to_snapshot() -> Dictionary:
	return {
		"seed": seed_value,
		"charge_tenths": charge_tenths,
		"charge_accumulator": charge_accumulator,
		"burst_count": burst_count,
		"sample_count": sample_count,
		"rng_state": _rng.state,
	}

static func from_snapshot(data: Dictionary) -> ScannerCore:
	var scanner := ScannerCore.new(int(data["seed"]))
	scanner.charge_tenths = int(data["charge_tenths"])
	scanner.charge_accumulator = int(data["charge_accumulator"])
	scanner.burst_count = int(data["burst_count"])
	scanner.sample_count = int(data["sample_count"])
	scanner._rng.state = int(data["rng_state"])
	return scanner
