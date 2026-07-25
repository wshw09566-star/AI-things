class_name SurveyCompletion
extends RefCounted

# DESIGN.md section 2 with correction 15.1.1: completion is an integer
# numerator over an integer denominator taken across the regions that still
# exist (erased regions are deleted, so only live and PENDING_ERASE space
# counts). A zero denominator is defined as exactly 0%, never a division, and
# the 100% gate compares integers rather than a formatted percentage.

const REGION_COMPLETE_PERMILLE := 920

static func of(graph: SurveyGraphV1) -> Dictionary:
	var numerator := 0
	var denominator := 0
	for region_id in graph.sorted_region_ids():
		var region: Dictionary = graph.regions[region_id]
		var cell_total := maxi(0, int(region["cell_total"]))
		denominator += cell_total
		numerator += SurveyCoverageBitset.popcount(String(region["cells"]), cell_total)
	var percent_tenths := 0
	if denominator > 0:
		percent_tenths = numerator * 1000 / denominator
	return {
		"numerator": numerator,
		"denominator": denominator,
		"percent_tenths": percent_tenths,
		"complete": denominator > 0 and numerator == denominator,
	}

static func percent_text(report: Dictionary) -> String:
	var tenths := int(report["percent_tenths"])
	return "%d.%d%%" % [tenths / 10, tenths % 10]

static func region_complete(region: Dictionary) -> bool:
	var cell_total := maxi(0, int(region["cell_total"]))
	if cell_total <= 0:
		return false
	var scanned := SurveyCoverageBitset.popcount(String(region["cells"]), cell_total)
	return scanned * 1000 >= REGION_COMPLETE_PERMILLE * cell_total
