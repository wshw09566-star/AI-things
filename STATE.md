# Current milestone and exit criteria

M0 Provision — active in shared sandbox `i93cr1v2zv6iqg96dfncr`, using `wshw09566-star/AI-things`. Exit: `./tools/doctor.sh` prints `DOCTOR OK`, the smoke test passes, and a real 640×360 llvmpipe screenshot is committed.

# Last QA verdict

No QA verdict yet — session one.

# Next three tasks

1. DESIGN LEAD — author `DESIGN.md` with exact survey graph schema and entity transition table.
2. ENGINEER — review `DESIGN.md` for implementability.
3. INFRA — provision M0 toolchain, tests, capture rig, and worktrees.

# Known defects

None recorded.

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

`./tools/doctor.sh`

`./tools/run.sh test`

`./tools/run.sh capture --output artifacts/m0-smoke.png --width 640 --height 360`
