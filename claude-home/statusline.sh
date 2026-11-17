#!/usr/bin/env bash
# Status line for the claude user. Shows usage and caches rate_limits for usage-pct.
input=$(cat)
cache="${USAGE_CACHE:-$HOME/.cache/claude-kanban/usage.json}"

limits=$(jq -c '.rate_limits // empty' <<<"$input" 2>/dev/null)
if [[ -n "$limits" && "$limits" != "{}" ]]; then
  mkdir -p "$(dirname "$cache")"
  printf '%s\n' "$limits" > "$cache.tmp" && mv "$cache.tmp" "$cache"
fi

model=$(jq -r '.model.display_name // "?"' <<<"$input")
week=$(jq -r '.rate_limits.seven_day.used_percentage // empty | floor' <<<"$input" 2>/dev/null)
five=$(jq -r '.rate_limits.five_hour.used_percentage // empty | floor' <<<"$input" 2>/dev/null)
printf '%s · 7d %s%% · 5h %s%%\n' "$model" "${week:-?}" "${five:-?}"
