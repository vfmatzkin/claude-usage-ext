#!/usr/bin/env bash
# Claude Code status line

set -f

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
    local projected
    projected=$(echo "$used_pct * $duration / $elapsed" | bc 2>/dev/null)
    [ -z "$projected" ] && return
    local time_left_m remaining_m time_color time_left_fmt arrow_str
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

    printf "${arrow_str}${time_left_fmt}"
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

printf "%b\n" "$out"
