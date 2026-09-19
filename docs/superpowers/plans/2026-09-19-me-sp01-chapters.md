# SP01 Chapter Import Plan

**Goal:** Import the missing first chapter and split the prologue using the existing generic extractor.

**Architecture:** Private configs select `SP01/Edge_p.me1` and `SP01/Escape_p.me1`. Both use `split_sections`; the existing SectionLoader previews one section in the editor and instances all sections at runtime. No runtime streaming change is included.

**Tech Stack:** Python via uv, Godot 4.7.1.

- [ ] Rename the private prologue config to `sp01a_edge.json`, update its id, and enable `split_sections` for Pt1/Pt2. Add `sp01b_escape.json` for Intro/Off/R1/St1/Plaza with Escape background and exterior lights.
- [ ] Run `extract.py` for each config, then `tools/me_level/build_level.gd`. Preserve any authored shell adjustments during migration.
- [ ] Update menu paths and add Flight between the prologue and chapter 2. Update active references and chapter documentation; retire the old prologue outputs only after replacements validate.
- [ ] Make the structural verifier count geometry and interactions across split sections. Run targeted checks for both chapters, including spawn/checkpoint floors and mover targets, and inspect diffs without overwriting existing user edits.
