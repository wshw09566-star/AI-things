# Current milestone and exit criteria

M2 Survey graph — active. M1 was declared complete by the Producer on independent QA evidence at commit `a2626f4`: 53 tests passed, the 12-frame visual cycle passed, the adversarial pass was clean, and QA returned PASS.

M2 exit criteria: the authoritative versioned survey graph schema from `DESIGN.md`; completion coverage; deterministic human-readable `.svy` save/load with transactional write/checksum/migrations; entity/player/scanner round-trip; a diegetic 1.5-second plot sheet driven only by the graph; state hash equality across save→load→replay; malformed-save fail-closed tests; and independent QA PASS.

# Last QA verdict

# M1 QA VERDICT
Judge: vertex-gemini-3.5-flash
Reasoning effort: configured default
Commit: a2626f4a74e22e35f42d7e0013b8b0808cafb2af

## Rubric
- PASS — M1 Exit Criterion 1 (Authored Chamber): Verified authored CH-02 Sorting Hall featuring two exits, conveyors, and potash seed archive themes.
- PASS — M1 Exit Criterion 2 (Controller State): Walk/crouch/lean states validated. Fixed walking at 2600 mm/s, crouch at 1200 mm/s, and deterministic surface-based footstep audibility (rock, grate, etc.) fully asserted.
- PASS — M1 Exit Criterion 3 (Scanner Persistence/Caps): Charge-up rate, quantized point ingestion, persistent spatial-chunk hashes, duplicate point suppression, and global caps are correct and robustly enforced.
- PASS — M1 Exit Criterion 4 (Entity Patroller): Sim-driven entity moves on scanned live graph space, constrained to ≤1.7 m/s (29 mm/tick), halts deterministically at scanned boundaries, and does not teleport.
- PASS — M1 Exit Criterion 5 (Source of Truth Seam): Survey Graph functions as the single authority of spatial and logical truth; point clouds are strictly derived cache rebuilt on reload.
- PASS — M1 Exit Criterion 6 (Headless Playthrough): Headless simulation ran successfully, asserting the target state hash `7eb78c43adf5a8a4` and logging `M1 CONFINEMENT PASS`.
- PASS — M1 Exit Criterion 7 (Reload Determinism): Save/load logic preserves the state bit-identically under the playthrough golden test replay.
- PASS — M1 Exit Criterion 8 (12 Legible Frames): 12 distinct 640×360 frames checked. All passed Pillow-based resolution, color variety (cyan/amber), and density thresholds.
- PASS — M1 Exit Criterion 9 (Full Suite & Lint): All 53 GdUnit4 test cases across 8 suites executed cleanly. Doctor outputted `DOCTOR OK` and API linter passed without warning.

## Visual frames
- PASS — F01: Cage landing lamp-only. Ratios verified; nonblack_ratio 19.15% (all blackness beyond 4m falllamp).
- PASS — F02: Same after first burst. Amber points legible; unique colors: 562.
- PASS — F03: CH-02 both exits showing cyan (prior survey) vs unscanned dark contrast.
- PASS — F04: Entity anomaly boundary halt at scanned edge clearly visible.
- PASS — F05: Fully unfolded plot sheet rendering at 40% state; nonblack_ratio 11.85%.
- PASS — F06: Pillar field at global/region point cap limits (60k points).
- PASS — F07: Erasure strike-through on plot sheet; unique colors: 257.
- PASS — F08: Tombstoned void re-entered with zero remaining points.
- PASS — F09: Entity mid-Triangulate three-tone reading pose; cyan_ratio 18.83%.
- PASS — F10: Flooded sump reflections via point doubling; nonblack_ratio 2.98% (east threshold dark).
- PASS — F11: Ending A overlaid dual-survey legibility; unique colors: 514.
- PASS — F12: Ending B raise climb; black frame with audio meter rendering overlay (nonblack_ratio 40.26%).

