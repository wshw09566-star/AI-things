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

**Footsteps:** floor material tag drives synthesis and detection. Each step emits `AudibleEvent(pos, loudness L, radius r)`: rock walk r=9 m L=1.0 · rock crouch r=4 m L=0.4 · grate r=14 m L=1.5 · water r=16 m L=1.8 · salt-crust r=11 m L=1.2. Entity hearing consumes AudibleEvents via **graph distance** over the full generated graph — scanned *and* unscanned edges, since sound travels through tunnels, not rock — never euclidean (§11 is authoritative).

**Scanner (initial targets, llvmpipe-safe; tuning range in brackets):**
- Charge 100 max; burst costs 25 [15–35]; recharge 5/s only while tripod deployed and player stationary within 1 m of it.
- Cone 55° full angle [45–70], range 24 m [18–28], 96×54 deterministic ray grid = 5,184 rays over 0.8 s [3k–7k rays].
- Each hit deposits 1 point into the region's chunks. Per-region cap 60,000 points; **hard global cap 900,000** [600k–1.2M]. At cap, chunks in the farthest region decimate 2:1 in ascending chunk-id order, dropping odd point indices within each chunk and rewriting `count`. Decimation touches only stored points — never nodes, edges, or `scanned` flags — so it can never invalidate a route or a coverage cell.
- LOD by camera distance: render every point < 15 m, every 2nd < 30 m, every 4th < 60 m, culled beyond. Point size 2 px at 640×360, rendered via MultiMesh quads (no custom GPU compute). **Visible-instance budget: ≤ 120,000 MultiMesh instances per frame** — one `MultiMeshInstance3D` per chunk, with `visible_instance_count` set each frame after frustum + LOD selection in ascending chunk-id order. The 900,000 figure is a *stored* cap, never a per-frame draw count; the 8 ms point budget is sized against the visible cap.
- Frame budget at 640×360 / 30 fps: points ≤ 8 ms, entity sim ≤ 2 ms, audio synth ≤ 2 ms, everything else ≤ 18 ms.

**Coverage & completion:** at generation, every region gets a 0.5 m coverage grid over walkable/wall surfaces (`cell_total`). A burst marks cells whose surface point lies in the cone with line-of-sight. Region is complete at ≥ 92% cells. **Global completion = Σ cells_scanned / Σ cell_total** over live (non-erased) regions. If Σ cell_total over live regions is 0 (every region erased — Ending B), completion is *defined* as exactly 0.0% and no division is performed. Shown on the plot sheet as `SURVEY nn.n%`, floored to one decimal, so `100.0%` can only appear when Σ cells_scanned == Σ cell_total exactly; act gates and endings compare those integers, never the displayed string.

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
  cost: int               — integer-only: cost = (length_mm * permille) / 1000, truncating integer division; permille = ROCK 1000, RAIL 1000, GRATE 1100, RUBBLE 1400, WATER 1600, SALT 1200. No float arithmetic in cost or pathfinding.
  scanned: bool

SRegion
  id: int
  chamber_code: String    — "CH-01"… or "DR-xx" for connective drifts
  name: String
  cell_total: int
  cells: String           — base64 (ASCII) bitset of scanned coverage cells; bit i = cell i of the region's generation-time cell list (scanline order: ascending z, then x, then y in mm), MSB-first within each byte, length ceil(cell_total / 8) bytes
  complete: bool          — cached (≥ 92% rule)
  status: enum {LIVE, PENDING_ERASE} — serialized as string; the §5 erasure state, must round-trip
  erase_deadline_tick: int | null — non-null only while PENDING_ERASE (§5 step 3)
  chunk_ids: Array[int]

PointChunk
  id: int
  region_id: int
  cell: int               — spatial hash key: 63-bit Morton interleave of the 4 m grid cell, biased so every axis is unsigned: cell = morton3(cx + 2^20, cy + 2^20, cz + 2^20) with cx = floor(pos_mm.x / 4000) etc., 21 bits per axis. Always non-negative, so it is a safe GDScript int and sorts deterministically.
  count: int              — number of points; count * 4 == points.size()
  points: PackedInt32Array — x,y,z,intensity quadruples; x,y,z in whole centimetres, intensity 0–255. Integers keep the JSON exact; the float32 render buffer is a derived cache rebuilt on load.

