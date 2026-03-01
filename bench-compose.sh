#!/usr/bin/env bash
#
# bench-compose.sh — Evaluate models for section-by-section composition
#
# Tests each candidate model on 3 representative sections from the extraction,
# scoring on: preamble waste, content quality, word count, quote usage, and speed.
#
# Usage: ./bench-compose.sh [extraction_file]

set -euo pipefail

OLLAMA_API="http://localhost:11434/api/generate"
EXTRACTION_FILE="${1:-/tmp/summarize-pipeline/test-transcript-extraction.txt}"
BENCH_DIR="/tmp/bench-compose"
RESULTS_FILE="$BENCH_DIR/results.tsv"

# Models to test (local models that fit in 24GB VRAM + cloud models)
MODELS=(
    "c_qwen3-30b-a3b-200k"
    "c_gemma3-27b-128k"
    "c_glm47-flash-198k"
    "c_gpt-oss-20b-128k"
    "c_qwen3-14b-40k"
    "c_phi4-reasoning-plus-32k"
)

# 3 test topics — early, middle, late from the extraction outline
# These represent different content types to test model versatility
TEST_TOPICS=(
    "Introduction of Daniel's background and work"
    "Discussion of five levels of AI integration in workflows"
    "Q&A about costs, technical implementation, and security"
)

# ── Color helpers ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
log_ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
log_warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
log_err()   { printf "${RED}[ERR]${NC}   %s\n" "$*" >&2; }
log_step()  { printf "\n${BOLD}${CYAN}━━━ %s ━━━${NC}\n" "$*"; }

# ── Validate ──
if [ ! -f "$EXTRACTION_FILE" ]; then
    log_err "Extraction file not found: $EXTRACTION_FILE"
    echo "Run the main pipeline first, or pass an extraction file as argument."
    exit 1
fi

rm -rf "$BENCH_DIR"
mkdir -p "$BENCH_DIR"

# ── Score a single section output ──
# Returns: preamble_pct content_words has_heading has_quote has_attribution has_separator quality_score
score_section() {
    local raw_file="$1"
    local output_file="$2"

    python3 - "$raw_file" "$output_file" << 'PYEOF'
import json, re, sys

raw_file = sys.argv[1]
output_file = sys.argv[2]

# Load raw response
with open(raw_file) as f:
    data = json.load(f)
response = data.get("response", "")
response_len = len(response)

# Load cleaned output
with open(output_file) as f:
    cleaned = f.read()
cleaned_len = len(cleaned)

# Preamble percentage (how much was stripped)
preamble_pct = round((1 - cleaned_len / max(response_len, 1)) * 100, 1)

# Word count of cleaned content
words = len(cleaned.split())

# Structural checks
has_heading = 1 if re.search(r'^## \S', cleaned, re.MULTILINE) else 0
has_quote = 1 if re.search(r'> \[!quote\]', cleaned) or re.search(r'^> "', cleaned, re.MULTILINE) else 0
has_attribution = 1 if re.search(r'(?:Daniel|Clint)\s+(?:explained|noted|stated|emphasized|argued|described|mentioned|observed|discussed|highlighted|revealed|clarified|elaborated|stressed|pointed)', cleaned) else 0
has_separator = 1 if re.search(r'^---\s*$', cleaned, re.MULTILINE) else 0

# Check for residual planning text (signs of preamble leakage)
planning_patterns = [
    r"Let's\s+(?:plan|break|check|look|identify|write|draft|structure)",
    r"We (?:are to|need to|must|should|will)\s+write",
    r"Requirements?:",
    r"Steps?:",
    r"Now,?\s+(?:let's|we|the)",
    r"Word count:",
    r"(?:first|second|third)\s+paragraph",
]
leaked_planning = 0
for pat in planning_patterns:
    if re.search(pat, cleaned, re.IGNORECASE):
        leaked_planning += 1

# Compute quality score (0-100)
# Weights: content(30) + structure(40) + cleanliness(30)
content_score = min(words / 4, 30)  # 400 words = max 30 pts
structure_score = has_heading * 10 + has_quote * 10 + has_attribution * 10 + has_separator * 10  # max 40
cleanliness_score = max(0, 30 - leaked_planning * 10 - max(0, preamble_pct - 50) * 0.3)  # max 30
quality_score = round(content_score + structure_score + cleanliness_score, 1)

print(f"{preamble_pct}\t{words}\t{has_heading}\t{has_quote}\t{has_attribution}\t{has_separator}\t{leaked_planning}\t{quality_score}")
PYEOF
}

