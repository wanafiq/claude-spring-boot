#!/bin/bash
input=$(cat)

# ── Extract all fields in one jq call for performance ──────────────
IFS=$'\t' read -r MODEL DIR COST PCT DURATION_MS LINES_ADD LINES_DEL < <(
  echo "$input" | jq -r '[
    .model.display_name // "Claude",
    .workspace.current_dir // ".",
    .cost.total_cost_usd // 0,
    .context_window.used_percentage // 0,
    .cost.total_duration_ms // 0,
    .cost.total_lines_added // 0,
    .cost.total_lines_removed // 0
  ] | map(tostring) | join("\t")'
)
PCT=${PCT%%.*}  # strip decimal

# ── Colors ─────────────────────────────────────────────────────────
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'
RED='\033[31m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'
GIT_ORANGE='\033[38;2;240;80;50m'

# ── Cached git branch (5s TTL) ─────────────────────────────────────
CACHE="/tmp/claude-statusline-git"
get_branch() {
  if [ -f "$CACHE" ] && [ "$(( $(date +%s) - $(stat -f%m "$CACHE" 2>/dev/null || echo 0) ))" -lt 5 ]; then
    cat "$CACHE"
  else
    local b=""
    git rev-parse --git-dir >/dev/null 2>&1 && b=$(git branch --show-current 2>/dev/null)
    echo "$b" > "$CACHE"
    echo "$b"
  fi
}
BRANCH=$(get_branch)

# ── Progress bar ───────────────────────────────────────────────────
# TODO: Your turn! Implement this function.
#
# Takes a percentage (0-100), outputs a colored 20-char bar using ▓ and ░
#
# Color thresholds:
#   GREEN  when pct < 70
#   YELLOW when 70 <= pct < 90
#   RED    when pct >= 90
#
# Example: render_bar 58  →  ▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░ (in green)
#
render_bar() {
  local pct=$1
  local filled=$((pct * 20 / 100))
  local empty=$((20 - filled))
  local color="$GREEN"
  [ "$pct" -ge 70 ] && color="$YELLOW"
  [ "$pct" -ge 90 ] && color="$RED"
  printf -v f "%${filled}s"; printf -v e "%${empty}s"
  echo -ne "${color}${f// /▓}${DIM}${e// /░}${RESET}"
}

# ── Compact duration ───────────────────────────────────────────────
format_duration() {
  local ms=$1
  local mins=$((ms / 60000))
  local secs=$(( (ms % 60000) / 1000 ))
  if [ "$mins" -gt 0 ] && [ "$secs" -gt 0 ]; then
    echo "${mins}m ${secs}s"
  elif [ "$mins" -gt 0 ]; then
    echo "${mins}m"
  else
    echo "${secs}s"
  fi
}

# ── Build segments ─────────────────────────────────────────────────
SEP="${DIM} │ ${RESET}"

# Model
OUT="${BOLD}${CYAN}${MODEL}${RESET}"

# Directory
OUT+="${SEP}📁 ${DIR##*/}"

# Git branch (if available)
GIT_ICON=$(printf '\xee\x82\xa0')
[ -n "$BRANCH" ] && OUT+="${SEP}${GIT_ORANGE}${GIT_ICON} ${BRANCH}${RESET}"

# Context bar
BAR=$(render_bar "$PCT")
OUT+="${SEP}${BAR} ${PCT}%"

# Cost (yellow highlight when > $1)
COST_FMT=$(printf '$%.2f' "$COST")
if (( $(echo "$COST > 1" | bc -l 2>/dev/null || echo 0) )); then
  OUT+="${SEP}${YELLOW}${COST_FMT}${RESET}"
else
  OUT+="${SEP}${COST_FMT}"
fi

# Lines changed (only if non-zero)
if [ "$LINES_ADD" != "0" ] || [ "$LINES_DEL" != "0" ]; then
  OUT+="${SEP}${GREEN}+${LINES_ADD}${RESET}/${RED}-${LINES_DEL}${RESET}"
fi

# Duration
DURATION=$(format_duration "$DURATION_MS")
OUT+="${SEP}⏱ ${DURATION}"

echo -e "$OUT"
