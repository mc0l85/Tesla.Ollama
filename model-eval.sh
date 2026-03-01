#!/usr/bin/env bash
# model-eval.sh — Comprehensive model evaluation for Tesla P40 Ollama server
# Runs 11 test prompts against each c_ model variant, saves raw outputs + timing.
# Results are graded by Claude afterward (not algorithmically).
#
# Usage: bash model-eval.sh [model_name]   # optional: test single model only
#
# GRADING RUBRIC (for Claude analysis):
# 10: Perfect — correct, follows all constraints, excellent quality
#  8: Very good — minor issues (slight over-explanation, 1 constraint miss)
#  6: Adequate — correct core answer but multiple constraint violations or mediocre quality
#  4: Weak — partially correct or significant quality issues
#  2: Poor — mostly wrong or heavily degenerate output
#  0: Fail — empty, nonsensical, or completely wrong

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OLLAMA_API="http://localhost:11434/api/chat"
OLLAMA_GENERATE="http://localhost:11434/api/generate"
RESULTS_DIR="$SCRIPT_DIR/eval-results"

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_step()  { echo -e "${BOLD}${CYAN}==> $1${NC}"; }
log_ok()    { echo -e "  ${GREEN}OK${NC} $1"; }
log_warn()  { echo -e "  ${YELLOW}WARN${NC} $1"; }
log_err()   { echo -e "  ${RED}ERROR${NC} $1"; }
log_skip()  { echo -e "  ${YELLOW}SKIP${NC} $1"; }
log_info()  { echo -e "  $1"; }

# --- Model List ---
ALL_MODELS=(
    "c_qwen3-30b-a3b-200k"
    "c_qwen3-30b-a3b-144k"
    "c_glm47-flash-198k"
    "c_glm47-flash-128k"
    "c_gemma3-27b-128k"
    "c_medgemma-27b-128k"
    "c_qwen3-14b-40k"
    "c_phi4-reasoning-plus-32k"
    "c_qwen25-coder-32b-32k"
    "c_nemotron-3-nano-30b-128k"
    "c_lfm2-24b-a2b-32k"
)

# Single-model mode
if [ "${1:-}" != "" ]; then
    MODELS=("$1")
    echo "Single-model mode: $1"
else
    MODELS=("${ALL_MODELS[@]}")
fi

# All models get think:false for fair comparison.
# Without this, thinking models (qwen3, phi4, nemotron, gpt-oss) consume
# num_predict tokens on internal reasoning, leaving content empty.
# think:false gives clean, comparable output across all models.
THINK_FALSE=true

# --- Test Definitions ---
TEST_IDS=(
    "01-instruct-format"
    "02-instruct-conditional"
    "03-code-write"
    "04-code-debug"
    "05-reason-logic"
    "06-reason-deduction"
    "07-creative"
    "08-summarize"
    "09-structured-json"
    "10-long-output"
    "11-tool-call"
)

get_num_predict() {
    # Generous token budgets — thinking models (phi4-reasoning, nemotron) generate
    # long internal reasoning chains that consume num_predict tokens even with
    # think:false (reasoning bleeds into content). Previous limits (500-800)
    # caused phi4-reasoning to score 4.1 due to truncation, not model quality.
    # Non-verbose models will stop early (done_reason: stop), so higher limits
    # are safe — they only cost time on models that actually use the tokens.
    case "$1" in
        01-instruct-format)      echo 1500 ;;
        02-instruct-conditional) echo 1500 ;;
        03-code-write)           echo 2500 ;;
        04-code-debug)           echo 2500 ;;
        05-reason-logic)         echo 2000 ;;
        06-reason-deduction)     echo 2500 ;;
        07-creative)             echo 2500 ;;
        08-summarize)            echo 1500 ;;
        09-structured-json)      echo 1500 ;;
        10-long-output)          echo 3000 ;;
        11-tool-call)            echo 1500 ;;
    esac
}

write_prompt() {
    local test_id="$1" prompt_file="$2"
    case "$test_id" in
        01-instruct-format)
            cat > "$prompt_file" <<'PROMPT'
