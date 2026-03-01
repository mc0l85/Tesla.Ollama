# Model Evaluation Dossier

**Date:** 2026-03-01
**Hardware:** Tesla P40 24GB, q4_0 KV cache, 46 threads
**Method:** 11 tests × 11 models via `/api/chat`, each model tested as-configured (own temperature, system prompt)

---

## Score Matrix (1-10)

| Model | IF-1 | IF-2 | Code-W | Code-D | Logic | Deduct | Creative | Summ | JSON | Long | Tool | **AVG** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **qwen3-14b** | 9 | 8 | 9 | 9 | 10 | 9 | 7 | 10 | 9 | 9 | 10 | **9.0** |
| **lfm2-24b-a2b** | 9 | 9 | 9 | 8 | 10 | 7 | 9 | 10 | 8 | 9 | 10 | **8.9** |
| **nemotron-3-nano** | 9 | 2 | 9 | 10 | 10 | 8 | 9 | 10 | 7 | 10 | 8 | **8.4** |
| **glm47-flash** | 8 | 2 | 9 | 9 | 10 | 9 | 8 | 9 | 6 | 9 | 8 | **7.9** |
| **qwen3-30b-a3b** | 9 | 3 | 9 | 7 | 6 | 4 | 8 | 4 | 9 | 8 | 10 | **7.0** |
| **gemma3-27b** | 9 | 2 | 9 | 5 | 10 | 7 | 9 | 8 | 6 | 9 | 0 | **6.7** |
| **medgemma-27b** | 9 | 2 | 10 | 9 | 9 | 4 | 9 | 8 | 6 | 8 | 0 | **6.7** |
| **qwen25-coder-32b** | 8 | 2 | 9 | 9 | 10 | 2 | 6 | 9 | 9 | 8 | 2 | **6.7** |
| **phi4-reasoning** | 9 | 2 | 2 | 5 | 4 | 3 | 1 | 3 | 9 | 7 | 0 | **4.1** |
| **gpt-oss-20b** | 8 | 2 | 5 | 2 | 5 | 0 | 0 | 1 | 1 | 0 | 8 | **2.9** |
| **qwen25-coder-7b** | 1 | 2 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | **0.4** |

### Speed Profile (gen t/s measured during eval)

| Model | Gen t/s | Prompt t/s | Max Ctx | Speed Tier |
|---|---|---|---|---|
| lfm2-24b-a2b | 58-74 | 358-1006 | 32K | Fastest |
| qwen25-coder-7b | 50-96* | 977-1160 | 32K | Fast (unusable) |
| gpt-oss-20b | 48-50 | 774-1083 | 128K | Fast |
| qwen3-14b | 24-28 | 372-452 | 40K | Medium |
| qwen3-30b-a3b | 17-20 | 145-438 | 200K | Medium |
| nemotron-3-nano | 13-18† | 139-563 | 32K | Medium† |
| phi4-reasoning | 16-17 | 258-438 | 32K | Medium |
| glm47-flash | 12-15 | 94-314 | 200K | Slow |
| gemma3-27b | 13-14 | 204-250 | 128K | Slow |
| medgemma-27b | 13-14 | 223-276 | 128K | Slow |
| qwen25-coder-32b | 12-13 | 201-243 | 32K | Slowest |

*qwen25-coder-7b speed is irrelevant — output quality is garbage.
†nemotron showed 13-18 t/s during eval vs 66.5 t/s baseline. The model generates thinking tokens (stripped from output), inflating apparent generation cost. Effective response quality-per-second is higher than the raw numbers suggest.

---

## Per-Model Dossiers

---

### 1. c_qwen3-14b-40k — The All-Rounder (AVG: 9.0)

**Rank: #1 overall**

