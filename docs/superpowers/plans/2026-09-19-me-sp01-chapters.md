# SP01 Chapter Import Plan

**Goal:** Import the missing first chapter and split the prologue using the existing generic extractor.

**Architecture:** Private configs select `SP01/Edge_p.me1` and `SP01/Escape_p.me1`. Both use `split_sections`; the existing SectionLoader previews one section in the editor and instances all sections at runtime. No runtime streaming change is included.

**Tech Stack:** Python via uv, Godot 4.7.1.

- [x] Rename the private prologue config to `sp01a_edge.json`, update its id, and enable `split_sections` for Pt1/Pt2. Add `sp01b_escape.json` for Intro/Off/R1/St1/Plaza with Escape background and exterior lights.
- [x] Run `extract.py` for each config, then `tools/me_level/build_level.gd`. Preserve any authored shell adjustments during migration.
- [x] Update menu paths and add Flight between the prologue and chapter 2. Update active references and chapter documentation; retire the old prologue outputs only after replacements validate.
- [x] Make the structural verifier count geometry and interactions across split sections. Run targeted checks for both chapters, including spawn/checkpoint floors and mover targets, and inspect diffs without overwriting existing user edits.

Validation found an additional supported bar type: Escape uses a horizontal catwalk support inside a swing volume. The generic swing search now includes that mesh family while retaining its horizontal/volume checks. Both new chapter structural checks pass, including all eight Escape interaction lines. The existing generated slide surface retains its persistent `uncontrolled_slide` group after serialization; declaring that group globally requires no extractor change.

Escape's Intro ladder also has a collapsed cooked spline despite valid step positions. The existing step-based repair now treats equal Start/End as invalid. Two asset-free Python regression tests cover collapsed and sound splines; the structural verifier rejects zero-length interaction lines.
