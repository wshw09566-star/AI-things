# Current milestone and exit criteria

M0 Provision — implementation merged at `d36c427` and independently re-run from clean clone; awaiting ENGINEER review of producer-authored infrastructure and then QA gate. Exit remains: `./tools/doctor.sh` prints `DOCTOR OK`, GdUnit4 passes, a real 640×360 llvmpipe screenshot is committed, adversarial M0 checks are clean, and QA returns PASS.

Evidence from clean clone `/work/verify-m0` in shared sandbox `i93cr1v2zv6iqg96dfncr`:

- Godot `4.7.1.stable.official.a13da4feb`.
- API-drift self-test: 13 fixtures; lint clean.
- GdUnit4: 2 cases, 0 errors, 0 failures, exit 0.
- llvmpipe capture: 640×360 PNG, 215 colors.
- Remote: `wshw09566-star/AI-things`, branch `main` at `edd3564` or later.

# Last QA verdict

No QA verdict yet — session one.

# Next three tasks

1. ENGINEER — finish `DESIGN.md` implementability review and review producer-authored M0 infrastructure before QA.
2. QA & ADVERSARY — run the pinned M0 rubric and adversarial checks sequentially; return per-item PASS/FAIL and defects.
3. ENGINEER + DESIGN LEAD — begin M1 only after M0 QA PASS: one chamber, controller, persistent scan cloud, and scanned-space entity confinement.

# Known defects

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

- Private GitHub repository selected by default to avoid publishing unfinished work.
- One shared E2B sandbox selected as required; separate per-agent sandboxes rejected.

# Rebuild and test commands

```bash
./tools/bootstrap.sh
./tools/doctor.sh
./tools/run.sh test
./tools/run.sh capture --output artifacts/m0-smoke.png --width 640 --height 360
```