| Strengths | Weaknesses |
|---|---|
| Only model to nail the conditional logic test (02) | Creative writing is competent but not top-tier |
| Perfect scores on logic, summarization, tool calling | 40K context limit (smallest window of the good models) |
| Clean, concise output with no format violations | 25 t/s is medium speed |
| Excellent instruction following across all categories | |

**Speed:** 25 t/s gen, 400+ t/s prompt. Solid medium tier.

**Best at:** Instruction following, structured output, summarization, tool calling. The most reliable general-purpose model.

**Worst at:** Creative writing (adequate but less vivid than gemma3/nemotron/lfm2). 40K context is limiting for long-document work.

**Quirks:** None observed. Cleanest outputs of any model — no leaked thinking, no format violations, no verbosity. Just answers the question. This makes it ideal for pipelines where you parse the output.

**Verdict:** Your best default model for almost everything. The only reason not to use it is when you need >40K context or >25 t/s speed.

---

### 2. c_lfm2-24b-a2b-32k — The Speed Demon (AVG: 8.9)

**Rank: #2 overall, #1 speed**

| Strengths | Weaknesses |
|---|---|
| 58-74 t/s — fastest model by 2x | 32K context limit |
| Only model besides qwen3-14b to ace the conditional test | Deduction puzzle answer was valid but reasoning got cut off |
| Clean tool calls, valid JSON, excellent summarization | |
| Consistent quality across all categories | |

**Speed:** 64-74 t/s gen, 500-1000 t/s prompt. In a league of its own.

**Best at:** Speed-sensitive workloads. Its quality matches qwen3-14b in most areas while being 2.5x faster. Summarization, instruction following, structured output all excellent.

**Worst at:** Complex multi-step deduction (adequate but not top-tier). 32K context is a hard limit.

**Quirks:** Hybrid conv+attention MoE architecture (only 10/40 layers are attention). This explains both the speed (SSM layers are fast) and the occasional weakness on tasks requiring deep multi-step reasoning over long working memory.

**Verdict:** When you need speed AND quality, this is the model. For the summarize-transcript pipeline's COMPOSE pass, this would be a strong upgrade over qwen3-14b — same quality, 2.5x faster.

---

### 3. c_nemotron-3-nano-30b-32k — The Deep Thinker (AVG: 8.4)

**Rank: #3 overall**

| Strengths | Weaknesses |
|---|---|
| Best code debugging answer (10/10) — thorough, methodical | Failed the conditional logic test (02) like most models |
| Best long-output essay — most technically deep | JSON output used wrong structure (object keys not array) |
| Excellent creative writing and summarization | Eval gen speed (13-18 t/s) much lower than baseline (66.5) |
| Superb at technical/analytical tasks | 32K context limit |

**Speed:** 13-18 t/s gen during eval (thinking overhead). Baseline 66.5 t/s without thinking.

**Best at:** Technical analysis, code review, long-form technical writing. Produced the most technically sophisticated CPU essay (mentioned ELF sections, .text/.data/.bss, relocation, dynamic linking, micro-ops, out-of-order execution, branch prediction, SIMD). Code debug answer was the best across all models.

**Worst at:** Conditional instruction following, structured output format adherence.

**Quirks:** Hybrid SSM+attention. The eval shows 13-18 t/s because thinking tokens are generated but stripped — the model reasons internally before responding. This is actually a feature: the thinking improves quality (it scored highest on several analytical tests), but the speed penalty is real. The model uses 23.4GB VRAM (barely fits) which limits concurrent use.

**Verdict:** Your go-to for technical writing, code review, and deep analysis tasks. The hidden thinking boosts quality significantly. Consider it for any task where you value thoroughness over speed.

---

### 4. c_glm47-flash-198k — The Long-Context Generalist (AVG: 7.9)

**Rank: #4 overall**

| Strengths | Weaknesses |
|---|---|
| Perfect logic test, excellent deduction | Failed conditional test (02) |
| 200K context — second largest window | JSON output wrapped in markdown fences |
| Consistent quality across most categories | 12-15 t/s is on the slow side |
| Good creative writing | |

