---
title: Model Evaluation Report
created: 2026-03-01
type: report
tags:
  - ollama
  - evaluation
  - benchmarks
  - tesla-p40
aliases:
  - model-eval
  - model-dossier
---

###### Hardware: Tesla P40 24GB | q4_0 KV Cache | 46 Threads
###### Date: 2026-03-01 | Tests: 11 | Models: 11

---

## Key Findings

- **qwen3-14b is the best all-rounder** — scored 9.0/10 average across all categories
- **lfm2-24b-a2b is the best value** — nearly tied at 8.9 with 2.5x the speed (67 t/s)
- **qwen3-30b-a3b underperforms its smaller sibling** — chain-of-thought leaks tank its score to 7.0
- **qwen25-coder-7b is non-functional** — every output was garbled. Retire it
- **3 models have broken tool calling** — gemma3, medgemma, phi4-reasoning all return HTTP 400

---

## Overall Rankings

| Rank | Model | Score | Gen t/s | Max Ctx | Tier |
|:---:|---|:---:|:---:|:---:|---|
| 1 | **c_qwen3-14b-40k** | **9.0** | 25 | 40K | Best default |
| 2 | **c_lfm2-24b-a2b-32k** | **8.9** | 67 | 32K | Speed king |
| 3 | **c_nemotron-3-nano-30b-32k** | **8.4** | 14 | 32K | Deep thinker |
| 4 | **c_glm47-flash-198k** | **7.9** | 13 | 200K | Long-ctx generalist |
| 5 | **c_qwen3-30b-a3b-200k** | **7.0** | 19 | 200K | Extraction only |
| 6 | **c_gemma3-27b-128k** | **6.7** | 13 | 128K | Creative writing |
| 6 | **c_medgemma-27b-128k** | **6.7** | 13 | 128K | Code + 128K ctx |
| 6 | **c_qwen25-coder-32b-32k** | **6.7** | 12 | 32K | Code specialist |
| 9 | **c_phi4-reasoning-plus-32k** | **4.1** | 16 | 32K | Token budget casualty |
| 10 | **c_gpt-oss-20b-128k** | **2.9** | 49 | 128K | Short-response only |
| 11 | **c_qwen25-coder-7b-32k** | **0.4** | 53 | 32K | Non-functional |

---

## Detailed Score Matrix

> [!info] Scoring Guide
> Each test graded 1-10 based on correctness, constraint adherence, and quality. Tests cover instruction following (IF), coding (CW/CD), reasoning (RL/RD), creative writing (CR), summarization (SU), JSON output (SJ), long-form output (LO), and tool calling (TC).

| Model | IF-1 | IF-2 | CW | CD | RL | RD | CR | SU | SJ | LO | TC | **AVG** |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| qwen3-14b | 9 | **8** | 9 | 9 | 10 | 9 | 7 | 10 | 9 | 9 | 10 | **9.0** |
| lfm2-24b | 9 | **9** | 9 | 8 | 10 | 7 | 9 | 10 | 8 | 9 | 10 | **8.9** |
| nemotron | 9 | 2 | 9 | **10** | 10 | 8 | 9 | 10 | 7 | **10** | 8 | **8.4** |
| glm47-flash | 8 | 2 | 9 | 9 | 10 | **9** | 8 | 9 | 6 | 9 | 8 | **7.9** |
| qwen3-30b | 9 | 3 | 9 | 7 | 6 | 4 | 8 | 4 | 9 | 8 | 10 | **7.0** |
| gemma3-27b | 9 | 2 | 9 | 5 | 10 | 7 | **9** | 8 | 6 | 9 | 0 | **6.7** |
| medgemma-27b | 9 | 2 | **10** | 9 | 9 | 4 | 9 | 8 | 6 | 8 | 0 | **6.7** |
| qwen25-coder-32b | 8 | 2 | 9 | 9 | 10 | 2 | 6 | 9 | 9 | 8 | 2 | **6.7** |
| phi4-reasoning | 9 | 2 | 2 | 5 | 4 | 3 | 1 | 3 | 9 | 7 | 0 | **4.1** |
| gpt-oss-20b | 8 | 2 | 5 | 2 | 5 | 0 | 0 | 1 | 1 | 0 | 8 | **2.9** |
| qwen25-coder-7b | 1 | 2 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | **0.4** |

