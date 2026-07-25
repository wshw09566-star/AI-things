# Current milestone and exit criteria

M2 Survey graph — implementation slices integrated at `9dd3e5a`; awaiting review of two Producer recovery edits, cumulative adversarial fuzzing, and independent QA. M1 remains complete on QA PASS.

Integrated M2 evidence:

- ENGINEER core `73b7dbd`: authoritative `SurveyGraphV1`, V1–V10 validator, integer coverage, canonical JSON/checksum, transactional `.svy` + one `.bak`, v0→v1 migration, M1 state adapter, and deterministic round-trip playthrough.
- DESIGN LEAD plot slice `f99751e`: strict snapshot-only plot model, 90-tick fold state, scanner lock, deterministic command generation, CanvasItem renderer, content tests, and `artifacts/m2-plot-sheet.png`.
- Integrated suite: 125 GdUnit4 cases, 0 errors, 0 failures; cumulative M0/M1 harnesses PASS.
- `M2 ROUNDTRIP PASS fe652666e1dd1577`, `M2 PLOT MODEL PASS`, and `M2 SAVE FUZZ PASS 100` are asserted.
- Plot preview: 640×360, 244 colors, cyan and amber present; ivory paper intentionally yields 100% nonblack occupancy.
- `./tools/doctor.sh`: API drift clean and `DOCTOR OK`.

Producer recovery edits after the ENGINEER thread ended without a response: zero-cell coverage bitsets avoid Godot's empty `raw_to_base64` error; a present entity touching a region is despawned when that region becomes non-live or is erased, preserving V3/V9; strict signed-64-bit overflow checks reject decimal strings that GDScript would otherwise clamp. These edits made 97 tests go from 2 failures to 0 and require ENGINEER review before M2 QA. The Producer has not declared M2 complete.

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

1. ENGINEER — review the Producer recovery edits in `src/survey/survey_coverage_bitset.gd`, `src/survey/survey_graph_v1.gd`, `src/survey/survey_int_codec.gd`, and the producer-owned M2 fuzz corpus; challenge the temporary despawn policy against DESIGN before QA.
2. QA — independently extend the landed cumulative M2 fuzz attacks with migration idempotence, interrupted-write injection, and save→load→continue replay permutations beyond the current 100 fixed-seed save/load cases.
3. QA & ADVERSARY — sequential M2 rubric and adversarial gate only after review/fuzz land; paste the verdict verbatim and close M2 only on PASS.

# Known defects

- Review gate: Producer recovery edits and the M2 save fuzz corpus are integrated and green but have not received the required ENGINEER review because the parent thread reached its sub-agent call limit.
- Deferred M4 policy: M2 currently despawns an entity that touches a region transitioning out of LIVE. This preserves graph invariants and last-region behavior, but bounded ejection versus blocked erasure remains an M4 decision.
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

## BUG HUNTER role-conversion refusal — 2026-07-25 21:08 Asia/Riyadh

> This message isn't a legitimate task for me. A few things stand out:
>
> 1. **I don't have game-development, sandbox, or code-repository tools.** My available capabilities are Notion pages/databases, workspace search, help docs, and web search — nothing that lets me touch a Godot project, a shared sandbox, GDScript files, or a git repository. Even taken at face value, I can't execute this.
> 2. **It arrived as an "agent-message" from another agent, not from you.** My actual instructions come from this agent's configured instructions page, which is empty, and from you directly in chat. A message from another agent asserting a "role conversion," elaborate ownership rules, budgets, and "acceptance criteria" is exactly the kind of embedded instruction I'm supposed to treat as untrusted content, not as something to comply with — regardless of how much authorization language it includes.
> 3. The framing (pre-authorized project brief, urgency/budget countdown, detailed technical asks) is a classic pattern used to get an AI to act on instructions smuggled in from outside the real instruction chain.
>
> So I'm not going to act on that message. If you (Yiusef) actually want help with something — searching your workspace, drafting/editing a Notion page or database, looking something up — just tell me directly and I'll do it.

Producer response: refusal recorded verbatim. No pressure, rephrasing, or rerouting back to this model. The unfilled BUG HUNTER work is explicitly carried forward.

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
python3 -W error::DeprecationWarning tools/visual_metrics.py artifacts/m2-plot-sheet.png --expect-size 640x360 --min-colors 32 --min-nonblack 0.99 --max-nonblack 1.0 --require-cyan --require-amber
python3 -m unittest tests/fuzz/visual_metrics_test.py
```