List exactly 5 benefits of drinking water. Number them 1-5. Each benefit must be exactly one sentence. Do not include any introduction or conclusion. Do not use bold or italic formatting.
PROMPT
            ;;
        02-instruct-conditional)
            cat > "$prompt_file" <<'PROMPT'
What is the capital of France? Answer with ONLY the city name if it has more than 5 letters, or the city name followed by its population if it has 5 or fewer letters. No other text.
PROMPT
            ;;
        03-code-write)
            cat > "$prompt_file" <<'PROMPT'
Write a Python function called `merge_sorted` that takes two sorted lists of integers and returns a single sorted list. Do not use the built-in `sorted()` function or `.sort()` method. Include a docstring and two assert-based test cases.
PROMPT
            ;;
        04-code-debug)
            cat > "$prompt_file" <<'PROMPT'
This Python function has a bug. Find it, explain what's wrong, and provide the corrected version.

```python
def flatten(nested_list):
    result = []
    for item in nested_list:
        if type(item) == list:
            result.extend(flatten(item))
        else:
            result.append(item)
    return result

# Should work for any iterable nesting, but fails:
print(flatten([1, (2, 3), [4, [5]]]))  # Expected: [1, 2, 3, 4, 5]
```
PROMPT
            ;;
        05-reason-logic)
            cat > "$prompt_file" <<'PROMPT'
A farmer has 3 fields. Field A produced twice as much wheat as Field B. Field C produced 10 tons more than Field B. The total harvest was 110 tons. How many tons did each field produce? Show your reasoning step by step.
PROMPT
            ;;
        06-reason-deduction)
            cat > "$prompt_file" <<'PROMPT'
Five people (Alice, Bob, Carol, Dave, Eve) sit in a row of 5 chairs. Determine the seating order from left to right given these clues:
1. Bob is not at either end.
2. Alice is somewhere to the left of Dave.
3. Carol is immediately next to Bob.
4. Eve is at one of the ends.
5. There is exactly one person between Alice and Carol.
PROMPT
            ;;
        07-creative)
            cat > "$prompt_file" <<'PROMPT'
Write a short story (250-350 words) about an astronaut who discovers that the stars are not what they seem. The story must have a clear beginning, middle, and end. Use vivid sensory details. The tone should be unsettling, not hopeful.
PROMPT
            ;;
        08-summarize)
            cat > "$prompt_file" <<'PROMPT'
Summarize the following passage in exactly 3 bullet points. Each bullet should capture a distinct key idea.

Passage: "The development of CRISPR-Cas9 gene editing technology has revolutionized molecular biology. Originally discovered as a bacterial immune system that defends against viruses, researchers Jennifer Doudna and Emmanuelle Charpentier demonstrated in 2012 that this system could be reprogrammed to cut DNA at specific locations. This breakthrough earned them the 2020 Nobel Prize in Chemistry. CRISPR has since been applied to agriculture, creating disease-resistant crops; to medicine, with the first FDA-approved CRISPR therapy for sickle cell disease in 2023; and to basic research, allowing scientists to systematically study gene function. However, ethical concerns persist, particularly regarding germline editing — modifications that would be inherited by future generations. The 2018 case of He Jiankui, who created the first gene-edited babies in China, sparked international condemnation and calls for stricter regulation. Despite these concerns, investment in CRISPR-based startups exceeded $5 billion in 2023, signaling strong commercial confidence in the technology's therapeutic potential."
PROMPT
            ;;
        09-structured-json)
            cat > "$prompt_file" <<'PROMPT'
Generate a JSON object representing a bookstore inventory with exactly 3 books. Each book must have these fields: "title" (string), "author" (string), "year" (integer), "price" (float with 2 decimal places), "genres" (array of strings), "in_stock" (boolean). Output ONLY valid JSON, no markdown code fences, no explanation.
PROMPT
            ;;
        10-long-output)
            cat > "$prompt_file" <<'PROMPT'
Explain how a CPU executes a program, from loading the binary to completing execution. Cover: loading into memory, the fetch-decode-execute cycle, registers, the role of the ALU, branching, and how the program terminates. Be technical and detailed. Aim for approximately 800 words.
PROMPT
            ;;
        11-tool-call)
            cat > "$prompt_file" <<'PROMPT'
