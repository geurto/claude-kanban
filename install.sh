#!/usr/bin/env bash
# Run as the claude user on the PC, from the clone at ~/claude-kanban. Safe to re-run.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
[[ "$repo" == "$HOME/claude-kanban" ]] || echo "warning: settings.json expects the repo at ~/claude-kanban (found $repo)" >&2

link() {  # link SOURCE TARGET – back up an existing regular file once
  mkdir -p "$(dirname "$2")"
  if [[ -e "$2" && ! -L "$2" ]]; then mv "$2" "$2.bak.$(date +%s)"; fi
  ln -sfn "$1" "$2"
  echo "linked $2"
}

chmod +x "$repo"/bin/board-run "$repo"/bin/board-report "$repo"/bin/usage-pct \
         "$repo"/claude-home/statusline.sh "$repo"/claude-home/hooks/*.sh

link "$repo/claude-home/settings.json" "$HOME/.claude/settings.json"
link "$repo/code-root/CLAUDE.md"       "$HOME/code/CLAUDE.md"
link "$repo/systemd/claude-kanban@.service" "$HOME/.config/systemd/user/claude-kanban@.service"

if [[ ! -f "$HOME/.config/claude-kanban/config.env" ]]; then
  mkdir -p "$HOME/.config/claude-kanban"
  cp "$repo/config.example.env" "$HOME/.config/claude-kanban/config.env"
  echo "created ~/.config/claude-kanban/config.env – review it"
fi

# shellcheck source=bin/lib.sh
source "$repo/bin/lib.sh"
ensure_dirs
systemctl --user daemon-reload
echo "done. Next: test with  board-run now  (see README, 'First run')."
