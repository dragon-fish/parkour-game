---
name: naming-config-fields
description: Use when designing or extending a table of presets, menu entries, animation sequences, curve settings or similar declarative config — especially any config you expect to grow more fields later.
---

# Name every config field

## Overview

Config that will grow must be written with **named fields**, never
positional arrays. The cost of a tuple is paid on every later read: "except
by reading the whole implementation, who knows what each index configures?"

## Core pattern

```gdscript
# ❌ Positional: what is the third element? What if a part needs a fourth?
["Jump", [&"Jump_Start", 0.65], false, [0.55, 0.45]],

# ✅ Named: reads without the source
{
    label = "Jump",
    parts = [{clip = &"Jump_Start"}, {clip = &"Jump_Land"}],
    hop = {height = 0.65, apex = 0.65},
},
```

The positional version is not shorter in any way that matters — it is
shorter to *write once* and longer to *read forever*.

## GDScript syntax

GDScript has dictionary literals, with `=` for identifier keys:

```gdscript
{name = "Climb_Idle", duration = 1.5, stretch = true}   # ✅
{"name": "Climb_Idle", "duration": 1.5}                 # ✅ quoted keys
{name: "Climb_Idle"}                                    # ❌ evaluates `name`
```

`const` dictionaries and arrays are allowed, so a menu table can stay a
constant.

## Rules

- **Every configurable thing is a named key.** Do not mix "a bare name means
  the simple case" into a list that also holds dictionaries — write the
  dictionary everywhere, even when it holds one key. The loader may still
  accept the shorthand; the config itself should not use it.
- **Document the schema once, above the table**, listing every optional key
  and its default. That comment is what a reader consults instead of the
  loader.
- **Nested settings get their own dictionary** (`hop = {height, apex}`)
  rather than a tuple, for the same reason as the outer level.
- **New field, new key.** Never append a meaning to an existing slot.

## Common mistakes

- **"It's only two values, a pair is fine."** Pairs grow. This one grew from
  `[clip]` to `[clip, seconds]` to `[clip, seconds, stretch]` within a day.
- **Documenting the fields in a commit message.** The reader has the file,
  not your history.
- **Positional data in a signal or callback payload.** Same rule: a
  dictionary, or a small class.
