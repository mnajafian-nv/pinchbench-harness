#!/usr/bin/env bash
set -euo pipefail

# A/B/C model comparison for PinchBench
#
# Usage:
#   ./abc_run.sh smoke   — 1-task test of all 3 models in "test-pinchbench" Phoenix project
#   ./abc_run.sh full    — full 53-task benchmark, separate Phoenix project per model
#
# Each model gets:   own Phoenix project  ·  own ATIF traces  ·  own results JSON
# Judge is Claude Sonnet for all three.  Runs = 1.

MODE="${1:-smoke}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
fi

log() { printf '==> [%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ── Model definitions ──────────────────────────────────────────────────────
MODEL_A="nvidia-inference/aws/anthropic/claude-opus-4-5"
MODEL_B="nvidia-inference/nvidia/nvidia/nemotron-3-super-v3"
MODEL_C="nvidia-inference/nvidia/openai/gpt-oss-120b"

LABEL_A="ClaudeOpus"
LABEL_B="NemotronSuper"
LABEL_C="GptOss"

JUDGE="nvidia-inference/azure/anthropic/claude-sonnet-4-6"
CONCURRENCY="${CONCURRENCY:-3}"

# ── Register new models in openclaw.json ───────────────────────────────────
register_models() {
    python3 << 'PYEOF'
import json, os, sys

cfg_path = os.path.expanduser("~/.openclaw/openclaw.json")
if not os.path.exists(cfg_path):
    print("ERROR: openclaw.json not found — run setup.sh first", file=sys.stderr)
    sys.exit(1)

with open(cfg_path) as f:
    cfg = json.load(f)

models = cfg["models"]["providers"]["nvidia-inference"]["models"]
existing_ids = {m["id"] for m in models}

new_models = [
    {
        "id": "azure/anthropic/claude-sonnet-4-6",
        "name": "Claude Sonnet 4.6 (NVIDIA Inference, Judge)",
        "reasoning": False,
        "input": ["text"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": 200000,
        "maxTokens": 8192
    },
    {
        "id": "nvidia/nvidia/nemotron-3-super-v3",
        "name": "Nemotron 3 Super (NVIDIA Inference)",
        "reasoning": True,
        "input": ["text"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": 131072,
        "maxTokens": 8192
    },
    {
        "id": "nvidia/openai/gpt-oss-120b",
        "name": "GPT-OSS 120B (NVIDIA Inference)",
        "reasoning": False,
        "input": ["text"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": 128000,
        "maxTokens": 8192
    }
]

added = 0
for m in new_models:
    if m["id"] not in existing_ids:
        models.append(m)
        added += 1

with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2)

print(f"Models registered: {len(models)} total ({added} new)")
PYEOF
}

# ── Run one model through the benchmark ────────────────────────────────────
run_model() {
    local label="$1"
    local model="$2"
    local project="$3"
    local suite_arg="${4:-}"

    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "  Model:   $label"
    log "  ID:      $model"
    log "  Judge:   $JUDGE"
    log "  Project: $project"
    log "  Concurrency: $CONCURRENCY"
    [[ -n "$suite_arg" ]] && log "  Suite:   $suite_arg"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local start_ts
    start_ts=$(date +%s)

    MODEL="$model" \
    JUDGE="$JUDGE" \
    RUNS="${RUNS:-3}" \
    CONCURRENCY="$CONCURRENCY" \
    PROJECT_NAME="$project" \
    SUITE="$suite_arg" \
        bash "$SCRIPT_DIR/run.sh" || {
            log "WARNING: $label exited with non-zero status"
        }

    local end_ts elapsed
    end_ts=$(date +%s)
    elapsed=$(( end_ts - start_ts ))
    log "Finished $label in $(( elapsed / 60 ))m $(( elapsed % 60 ))s"
    echo "$label,$project,$elapsed" >> "$RESULTS_DIR/abc_timings.csv"
}

# ── Main ───────────────────────────────────────────────────────────────────
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

log "Registering models..."
register_models

[[ -f "$RESULTS_DIR/abc_timings.csv" ]] || echo "model,phoenix_project,wall_clock_seconds" > "$RESULTS_DIR/abc_timings.csv"

case "$MODE" in
    smoke)
        SMOKE_SUITE="${SUITE:-task_sanity}"
        log "SMOKE TEST — all 3 models × 1 task ($SMOKE_SUITE) → test-pinchbench"
        run_model "$LABEL_A" "$MODEL_A" "test-pinchbench" "$SMOKE_SUITE"
        run_model "$LABEL_B" "$MODEL_B" "test-pinchbench" "$SMOKE_SUITE"
        run_model "$LABEL_C" "$MODEL_C" "test-pinchbench" "$SMOKE_SUITE"
        log "Smoke test complete — check Phoenix: http://localhost:6006"
        ;;
    full)
        log "FULL A/B/C — 53 tasks × 3 models × 1 run"
        run_model "$LABEL_A" "$MODEL_A" "PinchBench-Run_Full_Apr16_$LABEL_A" ""
        run_model "$LABEL_B" "$MODEL_B" "PinchBench-Run_Full_Apr16_$LABEL_B" ""
        run_model "$LABEL_C" "$MODEL_C" "PinchBench-Run_Full_Apr16_$LABEL_C" ""
        log "Full A/B/C run complete"
        ;;
    *)
        die "Usage: $0 {smoke|full}"
        ;;
esac

log ""
log "Timings: $RESULTS_DIR/abc_timings.csv"
log "Results: $RESULTS_DIR/"
log "Phoenix: http://localhost:6006"
