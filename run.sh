#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env first so overrides take effect
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
fi

NEMOFLOW_DIR="${NEMOFLOW_DIR:-$SCRIPT_DIR/NeMo-Flow}"
PHOENIX_VENV="${PHOENIX_VENV:-$SCRIPT_DIR/.venv}"
OPENCLAW_BIN="${OPENCLAW_BIN:-$HOME/.local/bin/openclaw}"
BENCH_SCRIPTS="$NEMOFLOW_DIR/third_party/skill/scripts"

# Ensure openclaw is on PATH even if shell rc hasn't been sourced yet
OPENCLAW_BIN_DIR="$(dirname "$OPENCLAW_BIN")"
[[ ":$PATH:" == *":$OPENCLAW_BIN_DIR:"* ]] || export PATH="$OPENCLAW_BIN_DIR:$PATH"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Verify setup has been run
[[ -f "$BENCH_SCRIPTS/benchmark.py" ]] || die "NeMo-Flow not found at $NEMOFLOW_DIR. Run ./setup.sh first."
[[ -f "$HOME/.openclaw/openclaw.json" ]] || die "OpenClaw not configured. Run ./setup.sh first."
command -v openclaw >/dev/null || die "openclaw not found on PATH. Run ./setup.sh first."

MODEL="${MODEL:-nvidia-inference/aws/anthropic/claude-opus-4-5}"
JUDGE="${JUDGE:-nvidia-inference/azure/anthropic/claude-sonnet-4-6}"
RUNS="${RUNS:-3}"
SUITE="${SUITE:-}"
CONCURRENCY="${CONCURRENCY:-1}"
PROJECT_NAME="${PROJECT_NAME:-PinchBench}"

# Update Phoenix project name if provided
if [[ "$PROJECT_NAME" != "PinchBench" ]]; then
    PHOENIX_PROJECT="$PROJECT_NAME" python3 -c "
import json, os
cfg_path = os.path.expanduser('~/.openclaw/openclaw.json')
with open(cfg_path) as f:
    cfg = json.load(f)
cfg['plugins']['entries']['nemo-flow']['config']['telemetry']['openInference']['resourceAttributes']['openinference.project.name'] = os.environ['PHOENIX_PROJECT']
with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=2)
"
    log "Phoenix project: $PROJECT_NAME"
fi

# Start Phoenix if not running
if ! pgrep -f "phoenix serve" >/dev/null 2>&1; then
    log "Starting Phoenix..."
    tmux new-session -d -s phoenix "$PHOENIX_VENV/bin/phoenix serve" 2>/dev/null \
        || log "Phoenix tmux session already exists"
    sleep 3
    log "Phoenix running at http://localhost:6006"
else
    log "Phoenix already running"
fi

# Copy SOUL.md and TOOLS.md into the fresh workspace (benchmark recreates it each run)
log "Ensuring bootstrap files are current..."
cp "$SCRIPT_DIR/config/SOUL.md" "$HOME/.openclaw/workspace/SOUL.md"
cp "$SCRIPT_DIR/config/TOOLS.md" "$HOME/.openclaw/workspace/TOOLS.md"

# Build benchmark command
log "Starting benchmark: model=$MODEL judge=$JUDGE runs=$RUNS"
cd "$BENCH_SCRIPTS"
BENCH_ARGS=(
    --model "$MODEL"
    --judge "$JUDGE"
    --runs "$RUNS"
    --no-upload
    --verbose
)
[[ -n "$SUITE" ]] && BENCH_ARGS+=(--suite "$SUITE")
[[ "$CONCURRENCY" -gt 1 ]] && BENCH_ARGS+=(--concurrency "$CONCURRENCY")
exec python3 benchmark.py "${BENCH_ARGS[@]}"
