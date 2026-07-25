# HOLLOW SURVEY — Implementation Contract (DESIGN.md)

Version 1.0 · Design Lead, Session 1 · 1979 potash-mine survey horror.
Engine: Godot 4.7.1, GDScript only, GdUnit4 tests, software rasterizer (llvmpipe, 1 vCPU), 640×360 QA captures, fully offline, zero downloaded assets, repo < 500 MB.

This document is the implementation contract. An engineer must be able to build the game from it without inventing core rules. Where numbers are uncertain, an initial target and a tuning range are given.

---

## 0. Premise (canon)

1979. The player is a contract surveyor for the Kestrel Survey Company, lowered 400 m into a decommissioned potash mine that was converted in 1974 into a seed archive and abandoned in 1977. The prior photogrammetric survey stands at 94% complete. The prior surveyor, R. Halvard, is missing; his tripod stations remain. Pay is per verified coverage percent.

**Core inversion (must survive every change):** progress requires scanning; the entity may occupy only scanned survey space; erasure makes space safe but destroys route knowledge and completion.

---

## 1. Design Pillars & Learning Arc

- **P1 — Knowledge is territory.** The world only exists (for you and for it) where it has been measured. Every convenience you create is a corridor you have opened.
- **P2 — The instrument is the character.** Tripod, cone, charge, plot sheet. No abstract UI; the scanner and paper are the whole interface.
- **P3 — The threat is procedural, legible, fair.** The entity obeys published rules (five states, straight measured lines, no teleporting, scanned space only). Fear comes from understanding it, not from surprise.
- **P4 — Nothing is loud.** No stingers, no chase music, no jump scares. Dread is administrative: quotas, station logs, a survey that is 94% done.

**Learning arc (no tutorial popups; all teaching is diegetic):**
- **Min 0–3:** Adit descent. Movement, crouch, lean. First mandatory scan to read the winch panel (light only reveals ~4 m; points reveal structure).
- **Min 3–8:** First drift. Plot sheet teaches completion %. Footstep audio differs on grate vs rock, teaching noise.
- **Min 8–15 (occupancy-rule inference, required by minute 15):** Chamber CH-02 is generated with exactly two exits: one covered by the prior survey (cyan residue points, plotted line), one virgin. The entity's first appearance is choreographed (first encounter only): it Intercepts along the scanned exit and **halts exactly at the boundary of scanned space**, holding a reading pose at the last scanned node while the player stands in unscanned dark 3 m away. Every subsequent encounter in Act I re-demonstrates the boundary halt with the same stop tones. Artifact A07 states it in fiction: *"It only walks where the work is done."* A telemetry assert enforces entity position ∈ scanned graph at all times, so the taught rule is the true rule.
- **Min 15+:** Player begins routing decisions: scan for progress vs. keep corridors closed. Erasure tool arrives Act II with the full tradeoff already understood.

---

## 2. Moment-to-Moment Loop, Controls, Scanner Budgets

**Loop:** walk dark space → deploy tripod → charge → burst-scan cone → read plot sheet → plan route between stations → manage noise → (later) erase regions to deny the entity space, at the cost of completion and route knowledge.

**Controls (rebindable):** WASD walk 2.6 m/s · crouch toggle C, 1.2 m/s · lean Q/E ±0.35 m · interact F · deploy/collapse tripod TAB (1.0 s) · scan burst LMB (hold) · plot sheet RMB (hold; 1.5 s unfold) · erase: hold X 3.0 s at a station · no jump, no sprint, no stamina.

**Footsteps:** floor material tag drives synthesis and detection. Each step emits `AudibleEvent(pos, loudness L, radius r)`: rock walk r=9 m L=1.0 · rock crouch r=4 m L=0.4 · grate r=14 m L=1.5 · water r=16 m L=1.8 · salt-crust r=11 m L=1.2. Entity hearing consumes AudibleEvents via **graph distance**, not euclidean (§11).

