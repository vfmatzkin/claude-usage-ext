# claude-statusline

A bash script that formats Claude Code's [statusline JSON](https://code.claude.com/docs/en/statusline#full-json-schema) into something readable.

```
[████████░░] 76%  2h:75%  45h:55%  Opus 4.6 (1M)  main
```

Context window, 5h usage (color-coded, with time until reset), 7d usage, model, git branch.

## Background

Claude Code pipes a JSON object to a shell command via stdin on every render (the [`statusLine` config](https://code.claude.com/docs/en/statusline)). On Pro/Max plans this JSON includes a `rate_limits` field with 5-hour and 7-day usage percentages and reset times. The data comes from Anthropic's API response headers.

This script just parses that JSON with `jq` and formats it. There are other tools that display rate limits too (like [ccstatusline](https://github.com/sirmalloc/ccstatusline)). This one is a single bash file, no dependencies beyond `jq`, nothing fancy.

## Install

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

## Requirements

- Claude Code CLI
- `jq` (`brew install jq`)
- Claude Pro or Max subscription (rate limits are not available on free/API plans)

## What it shows

- **Context bar** (10 chars, cyan) with percentage
- **5h limit** with time until reset. Green under 50%, yellow 50-80%, red above 80%
- **7d limit** (cyan) with time until reset
- **Model** (compact, strips "Claude" and "context")
- **Git branch**

All fields are optional. If rate limits aren't available yet (first render before any API call), those sections are just skipped.
