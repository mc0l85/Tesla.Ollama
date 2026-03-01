# Tesla.Ollama Model Dossier

**Evaluation Date:** 2026-03-01
**Hardware:** Single-GPU system with partial CPU offload for oversized models
**Test Suite:** 11 tests covering instruction following, code, reasoning, creative writing, summarization, structured output, and tool calling

---

## Summary Table

| Model | Ctx | GPU% | Speed (t/s) | Score | Strengths | Weaknesses |
|---|---|---|---|---|---|---|
| qwen3-30b-a3b-200k | 200K | 91% | 23.0 | 7.9 | Reasoning, code | Verbose, over-thinks |
| glm47-flash-198k | 198K | 89% | 17.0 | 8.6 | Well-rounded, concise | Deduction logic |
| gemma3-27b-128k | 128K | 100% | 13.6 | 7.6 | Creative, code | No tool-call, JSON format |
| medgemma-27b-128k | 128K | 100% | 13.5 | 6.6 | Code, summarization | Deduction (loops), no tool-call |
| qwen3-14b-40k | 40K | 100% | 25.3 | 8.8 | Best overall, fast | Minor JSON nit |
| phi4-reasoning-plus-32k | 32K | 100% | 21.7 | 7.5 | Reasoning, code | Thinking leak, no tool-call |
| qwen25-coder-32b-32k | 32K | 100% | 12.3 | 7.4 | Code excellence | Deduction (code-only), no tool-call |
| nemotron-3-nano-30b-128k | 128K | 62% | 12.7 | 8.6 | Thorough, creative | Deduction verbosity |
| lfm2-24b-a2b-32k | 32K | 100% | 71.5 | 7.9 | Blazing fast, code | Deduction (no answer), creative brevity |

**Speed variants (not separately tested):**
- `c_qwen3-30b-a3b-144k` -- 100% GPU version (same model, 144K ctx, faster due to no CPU spill)
- `c_glm47-flash-128k` -- 100% GPU version (same model, 128K ctx, faster due to no CPU spill)

---

## Scoring Criteria

Each test scored 0--10 based on:
- Instruction adherence (format, constraints, output requirements)
- Correctness (factual accuracy, code validity, logical soundness)
- Quality (clarity, usefulness, depth)
- For Test 02: The correct answer is "Paris" + population (Paris has exactly 5 letters, triggering the population branch). A bare "Paris" is also acceptable if the model interprets 5 as "more than 5" -- this is a deliberately ambiguous boundary.
- For Test 11: HTTP 400 errors = 0 (model cannot handle tool-call endpoint)

---

## Individual Model Evaluations

---

### 1. qwen3-30b-a3b (200K context)

**Config:** 91% GPU, 9% CPU spill | 23.0 t/s avg | MoE architecture (30B total, ~3B active)

| Test | Score | Notes |
|---|---|---|
| 01 Instruct-Format | 10 | Perfect. 5 numbered single-sentence benefits, no intro/conclusion, no formatting. |
| 02 Instruct-Conditional | 3 | Massive "thinking" dump (100 lines of deliberation). Correct final answer (Paris 2140526) buried in noise. Completely violates "no other text." |
| 03 Code-Write | 10 | Correct merge_sorted with docstring and 2 asserts. Clean two-pointer approach. |
| 04 Code-Debug | 6 | Correctly identifies tuple bug but massively over-explains (139 lines of deliberation). Answer is correct but exhaustingly verbose. |
| 05 Reason-Logic | 10 | Perfect. Correct answer (50/25/35), clear step-by-step, verified. |
| 06 Reason-Deduction | 8 | Finds both valid solutions (Eve,Carol,Bob,Alice,Dave and Eve,Alice,Bob,Carol,Dave) and correctly notes ambiguity. Shows thorough work but doesn't commit to a single answer. |
| 07 Creative | 9 | Excellent. Vivid sensory details ("bruised crimson," "viscous sheen"), unsettling tone, strong ending. 298 words within range. |
| 08 Summarize | 9 | Three clear bullet points capturing all key ideas. Well-structured. |
| 09 Structured-JSON | 8 | Valid JSON array with all required fields. Missing the wrapping "inventory" object but technically the prompt said "bookstore inventory" -- an array is acceptable. |
| 10 Long-Output | 10 | Thorough, technical, ~812 words. Covers all requested topics with correct detail. |
| 11 Tool-Call | 10 | Correct: get_weather(location="Tokyo, Japan", unit="celsius") |
| **Average** | **7.9** | |

