# Article voice contract

This applies to everything published under `article/`. It is scoped
narrower than `.claude/skills/no-ai-slop/SKILL.md` on purpose — that
skill also edits `docs/`, where a personal narrator voice would be
wrong. Articles are Raymon's own first-person account of building The
Factory. Docs are not.

## First person singular, not "we"

There is one author. When the piece refers to what was actually built,
found, tested, or decided, say **I**, never **we**, **our team**, or
any other third-person or plural distancing.

- "I built that infrastructure twice" — not "We built that
  infrastructure twice."
- "I use a hard-mandatory Sentinel policy" — not "We use a
  hard-mandatory Sentinel policy."
- "My first design assumed" — not "Our first design assumed."
- "I found" / "I tested" / "I kept the same cleanup behavior" — not
  "we found" / "we tested" / "we kept."

This is not a ban on every occurrence of the word "we." The published
first article already uses an inclusive, reader-addressing "we" in a
handful of places — *"how do we give agents room to discover and
reason,"* *"can we trust what the model says,"* *"can we reconstruct
the whole decision chain"* — and that device is legitimate: it draws
the reader into a shared question, it does not claim something the
author alone did. The rule targets the other case specifically: **"we"
standing in for "I" when describing the author's own work.** If a
sentence would read the same with "the reader and I" substituted for
"we," it is the inclusive form and can stay. If it would not, because
it is really describing what one person built or found, it is the
authorial form and needs to become "I."

## Before publishing a draft

Check every instance of "we," "our," and "us" against this distinction
before calling a draft final. It has been missed before — an earlier
draft (`the-vault-behind-the-permission_1.md`) used authorial "we"
throughout and needed a pass to fix it after the fact. Catch it before
that pass is needed, not after.

Run `.claude/skills/no-ai-slop/SKILL.md` as the editorial pass on top
of this, same as always. This file is about voice person, not about
AI-slop patterns generally — both apply.