**Speed:** 12-15 t/s gen, 94-314 t/s prompt.

**Best at:** Long-context tasks requiring solid general intelligence. The 200K window + good quality makes it viable for massive document processing. Strong at math, logic, and deduction.

**Worst at:** Conditional instruction following, structured output format adherence (added code fences when told not to).

**Quirks:** MLA (Multi-head Latent Attention) with compact KV. The 200K context is real and usable. However, the model sometimes outputs only 2 tokens for tasks where it should produce more (test 02: only 2 tokens generated). This suggests it can be overly terse when uncertain.

**Verdict:** Best choice when you need massive context windows. For the summarize-transcript pipeline's EXTRACT pass (currently qwen3-30b), glm47-flash is worth considering as a faster alternative with the same context capacity.

---

### 5. c_qwen3-30b-a3b-200k — The Flagship with a Leak (AVG: 7.0)

**Rank: #5 overall**

| Strengths | Weaknesses |
|---|---|
| 200K context — largest window | Chain-of-thought leaks into response text |
| Perfect tool calling, good JSON output | Logic/deduction answers truncated by reasoning verbosity |
| Good creative writing | Summarization ruined by token waste on reasoning |
| Excellent prompt processing speed | |

**Speed:** 17-20 t/s gen, 145-438 t/s prompt.

**Best at:** Tool calling, structured output, long-context ingestion. When the task has a clear, constrained format, qwen3-30b performs well because there's little room for the model to ramble.

**Worst at:** Tasks requiring concise output. The model's chain-of-thought reasoning bleeds into the response text (not in `<think>` tags — just inline reasoning), consuming token budget and producing verbose, unfocused answers. Test 02 used 500 tokens reasoning about Paris before answering. Test 08 produced only 1.5 of 3 required bullets.

**Quirks:** The inline chain-of-thought is NOT in `<think>` blocks, so the script's think-stripping doesn't help. This appears to be the model's natural reasoning style at its configured temperature. The 200K context works perfectly for ingestion (high prompt t/s), but generation quality suffers when the model "thinks out loud" in constrained-output tasks.

**Verdict:** Still the right choice for EXTRACT in the summarize pipeline (200K context, one-shot ingestion, structured extraction prompts that constrain output). But avoid it for tasks needing concise free-form responses. qwen3-14b is strictly better for general tasks.

---

### 6. c_gemma3-27b-128k — Medical/Research Grade (AVG: 6.7)

**Rank: #6 (tied)**

| Strengths | Weaknesses |
|---|---|
| Excellent creative writing (most vivid) | Tool calling completely broken (HTTP 400) |
| Perfect logic, good deduction | Code debug fix was WRONG (only changed to isinstance(item, list)) |
| Clean instruction following | JSON wrapped in code fences |
| 128K context | 13-14 t/s — slow |

**Speed:** 13-14 t/s gen, 204-250 t/s prompt.

**Best at:** Creative writing (most vivid and atmospheric prose), math/logic, long-context reading.

**Worst at:** Tool calling (completely non-functional), code debugging (gave a wrong fix). The tool calling HTTP 400 suggests the model doesn't support the tools API format, or the Modelfile configuration is incompatible.

**Quirks:** Sliding window attention (1024) on most layers with only ~10/62 global layers. This architecture may explain the code debugging failure — the model might struggle with tasks requiring precise attention to multiple code details simultaneously.

**Verdict:** Useful for creative and analytical tasks. NOT suitable for tool-calling pipelines or code review. The tool calling failure is a hard blocker for agentic use.

---

### 7. c_medgemma-27b-128k — Gemma3 with Better Code (AVG: 6.7)

**Rank: #6 (tied)**