**Scanner (initial targets, llvmpipe-safe; tuning range in brackets):**
- Charge 100 max; burst costs 25 [15–35]; recharge 5/s only while tripod deployed and player stationary within 1 m of it.
- Cone 55° full angle [45–70], range 24 m [18–28], 96×54 deterministic ray grid = 5,184 rays over 0.8 s [3k–7k rays].
- Each hit deposits 1 point into the region's chunks. Per-region cap 60,000 points; **hard global cap 900,000** [600k–1.2M]. At cap, chunks in the farthest region decimate 2:1 in deterministic chunk-id order.
- LOD by camera distance: render every point < 15 m, every 2nd < 30 m, every 4th < 60 m, culled beyond. Point size 2 px at 640×360, rendered via MultiMesh quads (no custom GPU compute).
- Frame budget at 640×360 / 30 fps: points ≤ 8 ms, entity sim ≤ 2 ms, audio synth ≤ 2 ms, everything else ≤ 18 ms.

**Coverage & completion:** at generation, every region gets a 0.5 m coverage grid over walkable/wall surfaces (`cell_total`). A burst marks cells whose surface point lies in the cone with line-of-sight. Region is complete at ≥ 92% cells. **Global completion = Σ cells_scanned / Σ cell_total** over live (non-erased) regions, shown on the plot sheet as `SURVEY nn.n%`.

---

## 3. Survey Graph (single source of truth)

The **Survey Graph** is the only source of truth for: entity navigation, plot sheet, completion, erasure, and save/load. The rendered point cloud is a derived cache, always rebuildable from chunks. No second store of spatial truth may exist.

### 3.1 Typed schema (GDScript type — JSON serialization type)

```
SurveyGraph
  version: int            — int; starts at 1 (migrations §3.4)
  seed: int               — int; world generation seed
  next_ids: {node,edge,region,chunk: int} — monotonic counters; ids are NEVER reused
  nodes: Dictionary[int, SNode]
  edges: Dictionary[int, SEdge]
  regions: Dictionary[int, SRegion]
  chunks: Dictionary[int, PointChunk]
  tombstones: Array[Tombstone]

SNode
  id: int
  pos: Vector3i           — millimetre-quantized world position
  region_id: int
  kind: enum {STATION, JUNCTION, WAYPOINT} — serialized as string
  scanned: bool
  station: StationMeta | null   — non-null iff kind == STATION

SEdge
  id: int
  a: int, b: int          — node ids, invariant a < b
  length_mm: int
  surface: enum {ROCK, RAIL, GRATE, WATER, RUBBLE, SALT}
  cost: int               — length_mm × multiplier: ROCK 1.0, RAIL 1.0, GRATE 1.1, RUBBLE 1.4, WATER 1.6, SALT 1.2 (rounded down)
  scanned: bool

SRegion
  id: int
  chamber_code: String    — "CH-01"… or "DR-xx" for connective drifts
  name: String
  cell_total: int
  cells: String           — base64 bitset of scanned coverage cells
  complete: bool          — cached (≥ 92% rule)
  chunk_ids: Array[int]

PointChunk
  id: int
  region_id: int
  cell: int               — spatial hash key: 64-bit Morton code of floor(pos / 4 m)
  count: int
  points: PackedFloat32Array — x,y,z,intensity quadruples, quantized to 1 cm

StationMeta
  station_no: String      — "S-0117"
  installed_by: String    — "HALVARD" | "PLAYER"
  log_id: String | null   — artifact reference (§9)

Tombstone
  region_id: int
  chamber_code: String
  erased_day: int         — in-fiction day counter
  node_ids: Array[int]
  edge_ids: Array[int]
  cell_total: int
```

### 3.2 Deterministic rules
- All dictionaries serialize with integer keys sorted ascending; arrays sorted by id. Any iteration whose order affects behavior (route ties, decimation, ejection, migration) MUST iterate sorted ids.
- Erased region/node/edge/chunk ids live forever in tombstones and are never reused. Rescanning erased space creates a **new** region with fresh ids and empty coverage: the old knowledge (plot lines, station metadata, completion history) is irrecoverably lost.

