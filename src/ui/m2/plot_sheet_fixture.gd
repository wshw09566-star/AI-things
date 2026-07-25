extends RefCounted
## Deterministic M2 plot-sheet preview fixture (HOLLOW SURVEY).
## A small hand-authored survey graph snapshot exercising every plot layer:
## Halvard's prior survey (cyan), fresh survey (amber), unscanned projection
## branches (dashed graphite), a PENDING_ERASE region (pencil strike), and two
## tombstoned voids (strike-through). Coordinates are integer millimetres.


static func snapshot() -> Dictionary:
	return {
		"nodes": {
			1: {"pos_mm": [2000, 9000], "region_id": 1, "kind": "STATION", "scanned": true},
			2: {"pos_mm": [9000, 9500], "region_id": 1, "kind": "JUNCTION", "scanned": true},
			3: {"pos_mm": [15000, 7000], "region_id": 1, "kind": "STATION", "scanned": true},
			4: {"pos_mm": [15500, 13000], "region_id": 2, "kind": "JUNCTION", "scanned": true},
			5: {"pos_mm": [22000, 14000], "region_id": 2, "kind": "STATION", "scanned": true},
			6: {"pos_mm": [28000, 11000], "region_id": 2, "kind": "WAYPOINT", "scanned": true},
			7: {"pos_mm": [33000, 16000], "region_id": 2, "kind": "WAYPOINT", "scanned": false},
			8: {"pos_mm": [30000, 5000], "region_id": 3, "kind": "WAYPOINT", "scanned": false},
			9: {"pos_mm": [24000, 4000], "region_id": 3, "kind": "STATION", "scanned": true},
		},
		"edges": {
			1: {"a": 1, "b": 2, "scanned": true, "prior": true},
			2: {"a": 2, "b": 3, "scanned": true, "prior": true},
			3: {"a": 3, "b": 4, "scanned": true, "prior": false},
			4: {"a": 4, "b": 5, "scanned": true, "prior": false},
			5: {"a": 5, "b": 6, "scanned": true, "prior": false},
			6: {"a": 6, "b": 7, "scanned": false, "prior": false},
			7: {"a": 8, "b": 9, "scanned": false, "prior": false},
			8: {"a": 6, "b": 9, "scanned": true, "prior": false},
		},
		"regions": {
			1: {"status": "LIVE"},
			2: {"status": "LIVE"},
			3: {"status": "PENDING_ERASE"},
		},
		"stations": {
			1: {"station_no": "S-0114"},
			3: {"station_no": "S-0117"},
			5: {"station_no": "S-0123"},
			9: {"station_no": "S-0131"},
		},
		"completion": {"numerator": 4213, "denominator": 11200},
		"tombstones": [
			{"region_id": 5, "erased_tick": 90000, "bounds_mm": [4000, 1000, 9000, 5000]},
			{"region_id": 7, "erased_tick": 118400, "bounds_mm": [6000, 15000, 12000, 19000]},
		],
	}