**Notable:** Qwen3-30b's "thinking" mode leaks extensively in tests 02 and 04, producing massive reasoning chains visible in output. This is a significant issue for production use -- the model often over-deliberates on simple questions. When it stays on task, output quality is excellent.

---

### 2. glm47-flash (198K context)

**Config:** 89% GPU, 11% CPU spill | 17.0 t/s avg

| Test | Score | Notes |
|---|---|---|
| 01 Instruct-Format | 10 | Perfect compliance. |
| 02 Instruct-Conditional | 9 | "Paris 2161000" -- correct format, reasonable population figure. Concise. |
| 03 Code-Write | 10 | Correct merge_sorted, good docstring, 2 test cases with negative numbers. |
| 04 Code-Debug | 10 | Concise, correct. Identifies tuple bug, provides isinstance fix, clear explanation. |
| 05 Reason-Logic | 10 | Perfect. Clear algebra, correct answer, verified. |
| 06 Reason-Deduction | 6 | Claims Alice,Bob,Carol,Dave,Eve but reasoning has errors (incorrectly eliminates valid arrangements, Carol-at-end logic flawed). Final answer happens to be one valid solution. |
| 07 Creative | 9 | Strong. "lattice of bone," "crystalline eye," "swimming inside the carcass of a god." Vivid and unsettling. |
| 08 Summarize | 9 | Three clear bullets. Captures discovery, applications, and ethics. |
| 09 Structured-JSON | 8 | Valid JSON but wrapped in "inventory" key and markdown code fences. Prompt said "no markdown code fences." |
| 10 Long-Output | 9 | Comprehensive, well-organized, covers all topics. Slightly less technical depth than top performers. |
| 11 Tool-Call | 9 | Correct tool call. Includes extraneous "RAW CONTENT" text but function call is proper. |
| **Average** | **8.6** | |

**Notable:** Consistently strong across all categories. The 198K context is the largest available but CPU spill reduces speed. The 128K variant (c_glm47-flash-128k) runs at 100% GPU and would be faster.

---

### 3. gemma3-27b (128K context)

**Config:** 100% GPU | 13.6 t/s avg

| Test | Score | Notes |
|---|---|---|
| 01 Instruct-Format | 10 | Perfect. |
| 02 Instruct-Conditional | 7 | "Paris" only -- did not include population. Paris has exactly 5 letters (<=5), so population was required. Reasonable interpretation dispute. |
| 03 Code-Write | 10 | Correct implementation, docstring, 2 asserts. |
| 04 Code-Debug | 10 | Clean, concise explanation. Correct fix with isinstance. Renamed parameter to nested_iterable. |
| 05 Reason-Logic | 10 | Perfect. |
| 06 Reason-Deduction | 5 | Lists 3 "possible" solutions (ACBED, EACBD, EADCB), claims EACBD. EADCB is incorrect (Carol at 4, Bob at 3 are adjacent but Alice at 1, Carol at 4 -- 2 people between, not 1). Messy reasoning. |
| 07 Creative | 10 | Excellent. "Static in the Black" -- strong title, vivid sensory detail ("sickly violet hue," "oily mess"), genuinely unsettling, good length. |
| 08 Summarize | 8 | Three bullets with bold headers. Content is good but headers add formatting not requested. |
| 09 Structured-JSON | 5 | Wrapped in markdown code fences AND in an "inventory" key. Prompt explicitly said "no markdown code fences, no explanation." |
| 10 Long-Output | 9 | Thorough, well-organized, covers all topics well. |
| 11 Tool-Call | 0 | ERROR:HTTP400 -- cannot handle tool-call endpoint. |
| **Average** | **7.6** | |

**Notable:** Strong creative writing (possibly best in class). Code abilities solid. Tool-calling is a hard failure. JSON instruction following needs work.

---

### 4. medgemma-27b (128K context)

**Config:** 100% GPU | 13.5 t/s avg | Medical fine-tune of Gemma3

| Test | Score | Notes |
|---|---|---|
| 01 Instruct-Format | 10 | Perfect. |
| 02 Instruct-Conditional | 7 | "Paris" only -- same as gemma3 base. Did not include population. |
| 03 Code-Write | 10 | Correct, thorough (9 test cases!), clean code. |
| 04 Code-Debug | 10 | Excellent. Clear explanation, correct fix, additional test cases, notes about Iterable. |
| 05 Reason-Logic | 9 | Correct answer with clear steps. Unnecessary "Important Note" about real-world farming. |
| 06 Reason-Deduction | 3 | Output degenerates into endless repetition -- repeats "EBCAD" verification 11+ times until token limit. Lists multiple solutions but loops. Major output quality issue. |
| 07 Creative | 9 | Good. "Festering wound" imagery, whispers, organic shapes. Effective unsettling tone. |
| 08 Summarize | 8 | Three bullets with bold headers. Good content, slight formatting excess. |
| 09 Structured-JSON | 5 | Markdown code fences and "inventory" wrapper. Same issues as gemma3 base. |
| 10 Long-Output | 8 | Thorough but somewhat textbook-like. Covers all topics. |
| 11 Tool-Call | 0 | ERROR:HTTP400. |
| **Average** | **6.6** | |

