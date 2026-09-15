---
name: attune
description: Tunes explanations to how each person likes them. Asks one quick question the first time (how they want things explained), remembers the answer, matches it in every reply, and adjusts live when the user says simpler, shorter, deeper, less narration, or more detail. Use when no saved preference exists yet, when the user wants to change how replies are pitched, or when they say replies are too long or too detailed.
allowed-tools: Read, Write
---

# attune

Make every explanation fit the person reading it. Learn how they like things once, follow it always, and let them change it anytime.

Two hooks carry the preference. At SessionStart you are told either the reader's saved preference or that none is set yet, plus the exact file path to save to. From then on the preference is restated every few prompts, because a single injection at the top of a long session gets buried. Follow whichever case applies.

## Two dials, not one

The saved file holds up to two independent settings. Keep them separate — conflating them is why "be brief" tends to fail.

- **Level — how deep.** How much explanation an answer carries. This is the dial "simpler" and "deeper" move.
- **Shape — how much narration.** Whether replies open with preamble, restate the plan, recap what was just done, or close with unrequested next steps. A reply can sit at the shallowest Level and still be long, purely from narration; Shape is what fixes that.

Set Level always. Set Shape only when the reader says something about length, narration, or wanting the bottom line first — otherwise leave it out.

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
Shape: <narration rules, if they gave any>
```

Keep each setting on one line — they are restated verbatim every few prompts, so every word is paid repeatedly. Omit the `Shape:` line entirely when there is nothing to say.

Confirm in one line, e.g. "Set to Level 2 (Balanced) — say 'simpler' or 'more detail' to move a rung anytime."

## Every reply after that

Read the saved settings and match them — the rung is your depth and length target, the Shape line governs narration, and any notes (e.g. "technical", "no waffle") refine both.

## Changing the settings

- **Relative:** "simpler" / "less detail" → step Level down a rung. "deeper" / "more detail" → step Level up.
- **Absolute:** "give me deep dives" / "just the answer" → jump straight to that rung.
- **Shape:** "stop narrating", "too long", "lead with the answer", "skip the recap" → write or extend the `Shape:` line. Record the rule they actually stated, in their words, not a generic instruction to be brief.
- Either way: adjust your current reply now, rewrite the saved file with the new settings, and acknowledge in one line.
- They can also edit or delete the file directly — deleting it re-triggers this setup.

## On Claude Code specifically

Claude Code ships a built-in **Concise** output style that already governs Shape for every reply, at a level no plugin can reach. If the reader is on Claude Code and wants shorter replies across the board, say so — `"outputStyle": "Concise"` in their settings file is the stronger fix, and Level still handles depth on top of it. Shape in this file remains the portable path, and on harnesses without output styles it is the only one.

## Rules

- Never be condescending. A low Level means brief and plain, not dumbed-down.
- Brevity never withholds. Error output, warnings, and anything the reader must act on keep their full content at every Level.
- The saved file stays on the reader's machine. Never send it anywhere.
- Keep the one-question setup genuinely quick — it is the whole onboarding.
- Settings are a guide, not a straitjacket — a one-line note ("technical", "no waffle") refines any rung.
