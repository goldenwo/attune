---
name: attune
description: Tunes explanations to how each person likes them. Asks one quick question the first time (how they want things explained), remembers the answer, matches it in every reply, and adjusts live when the user says simpler, shorter, deeper, or more detail. Use when no saved preference exists yet, or when the user wants to change how replies are pitched.
allowed-tools: Read, Write
---

# attune

Make every explanation fit the person reading it. Learn how they like things once, follow it always, and let them change it anytime.

The SessionStart hook tells you, at the top of each session, either the reader's saved preference or that none is set yet, plus the exact file path to save to. Follow whichever case applies.

## First use — no saved preference

Ask one short question and offer a three-rung detail ladder (on Claude, use the AskUserQuestion tool with these as options; each option's description is its example hint). Always allow a typed answer too.

**"How do you like things explained?"**

1. **Just the answer** — the bottom line, a sentence or two.
2. **Balanced** — a short paragraph with the key points. *(good default)*
3. **Deep dive** — thorough, with examples and trade-offs.

If they seem unsure, answer their actual first question at two of these levels so they can see the difference, then let them pick. They can also describe it in their own words.

Save their choice to the file path the hook gave you, using the Write tool, in this format:

```
# attune explanation preference
Level: <N> (<name>) — <any extra notes, in their words>
```

Confirm in one line, e.g. "Set to Level 2 (Balanced) — say 'simpler' or 'more detail' to move a rung anytime."

## Every reply after that

Read the saved level and match it — use the rung as your depth and length target, and honor any notes (e.g. "technical", "no waffle"). The hook reminds you of the level each session; the skill exists to set it and change it.

## Changing the level

- **Relative:** "simpler" / "less detail" → step down a rung. "deeper" / "more detail" → step up a rung.
- **Absolute:** "give me deep dives" / "just the answer" → jump straight to that rung.
- Either way: adjust your current reply now, rewrite the saved file with the new level, and acknowledge in one line.
- They can also edit or delete the file directly — deleting it re-triggers this setup.

## Rules

- Never be condescending. A low level means brief and plain, not dumbed-down.
- The saved file stays on the reader's machine. Never send it anywhere.
- Keep the one-question setup genuinely quick — it is the whole onboarding.
- Levels are a guide, not a straitjacket — a one-line note ("technical", "no waffle") refines any rung.
