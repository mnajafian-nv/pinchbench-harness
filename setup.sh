#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── 0. Load .env first so overrides take effect ──────────────────────────────
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
    log "Loaded .env"
else
    die "No .env file found. Copy .env.example to .env and fill in your keys."
fi
[[ -n "${NVIDIA_API_KEY:-}" ]] || die "NVIDIA_API_KEY not set in .env"
[[ "$NVIDIA_API_KEY" == sk-* ]] || die "NVIDIA_API_KEY must start with 'sk-'. Check your .env file."

NEMOFLOW_DIR="${NEMOFLOW_DIR:-$SCRIPT_DIR/NeMo-Flow}"
OPENCLAW_HOME="$HOME/.openclaw"
PHOENIX_VENV="${PHOENIX_VENV:-$SCRIPT_DIR/.venv}"
GITLAB_REPO="${GITLAB_REPO:-https://gitlab-master.nvidia.com/nemo-agent-toolkit/dev/NeMo-Flow.git}"
GITLAB_BRANCH="${GITLAB_BRANCH:-fix/openai-chat-optional-tool-fields}"

# ── 1. Check prerequisites ───────────────────────────────────────────────────
log "Checking prerequisites..."
for cmd in node python3 git tmux; do
    command -v "$cmd" >/dev/null || die "$cmd not found. Install it first."
done
node_ver=$(node --version | sed 's/v//')
node_major=$(echo "$node_ver" | cut -d. -f1)
node_minor=$(echo "$node_ver" | cut -d. -f2)
if [[ "$node_major" -lt 22 ]] || { [[ "$node_major" -eq 22 ]] && [[ "$node_minor" -lt 12 ]]; }; then
    die "Node >= 22.12 required (found $(node --version)). OpenClaw will not start on older versions."
fi
python3 -c "import sys; assert sys.version_info >= (3,10)" 2>/dev/null \
    || die "Python >= 3.10 required"
log "Prerequisites OK: node $(node --version), python3 $(python3 --version 2>&1 | awk '{print $2}')"

# ── 2. Clone NeMo-Flow ──────────────────────────────────────────────────────
if [[ -d "$NEMOFLOW_DIR/.git" ]]; then
    log "NeMo-Flow already cloned at $NEMOFLOW_DIR, pulling latest..."
    cd "$NEMOFLOW_DIR" && git fetch origin && git checkout "$GITLAB_BRANCH" && git pull origin "$GITLAB_BRANCH"
else
    log "Cloning NeMo-Flow..."
    git clone --branch "$GITLAB_BRANCH" "$GITLAB_REPO" "$NEMOFLOW_DIR"
fi

# ── 3. Build OpenClaw ────────────────────────────────────────────────────────
log "Building OpenClaw..."
cd "$NEMOFLOW_DIR/third_party/openclaw"
log "Enabling corepack for pinned pnpm version..."
corepack enable 2>/dev/null || npm install -g corepack
corepack install 2>/dev/null || true
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
pnpm build
# Verify nemo-flow-node symlink (pnpm install creates this from workspace refs)
if [[ ! -e "$NEMOFLOW_DIR/third_party/openclaw/node_modules/nemo-flow-node" ]]; then
    log "Creating nemo-flow-node symlink..."
    ln -sf "$NEMOFLOW_DIR/crates/node" "$NEMOFLOW_DIR/third_party/openclaw/node_modules/nemo-flow-node"
fi

# ── 4. Create openclaw CLI wrapper ──────────────────────────────────────────
OPENCLAW_BIN="${OPENCLAW_BIN:-$HOME/.local/bin/openclaw}"
OPENCLAW_BIN_DIR="$(dirname "$OPENCLAW_BIN")"
mkdir -p "$OPENCLAW_BIN_DIR"
log "Creating openclaw CLI at $OPENCLAW_BIN..."
cat > "$OPENCLAW_BIN" <<WRAPPER
#!/bin/bash
exec node $NEMOFLOW_DIR/third_party/openclaw/openclaw.mjs "\$@"
WRAPPER
chmod +x "$OPENCLAW_BIN"

# ── 5. Build NeMo-Flow native node extension ────────────────────────────────
if ls "$NEMOFLOW_DIR/crates/node/"*.node &>/dev/null; then
    log "NeMo-Flow native extension already built"
else
    log "Building NeMo-Flow native extension (requires Rust)..."
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    if ! command -v cargo >/dev/null; then
        log "Installing Rust toolchain..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    cd "$NEMOFLOW_DIR/crates/node"
    npm install @napi-rs/cli 2>/dev/null || true
    npx napi build --platform --release || die "napi build failed for nemo-flow-node"
fi

# ── 6. Install NeMo-Flow extension into OpenClaw ────────────────────────────
log "Linking NeMo-Flow extension..."
mkdir -p "$OPENCLAW_HOME/extensions"
EXTENSION_SRC="$NEMOFLOW_DIR/third_party/openclaw/extensions/nemo-flow"
EXTENSION_DST="$OPENCLAW_HOME/extensions/nemo-flow"
if [[ -L "$EXTENSION_DST" || -d "$EXTENSION_DST" ]]; then
    rm -rf "$EXTENSION_DST"