StationMeta
  station_no: String      — "S-0117"
  installed_by: String    — "HALVARD" | "PLAYER"
  log_id: String | null   — artifact reference (§9)

Tombstone
  region_id: int
  chamber_code: String
  erased_tick: int        — authoritative sim tick of erasure; tombstones are ordered by (erased_tick, region_id) and that order is part of the state hash
  erased_day: int         — display only, derived as 1 + playtime_ms / 86_400_000 (in-fiction day counter); never read by logic
  node_ids: Array[int]
  edge_ids: Array[int]
  cell_total: int
```

### 3.2 Deterministic rules
- All dictionaries serialize with integer keys sorted ascending; arrays sorted by id. Any iteration whose order affects behavior (route ties, decimation, ejection, migration) MUST iterate sorted ids.
- Erased region/node/edge/chunk ids live forever in tombstones and are never reused. Rescanning erased space creates a **new** region with fresh ids and empty coverage: the old knowledge (plot lines, station metadata, completion history) is irrecoverably lost.
- **Integer time and motion.** The 60 Hz sim tick is the only clock, and one tick is *not* an integer number of milliseconds, so every duration is stored as an integer **tick count** (1.5 s = 90, 2.0 s = 120, 3.0 s = 180, 4.0 s = 240, 9.0 s = 540, 45 s = 2,700). Milliseconds appear only in display and `playtime_ms`. All motion uses an integer fixed-point accumulator: for speed v mm/s, each tick `acc += v; step_mm = acc / 60; acc -= step_mm * 60` (entity 1700, walk 2600, crouch 1200). No float positions and no delta-time dependence; accumulators are serialized (§6).

### 3.3 Validation invariants (asserted on load and after every mutation batch; GdUnit4)
- V1 every edge's endpoints exist; a < b. V2 every node's region exists. V3 if an entity instance exists, its position refers to an existing scanned node or scanned edge; when the last live region is erased the entity is despawned (§5 step 6) and V3 is vacuous. V4 completion ∈ [0,100]. V5 tombstone ids ∩ live ids = ∅. V6 every chunk's region exists and is listed in region.chunk_ids. V7 the scanned subgraph may legitimately have several components — one burst can reveal disjoint parts of a chamber, and erasing a neighbour can split one — so the asserted form is: every scanned edge has both endpoints scanned, and no scanned node or edge belongs to an erased region. V8 next_ids strictly greater than any live or tombstoned id. V9 if an entity instance exists, every node and edge of its current route is live and scanned, and its whole component is scanned. V10 the audible-event queue, entity route memory, motion accumulators, and `pending` action all survive a save→load→hash round trip (§6).

### 3.4 Migrations
Loader switches on `version`; each migration is a pure function vN→vN+1 with a committed fixture save file per version and a GdUnit4 round-trip test. Unknown future versions refuse to load with a diegetic error.

---

## 4. The Entity — "The Other Surveyor"

Rendered only as a **point-density anomaly**: ~2,400 points sampled on a human silhouette volume, borrowing the palette of surrounding chunks but at 3× local density with slight jitter. Never a mesh, never lit, never textured.

**Movement law:** exists only on scanned nodes/edges of the Survey Graph. Travels in straight measured lines between stations at a constant 1.7 m/s. Never runs. Never teleports. Stops at stations for readings. It surveys; it does not chase the current player position — it triangulates and intercepts the **plotted route**.

**Suspicion:** scalar S ∈ [0,100], decays 1.0/s. Each AudibleEvent adds `L × 25 × exp(-d_graph / 20 m)` where d_graph is the shortest distance over the **full** graph, scanned or not (§11 hearing semantics), from event to entity [decay 15–30 m]. Suspicion is stored as an integer (×10); the exponential is evaluated once per event on the tick it is consumed, so no float state accumulates across ticks.

**Route prediction:** keeps the player's last 4 station-to-station legs; predicts the next leg by direction continuation on the plot; intercept node = scanned STATION/JUNCTION minimizing (entity travel time − predicted player arrival time) subject to entity arriving first. Ties: lowest node id.

### 4.1 Exact transition table (all five states)

| From | Trigger | Guard | Actions | To | Timing | Interrupt / save behavior |
|---|---|---|---|---|---|---|
| (spawn/load) | game start or save loaded | graph has ≥1 scanned station | place at the Halvard station of lowest graph cost to CH-05, ties broken by lowest node id; restore serialized state verbatim on load | Survey (or serialized state) | — | load restores state, node/edge+t, timers, route exactly |
| Survey | reading finished at station | — | pick next station: lowest visit_count, tie lowest id; A* by edge cost; walk | Survey | reading 6–14 s (seeded roll per station) | mid-edge position saved as (edge_id, t); resumes same t |
| Survey | S ≥ 40 | latest audible event within 80 m graph dist; the player may be in unscanned space (required by the CH-02 lesson) | halt; face last event bearing | Triangulate | ≤ 0.5 s | if saved mid-halt, resumes in Triangulate with timer |
| Survey | region containing it queued for erasure | — | begin ejection route (§5) | Withdraw | immediate | pending erasure serialized |
| Survey | `graph_mutated` invalidates its current route or target station | — | drop route | Recalibrate | immediate | — |
| Triangulate | 3 bearings taken | ≥2 distinct AudibleEvents recorded in last 30 s | compute intercept node; commit route | Intercept | 9.0 s fixed (3 × 3.0 s tones) | bearing count + elapsed serialized |
| Triangulate | S < 25 before bearings done | — | discard bearings | Survey | — | — |
| Triangulate | `graph_mutated` from erasure touching its bearings or route (point decimation never can: it changes no node, edge, or `scanned` flag) | — | drop bearings and targets | Recalibrate | immediate | — |
| Intercept | arrived at intercept node | — | hold, listening; reading pose | Intercept (waiting = true) | wait ≤ 45 s = 2,700 ticks [30–60] | wait elapsed serialized |
| Intercept | player audible within 12 m graph dist while waiting | — | walk toward event along scanned edges only; halt at scanned-space boundary if route leaves scanned space | Intercept | — | — |
| Intercept | contact: within 1.5 m of player for 2.0 s | player in scanned space | **Measurement** (§4.2) | Withdraw | 4.0 s sequence | if saved mid-measurement, measurement completes on load |
| Intercept | wait expires or S < 10 | — | — | Survey | — | — |
| Intercept | intercept node erased | — | — | Recalibrate | immediate | — |
| Any state | measurement done, scan burst covers ≥ 30% of its points, or ejection ordered (§5) | — | route to a scanned station ≥ 3 edges away in the least-player-visited region; walk | Withdraw | until arrival | route serialized; ejection routes also carry `erase_deadline_tick` |
| Withdraw | arrived | — | resume readings | Survey | — | — |
| Withdraw | route invalidated by any graph mutation (a route node or edge erased) | — | — | Recalibrate | immediate | pending erasure and its deadline preserved |
| Recalibrate | entered | — | stand still; re-run A* over current scanned graph; validate V3 | (result) | 2.0 s fixed | timer serialized |
| Recalibrate | valid route found | — | — | Survey | — | — |
| Recalibrate | no scanned station reachable | its component has no station | hold at nearest scanned node; retry every 5 s | Recalibrate | 5 s loop | — |

**FSM invariants:** entity position always satisfies V3 and V9; no transition may place it on unscanned or erased space; all timers are integer tick counts (§3.2); all random rolls come from the serialized sim RNG stream.

**Totality:** the five states are Survey, Triangulate, Intercept, Withdraw, Recalibrate. `Intercept (waiting)` is Intercept with a serialized `waiting` flag, not a sixth state. Any trigger not listed for the current state is ignored — an explicit self-loop with no state change — which makes the table total over (state × trigger). The only triggers that may fire from every state are the `Any state` row above and despawn (§5 step 6).

### 4.2 Measurement (contact consequence — no combat, no death)
The entity photographs the player: screen fills with its point density over 4.0 s, three bearing tones sound. It then confiscates the tripod and carries it to the station on its route farthest (by cost) from the contact point. The player keeps the plot sheet, must travel by memory to retrieve the tripod, and cannot scan or erase until retrieval. Repeated contact escalates only distance, never harm.

---

## 5. Erasure & Legal Ejection Algorithm

Erasing region R (hold X 3.0 s at any station of R):
1. Mark R `PENDING_ERASE` (plot sheet shows the region struck through in pencil).
2. If entity not in R: skip to step 4.
3. **Ejection:** compute Dijkstra by edge cost over the **pre-deletion** scanned graph from the entity's nearest node in R to the nearest scanned node outside R (ties: lowest node id). The entity enters Withdraw and walks that route at 1700 mm/s — a legal adjacent scanned route, never a teleport. While any region is PENDING_ERASE, R's nodes are forbidden as *targets* in every state (transit only), so the entity cannot re-enter R and stall the erasure indefinitely. `erase_deadline_tick` is set to `now + 2 × route_cost_in_ticks + 300`; a Recalibrate caused by further mutation recomputes the route but never extends the deadline. **Termination:** the graph is finite, each recomputation strictly re-solves Dijkstra on the current scanned graph, remaining route cost is non-increasing between mutations, and the deadline bounds the number of recomputations — so step 3 always ends in exactly one of two outcomes: the entity stands outside R, or erasure is refused. Refusal cases, both of which revert R to LIVE and print the diegetic message `CANNOT VOID — PLOT OCCUPIED`: (a) no scanned route leaves R (isolated scanned pocket); (b) `erase_deadline_tick` passes with the entity still inside R.
4. When R is entity-free: atomically delete R's nodes, edges, chunks, and coverage; append Tombstone; recompute global completion; remove R's plotted lines and station metadata (route knowledge loss). Player receives no map memory aid.
5. Fire `graph_mutated`; entity FSM reacts per table (Recalibrate if affected).
6. **Last live region.** Erasing the final live region is never refused: the entity's floor ceases to exist, so the confinement rule is satisfied by removal rather than by routing. Fixed order: skip steps 2–3, delete R, then **despawn** the entity (`entity.present = false`, no position, no route), recompute completion — exactly 0.0% by §2 — and open Ending B's raise climb. Despawn is removal, not movement, so HI1 and HI8 are untouched, and V3/V9 are vacuous while `present == false`. A despawned entity never returns, even if voided space is rescanned.

Rescanning erased space builds a new region from scratch (§3.2) — safe space can be re-opened, but the old survey is gone forever.

---

## 6. Save / Load — the Survey File

One human-readable file per slot: `survey_<station>.svy` — strict JSON, fixed key order (sorted), LF endings, ASCII, integers for all quantized values.

Sections: `header` {version, seed, tick (the authoritative clock), playtime_ms, act, checksum}, `rng` {gen_stream frozen post-generation, sim_stream state (two u64 words)}, `graph` (full §3 schema, including each region's `status` and `erase_deadline_tick`, and the tombstone list in (erased_tick, region_id) order), `entity` {present, state, waiting, edge_id+t_mm or node_id, motion accumulator, timers_ticks, bearings_taken, route node ids, visit_counts, route_memory — the last 4 station-to-station legs the prediction in §4 reads — suspicion ×10 as int}, `audio` {live AudibleEvents: pos_mm, loudness ×10, radius_mm, born_tick — the queue the 30 s Triangulate guard and suspicion decay read}, `player` {pos_mm, motion accumulator, yaw/pitch centidegrees, crouched, charge ×10, tripod_deployed|carried_by_entity node_id, inventory, artifacts_read}, `pending` {action ∈ {SCAN_BURST, ERASE_HOLD, PLOT_UNFOLD, NONE}, elapsed_ticks, params}. Any state a rule reads must appear here; the golden test below is what enforces it.

**Determinism contract:** simulation runs on a fixed 60 Hz tick; all gameplay state uses integers (mm, ms, centidegrees, tenths); all randomness from the serialized sim stream. Reload is behaviorally bit-identical: GdUnit4 golden test runs scripted inputs N ticks, compares full state hash against save→load→replay of the same inputs. Interruptible actions resume from `pending.elapsed_ticks` exactly.

**Transactional write:** serialize to `survey_<station>.svy.tmp`, flush and close, then rename over the slot in one `DirAccess.rename`; the displaced file is kept one generation as `.bak`. `header.checksum` is FNV-1a 64 over the canonical byte stream with the checksum field zeroed. On load, order is: parse → checksum → migrate (§3.4) → validate V1–V10 → rebuild derived caches (point buffers, coverage counts). Any failure, or an unknown `version`, refuses the slot with a diegetic error and offers `.bak`; a partially written `.tmp` is never loaded.

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

**Hooks:** `--sim` headless mode (no renderer) running the 60 Hz tick with scripted input tapes; state-hash function over SurveyGraph+entity+player; telemetry asserts (V1–V10, FSM invariants) hot in debug builds; deterministic screenshot harness for F01–F12; per-system GdUnit4 suites keyed to milestones.

- **M0** repo, CI, GdUnit4 harness, `--sim` skeleton.
- **M1** Survey Graph + serialization + invariants V1–V10 + migration fixture + **state-hash function and the save→load→replay golden harness** (§3, §6). The determinism contract is an M1 deliverable, not an M9 one: every later milestone lands its own replay case, so no system that must be deterministic ships before the test that proves it.
- **M2** player movement, footstep surfaces, AudibleEvents (§2, §11 events).
- **M3** scanner: cone cast, chunks, stored caps, LOD, visible-instance budget profiled on llvmpipe, coverage % (§2).
- **M4** plot sheet render + 1.5 s unfold + completion display (§2).
- **M5** entity FSM complete vs transition table incl. boundary halt (§4).
- **M6** erasure + ejection + tombstones + refusal case (§5).
- **M7** procgen + 12 chambers + guarantees G1–G8 (§8).
- **M8** artifacts A01–A25 placed; audio language complete (§9, §11).
- **M9** acts, both endings (incl. §5 step 6 total-erasure despawn), full-run golden determinism replay on the M1 harness, F01–F12 captures, 40+25 min content audit.

---

## 13. Non-Goals & Hard Invariants

**Non-goals:** no combat, no player death, no jump-scare triggers or stingers, no chase sequences, no flashlight-battery or stamina economies, no GPU compute or custom render pipelines, no multiplayer, no downloaded/licensed assets, no online services, no minimap HUD.

**Hard invariants:**
- HI1 The entity occupies only scanned graph space; it never teleports (including ejection and load). Total erasure removes the entity (§5 step 6); removal is not movement.
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

---

## 15. Engineering review

Implementability pass over §§2–13 for Godot 4.7.1 GDScript, fully offline, software rasterizer (llvmpipe, 1 vCPU, 640×360). Amendments were surgical: the core inversion, the 12 chamber briefs, the 25 artifacts, the 40-minute content floor, and both endings are unchanged.

### 15.1 Defects found and corrected

1. **Completion had no value at zero live regions** — Ending B (all regions erased) divided by an empty denominator. Completion is now *defined* as exactly 0.0% in that case, and the 100.0% gate compares integers rather than the floored display string (§2).
2. **`SRegion` could not express PENDING_ERASE**, the state §5 depends on, so a pending erasure could not round-trip through a save. Added `status` and `erase_deadline_tick` (§3.1).
3. **Total erasure broke the confinement invariant.** Erasing the last live region would either be refused as `CANNOT VOID — PLOT OCCUPIED` (softlocking Ending B) or leave the entity standing on deleted space. Added §5 step 6 (despawn), made V3/V9 conditional on an entity existing, and clarified HI1 that removal is not movement.
4. **The transition table was not total.** Route-destroying mutations were only handled from Triangulate, Intercept, and Withdraw-during-ejection; the Withdraw-entry row listed Withdraw as its own source state; `Intercept (wait)` read like a sixth state. Added a Survey→Recalibrate mutation row, restated the entry row as `Any state`, made `waiting` a serialized flag on Intercept, and added an explicit rule that unlisted triggers are ignored self-loops (§4.1).
5. **Ejection had no termination bound and one missing failure case**, and the entity could legally re-target the pending region and stall erasure forever. Added the no-targets-inside-R rule, `erase_deadline_tick`, an explicit termination argument, and the deadline refusal case (§5 step 3).
6. **The save file omitted state that live rules read**: the AudibleEvent queue behind the 30 s Triangulate guard, the 4-leg route memory behind prediction, bearings taken, motion accumulators, region erase status, and the tick clock. Reload could not have been behaviorally identical. All added, plus invariant V10 (§6, §3.3).
7. **“Integer milliseconds on the 60 Hz tick” is not representable** (a tick is 16.666… ms). Durations are now integer tick counts, and motion uses an integer per-tick accumulator so 1700/2600/1200 mm/s are exact and frame-rate independent (§3.2).
8. **`cost: int` was computed from float multipliers.** Now integer permille with truncating division (§3.1).
9. **A “64-bit Morton code” of signed grid coordinates** overflows or goes negative in a GDScript int. Now a biased 21-bits-per-axis interleave: always non-negative, stable to sort (§3.1).
10. **`PackedFloat32Array` point storage contradicted the integer / human-readable JSON rule.** Points are stored as centimetre integers; the float32 render buffer is a derived cache rebuilt on load (§3.1).
11. **The coverage bitset had no defined bit order, origin, or length.** Pinned to the region's generation-time cell list in scanline order, MSB-first, ceil(cell_total/8) bytes (§3.1).
12. **V7 was unmaintainable as written** (“each region's scanned subgraph is connected”): one burst can reveal disjoint parts of a chamber, and erasing a neighbour can split a component. Replaced with an assertable edge/region form, plus V9 covering the entity's route and component (§3.3).
13. **Hearing distance contradicted itself** — §11 propagates along scanned *and* unscanned edges, §4 said scanned-only. §11 is now authoritative in both places, and suspicion is stored as an int ×10 (§2, §4).
14. **The Survey→Triangulate guard contradicted the mandatory CH-02 lesson**, where the player stands in unscanned dark. The guard now keys off event graph distance; contact/Measurement still requires the player in scanned space, so confinement and the taught rule both hold (§4.1).
15. **Point decimation was cited as a route-invalidating mutation**, but it only rewrites stored points. Corrected in both places and its drop order made explicit (§2, §4.1).
16. **900k stored points was implicitly also a per-frame draw count**, which 1 vCPU llvmpipe cannot carry. Added an explicit ≤120k visible-instance budget through per-chunk `MultiMeshInstance3D.visible_instance_count` (§2).
17. **Tombstones carried only an in-fiction day**, giving no deterministic mutation ordering. Added `erased_tick` and a fixed (erased_tick, region_id) order that participates in the state hash (§3.1).
18. **Save writes were neither transactional nor integrity-checked.** Added tmp + atomic rename, one-generation `.bak`, an FNV-1a 64 checksum, and a fixed parse→checksum→migrate→validate→rebuild load order (§6).
19. **The determinism contract was only testable at M9**, after every system obliged to satisfy it. State hash and the save→load→replay harness moved to M1, with per-milestone replay cases (§12).

### 15.2 Reviewed and accepted as implementable without change

- **Godot API surface.** Cone casting via `intersect_ray` (5,184 rays over 48 ticks ≈ 108/tick), MultiMesh point rendering with vertex colour and an unshaded material, `AudioStreamGenerator` DSP, `DirAccess.rename`, JSON: all core Godot 4.7.1 GDScript. No GPU compute, no custom pipeline, no imported assets, no network.
- **Scanner and point budgets.** Charge 100 / burst 25 / 5 per s, 55° × 24 m, 96×54 deterministic grid, 60k per-region and 900k global *stored* caps, LOD tiers — all consistent with the 8/2/2/18 ms frame split once the visible-instance cap above is honoured.
- **Graph schema semantics.** Node/edge/region ownership, `a < b`, monotonic never-reused ids, tombstone permanence, 4 m spatial hash, sorted-id iteration for every order-sensitive operation, and migration-by-pure-function are coherent and serializable as strict JSON.
- **Milestone order.** M0→M9 has no inversion: graph and serialization precede the FSM, AudibleEvents precede hearing, the scanner precedes coverage and the plot sheet, the FSM precedes erasure, procgen precedes the guarantee suite. With correction 19, nothing that must be deterministic ships before its proof.
- **Confinement.** The entity remains inside scanned, live space on every corrected path: Survey routing, Triangulate, Intercept boundary halt, ejection, Recalibrate, load, and despawn.
- **Consistency with the fixed constraints.** No remaining contradiction with the core inversion, GDScript-only / offline / procedural-plain-text assets, 12 chambers, 25 artifacts, the 40-minute critical path, or the two endings.

### 15.3 Accepted risks

- 44.1 kHz synthesis in GDScript inside a 2 ms frame slice on 1 vCPU is the tightest budget in the document. Fallback: mix ambience at 22.05 kHz and keep footsteps and bearing tones at full rate. No rule depends on the sample rate.
- 900k stored points and 120k visible instances remain profiling targets; §14.4's ranges already cover dropping to 600k / 45k without altering a rule.
- Base64 coverage bitsets are ASCII but not eyeball-readable. Accepted for size: the cell list they index is regenerable from the seed, and every other field stays readable.
- §14's four forks are genuine design decisions for the design lead and producer; none blocks implementation as written.
