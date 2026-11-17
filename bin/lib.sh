# shellcheck shell=bash
# Shared helpers for board-run, board-report and usage-pct. Source, don't execute.

BOARD_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOARD_CONFIG="${BOARD_CONFIG:-$HOME/.config/claude-kanban/config.env}"
# shellcheck source=../config.example.env
[[ -f "$BOARD_CONFIG" ]] && source "$BOARD_CONFIG"

# Defaults (override in config.env)
: "${BOARD_HOME:=$HOME/board}"
: "${VAULT_DIR:=$BOARD_HOME/vault}"
: "${CODE_DIR:=$HOME/code}"
: "${SYNC:=rsync}"
: "${SERV_SSH:=boardsync@serv}"
: "${SERV_KEY:=$HOME/.ssh/board-sync}"
: "${CLAUDE_BIN:=claude}"
: "${YQ:=yq}"
: "${BOARD_MODEL:=sonnet}"
: "${TASK_TIMEOUT:=45m}"
: "${MAX_TURNS:=80}"
: "${SANDBOX:=systemd}"
: "${CAP_WEEKLY:=60}"
: "${USAGE_UNKNOWN:=allow}"
: "${ACTIVITY_FILE:=/run/claude-activity/last}"
: "${USAGE_CACHE:=$HOME/.cache/claude-kanban/usage.json}"
: "${USAGE_CACHE_MAX_AGE:=21600}"

TASKS_DIR="$VAULT_DIR/tasks"
OUTPUT_DIR="$VAULT_DIR/output"
REPORTS_DIR="$VAULT_DIR/reports"
STATE_DIR="$BOARD_HOME/state"
RUNS_DIR="$BOARD_HOME/runs"
WORKTREES_DIR="$BOARD_HOME/worktrees"
EVENTS_FILE="$STATE_DIR/events.jsonl"

# Paths an unattended run must never see, on top of the per-type ones.
SECRET_PATHS=("$HOME/.ssh" "$HOME/.config/gh" "$HOME/.git-credentials" "$HOME/.gnupg")

log() { printf '%s %s\n' "$(date -Is)" "$*" >&2; }

ensure_dirs() {
  mkdir -p "$TASKS_DIR" "$OUTPUT_DIR" "$REPORTS_DIR" "$STATE_DIR" "$RUNS_DIR" "$WORKTREES_DIR"
}

# --- frontmatter -------------------------------------------------------------

# fm_get FILE KEY -> value, or empty
fm_get() {
  local v
  v=$("$YQ" --front-matter=extract ".$2 // \"\"" "$1" 2>/dev/null) || v=""
  [[ "$v" == "null" ]] && v=""
  printf '%s' "$v"
}

# fm_set FILE KEY VALUE (string)
fm_set() {
  V="$3" "$YQ" --front-matter=process -i ".$2 = strenv(V)" "$1"
}

# fm_del FILE KEY
fm_del() {
  "$YQ" --front-matter=process -i "del(.$2)" "$1"
}

# card_body FILE -> markdown without frontmatter
card_body() {
  awk 'NR==1 && $0!="---" {fm=2} fm>=2 {print; next} $0=="---" {fm++; next}' "$1"
}

# --- keep the PC awake while we work -----------------------------------------

keep_awake_start() {
  ( trap 'kill "$s" 2>/dev/null; exit 0' TERM
    while true; do touch "$ACTIVITY_FILE" 2>/dev/null || true; sleep 60 & s=$!; wait "$s"; done
  ) </dev/null >/dev/null 2>&1 &
  KEEP_AWAKE_PID=$!
}

keep_awake_stop() {
  [[ -n "${KEEP_AWAKE_PID:-}" ]] && kill "$KEEP_AWAKE_PID" 2>/dev/null || true
  touch "$ACTIVITY_FILE" 2>/dev/null || true   # restart the idle clock once more
}

# --- sync with serv ----------------------------------------------------------

_rsync() {
  rsync -a --update --exclude='.claude-run/' --exclude='.trash/' \
    -e "ssh -i $SERV_KEY -o BatchMode=yes -o ConnectTimeout=10" "$@"
}

sync_pull() {
  [[ "$SYNC" == rsync ]] || return 0
  _rsync --delete "$SERV_SSH:./" "$VAULT_DIR/"
}

sync_push() {
  [[ "$SYNC" == rsync ]] || return 0
  _rsync "$VAULT_DIR/" "$SERV_SSH:./"
}

# --- usage cap ---------------------------------------------------------------

# usage_ok -> 0 when below the weekly cap (or unknown and USAGE_UNKNOWN=allow)
usage_ok() {
  local pct
  pct=$("$BOARD_REPO/bin/usage-pct" 2>/dev/null || true)
  if [[ -z "$pct" ]]; then
    [[ "$USAGE_UNKNOWN" == allow ]]
    return
  fi
  (( pct < CAP_WEEKLY ))
}

# --- events (input for the morning report) -----------------------------------

event() {  # event KEY=VALUE ...
  local args=() kv
  for kv in "$@"; do args+=(--arg "${kv%%=*}" "${kv#*=}"); done
  jq -cn --arg ts "$(date -u +%FT%TZ)" "${args[@]}" '$ARGS.named' >> "$EVENTS_FILE"
}

# --- running claude ----------------------------------------------------------

# run_claude KIND CWD PROMPT_FILE OUT_JSON [PATH_TO_HIDE...]
# Runs one headless Claude Code invocation with the settings in run-settings/KIND.json.
# User settings (Remote Control permissions and hooks) are not loaded.
run_claude() {
  local kind=$1 cwd=$2 prompt=$3 out=$4; shift 4
  local -a hide=("${SECRET_PATHS[@]}" "$@")
  local -a cmd=("$CLAUDE_BIN" -p
    --model "$BOARD_MODEL"
    --max-turns "$MAX_TURNS"
    --setting-sources project
    --settings "$BOARD_REPO/run-settings/$kind.json"
    --permission-mode dontAsk
    --output-format json)

  if [[ "$SANDBOX" == systemd ]]; then
    local -a props=(-p NoNewPrivileges=yes -p "RuntimeMaxSec=$TASK_TIMEOUT"
      -p "WorkingDirectory=$cwd" -p "Environment=PATH=$PATH")
    local p
    for p in "${hide[@]}"; do props+=(-p "InaccessiblePaths=-$p"); done
    systemd-run --user --wait --pipe --quiet --collect "${props[@]}" \
      "${cmd[@]}" < "$prompt" > "$out"
  else
    ( cd "$cwd" && timeout "$TASK_TIMEOUT" "${cmd[@]}" < "$prompt" > "$out" )
  fi
}

# render_prompt TEMPLATE KEY=VALUE ...  -> stdout, with {{KEY}} replaced
render_prompt() {
  local tpl=$1; shift
  local text kv
  text=$(<"$tpl")
  for kv in "$@"; do text=${text//"{{${kv%%=*}}}"/"${kv#*=}"}; done
  printf '%s\n' "$text"
}