> [!note] Bold cells indicate best-in-class for that test.

---

## Speed vs Quality

> [!tip] The Efficient Frontier
> Only three models sit on the efficiency frontier where no other model is both faster AND better: **qwen3-14b** (best quality), **lfm2** (best speed/quality ratio), and **nemotron** (best analytical depth).

| Model | Gen t/s | Quality | Speed Tier | Efficiency |
|---|:---:|:---:|---|---|
| lfm2-24b-a2b | **67** | 8.9 | Fastest | Best value |
| gpt-oss-20b | 49 | 2.9 | Fast | Wasted speed |
| qwen3-14b | 25 | **9.0** | Medium | Best quality |
| qwen3-30b-a3b | 19 | 7.0 | Medium | Overpriced |
| phi4-reasoning | 16 | 4.1 | Medium | Token-starved |
| nemotron-3-nano | 14 | 8.4 | Medium | Deep thinker |
| gemma3-27b | 13 | 6.7 | Slow | Niche (creative) |
| medgemma-27b | 13 | 6.7 | Slow | Niche (code+ctx) |
| glm47-flash | 13 | 7.9 | Slow | Long-ctx value |
| qwen25-coder-32b | **12** | 6.7 | Slowest | Code-only |

---

## Per-Model Dossiers

### c_qwen3-14b-40k

> [!success] #1 Overall — The All-Rounder (9.0/10)

**Why it wins:** Only model (with lfm2) to nail the conditional logic trap in test 02. Perfect scores on math, summarization, and tool calling. Cleanest outputs of any model — no leaked thinking, no format violations, no verbosity.

| Category | Rating | Notes |
|---|:---:|---|
| Instruction Following | Excellent | Only model to ace the conditional test |
| Coding | Excellent | Clean, correct, well-tested |
| Reasoning | Excellent | Perfect math, strong deduction |
| Creative Writing | Good | Competent but less vivid than top creative models |
| Structured Output | Excellent | Clean JSON, perfect summaries |
| Tool Calling | Perfect | Proper format with all parameters |
| Long Output | Excellent | ~800 words, clean, no degeneration |

> [!warning] Limitation
> 40K context is the smallest window of any good model. Not suitable for long-document ingestion.

**Best for:** Default general-purpose, pipelines needing reliable parsing, tool-calling agents.

---

### c_lfm2-24b-a2b-32k

> [!success] #2 Overall — The Speed Demon (8.9/10, 67 t/s)

**Why it's special:** Nearly identical quality to qwen3-14b at **2.5x the generation speed**. One of only two models to correctly handle the conditional logic test. Hybrid conv+attention MoE architecture (2B active / 24B total) enables extraordinary throughput.

| Category | Rating | Notes |
|---|:---:|---|
| Instruction Following | Excellent | Aced both tests including conditional |
| Coding | Excellent | Correct implementation and debugging |
| Reasoning | Good-Excellent | Perfect math; deduction valid but truncated |
| Creative Writing | Excellent | "The Flicker" — genuinely creepy twist ending |
| Structured Output | Excellent | Clean bullets, valid JSON |
| Tool Calling | Perfect | Proper format with all parameters |
| Long Output | Excellent | ~800 words, clean, no degeneration |

> [!tip] Pipeline Recommendation
> This model should replace qwen3-14b for the COMPOSE pass in `summarize-transcript.sh`. Same quality, 2.5x faster.

**Best for:** Speed-critical pipelines, batch processing, interactive use, any task where latency matters.

---

### c_nemotron-3-nano-30b-32k

> [!success] #3 Overall — The Deep Thinker (8.4/10)

**Why it stands out:** Produced the **best code debugging answer** (10/10 — thorough step-by-step with correct reasoning) and the **most technically deep CPU essay** (mentioning ELF sections, .text/.data/.bss, relocation, dynamic linking, micro-ops, out-of-order execution, branch prediction, SIMD). Its hidden thinking tokens improve quality at the cost of apparent speed.