| Strengths | Weaknesses |
|---|---|
| Best code-write answer (10/10, most test cases) | Tool calling completely broken (HTTP 400) |
| Good creative writing | Failed conditional test |
| Correct code debugging (unlike base gemma3) | JSON wrapped in code fences |
| 128K context | 13-14 t/s — slow |

**Speed:** 13-14 t/s gen, 223-276 t/s prompt.

**Best at:** Code generation (provided the most thorough test suite in the merge_sorted answer — 9 assert cases). Also strong at creative writing and general analysis.

**Worst at:** Tool calling (same HTTP 400 as gemma3), deduction puzzles (got lost in extensive analysis without concluding).

**Quirks:** Despite being a medical-domain model, it performed identically to gemma3-27b on most general tasks, and BETTER on code (correct debug fix using collections.abc.Iterable). This suggests the medical fine-tuning didn't degrade general capabilities.

**Verdict:** If you need code generation + 128K context and DON'T need tool calling, medgemma is slightly better than base gemma3. But qwen3-14b or lfm2 are better choices overall.

---

### 8. c_qwen25-coder-32b-32k — The Code Specialist (AVG: 6.7)

**Rank: #6 (tied)**

| Strengths | Weaknesses |
|---|---|
| Excellent code write and debug | Deduction: output Python code instead of reasoning (wrong approach) |
| Perfect logic, good summarization | Creative writing is generic and less vivid |
| Clean JSON output (no code fences) | Tool calling failed (emitted text JSON, not tool call format) |
| | 12-13 t/s — slowest model |

**Speed:** 12-13 t/s gen, 201-243 t/s prompt. Slowest model in the fleet.

**Best at:** Code generation and debugging. The merge_sorted implementation was clean and concise. The debug fix correctly used collections.abc.Iterable.

**Worst at:** Non-code tasks. When given the deduction puzzle, it wrote Python code to brute-force it (and the code had bugs). Creative writing was passable but uninspired. Tool calling failed because the model emitted a JSON string instead of a proper tool call.

**Quirks:** The model's instinct is to write code for everything, including puzzles that should be solved by reasoning. This is great when you need code but counterproductive for general tasks. At 12-13 t/s, it's also the slowest model, making it hard to justify for non-code work.

**Verdict:** Keep it for code-heavy workloads where you need a large (32B) model's quality. For code generation specifically, it's competitive with the top models. For everything else, qwen3-14b is better and 2x faster.

---

### 9. c_phi4-reasoning-plus-32k — Token Budget Casualty (AVG: 4.1)

**Rank: #9**

| Strengths | Weaknesses |
|---|---|
| Clean JSON output (no fences) | Deep thinking consumes all token budget |
| Good instruction following (when it responds) | Most responses truncated or leaked `<think>` blocks |
| | Tool calling broken (HTTP 400) |
| | Creative writing: only planning, no actual story |

**Speed:** 16-17 t/s gen, 258-438 t/s prompt.

**CRITICAL ISSUE:** phi4-reasoning generates extremely long `<think>` blocks before responding. With the eval's token limits (500-800 for most tests), thinking consumed the entire budget, leaving nothing for actual response. Test 03 (code): only produced a function signature. Test 05 (logic): set up the equation then ran out of tokens. Test 07 (creative): only planning notes, no story.

**The model is NOT this bad.** Its scores reflect a fundamental mismatch: phi4-reasoning needs 2000-4000+ token budgets to think AND respond. In the eval's constrained setup, it simply can't function.

**Verdict:** Only use with generous token budgets (num_predict 2000+). For short-response tasks (instruction following, JSON), it works fine. For anything requiring substantial output, you need to budget for its thinking overhead. Consider it the "high-latency, high-quality" option — but only if you can afford the tokens.

---

### 10. c_gpt-oss-20b-128k — Architecturally Limited (AVG: 2.9)

**Rank: #10**

