# Commercial licensing

This project is **dual-licensed**. Not "AGPL with an exception" — the AGPL is
not modified, and nothing is added to it. There are two separate grants, and
you pick one:

```
                ┌── GNU AGPL v3.0 only          (LICENSE, free to everyone)
Project ────────┤
                └── separate commercial terms   (by agreement, this page)
```

If the AGPL's conditions do not work for you, contact dragon-fish
(<xiaoyujundesu@outlook.com>). This page is a description and a contact
address; the commercial licence itself is a separate agreement signed at the
time.

## Which one do you need?

The AGPL is enough for you if you want to:

- play the game, or build it for yourself
- read, study, fork and learn from the code
- modify it and share your version, **under the AGPL**
- **sell** your AGPL version — the AGPL permits commercial use; what it asks is
  that the Corresponding Source travels with it

You need the commercial licence if you cannot meet the AGPL's conditions —
most often because you want to ship a closed-source product built on this
code, or to combine it into a work under a licence incompatible with the AGPL.

**The AGPL asks for source, not for money.** Commercial use is not what makes
the second licence necessary; needing to avoid the AGPL's copyleft obligations
is.

## What the AGPL actually requires

Two triggers, and the second is the one people miss:

1. **Distribution.** If you distribute a modified or combined work covered by
   the AGPL, you must make its **Corresponding Source** available under the
   AGPL.

2. **Network use — section 13.** If you modify the program and let users
   interact with your modified version **remotely over a network**, section 13
   may require you to offer those users the Corresponding Source, *even if you
   never distribute a copy to anyone*. This is the clause that distinguishes
   the AGPL from the plain GPL. It is unlikely to matter for a single-player
   game, and would matter for a hosted or streamed one.

Note what this does **not** say. The AGPL reaches the covered work — the
program and things combined with it into one work. Merely shipping an
independent program alongside it does not put that program under the AGPL;
the licence calls such a combination an *aggregate* and treats it differently.
Where the line falls in a given case is a real question, and it is the sort of
question worth asking a lawyer rather than a README.

## Why dual licensing is possible here

Because the copyright holder has the rights needed to license the work under
both sets of terms. Nothing in the AGPL constrains the person who granted it —
a copyright holder may license their own work as many different ways as they
like.

That stays true for outside contributions only because contributors grant the
rights needed to sublicense their work under alternative terms. Contributors
keep their own copyright; what they grant is a licence broad enough to carry
their lines into a commercial grant. See `CONTRIBUTING.md`.

This is the same arrangement Qt, MySQL and Grafana ship under.

## What this does not cover

The dual licence applies to **this repository's own code, scenes and
documentation**. It does not extend to third-party components, or to the assets
the game loads at runtime, which keep their own terms — see `NOTICE.md`. In
particular, no character model is tracked here, and the paid animation packs
are not redistributed; see `assets/animations/FULL-LIBRARY.md`.

**A commercial licence to this code is not a licence to anything in
`NOTICE.md`.** Those you clear yourself.