### 3.3 Validation invariants (asserted on load and after every mutation batch; GdUnit4)
- V1 every edge's endpoints exist; a < b. V2 every node's region exists. V3 entity position refers to an existing scanned node or scanned edge. V4 completion ∈ [0,100]. V5 tombstone ids ∩ live ids = ∅. V6 every chunk's region exists and is listed in region.chunk_ids. V7 each region's scanned subgraph is connected. V8 next_ids strictly greater than any live or tombstoned id.

### 3.4 Migrations
Loader switches on `version`; each migration is a pure function vN→vN+1 with a committed fixture save file per version and a GdUnit4 round-trip test. Unknown future versions refuse to load with a diegetic error.

---

## 4. The Entity — "The Other Surveyor"

Rendered only as a **point-density anomaly**: ~2,400 points sampled on a human silhouette volume, borrowing the palette of surrounding chunks but at 3× local density with slight jitter. Never a mesh, never lit, never textured.

**Movement law:** exists only on scanned nodes/edges of the Survey Graph. Travels in straight measured lines between stations at a constant 1.7 m/s. Never runs. Never teleports. Stops at stations for readings. It surveys; it does not chase the current player position — it triangulates and intercepts the **plotted route**.

**Suspicion:** scalar S ∈ [0,100], decays 1.0/s. Each AudibleEvent adds `L × 25 × exp(-d_graph / 20 m)` where d_graph is shortest scanned-graph distance from event to entity [decay 15–30 m].

**Route prediction:** keeps the player's last 4 station-to-station legs; predicts the next leg by direction continuation on the plot; intercept node = scanned STATION/JUNCTION minimizing (entity travel time − predicted player arrival time) subject to entity arriving first. Ties: lowest node id.

### 4.1 Exact transition table (all five states)

| From | Trigger | Guard | Actions | To | Timing | Interrupt / save behavior |
|---|---|---|---|---|---|---|
| (spawn/load) | game start or save loaded | graph has ≥1 scanned station | place at Halvard station nearest CH-05; restore serialized state verbatim on load | Survey (or serialized state) | — | load restores state, node/edge+t, timers, route exactly |
| Survey | reading finished at station | — | pick next station: lowest visit_count, tie lowest id; A* by edge cost; walk | Survey | reading 6–14 s (seeded roll per station) | mid-edge position saved as (edge_id, t); resumes same t |
| Survey | S ≥ 40 | player in scanned space within 80 m graph dist | halt; face last event bearing | Triangulate | ≤ 0.5 s | if saved mid-halt, resumes in Triangulate with timer |
| Survey | region containing it queued for erasure | — | begin ejection route (§5) | Withdraw | immediate | pending erasure serialized |
| Triangulate | 3 bearings taken | ≥2 distinct AudibleEvents recorded in last 30 s | compute intercept node; commit route | Intercept | 9.0 s fixed (3 × 3.0 s tones) | bearing count + elapsed serialized |
| Triangulate | S < 25 before bearings done | — | discard bearings | Survey | — | — |
| Triangulate | graph mutated (erasure/decimation touching its route) | — | drop targets | Recalibrate | immediate | — |
| Intercept | arrived at intercept node | — | hold, listening; reading pose | Intercept (wait) | wait ≤ 45 s [30–60] | wait elapsed serialized |
| Intercept | player audible within 12 m graph dist while waiting | — | walk toward event along scanned edges only; halt at scanned-space boundary if route leaves scanned space | Intercept | — | — |
| Intercept | contact: within 1.5 m of player for 2.0 s | player in scanned space | **Measurement** (§4.2) | Withdraw | 4.0 s sequence | if saved mid-measurement, measurement completes on load |
| Intercept | wait expires or S < 10 | — | — | Survey | — | — |
| Intercept | intercept node erased | — | — | Recalibrate | immediate | — |
| Withdraw | measurement done, scan burst covers ≥ 30% of its points, or ejection ordered | — | route to a scanned station ≥ 3 edges away in least-player-visited region; walk | Withdraw | until arrival | route serialized |
| Withdraw | arrived | — | resume readings | Survey | — | — |
| Withdraw | ejection route invalidated by further erasure | — | — | Recalibrate | immediate | — |
| Recalibrate | entered | — | stand still; re-run A* over current scanned graph; validate V3 | (result) | 2.0 s fixed | timer serialized |
| Recalibrate | valid route found | — | — | Survey | — | — |
| Recalibrate | no scanned station reachable | its component has no station | hold at nearest scanned node; retry every 5 s | Recalibrate | 5 s loop | — |

