# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tesla.Ollama is a toolkit for managing, tuning, evaluating, and deploying custom Ollama models on a Tesla P40 24GB GPU server (`10.80.4.228`, user `myron`). It consists of bash scripts, Ollama modelfiles, and evaluation infrastructure.

## Hardware & Environment

- **Server:** HP DL380 G10, 50GB RAM, 46 CPU cores
- **GPU:** NVIDIA Tesla P40 24GB VRAM (Pascal, 2016), clock-boosted to 1531 MHz via `override.conf`
- **Ollama:** v0.15.4, flash attention, q4_0 KV cache, 46 threads, `OLLAMA_KEEP_ALIVE=-1`, single model loaded at a time
- **API endpoint:** `http://localhost:11434` (on the server), bound to `0.0.0.0`
- **Systemd override:** `/etc/systemd/system/ollama.service.d/override.conf` (deployed from `override.conf`)

### Tesla P40 Performance Reality

Pascal architecture limits compute for modern large models despite the 24GB VRAM.

| Model Size | Eval Rate | Notes |
|---|---|---|
| 20B (13GB VRAM) | ~50 t/s | Excellent |
| 27B (17GB VRAM) | ~14 t/s | Hardware-limited |
| 30B+ (19GB+ VRAM) | ~10-12 t/s | Slow |

### Quantization

All models use **Q4_K_M** (4-bit with K-means). Q3_K_M gains ~20-30% speed but noticeably degrades reasoning/math/code quality.

## Key Scripts

### `deploy.sh`
7-step idempotent deployment: pre-flight checks, backup, sysctl tuning, sudoers, systemd override, modelfile deployment, `ollama create` for all `c_*` models, verification. Safe to re-run.

```bash
ssh myron@10.80.4.228 "cd ~/my.models && bash deploy.sh"
```

### `model-eval.sh [model_name]`
Runs 11 standardized tests (instruction following, code write/debug, logic, deduction, creative, summarize, JSON, long output, tool calling) against all `c_*` models. Saves raw JSON + extracted text to `eval-results/<model>/`. Supports resuming (skips existing results). Optional single-model mode.

```bash
# Full eval (all models, ~45 min)
ssh myron@10.80.4.228 "cd ~/my.models && bash model-eval.sh"
# Single model
ssh myron@10.80.4.228 "cd ~/my.models && bash model-eval.sh c_qwen3-14b-40k"
```

### `bench-compose.sh [extraction_file]`
Benchmarks models specifically for section-by-section article composition. Scores output on preamble waste, structural elements (heading, quote, attribution, separator), and leaked planning text. Used to select the best COMPOSE model for the summarize pipeline.

### `summarize-transcript.sh <transcript> [title] [channel] [url] [duration]`
Four-pass transcript-to-Obsidian-article pipeline using three specialized models:
- **Pass 1 (EXTRACT):** `c_qwen3-30b-a3b-200k` — ingests full transcript (200K ctx), produces structured extraction with quotes, topics, key facts
- **Pass 2 (COMPOSE):** `c_lfm2-24b-a2b-32k` — writes each section as Obsidian markdown (67 t/s, fast)
- **Pass 3-4 (REVIEW):** `c_qwen3-14b-40k` — reviews/fixes structure and content quality

Output goes to `~/summaries/`. Supports YAML header in transcript file for metadata.

## Modelfile Conventions

All custom models use the `c_` prefix. Naming pattern: `c_<base-model>-<context-window>.modelfile`

Common parameters across all modelfiles:
- `num_thread 46` (matches CPU core count)
- `num_batch 2048`
- `num_gpu 999` (offload everything to GPU)
- `num_keep 24` (keep system prompt tokens in context)

Temperature varies by model purpose: 0.1 for structured tasks (lfm2), 0.7 for general (qwen3), 1.0 for creative (gemma3).

## Model Fleet (ranked by eval score)

| Model | Score | Gen t/s | Context | Best For |
|---|---|---|---|---|
| c_qwen3-14b-40k | 9.0 | 25 | 40K | Default general-purpose |
| c_lfm2-24b-a2b-32k | 8.9 | 67 | 32K | Speed-critical, pipelines |
| c_nemotron-3-nano-30b-32k | 8.4 | 14 | 32K | Technical writing, code review |
| c_glm47-flash-198k | 7.9 | 13 | 200K | Long-context generalist |
| c_qwen3-30b-a3b-200k | 7.0 | 19 | 200K | Extraction (200K ingestion) |
| c_gemma3-27b-128k | 6.7 | 13 | 128K | Creative writing (no tool calling) |
| c_phi4-reasoning-plus-32k | 4.1* | 16 | 32K | Deep reasoning (needs generous num_predict) |
| c_qwen25-coder-32b-32k | 6.7 | 12 | 32K | Code generation only |

