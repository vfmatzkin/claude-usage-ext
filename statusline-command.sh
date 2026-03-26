#!/usr/bin/env bash
# Claude Code status line

input=$(cat)

# === Context window ===
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')

# Compact model name: "Claude Opus 4.6 (1M context)" → "Opus 4.6 (1M)"
model="${model#Claude }"
model="${model/ context/}"

branch=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

# Context bar (10 chars)
ctx_part=""
if [ -n "$used" ]; then
  ctx_pct=$(printf "%.0f" "$used")
  filled=$(printf "%.0f" "$(echo "$used / 10" | bc -l)")
  empty=$((10 - filled))
  bar=""
  for _ in $(seq 1 "$filled"); do bar="${bar}█"; done
  for _ in $(seq 1 "$empty");  do bar="${bar}░"; done
  ctx_part=$(printf '\033[0;36m[%s] %s%%\033[0m' "$bar" "$ctx_pct")
fi

# === Subscription usage (from Claude Code's native rate_limits) ===
usage_part=""
now=$(date +%s)

# Format minutes: >99 → "Xh", ≤99 → "Xm"
fmt_time() {
  local m="$1"
  [ -z "$m" ] && return
  if [ "$m" -gt 99 ]; then
    echo "$((m / 60))h"
  else
    echo "${m}m"
  fi
}

rl_five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_seven=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_resets_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_resets_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -n "$rl_five" ] || [ -n "$rl_seven" ]; then
  parts=()

  if [ -n "$rl_five" ]; then
    f=$(printf "%.0f" "$rl_five")
    if [ "$f" -ge 80 ]; then color="0;31"
    elif [ "$f" -ge 50 ]; then color="0;33"
    else color="0;32"; fi
    t5=""
    if [ -n "$rl_resets_5h" ] && [ "$rl_resets_5h" -gt "$now" ] 2>/dev/null; then
      t5=$(fmt_time $(( (rl_resets_5h - now) / 60 )))
    fi
    if [ -n "$t5" ]; then
      parts+=("$(printf '\033[%sm%s:%s%%\033[0m' "$color" "$t5" "$f")")
    else
      parts+=("$(printf '\033[%sm%s%%\033[0m' "$color" "$f")")
    fi
  fi

  if [ -n "$rl_seven" ]; then
    s=$(printf "%.0f" "$rl_seven")
    t7=""
    if [ -n "$rl_resets_7d" ] && [ "$rl_resets_7d" -gt "$now" ] 2>/dev/null; then
      t7=$(fmt_time $(( (rl_resets_7d - now) / 60 )))
    fi
    if [ -n "$t7" ]; then
      parts+=("$(printf '\033[0;36m%s:%s%%\033[0m' "$t7" "$s")")
    else
      parts+=("$(printf '\033[0;36m7d:%s%%\033[0m' "$s")")
    fi
  fi

  [ ${#parts[@]} -gt 0 ] && usage_part=$(IFS=" "; echo "${parts[*]}")
fi

# === Assemble ===
sections=()
[ -n "$ctx_part" ]   && sections+=("$ctx_part")
[ -n "$usage_part" ] && sections+=("$usage_part")
[ -n "$model" ]      && sections+=("$(printf '\033[0;35m%s\033[0m' "$model")")
[ -n "$branch" ]     && sections+=("$(printf '\033[0;32m%s\033[0m' "$branch")")

result=""
for s in "${sections[@]}"; do
  [ -z "$result" ] && result="$s" || result="$result  $s"
done

printf "%b\n" "$result"
