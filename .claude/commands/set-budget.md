---
name: set-budget
description: Use when the user wants to update their Claude usage budget or reset the initial usage / billing period
allowed-tools: Read, Bash, Edit
---

Manage the Claude usage budget tracked at `~/.claude-work/usage/.config`.

## Config file

Path: `~/.claude-work/usage/.config`

Fields:
- `budget` — monthly spending limit in USD
- `initial_usage` — baseline spend already accumulated before the tracking window, in USD
- `start_ts` — epoch timestamp; only session files written **after** this timestamp are counted. `0` = count all sessions ever (usually wrong).

How `period_total` is computed:
```
period_total = initial_usage + sum(session files where timestamp >= start_ts)
```

## Commands

### Update budget limit

```bash
bash ~/.claude/statusline-command.sh budget <new_budget>
```

### Set a new tracking baseline ("current billing total is X")

This is the most common case. Sets `initial_usage` and moves `start_ts` to now so existing session files are excluded from the sum (they're already included in the billing total you're reporting).

```bash
bash ~/.claude/statusline-command.sh usage <current_total>
# Then set start_ts to now:
sed -i '' "s/^start_ts=.*/start_ts=$(date +%s)/" ~/.claude-work/usage/.config
cat ~/.claude-work/usage/.config
```

### Reset for new billing period (offset approach — alternative)

Writes negative offsets for existing sessions (cancels them out) and updates `initial_usage`. Use this if you prefer offsets over timestamp filtering.

```bash
bash ~/.claude/statusline-command.sh sync <new_initial_usage>
```

## Steps

1. Read current config: `cat ~/.claude-work/usage/.config`
2. Run the appropriate command(s) based on what the user asked
3. Verify: `period_total` should equal `initial_usage` right after setting the baseline (no sessions have run yet since start_ts was just set to now)

## Common mistake

Setting `initial_usage` without updating `start_ts` causes double-counting: the billing total you entered PLUS all existing session files get summed. Always update both together when reporting a current billing total.