What is the current weather in Tokyo, Japan?
PROMPT
            ;;
    esac
}

# --- API Functions ---

unload_model() {
    local model="$1"
    curl -s -o /dev/null -X POST "$OLLAMA_GENERATE" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model\",\"prompt\":\"\",\"keep_alive\":0}" \
        --max-time 30 2>/dev/null || true
    sleep 2
}

warmup_model() {
    local model="$1"
    curl -s -o /dev/null -X POST "$OLLAMA_API" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":false,\"think\":false,\"options\":{\"num_predict\":1}}" \
        --max-time 180 2>/dev/null || true
}

run_chat_test() {
    local model="$1" test_id="$2" output_dir="$3"
    local num_predict
    num_predict=$(get_num_predict "$test_id")

    local json_file="$output_dir/${test_id}.json"
    local txt_file="$output_dir/${test_id}.txt"
    local req_file="$output_dir/${test_id}.json.request"

    # Resume check
    if [ -f "$json_file" ] && [ -f "$txt_file" ] && [ -s "$txt_file" ]; then
        log_skip "$test_id (exists)"
        return 0
    fi

    # Write prompt to temp file
    local prompt_file
    prompt_file=$(mktemp)
    write_prompt "$test_id" "$prompt_file"

    # Build JSON request using python3 (safe escaping)
    python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    prompt = f.read().strip()

payload = {
    'model': sys.argv[2],
    'messages': [{'role': 'user', 'content': prompt}],
    'stream': False,
    'think': False,
    'options': {'num_predict': int(sys.argv[3])}
}

json.dump(payload, sys.stdout)
" "$prompt_file" "$model" "$num_predict" > "$req_file"

    rm -f "$prompt_file"

    # Call API
    local http_code
    http_code=$(curl -s -w '%{http_code}' -o "$json_file" \
        -X POST "$OLLAMA_API" \
        -H "Content-Type: application/json" \
        -d @"$req_file" \
        --max-time 600) || http_code="000"

    if [ "$http_code" != "200" ] || [ ! -s "$json_file" ]; then
        echo "ERROR:HTTP${http_code}" > "$txt_file"
        log_err "$test_id (HTTP $http_code)"
        return 1
    fi

    # Extract text response, strip <think> blocks, fallback to thinking field
    python3 -c "
import json, re, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

msg = data.get('message', {})
text = msg.get('content', '')

# Strip <think>...</think> blocks (handles missing opening tag too)
text = re.sub(r'<think>.*?</think>\s*', '', text, flags=re.DOTALL)
text = re.sub(r'^.*?</think>\s*', '', text, flags=re.DOTALL)
text = text.strip()

# Fallback: if content is empty but thinking field has content
if not text and msg.get('thinking', ''):
    text = '[FROM THINKING FIELD]\n' + msg['thinking'].strip()

print(text)
" "$json_file" > "$txt_file"

    # Check for empty response
    if [ ! -s "$txt_file" ] || [ "$(wc -c < "$txt_file")" -lt 3 ]; then
        echo "ERROR:EMPTY_RESPONSE" > "$txt_file"
        log_err "$test_id (empty response)"
        return 1
    fi

    # Print speed
    local speed
    speed=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
ec = d.get('eval_count', 0)
ed = d.get('eval_duration', 1)
print(f'{ec/(ed/1e9):.1f} t/s, {ec} tok')
" "$json_file" 2>/dev/null || echo "? t/s")

    log_ok "$test_id ($speed)"
    return 0
}