# ── Generate one section with a model ──
generate_section() {
    local model="$1"
    local topic="$2"
    local section_num="$3"
    local output_dir="$4"

    local prompt_file="$output_dir/prompt-${section_num}.txt"
    local output_file="$output_dir/section-${section_num}.md"
    local raw_file="${output_file}.raw"

    # Build prompt
    cat > "$prompt_file" <<PROMPT_END
Write ONE section of an Obsidian knowledge base article about this specific topic:
"${topic}"

Include:
- A descriptive ## heading (use a specific name like "The Kai System Architecture", NOT the outline text verbatim)
- One > [!quote] callout with a verbatim quote from the DIRECT QUOTES section that is most relevant to this topic
- 3-4 detailed paragraphs with speaker attribution ("Daniel explained...", "Clint noted...")
- A --- separator at the end

Write around 400 words. Use ONLY facts from the extraction below. Do NOT cover other topics. Start IMMEDIATELY with the ## heading.

EXTRACTION:

PROMPT_END

    cat "$EXTRACTION_FILE" >> "$prompt_file"

    # Build JSON request
    python3 -c "
import json, sys
with open('${prompt_file}', 'r') as f:
    prompt = f.read()
payload = {
    'model': '${model}',
    'prompt': prompt,
    'stream': False,
    'think': False,
    'options': {
        'num_predict': 2048,
        'temperature': 0.6
    }
}
json.dump(payload, sys.stdout)
" > "${raw_file}.request"

    # Call API
    local start_time=$(date +%s)
    local http_code
    http_code=$(curl -s -w '%{http_code}' -o "$raw_file" \
        -X POST "$OLLAMA_API" \
        -H "Content-Type: application/json" \
        -d @"${raw_file}.request" \
        --max-time 300)
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    if [ "$http_code" != "200" ] || [ ! -s "$raw_file" ]; then
        printf 'FAIL\t0\t0\t0\t0\t0\t0\t0\t0\t%s\n' "$elapsed"
        return 1
    fi

    # Clean output (same logic as ollama_generate)
    python3 -c "
import json, sys, re

with open('${raw_file}', 'r') as f:
    data = json.load(f)
text = data.get('response', '')
if not text.strip() and data.get('thinking', '').strip():
    text = data['thinking']

# Strip leaked think blocks
text = re.sub(r'<think>.*?</think>\s*', '', text, flags=re.DOTALL)
text = re.sub(r'^.*?</think>\s*', '', text, flags=re.DOTALL)

# Preamble cleanup
yaml_block = ''
yaml_match = re.search(r'^---\n(?:.*?\n)?---[ \t]*\$', text, re.MULTILINE | re.DOTALL)
if yaml_match:
    yaml_block = yaml_match.group(0) + '\n\n'

search_from = yaml_match.end() if yaml_match else 0
content_start = re.search(r'^(?:###### Channel|## Key Takeaways)', text[search_from:], re.MULTILINE)
if content_start:
    text = yaml_block + text[search_from + content_start.start():]
else:
    heading = re.search(r'^#{1,6}\s', text[search_from:], re.MULTILINE)
    if heading:
        text = yaml_block + text[search_from + heading.start():]
    else:
        content = re.search(r'^(?:- \*\*|> |---\s*\$)', text[search_from:], re.MULTILINE)
        if content:
            text = yaml_block + text[search_from + content.start():]

# Dedup
lines = text.rstrip().split('\n')
cleaned = []
repeat_count = 0
prev_norm = None
for line in lines:
    norm = re.sub(r'\s+', ' ', line.strip().lower())
    if norm == prev_norm and len(norm) < 80:
        repeat_count += 1
        if repeat_count >= 2:
            continue
    else:
        repeat_count = 0
    cleaned.append(line)
    prev_norm = norm

print('\n'.join(cleaned))
" > "$output_file" 2>/dev/null

    if [ ! -s "$output_file" ]; then
        printf 'EMPTY\t0\t0\t0\t0\t0\t0\t0\t0\t%s\n' "$elapsed"
        return 1
    fi

    # Score
    local scores
    scores=$(score_section "$raw_file" "$output_file")
    printf '%s\t%s\n' "$scores" "$elapsed"
}

# ── Header ──
log_step "Section Composition Model Benchmark"
log_info "Extraction: $EXTRACTION_FILE ($(wc -w < "$EXTRACTION_FILE" | tr -d ' ') words)"
log_info "Testing ${#MODELS[@]} models × ${#TEST_TOPICS[@]} topics = $((${#MODELS[@]} * ${#TEST_TOPICS[@]})) generations"
log_info "Results: $RESULTS_FILE"
echo ""

# Write TSV header
echo -e "model\ttopic\tpreamble_pct\twords\thas_heading\thas_quote\thas_attribution\thas_separator\tleaked_planning\tquality_score\telapsed_s" > "$RESULTS_FILE"

