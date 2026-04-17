# pinchbench-harness

Benchmark harness for evaluating OpenClaw + NeMo Flow agents on [PinchBench](https://github.com/pinchbench/skill).

## Setup

```bash
cp .env.example .env        # add your NVIDIA Inference Hub API key
./setup.sh                   # installs everything (~10 min, idempotent)
```

## Run

```bash
./run.sh                                                        # default: 3 runs, Claude Opus 4.5
RUNS=1 ./run.sh                                                 # quick single run
SUITE=task_sanity,task_calendar ./run.sh                        # specific tasks only
SUITE=automated-only ./run.sh                                   # skip LLM-judged tasks (cheapest)
MODEL=nvidia-inference/azure/anthropic/claude-sonnet-4-6 ./run.sh   # different model
CONCURRENCY=4 ./run.sh                                          # parallel execution
PROJECT_NAME=my-experiment-v1 ./run.sh                          # custom Phoenix project name
```

## View Results

Phoenix UI: `http://localhost:6006`

If running on a remote machine, tunnel in from your laptop:

```bash
ssh -L 6006:localhost:6006 your-remote-host
```

Then open http://localhost:6006 in your browser.

## What's in This Repo

| File | Purpose |
|------|---------|
| `setup.sh` | One-time install: clones NeMo-Flow, builds OpenClaw, installs deps, configures everything |
| `run.sh` | Starts Phoenix + runs the benchmark |
| `config/openclaw.json.template` | OpenClaw config (API key injected at setup) |
| `config/SOUL.md` | Agent personality tuning |
| `config/TOOLS.md` | Agent tool-use guidance |
| `overrides/lib_grading.py` | Grading pipeline fixes (judge truncation, retry logic) |
| `overrides/lib_agent.py` | NVIDIA Inference Hub judge support |

## Requirements

- Linux (tested on Ubuntu 22.04 x86_64)
- Node.js >= 22.12 (install via [nvm](https://github.com/nvm-sh/nvm): `nvm install 22`)
- Python >= 3.10
- tmux
- Git access to `gitlab-master.nvidia.com` — configure a [personal access token](https://gitlab-master.nvidia.com/-/user_settings/personal_access_tokens) or SSH key before running `setup.sh`
- [NVIDIA Inference Hub](https://build.nvidia.com/) API key (starts with `sk-`)

## Gotchas

- **Node version matters.** OpenClaw requires Node >= 22.12. `setup.sh` checks this upfront.
- **Use tmux for long runs.** Full benchmark takes hours. Detach with `Ctrl+B, D`.
- **Phoenix must be running before the benchmark.** `run.sh` handles this automatically.
- **Rust toolchain.** `setup.sh` installs it if missing (needed for the NeMo-Flow native extension).
- **Model IDs must be exact.** If a model ID triggers OpenClaw's fallback resolution (e.g. dated variants like `claude-sonnet-4-5-20250514`), the task prompt gets swallowed. Use short IDs: `anthropic/claude-sonnet-4-5`, not the dated variant.
- **Concurrency requires direct-API judge.** With `CONCURRENCY > 1`, always use `--judge` with a direct API model. The default OpenClaw-based judge is not concurrent-safe.

## TODO

- [ ] Switch Phoenix from Python venv to Docker (`arizephoenix/phoenix:latest`). Eliminates venv and pip deps.
- [ ] Add `lib_phoenix.py` override to query Phoenix GraphQL for per-task LLM latency breakdowns after a run.
- [ ] Adopt predictable session IDs (`pb-{run_id}-{task_id}`) in `lib_agent.py` for deterministic Phoenix trace correlation.
- [ ] Evaluate `--local` mode for all tasks (ensures NeMo Flow flushes traces via `beforeExit`).