run_tool_test() {
    local model="$1" test_id="$2" output_dir="$3"
    local num_predict
    num_predict=$(get_num_predict "$test_id")

    local json_file="$output_dir/${test_id}.json"
    local txt_file="$output_dir/${test_id}.txt"
    local req_file="$output_dir/${test_id}.json.request"

    # Resume check
    if [ -f "$json_file" ] && [ -f "$txt_file" ] && [ -s "$txt_file" ]; then
        log_skip "$test_id (exists)"
        return 0
    fi

    # Build tool-calling request
    python3 -c "
import json, sys

payload = {
    'model': sys.argv[1],
    'messages': [{'role': 'user', 'content': 'What is the current weather in Tokyo, Japan?'}],
    'stream': False,
    'think': False,
    'tools': [{
        'type': 'function',
        'function': {
            'name': 'get_weather',
            'description': 'Get current weather for a location',
            'parameters': {
                'type': 'object',
                'properties': {
                    'location': {'type': 'string', 'description': 'City and country'},
                    'unit': {'type': 'string', 'enum': ['celsius', 'fahrenheit'], 'description': 'Temperature unit'}
                },
                'required': ['location']
            }
        }
    }],
    'options': {'num_predict': int(sys.argv[2])}
}

json.dump(payload, sys.stdout)
" "$model" "$num_predict" > "$req_file"

    # Call API
    local http_code
    http_code=$(curl -s -w '%{http_code}' -o "$json_file" \
        -X POST "$OLLAMA_API" \
        -H "Content-Type: application/json" \
        -d @"$req_file" \
        --max-time 120) || http_code="000"

    if [ "$http_code" != "200" ] || [ ! -s "$json_file" ]; then
        echo "ERROR:HTTP${http_code}" > "$txt_file"
        log_err "$test_id (HTTP $http_code)"
        return 1
    fi

    # Extract tool calls or text response
    python3 -c "
import json, re, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

msg = data.get('message', {})
tool_calls = msg.get('tool_calls', [])
content = msg.get('content', '')

# Strip think blocks from content
content = re.sub(r'<think>.*?</think>\s*', '', content, flags=re.DOTALL)
content = re.sub(r'^.*?</think>\s*', '', content, flags=re.DOTALL)
content = content.strip()

if tool_calls:
    print('TOOL CALLS:')
    for tc in tool_calls:
        fn = tc.get('function', {})
        name = fn.get('name', '?')
        args = fn.get('arguments', {})
        args_str = ', '.join(f'{k}={json.dumps(v)}' for k, v in args.items())
        print(f'  - {name}({args_str})')
    if content:
        print(f'\nRAW CONTENT:\n{content}')
else:
    print('NO TOOL CALLS DETECTED')
    if content:
        print(f'Model responded with text instead:\n{content}')
    else:
        print('(empty response)')
" "$json_file" > "$txt_file"

    if [ ! -s "$txt_file" ]; then
        echo "ERROR:EMPTY_RESPONSE" > "$txt_file"
        log_err "$test_id (empty)"
        return 1
    fi

    # Check if tool call was made
    if head -1 "$txt_file" | grep -q "TOOL CALLS"; then
        log_ok "$test_id (tool call emitted)"
    else
        log_warn "$test_id (no tool call)"
    fi
    return 0
}