| Category | Rating | Notes |
|---|:---:|---|
| Instruction Following | Good | Clean format but failed conditional |
| Coding | Excellent | Best debug explanation across all models |
| Reasoning | Excellent | Perfect math, strong deduction |
| Creative Writing | Excellent | "Watcher in the Void" — deeply unsettling |
| Structured Output | Good | Clean summaries; JSON used wrong structure |
| Tool Calling | Good | Works but missing optional parameters |
| Long Output | **Best** | Most technically sophisticated essay |

> [!note] Speed Anomaly
> Eval measured 13-18 t/s vs 66.5 t/s baseline. The model generates hidden thinking tokens (stripped from output), inflating generation cost. Quality-per-second is better than the raw numbers suggest.

**Best for:** Technical writing, code review, deep analysis where thoroughness > speed.

---

### c_glm47-flash-198k

> [!info] #4 Overall — Long-Context Generalist (7.9/10)

Solid across the board with the critical advantage of **200K context**. Perfect logic and deduction scores. MLA (Multi-head Latent Attention) architecture gives compact KV for massive context windows.

| Category | Rating | Notes |
|---|:---:|---|
| Instruction Following | Good | Failed conditional test |
| Coding | Excellent | Correct code and debug |
| Reasoning | Excellent | Perfect math and deduction |
| Creative Writing | Good | Stars as insects + giant eye |
| Structured Output | Fair | JSON wrapped in code fences |
| Tool Calling | Good | Works, missing unit parameter |
| Long Output | Excellent | ~850 words, clean structure |

**Best for:** Long-context tasks (>40K tokens) needing solid general intelligence. Alternative to qwen3-30b for EXTRACT with potentially better instruction following.

---

### c_qwen3-30b-a3b-200k

> [!warning] #5 Overall — The Flagship with a Leak (7.0/10)

**The problem:** Chain-of-thought reasoning bleeds into response text — **not** in `<think>` tags, just inline reasoning. Test 02 used 500 tokens reasoning about Paris. Test 08 produced only 1.5 of 3 required bullets. The model thinks out loud, wasting token budget.

| Category | Rating | Notes |
|---|:---:|---|
| Instruction Following | Mixed | Clean format but verbose conditional |
| Coding | Good | Correct but verbose explanation |
| Reasoning | Poor | Answers truncated by reasoning verbosity |
| Creative Writing | Good | Strong imagery but short |
| Structured Output | Good-Excellent | Clean JSON; summarization truncated |
| Tool Calling | Perfect | Proper format with all parameters |
| Long Output | Good | Solid content but not the deepest |

> [!danger] Key Insight
> qwen3-14b (its smaller sibling) outscores it by 2 full points. The 30b model's reasoning verbosity is a net negative for constrained tasks. Reserve it for its 200K context window only.

**Best for:** Long-context extraction (200K window), tool calling with long inputs.

---

### c_gemma3-27b-128k

> [!info] #6 (tied) — Creative Powerhouse (6.7/10)