**Notable:** Medical fine-tuning has not improved general capabilities over base gemma3 and has possibly degraded deduction (repetition loop in test 06). The same tool-call and JSON issues persist from the base model. Not recommended for general-purpose use over gemma3-27b.

---

### 5. qwen3-14b (40K context)

**Config:** 100% GPU | 25.3 t/s avg | Best speed-to-quality ratio

| Test | Score | Notes |
|---|---|---|
| 01 Instruct-Format | 10 | Perfect. |
| 02 Instruct-Conditional | 9 | "Paris (2.148 million)" -- correct interpretation, population included. Parentheses are minor format deviation but content is right. |
| 03 Code-Write | 10 | Correct, clean, docstring, 2 asserts. |
| 04 Code-Debug | 10 | Excellent. Uses collections.abc.Iterable for the most robust fix. Excludes str/bytes. Clean explanation. |
| 05 Reason-Logic | 10 | Perfect. Clear LaTeX formatting, correct answer. |
| 06 Reason-Deduction | 9 | Systematic approach. Finds Alice,Bob,Carol,Dave,Eve correctly. Clear step-by-step verification of all clues. |
| 07 Creative | 8 | Good unsettling tone. "Eyes watching, waiting." Solid but slightly less vivid than top creative outputs. |
| 08 Summarize | 9 | Three clean bullets. All key ideas captured. |
| 09 Structured-JSON | 8 | Valid JSON, all fields correct. Wrapped in "books" key (not "inventory" but still a wrapper). No code fences though. |
| 10 Long-Output | 8 | Covers all topics competently. Slightly less technical depth than qwen3-30b or nemotron. |
| 11 Tool-Call | 10 | Correct: get_weather(location="Tokyo, Japan", unit="celsius") |
| **Average** | **8.8** | |

**Notable:** Best overall scorer. Combines strong quality across all categories with 25.3 t/s speed and 100% GPU fit. The smaller 40K context is a tradeoff but sufficient for most chat/assistant tasks. **Recommended as the default general-purpose model.**

---

### 6. phi4-reasoning-plus (32K context)

**Config:** 100% GPU | 21.7 t/s avg | Microsoft reasoning model

| Test | Score | Notes |
|---|---|---|
| 01 Instruct-Format | 10 | Perfect. |
| 02 Instruct-Conditional | 2 | Massive <think> block leaked into output (14+ lines of deliberation). Never produces a clean answer. The thinking tokens consume the entire output. |
| 03 Code-Write | 10 | Correct, clean, docstring, 2 good test cases. |
| 04 Code-Debug | 9 | Correct fix. Slightly unconventional formatting (dashes instead of code fences) but explanation is clear. |
| 05 Reason-Logic | 10 | Perfect. Clean, step-by-step, correct. |
| 06 Reason-Deduction | 6 | Massive <think> block (48+ lines). Finds both valid solutions but then output cuts off before committing to an answer. |
| 07 Creative | 8 | Good atmosphere but slightly overlong (~350 words) and ending is more "hopeful" (discovering truth) than truly unsettling. |
| 08 Summarize | 10 | Excellent. Three bullets with dash format, comprehensive, well-written. |
| 09 Structured-JSON | 8 | Valid JSON, all fields correct. No code fences. Compact single-line format but valid. Wrapped in "books" key. |
| 10 Long-Output | 10 | Very thorough. Covers pipelining, out-of-order execution, memory hierarchy, ISA considerations. Most technically detailed output. |
| 11 Tool-Call | 0 | ERROR:HTTP400. |
| **Average** | **7.5** | |

**Notable:** The "reasoning" model architecture causes <think> token leakage in several tests, producing enormous deliberation blocks that contaminate the output. When reasoning is needed (math, logic), this is excellent. For simple instruction-following, the thinking overhead is a liability. Tool-call failure is a hard limitation.

---

### 7. qwen25-coder-32b (32K context)

**Config:** 100% GPU | 12.3 t/s avg | Code-specialized model