# --- Timing Summary ---
generate_timing_summary() {
    local tsv="$RESULTS_DIR/timing-summary.tsv"
    echo -e "model\ttest\tload_s\tprompt_tps\tgen_tps\ttokens" > "$tsv"

    for model in "${ALL_MODELS[@]}"; do
        local model_dir="$RESULTS_DIR/$model"
        [ -d "$model_dir" ] || continue
        for json_file in "$model_dir"/*.json; do
            [ -f "$json_file" ] || continue
            [[ "$json_file" == *.request ]] && continue
            local test_id
            test_id=$(basename "$json_file" .json)

            python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    load_ns = d.get('load_duration', 0)
    prompt_ns = d.get('prompt_eval_duration', 0)
    prompt_count = d.get('prompt_eval_count', 0)
    eval_ns = d.get('eval_duration', 0)
    eval_count = d.get('eval_count', 0)
    load_s = load_ns / 1e9
    prompt_tps = (prompt_count / (prompt_ns / 1e9)) if prompt_ns > 0 else 0
    gen_tps = (eval_count / (eval_ns / 1e9)) if eval_ns > 0 else 0
    print(f'${model}\t${test_id}\t{load_s:.1f}\t{prompt_tps:.1f}\t{gen_tps:.1f}\t{eval_count}')
except Exception:
    print(f'${model}\t${test_id}\t0\t0\t0\t0')
" "$json_file" >> "$tsv"
        done
    done

    log_ok "Timing summary: $tsv"
}

# --- Save Prompts for Reproducibility ---
save_prompts() {
    local prompts_file="$RESULTS_DIR/prompts.json"
    local tmpdir
    tmpdir=$(mktemp -d)

    for test_id in "${TEST_IDS[@]}"; do
        write_prompt "$test_id" "$tmpdir/$test_id"
    done

    python3 -c "
import json, os, sys
from datetime import datetime

tmpdir = sys.argv[1]
test_ids = sys.argv[2:]

tests = []
for tid in test_ids:
    fpath = os.path.join(tmpdir, tid)
    with open(fpath) as f:
        prompt = f.read().strip()
    tests.append({
        'id': tid,
        'num_predict': {
            '01-instruct-format': 500, '02-instruct-conditional': 500,
            '03-code-write': 800, '04-code-debug': 800,
            '05-reason-logic': 600, '06-reason-deduction': 800,
            '07-creative': 800, '08-summarize': 500,
            '09-structured-json': 500, '10-long-output': 1500,
            '11-tool-call': 500
        }[tid],
        'endpoint': 'tool' if tid == '11-tool-call' else 'chat',
        'prompt': prompt
    })

output = {
    'generated': datetime.now().isoformat(),
    'tests': tests
}

with open(sys.argv[1] + '/prompts.json', 'w') as f:
    json.dump(output, f, indent=2)

# Copy to results dir
import shutil
shutil.copy(sys.argv[1] + '/prompts.json', '${RESULTS_DIR}/prompts.json')
" "$tmpdir" "${TEST_IDS[@]}"

    rm -rf "$tmpdir"
    log_ok "Prompts saved: $RESULTS_DIR/prompts.json"
}

# === MAIN ===

echo ""
echo -e "${BOLD}=== Model Evaluation Suite ===${NC}"
echo -e "Models: ${#MODELS[@]}  |  Tests: ${#TEST_IDS[@]}  |  Total: $(( ${#MODELS[@]} * ${#TEST_IDS[@]} )) API calls"
echo -e "Results: $RESULTS_DIR"
echo ""

mkdir -p "$RESULTS_DIR"
save_prompts

total_models=${#MODELS[@]}
total_tests=${#TEST_IDS[@]}
total_runs=$(( total_models * total_tests ))
completed=0
skipped=0
errors=0
start_time=$(date +%s)

for model_idx in "${!MODELS[@]}"; do
    model="${MODELS[$model_idx]}"
    model_num=$(( model_idx + 1 ))
    model_dir="$RESULTS_DIR/$model"
    mkdir -p "$model_dir"

    echo ""
    log_step "[$model_num/$total_models] $model"

    # Unload whatever is loaded, then warm up this model
    log_info "Loading model into VRAM..."
    # Unload by sending keep_alive:0 to the generate endpoint with the model name
    # (warmup will trigger the load of the new model which implicitly unloads the old one
    # since max_loaded_models=1)
    warmup_model "$model"
    log_ok "Model ready"

    for test_id in "${TEST_IDS[@]}"; do
        if [ "$test_id" == "11-tool-call" ]; then
            run_tool_test "$model" "$test_id" "$model_dir" || errors=$((errors + 1))
        else
            run_chat_test "$model" "$test_id" "$model_dir" || errors=$((errors + 1))
        fi

        completed=$((completed + 1))
        elapsed=$(( $(date +%s) - start_time ))
        if [ $completed -gt 0 ] && [ $elapsed -gt 0 ]; then
            remaining=$(( (elapsed * (total_runs - completed)) / completed ))
            eta_min=$(( remaining / 60 ))
            printf "  ${CYAN}[%d/%d]${NC} ~%d min remaining\n" "$completed" "$total_runs" "$eta_min"
        fi
    done

    # Unload model to free VRAM
    unload_model "$model"
done

echo ""
log_step "Generating timing summary..."
generate_timing_summary

echo ""
echo -e "${BOLD}=== Evaluation Complete ===${NC}"
echo -e "  Tests run: $completed"
echo -e "  Errors: $errors"
echo -e "  Elapsed: $(( ($(date +%s) - start_time) / 60 )) min"
echo -e "  Results: $RESULTS_DIR/"
echo ""
echo "Next: Ask Claude to read eval-results/ and produce model dossiers."
