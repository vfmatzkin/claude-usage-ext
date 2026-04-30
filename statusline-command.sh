#!/usr/bin/env bash
# Claude Code status line

set -f

usage_dir="${CLAUDE_USAGE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage}"

# budget subcommand: bash statusline-command.sh budget <new_budget>
# Updates the budget= line in .config.
if [ "${1:-}" = "budget" ] && [ -n "${2:-}" ]; then
    [ ! -f "$usage_dir/.config" ] && echo "no config at $usage_dir/.config" && exit 1
    sed -i '' "s/^budget=.*/budget=$2/" "$usage_dir/.config"
    cat "$usage_dir/.config"
    exit 0
fi

# usage subcommand: bash statusline-command.sh usage <initial_usage>
# Directly overwrites initial_usage= in .config (no offset files written).
if [ "${1:-}" = "usage" ] && [ -n "${2:-}" ]; then
    [ ! -f "$usage_dir/.config" ] && echo "no config at $usage_dir/.config" && exit 1
    sed -i '' "s/^initial_usage=.*/initial_usage=$2/" "$usage_dir/.config"
    cat "$usage_dir/.config"
    exit 0
fi

# sync subcommand: bash statusline-command.sh sync <real_usage>
# Writes a negative offset for each session so continuing sessions only
# count the delta. Dead sessions cancel out (cost + -cost = 0).
# start_ts=0 disables timestamp filtering — offsets handle the math.
if [ "${1:-}" = "sync" ] && [ -n "${2:-}" ]; then
    [ ! -f "$usage_dir/.config" ] && echo "no config at $usage_dir/.config" && exit 1
    set +f
    for f in "$usage_dir"/*; do
        [ ! -f "$f" ] && continue
        base=$(basename "$f")
        case "$base" in .* | *_offset) continue ;; esac
        cost=$(awk -F'\t' '{print $2}' "$f")
        [ -n "$cost" ] && printf '%s\t-%s\toffset\t0\t0\t0\n' "$(date +%s)" "$cost" > "${f}_offset"
    done
    set -f
    sed -i '' "s/^initial_usage=.*/initial_usage=$2/; s/^start_ts=.*/start_ts=0/" "$usage_dir/.config"
    cat "$usage_dir/.config"
    exit 0
fi

input=$(cat)
[ -z "$input" ] && printf "Claude" && exit 0

# ===== Colors =====
blue='\033[38;2;97;175;239m'
amber='\033[38;2;229;192;123m'
cyan='\033[38;2;86;182;194m'
green='\033[38;2;80;200;120m'
orange='\033[38;2;255;176;85m'
yellow='\033[38;2;230;200;0m'
red='\033[38;2;235;87;87m'
magenta='\033[38;2;198;120;221m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ===== Helpers =====

fmt_time() {
    local m="$1"
    [ -z "$m" ] && return
    [ "$m" -gt 99 ] && echo "$((m / 60))h" || echo "${m}m"
}

# projected% = used% × duration / elapsed
# ↑ will exhaust before reset | → on pace | ↓ under-consuming
pace_arrow() {
    local used_pct="$1" resets_at="$2" duration="$3" now="$4"
    [ -z "$used_pct" ] || [ -z "$resets_at" ] && return
    local elapsed=$(( now - (resets_at - duration) ))
    [ "$elapsed" -le $(( duration / 50 )) ] && return
    local projected pace_pct
    projected=$(echo "$used_pct * $duration / $elapsed" | bc 2>/dev/null)
    pace_pct=$(echo "$elapsed * 100 / $duration" | bc 2>/dev/null)
    [ -z "$projected" ] && return
    local time_left_m remaining_m time_color time_left_fmt arrow_str pace_str
    time_left_m=$(echo "(100 - $used_pct) * $elapsed / $used_pct / 60" | bc 2>/dev/null)
    remaining_m=$(( (resets_at - now) / 60 ))

    time_color="$green"
    if [ -n "$time_left_m" ] && [ "$remaining_m" -gt 0 ] 2>/dev/null; then
        local ratio_pct=$(( time_left_m * 100 / remaining_m ))
        if   [ "$ratio_pct" -lt 33 ]; then time_color="$red"
        elif [ "$ratio_pct" -lt 66 ]; then time_color="$orange"
        fi
    fi

    time_left_fmt=""
    [ -n "$time_left_m" ] && time_left_fmt=" ${time_color}$(fmt_time "$time_left_m")${reset}"

    if   [ "$projected" -gt 115 ]; then arrow_str="${red}↑${reset}"
    elif [ "$projected" -gt 85  ]; then arrow_str="${yellow}→${reset}"
    else                                 arrow_str="${green}↓${reset}"; time_left_fmt=""
    fi

    pace_str=""
    [ -n "$pace_pct" ] && pace_str=":${dim}${pace_pct}%${reset}"

    printf '%s' "${pace_str}${arrow_str}${time_left_fmt}"
}