fi
ln -s "$EXTENSION_SRC" "$EXTENSION_DST"

# ── 7. Install gws + fws (Google Workspace CLI + mock server) ────────────
if ! command -v gws >/dev/null; then
    log "Installing gws (Google Workspace CLI)..."
    npm install -g @googleworkspace/cli
else
    log "gws already installed ($(gws --version 2>&1 | head -1))"
fi
if ! command -v fws >/dev/null; then
    log "Installing fws (Google Workspace mock server)..."
    npm install -g @juppytt/fws
else
    log "fws already installed ($(fws --version 2>&1 | head -1))"
fi

# ── 8. Install PinchBench Python deps ──────────────────────────────────────
log "Installing PinchBench Python dependencies..."
PIP_BREAK_SYSTEM_PACKAGES=1 pip3 install --quiet pyyaml

# ── 9. Create Phoenix venv ──────────────────────────────────────────────────
log "Setting up Phoenix telemetry..."
if [[ ! -d "$PHOENIX_VENV" ]]; then
    python3 -m venv "$PHOENIX_VENV"
fi
"$PHOENIX_VENV/bin/pip" install --quiet \
    "arize-phoenix>=13.0" \
    arize-phoenix-otel
"$PHOENIX_VENV/bin/pip" install --quiet nvidia-nat-phoenix 2>/dev/null \
    || log "nvidia-nat-phoenix not available (optional)"

# ── 10. Install OTel client libs (system) ───────────────────────────────────
log "Installing OpenTelemetry client libraries..."
PIP_BREAK_SYSTEM_PACKAGES=1 pip3 install --quiet \
    opentelemetry-api \
    opentelemetry-sdk \
    opentelemetry-exporter-otlp \
    openinference-instrumentation \
    arize-phoenix-client

# ── 11. Configure openclaw.json ────────────────────────────────────────────
log "Configuring openclaw.json..."
mkdir -p "$OPENCLAW_HOME/workspace" "$OPENCLAW_HOME/agents" "$OPENCLAW_HOME/plugins"
TEMPLATE="$SCRIPT_DIR/config/openclaw.json.template"
TARGET="$OPENCLAW_HOME/openclaw.json"
if [[ -f "$TARGET" ]]; then
    cp "$TARGET" "$TARGET.bak"
    log "Backed up existing openclaw.json"
fi
GATEWAY_TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(24))")
sed \
    -e "s|__NVIDIA_API_KEY__|$NVIDIA_API_KEY|g" \
    -e "s|__PHOENIX_PROJECT_NAME__|PinchBench|g" \
    -e "s|__NEMOFLOW_DIR__|$NEMOFLOW_DIR|g" \
    -e "s|__HOME__|$HOME|g" \
    -e "s|__GATEWAY_TOKEN__|$GATEWAY_TOKEN|g" \
    "$TEMPLATE" > "$TARGET"

# ── 12. Copy SOUL.md and TOOLS.md ──────────────────────────────────────────
log "Installing agent bootstrap files..."
cp "$SCRIPT_DIR/config/SOUL.md" "$OPENCLAW_HOME/workspace/SOUL.md"
cp "$SCRIPT_DIR/config/TOOLS.md" "$OPENCLAW_HOME/workspace/TOOLS.md"

# ── 13. Copy override files ────────────────────────────────────────────────
log "Applying override files..."
SCRIPTS_DIR="$NEMOFLOW_DIR/third_party/skill/scripts"
cp "$SCRIPT_DIR/overrides/lib_grading.py" "$SCRIPTS_DIR/lib_grading.py"
cp "$SCRIPT_DIR/overrides/lib_agent.py" "$SCRIPTS_DIR/lib_agent.py"

# ── 14. Update shell rc (env var + PATH) ─────────────────────────────────
SHELL_RC="$HOME/.bashrc"
[[ "$(basename "$SHELL")" == "zsh" ]] && SHELL_RC="$HOME/.zshrc"
if ! grep -q "NVIDIA_API_KEY" "$SHELL_RC" 2>/dev/null; then
    echo "export NVIDIA_API_KEY=\"$NVIDIA_API_KEY\"" >> "$SHELL_RC"
    log "Added NVIDIA_API_KEY to $SHELL_RC"
fi
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$OPENCLAW_BIN_DIR" && \
   ! grep -q "$OPENCLAW_BIN_DIR" "$SHELL_RC" 2>/dev/null; then
    echo "export PATH=\"$OPENCLAW_BIN_DIR:\$PATH\"" >> "$SHELL_RC"
    log "Added $OPENCLAW_BIN_DIR to PATH in $SHELL_RC"
fi

log ""
log "Setup complete."
log "  1. Start a new shell or run: source $SHELL_RC"
log "  2. Run the benchmark: ./run.sh"
