#!/usr/bin/env bash
# UserPromptSubmit hook: refuse new prompts once weekly usage reaches CAP_WEEKLY.
# Exit code 2 blocks the prompt and shows stderr to the user (on the phone too).
board_bin="$(cd "$(dirname "$(readlink -f "$0")")/../../bin" && pwd)"
# shellcheck source=../../bin/lib.sh
source "$board_bin/lib.sh"

pct=$("$board_bin/usage-pct" --stdin 2>/dev/null)

if [[ -z "$pct" ]]; then
  [[ "$USAGE_UNKNOWN" == deny ]] && { echo "Weekly usage is unknown and USAGE_UNKNOWN=deny; prompt refused." >&2; exit 2; }
  exit 0
fi

if (( pct >= CAP_WEEKLY )); then
  echo "Weekly usage is at ${pct}%, the cap for this machine is ${CAP_WEEKLY}%. Prompt refused until the weekly reset (or raise CAP_WEEKLY in ~/.config/claude-kanban/config.env)." >&2
  exit 2
fi
exit 0