add() { [ -z "$out" ] && out+="$1" || out+="${sep}$1"; }

# ===== Extract data =====
model=$(echo "$input" | jq -r '.model.display_name // empty')
cwd=$(echo "$input"   | jq -r '.workspace.current_dir // .cwd // empty')
used=$(echo "$input"  | jq -r '.context_window.used_percentage // empty')

# "Claude Opus 4.6 (1M context)" → "Opus 4.6 (1M)"
model="${model#Claude }"
model="${model/ context/}"

branch=""
[ -n "$cwd" ] && branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)

now=$(date +%s)
rl_five=$(echo "$input"      | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_seven=$(echo "$input"     | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_resets_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_resets_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

cost_usd=$(echo "$input"       | jq -r '.cost.total_cost_usd // empty')
duration_ms=$(echo "$input"    | jq -r '.cost.total_duration_ms // empty')
api_duration_ms=$(echo "$input"| jq -r '.cost.total_api_duration_ms // empty')
lines_added=$(echo "$input"    | jq -r '.cost.total_lines_added // empty')
lines_removed=$(echo "$input"  | jq -r '.cost.total_lines_removed // empty')
session_id=$(echo "$input"     | jq -r '.session_id // empty')
total_input=$(echo "$input"    | jq -r '.context_window.total_input_tokens // empty')
total_output=$(echo "$input"   | jq -r '.context_window.total_output_tokens // empty')
cache_read=$(echo "$input"     | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
cache_create=$(echo "$input"   | jq -r '.context_window.current_usage.cache_creation_input_tokens // empty')

# ===== Usage tracking =====
today=$(date +%Y-%m-%d)
daily_total=""

if [ -n "$session_id" ] && [ -n "$cost_usd" ] && [ -z "$rl_five" ] && [ -z "$rl_seven" ]; then
    mkdir -p "$usage_dir"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$now" "$cost_usd" "${model:-unknown}" \
        "${api_duration_ms:-0}" "${lines_added:-0}" "${lines_removed:-0}" \
        > "$usage_dir/$session_id"
fi

# Load config: budget, initial_usage, start_ts (epoch)
budget="" initial_usage="" start_ts=""
[ -f "$usage_dir/.config" ] && . "$usage_dir/.config" 2>/dev/null
period_total=""
if [ -n "$budget" ] && [ -n "$start_ts" ]; then
    set +f
    tracked=$(awk -v t="$start_ts" -F'\t' '($1+0) >= (t+0) {s += $2} END {printf "%.2f", s}' "$usage_dir"/* 2>/dev/null)
    set -f
    period_total=$(echo "scale=2; ${initial_usage:-0} + ${tracked:-0}" | bc 2>/dev/null)
fi

# ===== Assemble =====
out=""

# Model — amber for Opus, cyan for Haiku, blue otherwise
if [ -n "$model" ]; then
    model_color="$blue"
    case "$model" in *Opus*)  model_color="$amber" ;; *Haiku*) model_color="$cyan" ;; esac
    add "${model_color}${model}${reset}"
fi

# Git branch
[ -n "$branch" ] && add "${dim}⎇${reset} ${magenta}${branch}${reset}"

# Context window %
if [ -n "$used" ]; then
    ctx_pct=$(printf "%.0f" "$used")
    if   [ "$ctx_pct" -ge 80 ]; then ctx_color="$red"
    elif [ "$ctx_pct" -ge 50 ]; then ctx_color="$orange"
    else ctx_color="$cyan"; fi
    add "${dim}ctx${reset} ${ctx_color}${ctx_pct}%${reset}"
fi

# Rate limits — 5h
if [ -n "$rl_five" ]; then
    f=$(printf "%.0f" "$rl_five")
    arrow5=$(pace_arrow "$rl_five" "$rl_resets_5h" 18000 "$now")

    if   [ "$f" -ge 80 ]; then pct_color="$red"
    elif [ "$f" -ge 50 ]; then pct_color="$yellow"
    else pct_color="$cyan"; fi

    t5=""
    [ -n "$rl_resets_5h" ] && [ "$rl_resets_5h" -gt "$now" ] 2>/dev/null && \
        t5=$(fmt_time $(( (rl_resets_5h - now) / 60 )))

    if [ -n "$t5" ]; then
        add "${pct_color}${t5}:${f}%${arrow5}${reset}"
    else
        add "${pct_color}${f}%${arrow5}${reset}"
    fi
fi

# Rate limits — 7d
if [ -n "$rl_seven" ]; then
    s=$(printf "%.0f" "$rl_seven")
    arrow7=$(pace_arrow "$rl_seven" "$rl_resets_7d" 604800 "$now")

    t7=""
    [ -n "$rl_resets_7d" ] && [ "$rl_resets_7d" -gt "$now" ] 2>/dev/null && \
        t7=$(fmt_time $(( (rl_resets_7d - now) / 60 )))

    if [ -n "$t7" ]; then
        add "${cyan}${t7}:${s}%${arrow7}${reset}"
    else
        add "${cyan}7d:${s}%${arrow7}${reset}"
    fi
fi

# Cache hit rate — also shown alongside rate limits
if [ -n "$rl_five" ] || [ -n "$rl_seven" ]; then
    cache_total=$(( ${cache_read:-0} + ${cache_create:-0} ))
    if [ "$cache_total" -gt 0 ] 2>/dev/null; then
        hit_pct=$(( cache_read * 100 / cache_total ))
        if   [ "$hit_pct" -ge 80 ]; then cache_color="$green"
        elif [ "$hit_pct" -ge 50 ]; then cache_color="$cyan"
        else cache_color="$orange"; fi
        add "${dim}cache${reset} ${cache_color}${hit_pct}%${reset}"
    fi
fi

# API cost fallback — shown when no rate_limits (enterprise/API billing)
if [ -z "$rl_five" ] && [ -z "$rl_seven" ] && [ -n "$cost_usd" ]; then
    cost_fmt=$(printf "$%.2f" "$cost_usd")

    # Active burn rate (cost / api hours, not wall hours)
    active_rate=""
    if [ -n "$api_duration_ms" ] && [ "$api_duration_ms" -gt 0 ] 2>/dev/null; then
        active_rate=$(echo "scale=2; $cost_usd / ($api_duration_ms / 3600000)" | bc 2>/dev/null)
    fi

    cost_str="${green}${cost_fmt}${reset}"
    [ -n "$active_rate" ] && cost_str+=" ${dim}${active_rate}/hr${reset}"

    # Cache hit rate — cache_read / (cache_read + cache_create)
    cache_total=$(( ${cache_read:-0} + ${cache_create:-0} ))
    if [ "$cache_total" -gt 0 ] 2>/dev/null; then
        hit_pct=$(( cache_read * 100 / cache_total ))
        if   [ "$hit_pct" -ge 80 ]; then cache_color="$green"
        elif [ "$hit_pct" -ge 50 ]; then cache_color="$cyan"
        else cache_color="$orange"; fi
        add "${cost_str}${sep}${dim}cache${reset} ${cache_color}${hit_pct}%${reset}"
        cost_str=""
    fi

    [ -n "$cost_str" ] && add "$cost_str"

    # Cost per 1k tokens + net lines
    total_tokens=$(( ${total_input:-0} + ${total_output:-0} ))
    if [ "$total_tokens" -gt 0 ] 2>/dev/null; then
        cpk=$(echo "scale=2; $cost_usd * 1000 / $total_tokens" | bc 2>/dev/null)
        tok_str=""
        [ -n "$cpk" ] && tok_str="${dim}\$${cpk}/kt${reset}"
        net_lines=$(( ${lines_added:-0} - ${lines_removed:-0} ))
        if [ "$net_lines" -ge 0 ]; then
            net_str="${green}+${net_lines}${reset}"
        else
            net_str="${red}${net_lines}${reset}"
        fi
        [ -n "$tok_str" ] && add "${tok_str} ${net_str}"
    fi

    # Budget tracking — accumulated across billing period
    if [ -n "$period_total" ] && [ -n "$budget" ] && [ -n "$active_rate" ]; then
        budget_pct=$(echo "scale=0; $period_total * 100 / $budget" | bc 2>/dev/null)
        if [ -n "$budget_pct" ]; then
            if   [ "$budget_pct" -ge 80 ]; then bgt_color="$red"
            elif [ "$budget_pct" -ge 50 ]; then bgt_color="$yellow"
            else bgt_color="$cyan"; fi

            remaining_usd=$(echo "scale=2; $budget - $period_total" | bc 2>/dev/null)
            time_left_m=""
            if [ -n "$remaining_usd" ]; then
                cmp=$(echo "$active_rate > 0" | bc 2>/dev/null)
                [ "$cmp" = "1" ] && \
                    time_left_m=$(echo "scale=0; $remaining_usd * 60 / $active_rate" | bc 2>/dev/null)
            fi

            time_left_fmt=""
            if [ -n "$time_left_m" ] && [ "$time_left_m" -ge 0 ] 2>/dev/null; then
                tlf=$(fmt_time "$time_left_m")
                time_left_fmt=" ${dim}${tlf}${reset}"
            fi

            period_fmt=$(printf "$%.2f" "$period_total")
            add "${bgt_color}${period_fmt}/${budget}${time_left_fmt}${reset}"
        fi
    fi
fi

printf "%b\n" "$out"