**FSM invariants:** entity position always satisfies V3; no transition may place it on unscanned or erased space; all timers are integer milliseconds on the 60 Hz tick; all random rolls come from the serialized sim RNG stream.

### 4.2 Measurement (contact consequence — no combat, no death)
The entity photographs the player: screen fills with its point density over 4.0 s, three bearing tones sound. It then confiscates the tripod and carries it to the station on its route farthest (by cost) from the contact point. The player keeps the plot sheet, must travel by memory to retrieve the tripod, and cannot scan or erase until retrieval. Repeated contact escalates only distance, never harm.

---

## 5. Erasure & Legal Ejection Algorithm

Erasing region R (hold X 3.0 s at any station of R):
1. Mark R `PENDING_ERASE` (plot sheet shows the region struck through in pencil).
2. If entity not in R: skip to step 4.
3. **Ejection:** compute Dijkstra by edge cost over the **pre-deletion** scanned graph from the entity's nearest node in R to the nearest scanned node outside R. Entity enters Withdraw and walks that route at 1.7 m/s — through a legal adjacent scanned route, never a teleport. If no scanned route exits R (isolated scanned pocket), erasure is refused with the diegetic message `CANNOT VOID — PLOT OCCUPIED`, and R reverts from PENDING_ERASE.
4. When R is entity-free: atomically delete R's nodes, edges, chunks, and coverage; append Tombstone; recompute global completion; remove R's plotted lines and station metadata (route knowledge loss). Player receives no map memory aid.
5. Fire `graph_mutated`; entity FSM reacts per table (Recalibrate if affected).

Rescanning erased space builds a new region from scratch (§3.2) — safe space can be re-opened, but the old survey is gone forever.

---

## 6. Save / Load — the Survey File

One human-readable file per slot: `survey_<station>.svy` — strict JSON, fixed key order (sorted), LF endings, ASCII, integers for all quantized values.

Sections: `header` {version, seed, playtime_ms, act}, `rng` {gen_stream frozen post-generation, sim_stream state (two u64 words)}, `graph` (full §3 schema), `entity` {state, edge_id+t_mm or node_id, timers_ms, route node ids, visit_counts, suspicion ×10 as int}, `player` {pos_mm, yaw/pitch centidegrees, crouched, charge ×10, tripod_deployed|carried_by_entity node_id, inventory, artifacts_read}, `pending` {action ∈ {SCAN_BURST, ERASE_HOLD, PLOT_UNFOLD, NONE}, elapsed_ms, params}.

**Determinism contract:** simulation runs on a fixed 60 Hz tick; all gameplay state uses integers (mm, ms, centidegrees, tenths); all randomness from the serialized sim stream. Reload is behaviorally bit-identical: GdUnit4 golden test runs scripted inputs N ticks, compares full state hash against save→load→replay of the same inputs. Interruptible actions resume from `pending.elapsed_ms` exactly.

---

## 7. Three Acts & Two Endings

- **Act I — Descent (target 12 min):** adit → Level 1. Teach scan/plot/noise; choreographed CH-02 occupancy lesson (§1). Gate: winch power unlocks at 40.0% survey.
- **Act II — The Other Survey (target 15 min):** Levels 1–2. Halvard's stations and logs; entity gains Triangulate/Intercept pressure; erasure tool (the Void Stamp) found at CH-07 with Halvard's warning ledger. Gate: reach Level 3 winze, requires either 65% survey or first deliberate erasure.
- **Act III — Reconciliation (target 13+ min):** Level 3 + flooded margins. Player commits:
  - **Ending A — FILED (100.0% survey):** finish every live region under maximum Intercept pressure. The company seal releases the cage elevator; the final plot shows two complete surveys overlaid — yours and its. Mechanics: scanner mastery, charge routing, noise discipline.
  - **Ending B — VOID (0.0%, all regions erased, then reach the surface):** erase everything including the space you stand in (last region auto-voids at the shaft); climb the unsurveyed winch raise with no plot sheet, no points, navigating by footstep echo and synthesized airflow only. Mechanically distinct: zero graph, pure audio navigation.
