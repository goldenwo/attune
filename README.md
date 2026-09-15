# attune

**Explanations tuned to you.**

attune asks you one quick question the first time you use it — how you like things explained — then matches every explanation to your answer. Too much? Say **"simpler."** Too shallow? Say **"deeper."** Too much narration? Say **"lead with the answer."** It remembers, so you set it once.

## Install

```
/plugin marketplace add goldenwo/attune
/plugin install attune@attune
```

Restart your session after installing.

## How it works

- A one-time setup asks one short question — pick a level (each shows a quick example) or answer in your own words.
- Your answer is saved locally at `~/.claude/attune/level.md` — nothing is sent anywhere.
- Every reply is pitched the way you asked, and the preference is restated every few prompts so it still holds late in a long session.
- Say **"simpler"**, **"more detail"**, or **"stop narrating"** anytime to adjust; the change sticks.

### Two dials

`level.md` holds up to two settings, because "be brief" usually means two different things:

- **Level** — how deep the explanation goes. Moved by "simpler" / "deeper".
- **Shape** — how much narration surrounds it (preamble, plan restatements, recaps, unrequested next steps). A reply can be shallow and still long; Shape is what fixes that. Only written once you ask for it.

## Settings

Optional, at `~/.claude/attune/config.json`:

```json
{ "every": 5, "disable": false }
```

- `every` — restate the preference once every N prompts (default 5; 0 or less turns restating off).
- `disable` — turn restating off entirely.

Environment variables `ATTUNE_EVERY` and `ATTUNE_DISABLE=1` override the file for a single session.

## Portability

attune runs on **Claude Code** and **Codex CLI** from the same files — the hooks are registered for both, and the preference file is shared, so the two see the same settings.

On Claude Code, the built-in **Concise** output style governs narration for every reply at a level no plugin can reach. If you want shorter replies across the board there, set `"outputStyle": "Concise"` in your settings file and let attune's Level handle depth on top of it. attune's Shape dial is the portable equivalent, and on harnesses without output styles it is the only one.

## Privacy

Your preference lives only on your machine, in a plain text file you can read, edit, or delete at any time.

## License

MIT
