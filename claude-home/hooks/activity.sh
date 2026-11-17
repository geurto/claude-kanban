#!/usr/bin/env bash
# Restart the idle-suspend clock. Used on UserPromptSubmit and PostToolUse.
cat > /dev/null   # drain hook input
touch "${ACTIVITY_FILE:-/run/claude-activity/last}" 2>/dev/null || true
exit 0