- **Content floor:** critical path ≥ 40 min; ≥ 25 min spare: optional flooded sump wing (CH-10–CH-12), 25 artifacts, quota side-ledgers, optional 100%-per-region bonuses.

---

## 8. Procedural Generation & the 12 Chambers

**Vocabulary:** adit (entry tunnel), drift (horizontal tunnel), crosscut (connector), chamber (room-and-pillar void), winze (down-shaft), raise (up-shaft), flooded sump (drainage pool), mucking bay (loading alcove).

Seeded layout: 3 levels; skeleton graph of drifts/crosscuts (widths 2.4–4.2 m, corridor grammar) stitching **12 authored chambers** (hand-built packed scenes). Guarantees: G1 full connectivity; G2 CH-02 two-exit teaching setup; G3 ≥ 26 stations placed; G4 every chamber reachable without water until Act III; G5 no cycle shorter than 40 m; G6 sump wing optional; G7 first-encounter choreography solvable; G8 generation is a pure function of seed (gen RNG frozen afterward).

1. **CH-01 Cage Landing** — 400 m level marker, winch panel, first mandatory scan.
2. **CH-02 Sorting Hall** — two exits; the occupancy lesson; conveyor skeletons.
3. **CH-03 Seed Vault Alpha** — 1974 archive racks, climate ducting, artifact cluster.
4. **CH-04 Pillar Field** — room-and-pillar maze; sightline play; salt-crust floor noise.
5. **CH-05 Halvard's Base Camp** — cot, dead radio, station S-0114, his first logs.
6. **CH-06 Machine Shop** — rail junction, grate floors (loud), tool artifacts.
7. **CH-07 Assay Office** — the Void Stamp, quota ledgers, erasure tutorial-by-document.
8. **CH-08 Collapse Gallery** — rubble edges (cost 1.4), squeeze route, unstable audio.
9. **CH-09 Ventilation Plenum** — airflow synth showcase; fan silhouettes; echo play.
10. **CH-10 Flooded Sump West** — optional; water traversal (loud, slow), drowned racks.
11. **CH-11 Seed Vault Beta** — optional; intact vault, the archive's last shipment, cold.
12. **CH-12 The 94% Room** — Halvard's final station S-0141; the missing 6% starts here; Act III pivot.

---

## 9. Environmental Narrative Artifacts (25, one coherent story)

One story told through operational paperwork: conversion, quota pressure, Halvard's obsession, the second surveyor in his own data, evacuation. Each artifact is a readable prop bound to a station/region.

