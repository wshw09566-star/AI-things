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

None recorded.

# Decisions and rejected alternatives

- Private GitHub repository selected by default to avoid publishing unfinished work.
- One shared E2B sandbox selected as required; separate per-agent sandboxes rejected.

# Rebuild and test commands

`./tools/doctor.sh`

`./tools/run.sh test`

`./tools/run.sh capture --output artifacts/m0-smoke.png --width 640 --height 360`
