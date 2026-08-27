# Contributing

Bug reports, questions and pull requests are all welcome.

## The inbound licence grant

This project is dual-licensed: the GNU AGPL version 3 only (`AGPL-3.0-only`)
for everyone, and separate commercial terms available from the copyright
holder (see `COMMERCIAL-LICENSING.md`).

That second grant is only possible if the copyright holder holds rights broad
enough to license **every** part of the project under both sets of terms. Your
contribution is part of the project, so that has to include your contribution.

So, by opening a pull request against this repository, you agree that:

1. **You grant dragon-fish a licence broad enough to relicense your work.**
   Specifically: a perpetual, worldwide, non-exclusive, royalty-free,
   irrevocable licence to use, reproduce, modify, prepare derivative works of,
   publicly display, publicly perform, make available, distribute and
   **sublicense** your contribution — on its own and **as part of the project
   as a whole** — **under any licence terms, including proprietary ones**.

2. **You grant a patent licence on the same footing.** A perpetual, worldwide,
   non-exclusive, royalty-free, irrevocable licence, under any patent claims
   you own or control that your contribution necessarily infringes, to make,
   use, sell, offer to sell, import and otherwise transfer the project. A
   copyright licence alone does not carry patent rights, and a commercial
   licence that omitted them would be worth less than it looks.

3. **You keep your copyright.** This is a licence, not an assignment. You may
   go on using your own work however you like, including in other projects
   under other licences.

4. **Your attribution stays.** See the section below.

5. **The contribution is yours to give.** You wrote it, or you otherwise have
   the right to contribute it under these terms — including, if you are
   contributing in the course of employment or under contract, that you have
   your employer's or client's authorisation to do so. It carries no licence
   that conflicts with the above: no code copied from GPL, CC BY-NC-SA, or
   anything else whose terms this project cannot honour.

Points 1 and 2 are the ones people skim, and they are the whole mechanism.
**Sublicensing under any terms** is what lets a commercial licence cover your
lines; a grant that only said "the author may use this" would not.

⚠️ Note what point 3 means for the explanation you may have read elsewhere:
after the first outside contribution the copyright in this project is **not**
held by one person, and the dual licence does not depend on it being. It
depends on the grant above. Any wording suggesting otherwise is wrong and
should be reported as a bug in this file.

If you would rather not grant that, say so in the pull request. It is a
reasonable position, and far better said out loud than discovered later — the
likely outcome is that the change gets reimplemented rather than merged, which
is nobody's favourite outcome but beats a licence problem nobody noticed.

## Attribution

Contributor attribution is preserved in the commit history and in
`AUTHORS.md`. Nothing in the grant above asks you to give up your name, and it
is not the project's intent to remove it: attribution will not be intentionally
removed from `AUTHORS.md` without the contributor's consent, except where
required by law or by the contributor's own request.

That is a statement of intent about how the project is run, subject to ordinary
repository maintenance — histories get rewritten, repositories get migrated,
commits get squashed. It is not a warranty that a particular string will
survive in a particular file forever.

## Practical notes

- **Comments in English**, and about the *why* a number is what it is — most of
  those reasons came from measuring the original game, so if you change a value,
  change the reasoning above it.
- **A comment exists so a mistake is not repeated, not so the project's history
  can be read.** Write the external constraint the code cannot state, the
  pothole somebody already fell into *and what it cost*, and the outright
  prohibition. Phrase it as "this is how it is, do not change it to X" — never
  as "it used to be X, then we changed it".
- **Do not write** quoted conversations, dates, requirement-change records, or
  before/after comparisons.
- **When you change the logic, rewrite the comment rather than appending to
  it.** A new constraint replaces the old one; delete the old one. A stale
  comment is worse than no comment, because it is believed. When you are done,
  the comment should read as though it were written in one sitting.
- **Conventional Commits** for commit messages, in English.
- Movement values are calibrated against measurements of Mirror's Edge (2008),
  recorded in `docs/feel-backlog.md`. A change that makes something *feel*
  better but contradicts a measurement should say so explicitly rather than
  quietly overwrite it.
- No character models or paid animation packs in the repository — see
  `NOTICE.md` and `assets/animations/FULL-LIBRARY.md` for the runtime
  attachment points that exist instead.