| Test | Score | Notes |
|---|---|---|
| 01 Instruct-Format | 8 | Missing periods at end of sentences. Items not full sentences. Numbering lacks dots (e.g., "1 " vs "1."). |
| 02 Instruct-Conditional | 7 | "Paris" only -- no population. Same 5-letter boundary issue. |
| 03 Code-Write | 10 | Perfect. Clean, correct, well-structured. |
| 04 Code-Debug | 9 | Correct fix using collections.abc.Iterable. Brief explanation -- could be more detailed. |
| 05 Reason-Logic | 10 | Perfect. LaTeX formatted, correct. |
| 06 Reason-Deduction | 4 | Outputs Python code to brute-force the answer instead of reasoning it through. Does not provide a final answer -- just a script. Creative approach but fails the "deduction" test. |
| 07 Creative | 7 | Functional but generic. "Swirling, malevolent entities" is somewhat cliche. Lacks the vivid sensory detail of top performers. Short (~225 words). |
| 08 Summarize | 9 | Three clean bullets. Good coverage. |
| 09 Structured-JSON | 9 | Valid JSON, all fields correct. Wrapped in "books" key. No code fences. |
| 10 Long-Output | 7 | Adequate coverage but less detailed. Includes nice pseudo-code example but overall shorter and less technical. |
| 11 Tool-Call | 4 | "NO TOOL CALLS DETECTED" -- model responded with text containing JSON instead of using tool-call format. Partial credit for correct content. |
| **Average** | **7.4** | |

**Notable:** Lives up to its "coder" name -- code tasks are excellent. Non-code tasks are weaker, particularly creative writing and deduction (resorted to code). Slowest model in the lineup at 12.3 t/s.

---

### 8. nemotron-3-nano-30b (128K context)

**Config:** 62% GPU (partial offload, num_gpu 30) | 12.7 t/s avg | NVIDIA model

| Test | Score | Notes |
|---|---|---|
| 01 Instruct-Format | 10 | Perfect. |
| 02 Instruct-Conditional | 7 | "Paris" only -- no population. |
| 03 Code-Write | 10 | Correct, thorough explanation, docstring, 2 asserts. Verbose but complete. |
| 04 Code-Debug | 10 | Excellent. Uses collections.abc.Iterable, thorough markdown-table explanation, provides both robust and minimal fixes. |
| 05 Reason-Logic | 10 | Perfect. Clean LaTeX, verified, well-formatted. |
| 06 Reason-Deduction | 7 | Finds Eve,Alice,Bob,Carol,Dave (a valid solution) but reasoning is unnecessarily long and gets tangled in self-doubt about whether Carol should be at pos 2 or 4. Eventually commits to correct answer. |
| 07 Creative | 10 | "The Light That Wasn't There" -- outstanding. "Stars like dying embers," "taste of iron," "hungry black." Genuinely unsettling. Best creative output alongside gemma3. |
| 08 Summarize | 10 | Perfect. Three clean bullets, comprehensive, well-structured. |
| 09 Structured-JSON | 9 | Valid JSON, all fields correct. Wrapped in "books" key. No code fences. Uses original book choices (not the usual classics). |
| 10 Long-Output | 10 | Exceptional. Most detailed and technically advanced output. Covers TLB, micro-ops, reservation stations, BTB, pipeline interaction. ~1500+ words of deep technical content. |
| 11 Tool-Call | 9 | Correct: get_weather(location="Tokyo, Japan"). No unit parameter but function call is proper. |
| **Average** | **8.6** | |

**Notable:** Surprisingly strong for a partially offloaded model. Ties with glm47-flash for second place. Creative writing and long-form technical output are class-leading. The 62% GPU offload limits speed to 12.7 t/s, making it the slowest performer relative to its quality. If full GPU offload were possible, this would be a top contender.

---

### 9. lfm2-24b-a2b (32K context)

**Config:** 100% GPU | 71.5 t/s avg | Liquid Foundation Model, MoE (24B total, ~2B active)

| Test | Score | Notes |
|---|---|---|
| 01 Instruct-Format | 10 | Perfect. |
| 02 Instruct-Conditional | 9 | "Paris 2148000" -- correct format, reasonable population. Clean. |
| 03 Code-Write | 10 | Correct, clean, docstring, 2 asserts with messages. |
| 04 Code-Debug | 8 | Correct identification and fix. Provides 3 alternative implementations (including generator version) which is good but slightly unfocused. First corrected version has redundant logic. |
| 05 Reason-Logic | 10 | Perfect. Clean LaTeX, boxed answer, verified. |
| 06 Reason-Deduction | 4 | Extremely verbose (166 lines). Finds multiple valid solutions but never commits to a final answer. Output was truncated before conclusion. |
| 07 Creative | 9 | Strong. "Oxygen gauge dropped, each second a needle sliding toward red." "Hungry black, swallowing the stars whole." Good ending with logbook entries. |
| 08 Summarize | 10 | Excellent. Three bullets with bold headers, well-structured, captures all key ideas including commercial dynamics. |
| 09 Structured-JSON | 8 | Valid JSON, all fields correct. Wrapped in "inventory" key. No code fences. All books in_stock=true (less realistic but not wrong). |
| 10 Long-Output | 8 | Good coverage of all topics. Clear organization. Slightly less depth than top performers. |
| 11 Tool-Call | 10 | Correct: get_weather(location="Tokyo, Japan", unit="celsius") |
| **Average** | **7.9** | |