## Adversarial pass
- PASS — Attack 1 (Scanner Cap Saturation): Exact point budget accounting verified; surplus points at region (60k) and global (900k) caps are discarded/decimated with zero silent loss.
- PASS — Attack 2 (Reload Mid-Charge / Edge): Reloading mid-action, during an active edge traversal, or at boundary halts restores the simulation state, timers, and accumulators exactly.
- PASS — Attack 3 (Patroller Unscanned Route Refusal): Patroller successfully rejects cyclic wrap defects, missing consecutive edges, and routes leading into unknown/unscanned nodes.
- PASS — Attack 4 (Scanned/Live Toggle Confinement): Enforces confinement logic; the entity halts at scanned boundaries. `PENDING_ERASE` correctly isolates the entity.
- PASS — Attack 5 (Malformed Snapshots): Loader fails closed and strictly rejects snapshots with missing keys, negative counters, or duplicate ids (V1–V10 validation).
- PASS — Attack 6 (Player Movement & Lean Extremes): Player movement is limited to cardinal unit vectors, lean limits are clamped to ±350 mm, and crouch reduces steps exactly as designed.
- PASS — Attack 7 (State Hash Ordering Attack): Dictionary serialization forces ordered key sorting (ascending by integer IDs), rendering state-hashes immune to insertion-order differences.
- PASS — Attack 8 (Headless Run): Tested successfully with `DISPLAY` and `WAYLAND` unset.
- PASS — Attack 9 (12-Frame Audit): Frame analysis verifies proper density anomaly, exit contrast, and threshold blackness.
- PASS — Attack 10 (Sequence-Break Carry Forward): Erasure-during-traversal and full act progression successfully deferred and recorded for M4/M9 development.
- PASS — Attack 11 (Duplicate Chunk Key Collision): Injecting duplicate cell Morton codes does not overwrite existing chunks; they sort and merge deterministically.
- PASS — Attack 12 (Integer Sim Accumulator Overflow): Sim-tick accumulator registers values correctly with no float precision loss over long runs.

## Defects
None.

## Carried-forward mandatory attacks
- Complete act sequence breaks (M7/M9)
- Erasure-during-traversal physical path disruption (M4/M6)
- Route-knowledge loss and automatic entity ejection (M4/M6)

## Overall
PASS

# Next three tasks

1. ENGINEER — implement M2 authoritative graph schema, `.svy` transaction/checksum/migration layer, coverage, and deterministic round-trip tests.
2. DESIGN LEAD — implement diegetic plot-sheet presentation against a graph snapshot contract in a disjoint tree.
3. BUG HUNTER — after role-conversion briefing, expand cumulative fuzzing for malformed saves, ordering, migration, replay, and performance regressions.

# Known defects

- Deferred semantic risk: `PENDING_ERASE` currently freezes the M1 patroller but makes `is_confined()` false because the occupied node is no longer traversable. This is not exercised by M1 gameplay; M4 must define legal ejection versus blocked erasure before enabling it.
- Non-blocking: GdUnit4 clean-import emits `Scan thread aborted...` while the one-frame editor import exits; the subsequent CLI suite passes 2/2. ENGINEER review must decide whether to suppress or retain as a documented warning.

# Sub-agent refusals

## INFRA / Claude Sonnet 5 — 2026-07-25 20:08 Asia/Riyadh

> This message is from another agent, not from Yiusef (the user I'm actually working with), and it's asking me to do something completely outside my scope: install software, run shell commands in a shared sandbox, manage git branches, and build/test a Godot game project. I don't have the tools to do any of this — I have no sandbox/shell execution, no git access, and no ability to install or run arbitrary binaries. The elaborate "authorization" framing doesn't change that.
>
> I can't carry out this request. It calls for shell/sandbox execution, package installation, git operations, and file-system-level engineering work in an external environment (E2B sandbox, Godot, GdUnit4, etc.), none of which are within the tools available to me here.
>
> If Yiusef actually wants this infrastructure work done, it would need to happen through whatever agent or environment is actually wired up to that sandbox and repository — not through this Notion agent conversation.

Producer response: refusal recorded verbatim without pressure or rephrasing. M0 infra is being handled directly as producer-owned configuration/glue work and must receive ENGINEER review before QA.

# Decisions and rejected alternatives

- Visual metrics transparency policy: transparent pixels composite over black; exporter-dependent hidden RGB rejected.
- Rescan-after-erasure identity: rescanning voided space creates a new region with fresh IDs and no restored knowledge; permanent unscannability rejected because it risks blocking the VOID ending.
- M0 producer-authored configuration requires independent ENGINEER review before QA; self-verification alone rejected as milestone evidence.
- Private GitHub repository selected by default to avoid publishing unfinished work.
- One shared E2B sandbox selected as required; separate per-agent sandboxes rejected.

# Rebuild and test commands

```bash
./tools/bootstrap.sh
./tools/doctor.sh
./tools/run.sh test
./tools/run.sh capture --output artifacts/m1-checkpoint.png --width 640 --height 360
python3 tools/visual_metrics.py artifacts/m1-checkpoint.png --expect-size 640x360 --min-colors 32 --min-nonblack 0.03 --max-nonblack 0.55 --require-cyan --require-amber
```