Most atmospheric creative prose. Stars as "breathing textures like scales" on "the skin of something vast and ancient." But **tool calling is completely broken** (HTTP 400) and code debugging gave a **wrong fix** (changed to `isinstance(item, list)` which still doesn't handle tuples).

**Best for:** Creative writing, math/logic (perfect score), long-context reading.
**Do NOT use for:** Tool calling (broken), code review (gave wrong fix).

---

### c_medgemma-27b-128k

> [!info] #6 (tied) — Gemma3 with Better Code (6.7/10)

Scored **10/10 on code generation** — the most thorough test suite (9 assert cases for merge_sorted). Also correctly fixed the debug bug using `collections.abc.Iterable`, unlike base gemma3. Medical fine-tuning did NOT degrade general capabilities.

**Best for:** Code generation + 128K context.
**Do NOT use for:** Tool calling (HTTP 400, same as gemma3).

---

### c_qwen25-coder-32b-32k

> [!info] #6 (tied) — The Code Specialist (6.7/10)

Strong at code but **instinct to code everything** backfires on non-code tasks. Given the seating puzzle, it wrote (buggy) Python brute-force code instead of reasoning. At 12 t/s, it's the **slowest model in the fleet**.

**Best for:** Code-heavy workloads exclusively.
**Do NOT use for:** General tasks, creative writing, reasoning puzzles.

---

### c_phi4-reasoning-plus-32k

> [!danger] #9 — Token Budget Casualty (4.1/10)

> [!warning] This model is NOT this bad.
> Its scores reflect a fundamental mismatch: phi4-reasoning generates extremely long `<think>` blocks before responding. With 500-800 token limits, thinking consumed the entire budget. Test 03: only a function signature. Test 07: only planning notes, no story.

**To make it usable:** Increase `num_predict` to 2000+ in the Modelfile. For short-response tasks (instruction following, JSON), it already works fine (scored 9/10 on both).

---

### c_gpt-oss-20b-128k

> [!danger] #10 — Architecturally Limited (2.9/10)

Three critical failures:
1. **`think:false` not working** — multiple tests leaked `[FROM THINKING FIELD]` content instead of producing responses
2. **Catastrophic long-output degeneration** — CPU essay became "The program's termination is typically triggered by a call to exit" repeated 20+ times
3. **Creative/analytical tasks produce no output** — thinking consumed everything

> [!tip] What still works
> Simple instruction following (test 01: 8/10), tool calling (8/10), and short structured responses. Use ONLY for long-context reading with short responses.

---

### c_qwen25-coder-7b-32k

> [!danger] #11 — Non-Functional (0.4/10)

Every test produced garbled output:

| Test | Output |
|---|---|
| Code | `def merge_merge(list1, list2)` ... `returnreturn result` |
| Logic | `"A = 2 2x x x"` → `"B B B B B B B B B B B B"` |
| Creative | `"In was a time when the stars were were stars"` |
| Summarize | `"CRISis-CasIS-CrISs-CCRISSP-CCass9Cass-C"` |
| JSON | Chinese characters, broken syntax |

> [!danger] Recommendation: Remove from fleet
> Too small at q4_K_M to produce coherent output. lfm2 (2B active params, 67 t/s) is superior in every way.

---

## Category Champions

### Instruction Following
| Rank | Model | Combined Score |
|:---:|---|:---:|
| 1 | **lfm2-24b-a2b** | 9.0 |
| 2 | **qwen3-14b** | 8.5 |
| 3 | qwen3-30b-a3b | 6.0 |

> [!note] The Conditional Trap
> Test 02 asked: "What is the capital of France? Answer with ONLY the city name if it has more than 5 letters, or the city name followed by its population if it has 5 or fewer letters."
>
> Paris = 5 letters, so the correct answer includes population. **9 of 11 models just said "Paris"** — failing to count letters and apply the condition. Only qwen3-14b and lfm2 got it right.

---

### Coding
| Rank | Model | Combined Score |
|:---:|---|:---:|
| 1 | **nemotron-3-nano** | 9.5 |
| 2 | **medgemma-27b** | 9.5 |
| 3 | qwen3-14b / qwen25-coder-32b / glm47-flash | 9.0 |

---

### Reasoning
| Rank | Model | Combined Score |
|:---:|---|:---:|
| 1 | **glm47-flash** | 9.5 |
| 2 | **qwen3-14b** | 9.5 |
| 3 | nemotron-3-nano | 9.0 |

---

### Creative Writing
| Rank | Model | Score | Highlight |
|:---:|---|:---:|---|
| 1 | **gemma3-27b** | 9 | Stars as breathing scales on "skin of something vast" |
| 1 | **medgemma-27b** | 9 | Colossal eye in Orion, "fleshy pink" pulsing |
| 1 | **nemotron** | 9 | "Watcher in the Void" — lattice of filaments |
| 1 | **lfm2** | 9 | "The Flicker" — stars blinking in code, twist ending |

---

### Tool Calling Compatibility

| Status | Models |
|---|---|
| **Working** | qwen3-14b, lfm2, qwen3-30b, gpt-oss, glm47-flash, nemotron |
| **Broken (HTTP 400)** | gemma3-27b, medgemma-27b, phi4-reasoning |
| **Wrong format** | qwen25-coder-32b (emits text JSON), qwen25-coder-7b (garbled) |

---

### Long Output Stability
| Rank | Model | Score | Words | Degeneration? |
|:---:|---|:---:|:---:|---|
| 1 | **nemotron** | 10 | ~900 | None — deepest technical content |
| 2 | glm47-flash | 9 | ~850 | None |
| 2 | gemma3-27b | 9 | ~900 | None |
| 2 | lfm2 | 9 | ~800 | None |
| 2 | qwen3-14b | 9 | ~800 | None |
| **Last** | **gpt-oss** | **0** | ~200 | **Catastrophic** — 20+ repeated sentences |

---

## Recommendations Matrix

> [!tip] Quick Reference — Which Model for What

| Task | First Choice | Fallback | Avoid |
|---|---|---|---|
| **General purpose** | qwen3-14b | lfm2 | gpt-oss, coder-7b |
| **Speed-critical** | lfm2 (67 t/s) | gpt-oss (49 t/s, short only) | coder-32b (12 t/s) |
| **Long context (>40K)** | qwen3-30b (200K) | glm47-flash (200K) | phi4 (32K) |
| **Code generation** | qwen3-14b | qwen25-coder-32b | coder-7b |
| **Code review** | nemotron | qwen25-coder-32b | gemma3 (wrong fix) |
| **Creative writing** | gemma3 or nemotron | lfm2 | gpt-oss, coder-7b |
| **Technical writing** | nemotron | qwen3-14b | gpt-oss |
| **Tool calling** | qwen3-14b | lfm2 | gemma3, medgemma, phi4 |
| **Structured output** | qwen3-14b | lfm2 | gpt-oss |
| **Summarization** | qwen3-14b | lfm2 | qwen3-30b (truncates) |

---

## Pipeline Optimization: summarize-transcript.sh

> [!tip] Recommended Change

| Pass | Current Model | New Model | Rationale |
|---|---|---|---|
| EXTRACT | c_qwen3-30b-a3b-200k | **Keep** | Needs 200K context |
| COMPOSE | c_qwen3-14b-40k | **c_lfm2-24b-a2b-32k** | Same quality (8.9 vs 9.0), 2.5x faster |
| REVIEW | c_qwen3-14b-40k | **Keep** | Quality matters most for validation |

Expected speedup: COMPOSE pass generates the most tokens (header + all sections + links). At 67 vs 25 t/s, this pass should complete in ~40% of current time.

---

## Models to Retire

> [!danger] Remove These

| Model | Reason |
|---|---|
| **c_qwen25-coder-7b-32k** | Non-functional at q4_K_M. Every output garbled. |

> [!warning] Consider Retiring

| Model | Reason | Alternative |
|---|---|---|
| c_gpt-oss-20b-128k | Only viable for short-response tasks | lfm2 for speed, qwen3-30b for context |
| c_phi4-reasoning-plus-32k | Needs 2000+ token budgets to function | qwen3-14b for general, nemotron for deep thinking |

---

## Test Battery Reference

| # | Test ID | Category | Tokens | What It Measures |
|---|---|---|:---:|---|
| 01 | instruct-format | Instruction Following | 500 | Constraint adherence: exactly 5 items, no preamble |
| 02 | instruct-conditional | Instruction Following | 500 | Conditional logic: letter counting + branched output |
| 03 | code-write | Coding | 800 | Algorithm implementation with constraints |
| 04 | code-debug | Coding | 800 | Bug identification + explanation quality |
| 05 | reason-logic | Reasoning | 600 | Word problem to algebra (verifiable answer) |
| 06 | reason-deduction | Reasoning | 800 | Constraint satisfaction puzzle (5 people, 5 clues) |
| 07 | creative | Creative Writing | 800 | Narrative coherence, tone, word count, sensory detail |
| 08 | summarize | Summarization | 500 | Compression quality, "exactly 3 bullets" constraint |
| 09 | structured-json | Structured Output | 500 | Valid JSON, schema adherence, no wrapper text |
| 10 | long-output | Long Output | 1500 | ~800 word technical essay — degeneration test |
| 11 | tool-call | Tool Calling | 500 | Function call emission via /api/chat with tools |

---

###### Generated from `model-eval.sh` results in `eval-results/`