1. **A01** Brass plate, cage landing: "KESTREL POTASH No.2 — SUNK 1951 — 400 m LEVEL."
2. **A02** Conversion order, CH-03: "Ministry contract 74-118: convert Levels 1–2 to long-term germplasm storage. Effective 3 May 1974."
3. **A03** Climate log, CH-03: daily 4.1°C entries ending 11 Nov 1977 mid-line.
4. **A04** Quota board, CH-06: "SURVEY COVERAGE — WEEK 41: REQUIRED 82%, ACHIEVED 79%. NO BONUS."
5. **A05** Halvard log 1, CH-05 (S-0114): "Company wants the whole void photographed before insurers visit. Alone for this? Fine. Quiet suits me."
6. **A06** Wage slip carbon, CH-05: "R. HALVARD — rate 0.40/percent verified — advance withheld."
7. **A07** Halvard log 4, CH-02: "Something follows the finished plats. Never the raw rock. It only walks where the work is done."
8. **A08** Station tag S-0117: "Reset 3×. Tripod moved overnight. Bearings differ by 0.3 grad. Not mine."
9. **A09** Requisition slip, CH-06: "Requested: 2nd surveyor. DENIED — headcount frozen since closure."
10. **A10** Halvard log 7, CH-04: "Counted my exposures: 212. The ledger says 424. Someone is doubling my survey, station for station."
11. **A11** Assay ledger, CH-07: margin note — "Void Stamp: for plats condemned after collapse. Voided ground is UNKNOWN ground. Use sparingly. — J.P., 1969."
12. **A12** Evacuation memo, CH-01: "12 Nov 1977: seed program suspended. All personnel to surface by 18:00. Leave instruments."
13. **A13** Halvard log 9, CH-08: "Voided the collapse gallery today. It stood at the edge of the void like a man at the sea."
14. **A14** Seed manifest, CH-11: "Shipment 77-31: 18,000 accessions, hard red wheat. Never logged out."
15. **A15** Depth chalk, winze wall: "−412 m — pump off since '77 — water rising 4 cm/yr."
16. **A16** Halvard log 11, CH-09: "It takes readings when I stop. Nine-second habit. I timed it: three tones, always three."
17. **A17** Torn plat sheet, CH-04: hand-plotted lines with a second set of lines beneath, in harder pencil.
18. **A18** Union notice, CH-06: "Grate walkways to be replaced Q1 1978" — never happened; grates still ring.
19. **A19** Halvard log 13, CH-12 (S-0141): "94.0%. The remainder is the sump wing and the raise. If I finish, what does it do when there is nowhere it cannot go?"
20. **A20** Radio repair tag, CH-05: "No carrier at 400 m. Antenna run cancelled 1975 — budget."
21. **A21** Canteen inventory, CH-05: rations for 30 days, 11 tins remaining, neatly restacked twice.
22. **A22** Insurance survey notice, CH-07: "Lloyd's assessor visit deferred to Feb 1978 pending 100% coverage certificate."
23. **A23** Halvard log 14, loose at CH-12: "Decided. I will void it all and walk out by feel, the way the old miners did. If the plats are gone, it has no floor."
24. **A24** Final station card S-0141: reverse reads "COVERAGE 94.0% — SURVEY CONTINUES" in handwriting that is not Halvard's.
25. **A25** Cage log, CH-01: last ascent 14 Nov 1977, two names signed out; only one signed in at the pithead. The second signature is yours to compare.

---

## 10. Visual Direction & QA Shot List (llvmpipe-practical)