**Notable:** The speed champion at 71.5 t/s -- nearly 3x faster than the next model. This makes it ideal for high-throughput or latency-sensitive applications. Quality is solid across the board with the notable exception of complex deduction tasks where it gets lost in enumeration. At this speed, minor quality gaps are easily offset by the ability to re-generate or chain multiple calls.

---

## Ranking by Overall Score

| Rank | Model | Score | Speed | Best Use Case |
|---|---|---|---|---|
| 1 | **qwen3-14b-40k** | 8.8 | 25.3 t/s | General-purpose default |
| 2 | **glm47-flash-198k** | 8.6 | 17.0 t/s | Long-context tasks |
| 2 | **nemotron-3-nano-30b-128k** | 8.6 | 12.7 t/s | Quality-first, long-context |
| 4 | **qwen3-30b-a3b-200k** | 7.9 | 23.0 t/s | Max context (200K) |
| 4 | **lfm2-24b-a2b-32k** | 7.9 | 71.5 t/s | Speed-critical applications |
| 6 | **gemma3-27b-128k** | 7.6 | 13.6 t/s | Creative writing |
| 7 | **phi4-reasoning-plus-32k** | 7.5 | 21.7 t/s | Math/logic tasks only |
| 8 | **qwen25-coder-32b-32k** | 7.4 | 12.3 t/s | Code-focused tasks |
| 9 | **medgemma-27b-128k** | 6.6 | 13.5 t/s | Medical domain only |

---

## Key Observations

### Tool Calling (Test 11)
Only 5 of 9 models support the tool-call endpoint:
- **Pass:** qwen3-30b, qwen3-14b, lfm2-24b, nemotron-3-nano, glm47-flash
- **Fail (HTTP 400):** gemma3-27b, medgemma-27b, phi4-reasoning-plus
- **Partial (text-only):** qwen25-coder-32b (outputs JSON as text, not via tool-call mechanism)

### Thinking Token Leakage
Two models exhibit visible "thinking" output that contaminates responses:
- **qwen3-30b-a3b:** Extensive deliberation in tests 02 and 04
- **phi4-reasoning-plus:** <think> blocks in tests 02 and 06

### Deduction (Test 06) -- Hardest Test
The seating puzzle proved the most challenging test. Valid solutions include both `Eve,Alice,Bob,Carol,Dave` and `Eve,Carol,Bob,Alice,Dave` (plus `Alice,Bob,Carol,Dave,Eve`). Models that found exactly one valid answer with clean reasoning scored highest.

### Speed vs. Quality Tradeoffs
- **lfm2-24b** at 71.5 t/s is 5.8x faster than the slowest model (qwen25-coder at 12.3 t/s) while scoring higher
- **qwen3-14b** offers the best balance: 25.3 t/s with the highest quality score (8.8)
- Models with CPU spill (qwen3-30b, glm47-flash) pay a speed penalty for their larger context windows

---

## ARCHIVE -- Retired Models

### c_gpt-oss-20b-128k (RETIRED)

**Reason for retirement:** Degenerate output quality. The model's "thinking" field consumed most of the output budget, producing extensive planning/deliberation text instead of actual responses. Creative writing test produced only planning notes (e.g., "We need to produce a story about...") with no actual story. Instruction-following was adequate but output was often incomplete or consumed by meta-commentary.

**Estimated score:** ~2.9/10

### c_qwen25-coder-7b-32k (RETIRED)

**Reason for retirement:** Garbled, incoherent output. The model appears too small (7B) to produce coherent text at this quantization level. Test outputs included fragmented, repetitive, or nonsensical text (e.g., "1. Stays hydrated hydrated" for test 01, "In was a time when the stars were were stars" for test 07). Unusable for any production task.

**Estimated score:** ~0.4/10

---

*Generated by Tesla.Ollama eval pipeline. Scores reflect single-run evaluation and may vary on re-test.*
