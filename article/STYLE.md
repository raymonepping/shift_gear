# Article voice contract

This applies to everything published under `article/`. It is scoped
narrower than `.agents/skills/no-ai-slop/SKILL.md` on purpose — that
skill also edits `docs/`, where a personal narrator voice would be
wrong. Articles are Raymon's own first-person accounts of the projects
and subjects he writes about. Docs are not.

## Title and subtitle: always use H1 and H2

Start every article with this structure:

```markdown
# Title

## Subtitle

> Pull quote
```

Always make both the title and subtitle as SEO-friendly as possible
while preserving natural language, accuracy and Raymon's voice.

- Use one H1 title that names the subject and gives a concrete reason
  to read. Include the main search phrase naturally.
- Put the subtitle immediately below it as an H2, not an italic
  paragraph. Expand the title with relevant search terms, the product
  name or the reader's use case rather than repeating it.
- Write for people looking for this subject. Avoid keyword stuffing,
  vague hooks and promises the article cannot support. Do not claim
  search rankings or invent search-volume evidence.
- Place the pull quote directly below the subtitle, before the body.
- Use descriptive H2 section headings that help readers find the
  functionality or question they came for. Keep tables out of articles;
  use prose or bulleted lists where they fit.

For product articles, lead with why Raymon wanted the product and what
he can do with it. Include the development process or tools only when
they serve the requested angle.

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

Run `.agents/skills/no-ai-slop/SKILL.md` as the editorial pass on top
of this, same as always. This file is about voice person, not about
AI-slop patterns generally — both apply.