| Strengths | Weaknesses |
|---|---|
| 48-50 t/s — fast | think:false not working: thinking leaks everywhere |
| 128K context with flat speed | Long output degenerates catastrophically |
| Tool calling works | Creative writing: no output at all |
| Instruction following (test 01) was clean | Summarization, JSON, deduction: all failed |

**Speed:** 48-50 t/s gen, 774-1083 t/s prompt. Best prompt processing speed.

**CRITICAL ISSUES:**
1. **think:false not suppressing thinking**: Despite the eval passing `think:false`, multiple tests show `[FROM THINKING FIELD]` output — the model's response field was empty and all content went to thinking. The model reasons internally but produces no response.
2. **Catastrophic long-output degeneration**: The CPU essay (test 10) degenerated into "The program's termination is typically triggered by a call to exit" repeated 20+ times. This confirms the known sliding_window=128 limitation.
3. **Creative/analytical tasks produce no output**: Tests 07, 08, 09 all failed because thinking consumed everything.

**What still works:** Simple instruction following (test 01: clean 5 items), tool calling (proper format), and short structured responses. These succeed because they require minimal generation.

**Verdict:** Confirmed: use ONLY for long-context reading with short responses, tool calling, and structured Q&A. The 128K context + 49 t/s speed is unmatched for ingestion workloads. Do NOT use for any task requiring >200 tokens of coherent output.

---

### 11. c_qwen25-coder-7b-32k — Non-Functional (AVG: 0.4)

**Rank: #11 (last)**

Every test except 02 (which just said "Paris") produced garbled, degenerate output. Examples:
- Code: `def merge_merge(list1, list2)` with broken syntax, `returnreturn result`
- Logic: `"A = 2 2x x x"` degenerating into `"B B B B B B B B B B B B"`
- Creative: `"In was a time when the stars were were stars"`
- Summarize: `"CRISis-CasIS-CrISs-CCRISSP-CCass9Cass-C—Crbrism—brbr"`
- JSON: Chinese characters, broken syntax, wrong fields
- Long output: `"code code code code code code code code code code"`

**Speed:** 50-96 t/s (irrelevant).

**Verdict:** This model is too small at q4_K_M quantization to produce coherent output for any general-purpose task. The 7B parameter count at 4-bit quantization simply doesn't have enough capacity. **Recommend removing from the fleet** — it wastes VRAM and evaluation time. If you need a small fast model, lfm2-24b-a2b (2B active params, 67 t/s) is superior in every way.

---

## Category Rankings

### Instruction Following (Tests 01-02 combined)
1. lfm2 (9.0) — only model to ace both tests
2. qwen3-14b (8.5) — nailed the conditional
3. qwen3-30b (6.0) — verbose reasoning leaked
4. All others (5.0-5.5) — all failed the conditional

### Coding (Tests 03-04 combined)
1. medgemma-27b (9.5) — most thorough code, correct debug
2. qwen25-coder-32b (9.0) — clean code, correct debug
3. qwen3-14b (9.0) — clean code, correct debug
4. nemotron (9.5) — correct code, best debug explanation
5. glm47-flash (9.0)

### Reasoning (Tests 05-06 combined)
1. qwen3-14b (9.5) — perfect logic, excellent deduction
2. nemotron (9.0) — perfect logic, strong deduction
3. glm47-flash (9.5) — perfect logic, perfect deduction
4. gemma3-27b (8.5) — perfect logic, good deduction

### Creative Writing (Test 07)
1. gemma3-27b (9) — most atmospheric prose
2. medgemma-27b (9) — vivid sensory details
3. nemotron (9) — "Watcher in the Void" deeply unsettling
4. lfm2 (9) — "The Flicker" excellent structure/twist

### Structured Output (Tests 08-09 combined)
1. qwen3-14b (9.5) — clean bullets, clean JSON
2. lfm2 (9.0) — clean bullets, clean JSON
3. nemotron (8.5) — clean bullets, wrong JSON structure
4. qwen25-coder-32b (9.0) — clean bullets, clean JSON