# ── Run benchmark ──
for model in "${MODELS[@]}"; do
    log_step "Testing: $model"

    MODEL_DIR="$BENCH_DIR/$model"
    mkdir -p "$MODEL_DIR"

    # Warm up model (load into VRAM)
    log_info "Loading model..."
    curl -s -o /dev/null -X POST "$OLLAMA_API" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model\",\"prompt\":\"hi\",\"stream\":false,\"options\":{\"num_predict\":1}}" \
        --max-time 120
    log_ok "Model loaded"

    topic_num=0
    total_quality=0
    total_words=0
    total_time=0

    for topic in "${TEST_TOPICS[@]}"; do
        topic_num=$((topic_num + 1))
        topic_short="${topic:0:50}"
        [ ${#topic} -gt 50 ] && topic_short="${topic_short}..."

        printf "  Topic %d/3: %-55s" "$topic_num" "\"$topic_short\""

        result=$(generate_section "$model" "$topic" "$topic_num" "$MODEL_DIR")

        if echo "$result" | grep -q "^FAIL\|^EMPTY"; then
            printf " ${RED}FAILED${NC}\n"
            echo -e "${model}\t${topic}\t${result}" >> "$RESULTS_FILE"
            continue
        fi

        # Parse result fields
        preamble_pct=$(echo "$result" | cut -f1)
        words=$(echo "$result" | cut -f2)
        has_heading=$(echo "$result" | cut -f3)
        has_quote=$(echo "$result" | cut -f4)
        has_attr=$(echo "$result" | cut -f5)
        has_sep=$(echo "$result" | cut -f6)
        leaked=$(echo "$result" | cut -f7)
        quality=$(echo "$result" | cut -f8)
        elapsed=$(echo "$result" | cut -f9)

        total_quality=$(python3 -c "print($total_quality + $quality)")
        total_words=$((total_words + words))
        total_time=$((total_time + elapsed))

        # Status indicators
        indicators=""
        [ "$has_heading" = "1" ] && indicators+="H" || indicators+="."
        [ "$has_quote" = "1" ] && indicators+="Q" || indicators+="."
        [ "$has_attr" = "1" ] && indicators+="A" || indicators+="."
        [ "$has_sep" = "1" ] && indicators+="S" || indicators+="."
        [ "$leaked" = "0" ] && indicators+="${GREEN}✓${NC}" || indicators+="${RED}L${leaked}${NC}"

        printf " [${indicators}] %4d words  %3.0f%% preamble  Q:%-5s  %ds\n" \
            "$words" "$preamble_pct" "$quality" "$elapsed"

        echo -e "${model}\t${topic}\t${result}" >> "$RESULTS_FILE"
    done

    avg_quality=$(python3 -c "print(round($total_quality / 3, 1))")
    avg_words=$((total_words / 3))

    log_ok "Average: quality=$avg_quality/100  words=$avg_words  time=${total_time}s total"
done

# ── Summary ──
log_step "Final Rankings"

python3 - "$RESULTS_FILE" << 'PYEOF'
import sys, csv

results_file = sys.argv[1]

models = {}
with open(results_file, newline='') as f:
    reader = csv.DictReader(f, delimiter='\t')
    for row in reader:
        model = row['model']
        if model not in models:
            models[model] = {'scores': [], 'words': [], 'times': [], 'preambles': [], 'leaked': []}
        try:
            models[model]['scores'].append(float(row['quality_score']))
            models[model]['words'].append(int(row['words']))
            models[model]['times'].append(int(row['elapsed_s']))
            models[model]['preambles'].append(float(row['preamble_pct']))
            models[model]['leaked'].append(int(row['leaked_planning']))
        except (ValueError, KeyError):
            pass

# Rank by average quality score
ranked = []
for model, data in models.items():
    if not data['scores']:
        continue
    avg_score = sum(data['scores']) / len(data['scores'])
    avg_words = sum(data['words']) // len(data['words'])
    avg_time = sum(data['times']) // len(data['times'])
    avg_preamble = sum(data['preambles']) / len(data['preambles'])
    total_leaked = sum(data['leaked'])
    ranked.append((model, avg_score, avg_words, avg_time, avg_preamble, total_leaked))

ranked.sort(key=lambda x: x[1], reverse=True)

print(f"\n{'Rank':<5} {'Model':<35} {'Score':>6} {'Words':>6} {'Time':>5} {'Preamble':>9} {'Leaked':>7}")
print("-" * 80)
for i, (model, score, words, time, preamble, leaked) in enumerate(ranked, 1):
    marker = " ← BEST" if i == 1 else ""
    leak_str = f"{leaked}/3" if leaked > 0 else "0/3"
    print(f"{i:<5} {model:<35} {score:>5.1f} {words:>5}w {time:>4}s {preamble:>7.1f}% {leak_str:>6}{marker}")

if ranked:
    best = ranked[0]
    print(f"\n★ RECOMMENDED: {best[0]}")
    print(f"  Score: {best[1]:.1f}/100  |  Avg words: {best[2]}  |  Avg time: {best[3]}s  |  Preamble waste: {best[4]:.1f}%")
PYEOF

echo ""
log_ok "Raw results: $RESULTS_FILE"
log_ok "Section outputs: $BENCH_DIR/<model>/section-*.md"