- **World rendering:** true dark; constant dim headlamp (4 m falloff, never depletes — not a battery mechanic); geometry silhouettes only within lamp range. Structure is revealed by points.
- **Palette:** fresh survey points amber (#E8A33D); prior/Halvard survey cyan (#6FD3C7); station markers red-orange (#D9502A); entity anomaly desaturated white with local palette bleed; plot sheet ivory paper, graphite lines.
- **Points:** MultiMesh 2 px quads, unshaded material, vertex color, distance LOD (§2). No custom GPU shaders beyond canvas/spatial unshaded; no post stack except ordered dithering + 8% vignette (CanvasLayer shader-free texture overlay).
- **Lighting:** one lamp light + per-chamber baked ambient constant; no shadows (llvmpipe).
- **12-frame QA shot list (640×360 PNG, deterministic seed 1979, scripted camera):**
  F01 cage landing lamp-only · F02 same after first burst · F03 CH-02 both exits, cyan vs dark · F04 entity boundary halt at scanned edge · F05 plot sheet fully unfolded 40% state · F06 pillar field at 60k region cap · F07 erasure strike-through on plot · F08 tombstoned void re-entered (no points) · F09 entity mid-Triangulate three-tone pose · F10 flooded sump reflections via point doubling · F11 Ending A overlaid double survey · F12 Ending B raise climb, black frame with audio meters overlay (debug).

---

## 11. Runtime Audio (all synthesized, no assets)

All audio generated at runtime via AudioStreamGenerator + additive/subtractive DSP in GDScript, mixed at 44.1 kHz.
- **Footsteps:** filtered noise bursts; per-surface filter/envelope (rock LP 900 Hz thud; grate metallic band 2.2 kHz ring 300 ms; water splash + LP wash; salt crunch HP 3 kHz crackle). These emit the AudibleEvents of §2.
- **Scanner:** charge = saw 55→110 Hz + LP sweep; burst = Geiger tick train, density mapped to hit count; completion chime = 2 sines (660/990 Hz) 120 ms.
- **Plot sheet:** paper crackle (enveloped noise) over 1.5 s unfold.
- **Entity:** reading = three pure sine bearing tones (432, 486, 540 Hz, 3.0 s apart — A16's "three tones"); movement = faint tripod tick per 1.7 m step. Audible only within 22 m graph distance.
- **Ambience:** per-region airflow (filtered brown noise, chamber-volume mapped), drips (Poisson, seeded from sim RNG), distant settle groans (rare, sine cluster).
- **Hearing semantics (authoritative):** entity hears only AudibleEvents propagated along scanned+unscanned graph edges (sound travels through tunnels, not rock); attenuation exp(−d_graph/20); events older than 30 s expire; suspicion math in §4.

---

## 12. Testability Hooks & Milestones

**Hooks:** `--sim` headless mode (no renderer) running the 60 Hz tick with scripted input tapes; state-hash function over SurveyGraph+entity+player; telemetry asserts (V1–V8, FSM invariants) hot in debug builds; deterministic screenshot harness for F01–F12; per-system GdUnit4 suites keyed to milestones.

- **M0** repo, CI, GdUnit4 harness, `--sim` skeleton.
- **M1** Survey Graph + serialization + invariants + migration fixture (§3, §6 format).
- **M2** player movement, footstep surfaces, AudibleEvents (§2, §11 events).
- **M3** scanner: cone cast, chunks, caps, LOD, coverage % (§2).
- **M4** plot sheet render + 1.5 s unfold + completion display (§2).
- **M5** entity FSM complete vs transition table incl. boundary halt (§4).
- **M6** erasure + ejection + tombstones + refusal case (§5).
- **M7** procgen + 12 chambers + guarantees G1–G8 (§8).
- **M8** artifacts A01–A25 placed; audio language complete (§9, §11).
- **M9** acts, both endings, golden determinism test, F01–F12 captures, 40+25 min content audit.

---

## 13. Non-Goals & Hard Invariants

**Non-goals:** no combat, no player death, no jump-scare triggers or stingers, no chase sequences, no flashlight-battery or stamina economies, no GPU compute or custom render pipelines, no multiplayer, no downloaded/licensed assets, no online services, no minimap HUD.

**Hard invariants:**
- HI1 The entity occupies only scanned graph space; it never teleports (including ejection and load).
- HI2 The Survey Graph is the sole source of spatial truth; renderer state is derived cache.
- HI3 Erasure is irreversible knowledge loss; ids are never reused; tombstones are permanent.
- HI4 Save→load→resume is behaviorally bit-identical under the golden test.
- HI5 All progression flows through completion %; no hidden flags gate the endings.
- HI6 Every taught rule is the enforced rule (no scripted violations after the CH-02 choreography, which itself obeys HI1).
- HI7 Global point cap and frame budgets hold on 1 vCPU llvmpipe at 640×360.
- HI8 The entity never moves faster than 1.7 m/s in any state.

---

## 14. Assumptions & Open Questions (genuine design forks)

1. **Rescan-after-erasure identity:** currently rescanning voided space creates a new region (Ending B remains reachable because completion counts only live regions). Alternative: voided space is permanently unscannable. Affects §3.2/§5/§7; recommend current rule, needs producer sign-off.
2. **Measurement severity:** tripod confiscation distance (farthest station) may be too punitive early; alternative is nearest Halvard station in Act I only.
3. **Act III gate:** Ending B requires erasing regions while standing in shrinking scanned space; if playtests show softlocks near the raise, allow the final region to auto-void on cage contact instead of at the shaft threshold.
4. **Point cap value:** 900k assumed viable on llvmpipe at 2 px; if M3 profiling disagrees, drop to 600k and tighten per-region cap to 45k.