*phi4-reasoning scored low due to eval token budget truncation, not model quality. Its thinking chains consume `num_predict` tokens — eval limits have been increased to 1500-3000 to fix this. Re-eval needed.

**Retired models:** `c_qwen25-coder-7b-32k` (non-functional garbled output) and `c_gpt-oss-20b-128k` (think:false broken, catastrophic degeneration) have been removed from the fleet.

**Tool calling works with:** qwen3-14b, lfm2-24b, qwen3-30b. Broken on gemma3, medgemma, phi4-reasoning (HTTP 400).

## Eval Results Structure

`eval-results/<model_name>/` contains per-test files:
- `<test-id>.json` — raw Ollama API response (timing, token counts)
- `<test-id>.json.request` — the request payload sent
- `<test-id>.txt` — extracted text response (think blocks stripped)

Top-level eval artifacts:
- `eval-results/MODEL-DOSSIER.md` — detailed per-model analysis with scores
- `eval-results/Model Evaluation Report.md` — formatted Obsidian report
- `eval-results/timing-summary.tsv` — load time, prompt t/s, gen t/s per model/test
- `eval-results/prompts.json` — all 11 test prompts for reproducibility

## Working with the Ollama API

All scripts use the Ollama REST API directly (not the CLI for inference):
- **Chat:** `POST /api/chat` with `messages`, `stream: false`, `think: false`
- **Generate:** `POST /api/generate` with `prompt`, `stream: false`
- **Unload:** `POST /api/generate` with `keep_alive: 0`

Always pass `think: false` for fair comparisons — thinking models (qwen3, phi4, nemotron) consume `num_predict` tokens on internal reasoning otherwise.

## Temporary Passwordless Sudo (for deployment)

deploy.sh requires passwordless sudo for systemctl, nvidia-smi, and sysctl. To grant temporary access:

```bash
# Grant (run on server as root or with existing sudo)
ssh myron@10.80.4.228 "echo 'myron ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/temp-myron"
```

**IMPORTANT: Removal of temporary sudo requires human approval.** Do not automatically remove it — always ask the user before running:
```bash
# Remove (REQUIRES HUMAN APPROVAL)
ssh myron@10.80.4.228 "sudo rm /etc/sudoers.d/temp-myron"
```

For permanent scoped access (preferred over temp ALL), the server uses `/etc/sudoers.d/ollama-tuning`:
```
myron ALL=(ALL) NOPASSWD: /usr/bin/nvidia-smi, /usr/bin/systemctl daemon-reload, /usr/bin/systemctl restart ollama, /usr/sbin/sysctl, /usr/local/bin/update-ollama-override
```

## Deploying Changes

After modifying modelfiles or `override.conf`:
1. Copy files to server: `scp *.modelfile override.conf myron@10.80.4.228:~/my.models/`
2. Run deploy: `ssh myron@10.80.4.228 "cd ~/my.models && bash deploy.sh"`

Or edit directly on server and run deploy.sh there. The script handles backup, systemd reload, and `ollama create` for all models.

## Cloud Models (Available via Ollama)

- kimi-k2-thinking:cloud
- glm-4.6:cloud
- qwen3-coder:480b-cloud
- gpt-oss:120b-cloud
- deepseek-v3.1:671b-cloud
- kimi-k2:1t-cloud

## Future: Llama Throughput Lab (Multi-Instance llama.cpp)

For concurrent/agentic workloads, run multiple llama.cpp instances behind an nginx load balancer instead of single-instance Ollama. Aggregate throughput can reach 800-1200+ t/s vs 20-60 t/s single-instance.

Reference: https://github.com/alexziskind1/llama-throughput-lab

Architecture: nginx (port 8080) round-robin/least-conn to N llama.cpp servers (ports 8081+). Can coexist with Ollama (port 11434) for interactive use.

Estimated capacity on Tesla P40 24GB:

| Model Size | Instances | Context | Aggregate t/s |
|---|---|---|---|
| 7B Q4_K_M (~4GB) | 4-5 | 4K | 200-300 |
| 13B Q4_K_M (~8GB) | 2-3 | 4K | 100-150 |
| 20B+ | 1 | 4K | 40-60 |

Best for: agentic workflows, batch processing, multi-user serving. Not needed for single-user interactive chat.