### Long Output Stability (Test 10)
1. nemotron (10) — most technical depth, no degeneration
2. glm47-flash (9) — excellent, ~850 words
3. gemma3-27b (9) — very detailed, ~900 words
4. lfm2 (9) — clean ~800 words
5. qwen3-14b (9) — clean ~800 words
6. gpt-oss (0) — catastrophic degeneration

### Tool Calling (Test 11)
1. qwen3-14b (10) — perfect call with all params
2. qwen3-30b (10) — perfect call with all params
3. lfm2 (10) — perfect call with all params
4. gpt-oss (8) — works but used "C" instead of "celsius"
5. gemma3/medgemma/phi4 (0) — HTTP 400, completely broken

---

## Recommendations

### Default General-Purpose Model
**c_qwen3-14b-40k** — Highest overall score (9.0), clean outputs, reliable across all task types. Use this unless you have a specific reason not to.

### Speed-Critical Workloads
**c_lfm2-24b-a2b-32k** — Nearly identical quality (8.9) at 2.5x the speed. Best choice for pipelines, batch processing, and interactive use where latency matters.

### Long-Context Ingestion (>40K tokens)
**c_qwen3-30b-a3b-200k** — 200K context, good extraction quality. Best for the EXTRACT pass in summarize-transcript.sh. For COMPOSE/REVIEW passes (shorter context), switch to qwen3-14b or lfm2.

### Technical Writing & Code Review
**c_nemotron-3-nano-30b-32k** — Deepest technical analysis, best code debugging explanation. Its hidden thinking improves quality. Use when thoroughness matters more than speed.

### Code Generation
**c_qwen25-coder-32b-32k** or **c_qwen3-14b-40k** — Both produce correct, clean code. qwen25-coder-32b has slightly more coding instinct but is 2x slower. qwen3-14b is the better default.

### Creative Writing
**c_gemma3-27b-128k** or **c_nemotron-3-nano-30b-32k** — Most vivid, atmospheric prose. lfm2 is also excellent and 4x faster.

### Tool Calling / Agentic Use
**c_qwen3-14b-40k**, **c_lfm2-24b-a2b-32k**, or **c_qwen3-30b-a3b-200k** — All emit clean tool calls. Avoid gemma3/medgemma/phi4 (broken) and qwen25-coder (emits text JSON, not tool format).

### Models to Retire
- **c_qwen25-coder-7b-32k** — Non-functional. Remove from fleet.
- **c_gpt-oss-20b-128k** — Only viable for short-response tasks with long context input. The think:false issue makes it unreliable for most workloads.
- **c_phi4-reasoning-plus-32k** — Only usable with 2000+ token budgets. Consider increasing num_predict in its Modelfile if you want to keep it.

### Summarize-Transcript Pipeline Optimization
| Pass | Current | Recommended | Why |
|---|---|---|---|
| EXTRACT | qwen3-30b-a3b | qwen3-30b-a3b (keep) | Needs 200K context |
| COMPOSE | qwen3-14b | lfm2-24b-a2b | Same quality, 2.5x faster |
| REVIEW | qwen3-14b | qwen3-14b (keep) | Best quality for critical review |

---

## Test 02 Post-Mortem: The Conditional Logic Trap

The conditional instruction test ("Paris" = 5 letters, so include population) exposed a systemic weakness. **9 of 11 models** answered just "Paris" — failing to count letters and apply the conditional rule. Only qwen3-14b and lfm2 got it right.

This isn't a fluke. It reveals that most models treat "What is the capital of France?" as a retrieval task and ignore the conditional wrapper. The models that succeeded (qwen3-14b, lfm2) likely processed the FULL instruction before answering, while the others pattern-matched on the simple question and short-circuited.

**Implication:** For prompts with embedded conditional logic, prefer qwen3-14b or lfm2. Other models may ignore conditions attached to simple questions.
