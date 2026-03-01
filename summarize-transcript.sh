#!/usr/bin/env bash
#
# summarize-transcript.sh — Four-pass transcript summarization pipeline
#
# Pass 1: c_qwen3-30b-a3b-200k (MoE, extraction — 23.8 tok/s)
# Pass 2: c_lfm2-24b-a2b-32k (hybrid MoE, composition — 67 tok/s, strong structure + 2.7× faster)
# Pass 3-4: c_qwen3-14b-40k (dense, review — perfect structure, zero planning waste)
#
# Usage:
#   ./summarize-transcript.sh <transcript-file> [title] [channel] [url] [duration]
#
# The transcript file may optionally contain a YAML-style header block:
#   ---
#   title: Video Title
#   channel: Channel Name
#   url: https://...
#   duration: HH:MM:SS
#   ---

# ── Configuration ──────────────────────────────────────────────────────────
# Best model per role — two model swaps: extraction → composition → review
# Pass 1: qwen3-30b MoE for extraction (23.8 tok/s, reliable instruction following)
# Pass 2: lfm2-24b hybrid MoE for composition (67 tok/s, scored 8.9/10 — best speed/quality ratio)
# Pass 3-4: qwen3-14b dense for review (perfect structure, zero planning waste)
EXTRACT_MODEL="c_qwen3-30b-a3b-200k"
COMPOSE_MODEL="c_lfm2-24b-a2b-32k"
REVIEW_MODEL="c_qwen3-14b-40k"
OLLAMA_API="http://localhost:11434/api/generate"
SUMMARY_DIR="$HOME/summaries"
TEMP_DIR="/tmp/summarize-pipeline"

# Token limits per pass (prevents runaway generation)
PASS1_MAX_TOKENS=8192
PASS2_HEADER_MAX_TOKENS=2048
PASS2_SECTION_MAX_TOKENS=3072
PASS2_LINKS_MAX_TOKENS=512

# ── Color helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
log_success() { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
log_warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
log_error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
log_step()    { printf "\n${BOLD}${CYAN}━━━ %s ━━━${NC}\n" "$*"; }

# ── Elapsed time formatter ─────────────────────────────────────────────────
fmt_elapsed() {
    local secs=$1
    local mins=$((secs / 60))
    local rem=$((secs % 60))
    if [ "$mins" -gt 0 ]; then
        printf "%dm %ds" "$mins" "$rem"
    else
        printf "%ds" "$rem"
    fi
}

# ── Helper: Build JSON and call Ollama API ─────────────────────────────────
# Args: $1=model $2=prompt_file $3=output_file $4=num_predict $5=temperature $6=max_time $7=think(true/false) $8=skip_degen(true/false)
ollama_generate() {
    local model="$1"
    local prompt_file="$2"
    local output_file="$3"
    local num_predict="$4"
    local temperature="$5"
    local max_time="$6"
    local think="${7:-false}"
    local skip_degen="${8:-false}"
    local raw_file="${output_file}.raw"

    # Use python3 to build proper JSON (handles escaping of large text)
    python3 -c "
import json, sys
with open('${prompt_file}', 'r') as f:
    prompt = f.read()
think_val = '${think}' == 'true'
payload = {
    'model': '${model}',
    'prompt': prompt,
    'stream': False,
    'think': think_val,
    'options': {
        'num_predict': ${num_predict},
        'temperature': ${temperature}
    }
}
json.dump(payload, sys.stdout)
" > "${raw_file}.request"

    # Call Ollama API
    local http_code
    http_code=$(curl -s -w '%{http_code}' -o "$raw_file" \
        -X POST "$OLLAMA_API" \
        -H "Content-Type: application/json" \
        -d @"${raw_file}.request" \
        --max-time "$max_time")

    if [ "$http_code" != "200" ] || [ ! -s "$raw_file" ]; then
        log_error "Ollama API call failed (HTTP $http_code)."
        return 1
    fi

    # Extract response text from JSON, clean up degenerate output
    python3 -c "
import json, sys, re

with open('${raw_file}', 'r') as f:
    data = json.load(f)
text = data.get('response', '')
if not text.strip() and data.get('thinking', '').strip():
    text = data['thinking']

# Strip leaked <think>...</think> blocks (also handles missing opening tag)
text = re.sub(r'<think>.*?</think>\s*', '', text, flags=re.DOTALL)
text = re.sub(r'^.*?</think>\s*', '', text, flags=re.DOTALL)

# Robust preamble cleanup: extract YAML + find content start
# Step 1: Extract YAML frontmatter (--- ... ---)
yaml_block = ''
yaml_match = re.search(r'^---\n(?:.*?\n)?---[ \t]*$', text, re.MULTILINE | re.DOTALL)
if yaml_match:
    yaml_block = yaml_match.group(0) + '\n\n'

# Step 2: Find content start — first '###### Channel' or '## Key Takeaways' AFTER yaml
search_from = yaml_match.end() if yaml_match else 0
content_start = re.search(r'^(?:###### Channel|## Key Takeaways)', text[search_from:], re.MULTILINE)
if content_start:
    text = yaml_block + text[search_from + content_start.start():]
else:
    # Fallback: strip to first heading (works for section outputs with no YAML too)
    heading = re.search(r'^#{1,6}\s', text[search_from:], re.MULTILINE)
    if heading:
        text = yaml_block + text[search_from + heading.start():]
    else:
        # Last resort: strip to first markdown content (bold bullet, blockquote, or ---  separator)
        content = re.search(r'^(?:- \*\*|> |---\s*$)', text[search_from:], re.MULTILINE)
        if content:
            text = yaml_block + text[search_from + content.start():]

# Detect degenerate output: planning loops produce many near-duplicate lines
# If unique-line ratio is very low (< 30%), output is garbage
# Skip for structured outputs (validation reports have repetitive format by design)
if '${skip_degen}' != 'true':
    non_empty = [re.sub(r'\s+', ' ', l.strip().lower()) for l in text.split('\n') if l.strip()]
    if len(non_empty) > 20:
        unique_ratio = len(set(non_empty)) / len(non_empty)
        if unique_ratio < 0.3:
            sys.stderr.write(f'DEGENERATE: only {unique_ratio:.0%} unique lines ({len(set(non_empty))}/{len(non_empty)})\n')
            sys.exit(1)

# Remove degenerate repetitions (fuzzy: normalize whitespace before comparing)
lines = text.rstrip().split('\n')
cleaned = []
repeat_count = 0
prev_norm = None
for line in lines:
    # Normalize for comparison: lowercase, strip, collapse whitespace
    norm = re.sub(r'\s+', ' ', line.strip().lower())
    if norm == prev_norm and len(norm) < 80:
        repeat_count += 1
        if repeat_count >= 2:
            continue  # Skip 3rd+ consecutive duplicate
    else:
        repeat_count = 0
    cleaned.append(line)
    prev_norm = norm

print('\n'.join(cleaned))
" > "$output_file" 2>"${output_file}.log"

    if [ ! -s "$output_file" ]; then
        if grep -q "DEGENERATE" "${output_file}.log" 2>/dev/null; then
            log_error "Model produced degenerate output (planning loop / no markdown). Check raw: $raw_file"
        else
            log_error "Model produced empty output after cleanup."
        fi
        return 1
    fi

    return 0
}

# ── Argument parsing ──────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    echo "Usage: $0 <transcript-file> [title] [channel] [url] [duration]"
    echo ""
    echo "Arguments:"
    echo "  transcript-file   Path to the transcript text file"
    echo "  title             (optional) Video/content title"
    echo "  channel           (optional) Channel or author name"
    echo "  url               (optional) Source URL"
    echo "  duration          (optional) Duration (e.g., 00:48:37)"
    echo ""
    echo "You can also embed metadata in the file with a YAML header block."
    exit 1
fi

TRANSCRIPT_FILE="$1"
ARG_TITLE="${2:-}"
ARG_CHANNEL="${3:-}"
ARG_URL="${4:-}"
ARG_DURATION="${5:-}"

# ── Validate input file ──────────────────────────────────────────────────
if [ ! -f "$TRANSCRIPT_FILE" ]; then
    log_error "Transcript file not found: $TRANSCRIPT_FILE"
    exit 1
fi

if [ ! -s "$TRANSCRIPT_FILE" ]; then
    log_error "Transcript file is empty: $TRANSCRIPT_FILE"
    exit 1
fi

# ── Check dependencies ───────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    log_error "python3 is required but not found."
    exit 1
fi

if ! command -v curl &>/dev/null; then
    log_error "curl is required but not found."
    exit 1
fi

# ── Check that models are available ───────────────────────────────────────
log_step "Preflight Checks"

log_info "Checking model availability..."

AVAILABLE_MODELS="$(ollama list 2>&1 || true)"

if ! echo "$AVAILABLE_MODELS" | grep -q "$EXTRACT_MODEL"; then
    log_error "Extract model '$EXTRACT_MODEL' not found. Run: ollama list"
    exit 1
fi
log_success "Extract model ready: $EXTRACT_MODEL"

if [ "$COMPOSE_MODEL" != "$EXTRACT_MODEL" ]; then
    if ! echo "$AVAILABLE_MODELS" | grep -q "$COMPOSE_MODEL"; then
        log_error "Compose model '$COMPOSE_MODEL' not found. Run: ollama list"
        exit 1
    fi
    log_success "Compose model ready: $COMPOSE_MODEL"
fi

if ! echo "$AVAILABLE_MODELS" | grep -q "$REVIEW_MODEL"; then
    log_error "Review model '$REVIEW_MODEL' not found. Run: ollama list"
    exit 1
fi
log_success "Review model ready: $REVIEW_MODEL"

# Check Ollama API is responding
if ! curl -s --max-time 5 "$OLLAMA_API" -X POST -d '{"model":"'$EXTRACT_MODEL'","prompt":"hi","stream":false,"options":{"num_predict":1}}' -H "Content-Type: application/json" -o /dev/null; then
    log_warn "Ollama API at $OLLAMA_API may not be responding. Proceeding anyway..."
fi
log_success "Ollama API reachable"

# ── Parse metadata from arguments or file header ─────────────────────────
TITLE="$ARG_TITLE"
CHANNEL="$ARG_CHANNEL"
URL="$ARG_URL"
DURATION="$ARG_DURATION"

# Try to parse YAML-style header if present and args not given
FIRST_LINE="$(head -1 "$TRANSCRIPT_FILE")"
if echo "$FIRST_LINE" | grep -q '^---'; then
    HEADER_BLOCK="$(sed -n '2,/^---$/p' "$TRANSCRIPT_FILE" | head -n -1)"
    if [ -n "$HEADER_BLOCK" ]; then
        [ -z "$TITLE" ]    && TITLE="$(echo "$HEADER_BLOCK" | grep -i '^title:' | sed 's/^[Tt]itle:[[:space:]]*//' | head -1)"
        [ -z "$CHANNEL" ]  && CHANNEL="$(echo "$HEADER_BLOCK" | grep -i '^channel:' | sed 's/^[Cc]hannel:[[:space:]]*//' | head -1)"
        [ -z "$URL" ]      && URL="$(echo "$HEADER_BLOCK" | grep -i '^url:' | sed 's/^[Uu]rl:[[:space:]]*//' | head -1)"
        [ -z "$DURATION" ] && DURATION="$(echo "$HEADER_BLOCK" | grep -i '^duration:' | sed 's/^[Dd]uration:[[:space:]]*//' | head -1)"
    fi
fi

# Defaults
[ -z "$TITLE" ]    && TITLE="Untitled Transcript"
[ -z "$CHANNEL" ]  && CHANNEL="Unknown"
[ -z "$URL" ]      && URL="N/A"
[ -z "$DURATION" ] && DURATION="Unknown"

# ── Prepare output paths ─────────────────────────────────────────────────
mkdir -p "$SUMMARY_DIR" "$TEMP_DIR"

BASENAME="$(basename "$TRANSCRIPT_FILE" | sed 's/\.[^.]*$//')"
EXTRACTION_FILE="$TEMP_DIR/${BASENAME}-extraction.txt"
SUMMARY_FILE="$SUMMARY_DIR/${BASENAME}-summary.md"
PASS1_PROMPT_FILE="$TEMP_DIR/${BASENAME}-pass1-prompt.txt"

WORD_COUNT=$(wc -w < "$TRANSCRIPT_FILE" | tr -d ' ')

log_info "Transcript: $TRANSCRIPT_FILE"
log_info "Word count: $WORD_COUNT words"
log_info "Title: $TITLE"
log_info "Channel: $CHANNEL"
log_info "Extraction output: $EXTRACTION_FILE"
log_info "Summary output: $SUMMARY_FILE"

# ── PASS 1: Extraction (thinking model) ─────────────────────────────────
log_step "PASS 1: Extraction — $EXTRACT_MODEL"
log_info "Feeding full transcript for comprehensive extraction..."
log_info "Max tokens: $PASS1_MAX_TOKENS"

PASS1_START=$(date +%s)

# Build pass 1 prompt file
cat > "$PASS1_PROMPT_FILE" <<'PROMPT_HEADER'
You are an expert research assistant performing a comprehensive extraction pass on a transcript. Your job is NOT to summarize — it is to EXTRACT every piece of valuable information so that another AI can compose a polished summary from your output.

CRITICAL: Extract ONLY what is explicitly stated in the transcript. Do NOT infer, explain, editorialize, or add context that is not present. If a category has no relevant content, write "None identified" and move on.

Use this EXACT markdown format:

## SPEAKERS
- [Name] — [role/background as stated in transcript]

## CHRONOLOGICAL OUTLINE
1. [First topic/segment] — [brief description]
2. [Next topic] — [brief description]
[Continue for all major topic shifts]

## CLAIMS AND ARGUMENTS
- **Claim**: "[claim as stated]" — **Evidence/reasoning**: "[supporting detail]" — **Speaker**: [name]
[One bullet per distinct claim]

## SPECIFIC DETAILS
**People mentioned**: [Name (who they are/context)]
**Numbers/costs/dates**: [Stat — context]
**Tools/technologies**: [Name — how used or referenced]
**Projects/organizations**: [Name — context]

## DIRECT QUOTES
> "[Exact verbatim quote]" — [Speaker name]
[8-15 of the most impactful, memorable, or quotable statements]

## STRUCTURED DATA
[Any comparisons, frameworks, hierarchies, levels, or pricing discussed — preserve the structure]

## RECOMMENDATIONS AND RESOURCES
- [Advice or resource] — [Speaker] — [context]

## ENTITY CHECKLIST
**All people**: [comma-separated list of every person named]
**All tools/platforms**: [comma-separated list]
**All costs/numbers**: [comma-separated list of every specific number mentioned]

When you have extracted everything, STOP. Do not repeat yourself or add filler.

Here is the transcript:

PROMPT_HEADER

# Append transcript
cat "$TRANSCRIPT_FILE" >> "$PASS1_PROMPT_FILE"

# Run pass 1 without thinking — extraction is mechanical, thinking makes it too concise
if ! ollama_generate "$EXTRACT_MODEL" "$PASS1_PROMPT_FILE" "$EXTRACTION_FILE" "$PASS1_MAX_TOKENS" "0.3" "900" "false"; then
    log_error "Pass 1 extraction failed."
    exit 1
fi

PASS1_END=$(date +%s)
PASS1_ELAPSED=$((PASS1_END - PASS1_START))

EXTRACTION_WORDS=$(wc -w < "$EXTRACTION_FILE" | tr -d ' ')
log_success "Pass 1 complete in $(fmt_elapsed $PASS1_ELAPSED)"
log_info "Extraction: $EXTRACTION_WORDS words"
log_info "Saved to: $EXTRACTION_FILE"

# ── PASS 2: Section-by-Section Composition ────────────────────────────
log_step "PASS 2: Composition — $COMPOSE_MODEL (section-by-section)"

PASS2_START=$(date +%s)

# ── Step 1: Parse topics from extraction's CHRONOLOGICAL OUTLINE ──
TOPICS_FILE="$TEMP_DIR/${BASENAME}-topics.txt"
# Extract ONLY numbered items from the CHRONOLOGICAL OUTLINE section
# Uses findall to handle preamble duplication — picks the instance with the most items
python3 -c "
import re, sys
with open('${EXTRACTION_FILE}') as f:
    text = f.read()
# Find ALL CHRONOLOGICAL OUTLINE sections, pick the one with the most numbered items
sections = re.findall(r'## CHRONOLOGICAL OUTLINE\s*\n(.*?)(?=\n## |\Z)', text, re.DOTALL)
best_items = []
for section in sections:
    items = []
    for line in section.strip().split('\n'):
        line = line.strip()
        cleaned = re.sub(r'^[0-9]+\.\s*', '', line)
        if cleaned and cleaned != line:
            items.append(cleaned)
    if len(items) > len(best_items):
        best_items = items
for item in best_items:
    print(item)
" > "${TOPICS_FILE}.raw"

# Deduplicate near-identical topics (extraction sometimes lists them twice with slight rewording)
python3 -c "
import re, sys

with open('${TOPICS_FILE}.raw') as f:
    topics = [line.strip() for line in f if line.strip()]

def normalize(t):
    t = t.lower()
    t = re.sub(r'^the\s+', '', t)
    t = re.sub(r'[^a-z0-9\s]', '', t)
    return set(t.split())

kept = []
for topic in topics:
    words = normalize(topic)
    if not words:
        continue
    is_dup = False
    for existing in kept:
        existing_words = normalize(existing)
        overlap = len(words & existing_words)
        smaller = min(len(words), len(existing_words))
        if smaller > 0 and overlap / smaller >= 0.7:
            is_dup = True
            break
    if not is_dup:
        kept.append(topic)

for t in kept:
    print(t)
" > "$TOPICS_FILE"

# ── Step 1.5: Consolidate topics into 5-9 logical sections ──
CONSOLIDATED_FILE="$TEMP_DIR/${BASENAME}-topics-consolidated.txt"
CONSOLIDATION_PROMPT_FILE="$TEMP_DIR/${BASENAME}-consolidation-prompt.txt"
CONSOLIDATION_RAW_FILE="$TEMP_DIR/${BASENAME}-consolidation-raw.txt"
RAW_TOPIC_COUNT=$(wc -l < "$TOPICS_FILE" | tr -d ' ')

log_info "Raw topics after dedup: $RAW_TOPIC_COUNT"

if [ "$RAW_TOPIC_COUNT" -gt 9 ]; then
    log_info "Consolidating $RAW_TOPIC_COUNT topics into 5-9 sections..."

    cat > "$CONSOLIDATION_PROMPT_FILE" <<CONSOL_END
You have ${RAW_TOPIC_COUNT} topics extracted from a transcript. Group them into 5-9 logical sections that would make sense as chapters in a summary article. Combine closely related topics into a single section.

For each group, write a descriptive section title and list which original topics it covers.

Output ONLY numbered items in this exact format (no other text):
1. [Section Title] — covers: [topic a], [topic b]
2. [Section Title] — covers: [topic a], [topic b], [topic c]

TOPICS:
$(cat "$TOPICS_FILE" | nl -ba -s '. ')

CONSOL_END

    if ollama_generate "$COMPOSE_MODEL" "$CONSOLIDATION_PROMPT_FILE" "$CONSOLIDATION_RAW_FILE" 1024 "0.4" "300" "false"; then
        # Parse consolidated output: extract section title and subtopics
        python3 -c "
import re, sys

with open('${CONSOLIDATION_RAW_FILE}') as f:
    text = f.read()

sections = []
for match in re.finditer(r'^\d+\.\s*(.+?)\s*—\s*covers?:\s*(.+)$', text, re.MULTILINE):
    title = match.group(1).strip()
    subtopics = match.group(2).strip()
    sections.append(f'{title}\t{subtopics}')

if 3 <= len(sections) <= 12:
    for s in sections:
        print(s)
else:
    sys.exit(1)
" > "$CONSOLIDATED_FILE" 2>/dev/null

        if [ $? -eq 0 ] && [ -s "$CONSOLIDATED_FILE" ]; then
            CONSOL_COUNT=$(wc -l < "$CONSOLIDATED_FILE" | tr -d ' ')
            log_success "Consolidated $RAW_TOPIC_COUNT topics → $CONSOL_COUNT sections"
            cp "$CONSOLIDATED_FILE" "$TOPICS_FILE"
            TOPICS_CONSOLIDATED=true
        else
            log_warn "Consolidation output unparseable — using original $RAW_TOPIC_COUNT topics"
            TOPICS_CONSOLIDATED=false
        fi
    else
        log_warn "Consolidation call failed — using original $RAW_TOPIC_COUNT topics"
        TOPICS_CONSOLIDATED=false
    fi
else
    log_info "Only $RAW_TOPIC_COUNT topics — skipping consolidation"
    TOPICS_CONSOLIDATED=false
fi

TOPIC_COUNT=$(wc -l < "$TOPICS_FILE" | tr -d ' ')

if [ "$TOPIC_COUNT" -lt 3 ]; then
    log_error "Only $TOPIC_COUNT topics found in extraction — expected 5+. Check extraction quality."
    exit 1
fi

log_info "Found $TOPIC_COUNT topics for composition"
log_info "Generating: 1 header + $TOPIC_COUNT sections + 1 related links = $((TOPIC_COUNT + 2)) API calls"

# Working files for assembly
PASS2_HEADER_FILE="$TEMP_DIR/${BASENAME}-p2-header.md"
PASS2_SECTIONS_DIR="$TEMP_DIR/${BASENAME}-sections"
PASS2_LINKS_FILE="$TEMP_DIR/${BASENAME}-p2-links.md"
USED_QUOTES_FILE="$TEMP_DIR/${BASENAME}-used-quotes.txt"

# Clean any leftover sections from previous runs, then create fresh
rm -rf "$PASS2_SECTIONS_DIR"
mkdir -p "$PASS2_SECTIONS_DIR"
> "$USED_QUOTES_FILE"

# ── Step 2: Generate Key Takeaways (one call) ──
log_info "Generating Key Takeaways..."

HEADER_PROMPT_FILE="$TEMP_DIR/${BASENAME}-p2-header-prompt.txt"
cat > "$HEADER_PROMPT_FILE" <<'HEADER_PROMPT_END'
You are an expert technical writer. Write ONLY a "## Key Takeaways" section with 4-5 bold bullet points summarizing the most important insights from the extraction below.

FORMAT:
## Key Takeaways
- **[Bold insight title]** — [1-2 sentence explanation with speaker attribution]
- **[Bold insight title]** — [1-2 sentence explanation with speaker attribution]
[4-5 bullets total]

---

Start IMMEDIATELY with "## Key Takeaways". No preamble. Use ONLY facts from the extraction.

EXTRACTION:

HEADER_PROMPT_END

cat "$EXTRACTION_FILE" >> "$HEADER_PROMPT_FILE"

HEADER_START=$(date +%s)

if ! ollama_generate "$COMPOSE_MODEL" "$HEADER_PROMPT_FILE" "$PASS2_HEADER_FILE" "$PASS2_HEADER_MAX_TOKENS" "0.6" "300" "false"; then
    log_error "Pass 2 header generation failed."
    exit 1
fi

HEADER_END=$(date +%s)
HEADER_WORDS=$(wc -w < "$PASS2_HEADER_FILE" | tr -d ' ')
log_success "Key Takeaways: $HEADER_WORDS words ($(fmt_elapsed $((HEADER_END - HEADER_START))))"

# ── Step 3: Generate each section (one call per topic) ──
SECTION_NUM=0

while IFS= read -r TOPIC_TEXT; do
    SECTION_NUM=$((SECTION_NUM + 1))
    SECTION_PROMPT_FILE="$TEMP_DIR/${BASENAME}-p2-section-${SECTION_NUM}-prompt.txt"
    SECTION_OUTPUT_FILE="$PASS2_SECTIONS_DIR/section-$(printf '%02d' $SECTION_NUM).md"

    # Build used-quotes exclusion block
    USED_QUOTES_BLOCK=""
    if [ -s "$USED_QUOTES_FILE" ]; then
        USED_QUOTES_BLOCK="

Do NOT use these quotes (already used in earlier sections):
$(cat "$USED_QUOTES_FILE")"
    fi

    # Parse topic line — may be consolidated (tab-delimited) or plain
    if [[ "$TOPIC_TEXT" == *$'\t'* ]]; then
        SECTION_TITLE="${TOPIC_TEXT%%$'\t'*}"
        SUBTOPICS="${TOPIC_TEXT#*$'\t'}"
        # Scale word budget: 400 base + 150 per subtopic, cap 900
        SUBTOPIC_COUNT=$(echo "$SUBTOPICS" | tr ',' '\n' | wc -l | tr -d ' ')
        WORD_BUDGET=$((400 + 150 * SUBTOPIC_COUNT))
        [ "$WORD_BUDGET" -gt 900 ] && WORD_BUDGET=900
        TOPIC_BLOCK="Write ONE section covering these related topics:
\"${SECTION_TITLE}\"
Subtopics to cover: ${SUBTOPICS}"
    else
        SECTION_TITLE="$TOPIC_TEXT"
        WORD_BUDGET=500
        TOPIC_BLOCK="Write ONE section of an Obsidian knowledge base article about this specific topic:
\"${SECTION_TITLE}\""
    fi

    # Scale tokens: ~1.5 tokens per word + buffer for formatting
    SECTION_TOKENS=$((WORD_BUDGET * 3))
    [ "$SECTION_TOKENS" -gt "$PASS2_SECTION_MAX_TOKENS" ] && SECTION_TOKENS="$PASS2_SECTION_MAX_TOKENS"

    cat > "$SECTION_PROMPT_FILE" <<SECTION_PROMPT_END
${TOPIC_BLOCK}

Include:
- A descriptive ## heading (use a specific name, NOT the outline text verbatim)
- One > [!quote] callout with a verbatim quote from the DIRECT QUOTES section
- 3-4 detailed paragraphs with speaker attribution ("Daniel explained...", "Clint noted...")
- A --- separator at the end

Write around ${WORD_BUDGET} words. Use ONLY facts from the extraction below. Do NOT cover other topics. Start IMMEDIATELY with the ## heading.${USED_QUOTES_BLOCK}

EXTRACTION:

SECTION_PROMPT_END

    cat "$EXTRACTION_FILE" >> "$SECTION_PROMPT_FILE"

    SEC_START=$(date +%s)

    if ! ollama_generate "$COMPOSE_MODEL" "$SECTION_PROMPT_FILE" "$SECTION_OUTPUT_FILE" "$SECTION_TOKENS" "0.6" "300" "false"; then
        log_warn "Section $SECTION_NUM/$TOPIC_COUNT failed: \"$TOPIC_TEXT\" — skipping"
        continue
    fi

    SEC_END=$(date +%s)
    SEC_ELAPSED=$((SEC_END - SEC_START))
    SEC_WORDS=$(wc -w < "$SECTION_OUTPUT_FILE" | tr -d ' ')

    # Extract used quote for deduplication
    grep -oP '> \[!quote\]\s*\K"[^"]+"' "$SECTION_OUTPUT_FILE" >> "$USED_QUOTES_FILE" 2>/dev/null || true
    # Also catch bare quotes that post-processing will convert
    grep -oP '^> \K"[^"]+"' "$SECTION_OUTPUT_FILE" >> "$USED_QUOTES_FILE" 2>/dev/null || true

    # Truncate topic for display (use section title, not full subtopic line)
    TOPIC_DISPLAY="${SECTION_TITLE}"
    [ ${#TOPIC_DISPLAY} -gt 60 ] && TOPIC_DISPLAY="${TOPIC_DISPLAY:0:57}..."

    log_success "Section $SECTION_NUM/$TOPIC_COUNT: \"$TOPIC_DISPLAY\" — $SEC_WORDS words (${SEC_ELAPSED}s)"

done < "$TOPICS_FILE"

# ── Step 4: Generate Related Links (one call) ──
log_info "Generating Related Links..."

LINKS_PROMPT_FILE="$TEMP_DIR/${BASENAME}-p2-links-prompt.txt"
cat > "$LINKS_PROMPT_FILE" <<'LINKS_PROMPT_END'
Write a ## Related Links section with 5-8 Obsidian [[wiki-link]] tags based on the key topics, tools, people, and concepts in this extraction.

FORMAT:
## Related Links
- [[Topic or Tool Name]]
- [[Person Name]]
[5-8 links total]

Start IMMEDIATELY with "## Related Links". No preamble.

EXTRACTION:

LINKS_PROMPT_END

cat "$EXTRACTION_FILE" >> "$LINKS_PROMPT_FILE"

LINKS_START=$(date +%s)

if ! ollama_generate "$COMPOSE_MODEL" "$LINKS_PROMPT_FILE" "$PASS2_LINKS_FILE" "$PASS2_LINKS_MAX_TOKENS" "0.6" "120" "false"; then
    log_warn "Related Links generation failed — using placeholder"
    echo "## Related Links" > "$PASS2_LINKS_FILE"
    echo "- [[$(echo "$TITLE" | sed 's/ /_/g')]]" >> "$PASS2_LINKS_FILE"
fi

LINKS_END=$(date +%s)
log_success "Related Links generated ($(fmt_elapsed $((LINKS_END - LINKS_START))))"

# ── Step 5: Assemble final summary ──
log_info "Assembling final summary..."

CREATED_DATE=$(date -Iseconds)

# Write YAML frontmatter + metadata header (static, built in bash)
cat > "$SUMMARY_FILE" <<ASSEMBLY_HEADER
---
title: "$TITLE"
created: $CREATED_DATE
channel: "$CHANNEL"
source: "$URL"
---

###### Channel: $CHANNEL
###### Video Link: $URL
###### Duration: $DURATION

---

ASSEMBLY_HEADER

# Append Key Takeaways
cat "$PASS2_HEADER_FILE" >> "$SUMMARY_FILE"

# Append all sections in order
for SECTION_FILE in "$PASS2_SECTIONS_DIR"/section-*.md; do
    [ -f "$SECTION_FILE" ] && cat "$SECTION_FILE" >> "$SUMMARY_FILE"
done

# Append Related Links
printf "\n" >> "$SUMMARY_FILE"
cat "$PASS2_LINKS_FILE" >> "$SUMMARY_FILE"

# ── Step 6: Post-processing (same as before) ──
python3 -c "
import re

with open('${SUMMARY_FILE}') as f:
    text = f.read()

# Fix doubled heading markers: '## ## Topic' or '## ## Topic:' → '## Topic'
text = re.sub(r'^## ## (.+?)(?::?\s*)$', r'## \1', text, flags=re.MULTILINE)

# Fix heading format: '## Topic Name:' trailing colon → '## Topic Name'
text = re.sub(r'^(## .+):$', r'\1', text, flags=re.MULTILINE)

# Fix metadata heading levels: '## Channel:' → '###### Channel:' etc.
text = re.sub(r'^## (Channel:.*)$', r'###### \1', text, flags=re.MULTILINE)
text = re.sub(r'^## (Video Link:.*)$', r'###### \1', text, flags=re.MULTILINE)
text = re.sub(r'^## (Duration:.*)$', r'###### \1', text, flags=re.MULTILINE)

# Convert bare blockquotes to [!quote] callouts: '> \"text\"' → '> [!quote] \"text\"'
text = re.sub(r'^> \"', '> [!quote] \"', text, flags=re.MULTILINE)

# Remove extraction-copy sections (ALL-CAPS headings from extraction format)
text = re.sub(r'\n---\s*\n\s*## (?:SPEAKERS|SPECIFIC DETAILS|STRUCTURED DATA|RECOMMENDATIONS AND RESOURCES|CHRONOLOGICAL OUTLINE|CLAIMS AND ARGUMENTS|DIRECT QUOTES|ENTITY CHECKLIST)\b.*?(?=\n---\s*\n\s*## |\n## Related Links|\Z)', '', text, flags=re.DOTALL)

# Strip non-quote callout types (tip, important, note, etc.) — keep only > [!quote]
text = re.sub(r'^> \[!(?!quote\])(\w+)\].*(?:\n> .*)*', '', text, flags=re.MULTILINE)

with open('${SUMMARY_FILE}', 'w') as f:
    f.write(text)
" 2>/dev/null || true

# ── Step 7: Timing & reporting ──
PASS2_END=$(date +%s)
PASS2_ELAPSED=$((PASS2_END - PASS2_START))

SUMMARY_WORDS=$(wc -w < "$SUMMARY_FILE" | tr -d ' ')
SECTIONS_GENERATED=$(ls "$PASS2_SECTIONS_DIR"/section-*.md 2>/dev/null | wc -l | tr -d ' ')

log_success "Pass 2 complete in $(fmt_elapsed $PASS2_ELAPSED)"
log_info "Summary: $SUMMARY_WORDS words across $SECTIONS_GENERATED sections"
log_info "Saved to: $SUMMARY_FILE"

# ── PASS 3: Gap fill (same model, no swap) ──────────────────────────────
# Compare extraction against summary draft and write sections for missed topics
log_step "PASS 3: Gap Fill — $REVIEW_MODEL"

PASS3_START=$(date +%s)
PASS3_PROMPT_FILE="$TEMP_DIR/${BASENAME}-pass3-prompt.txt"
GAPFILL_FILE="$TEMP_DIR/${BASENAME}-gapfill.md"

cat > "$PASS3_PROMPT_FILE" <<'PASS3_HEADER'
You are a quality reviewer. Compare the EXTRACTION against the SUMMARY DRAFT below.

Your job: Find 1-3 MAJOR topics from the EXTRACTION that have substantial content (multiple bullet points or paragraphs) but are completely MISSING from the SUMMARY DRAFT. Write new sections ONLY for these gaps.

STRICT RULES:
- A "gap" is a topic with SUBSTANTIAL content in the extraction (3+ bullet points or a whole subsection) that has NO corresponding ## section in the draft.
- If a topic already has a ## section in the draft — even if briefly covered — it is NOT a gap. Skip it.
- Write at most 3 new sections. Each section: ## heading, one > [!quote] callout, 2-3 paragraphs, --- separator.
- Do NOT invent information. Only use details from the EXTRACTION.
- Do NOT rewrite, expand, or repeat content already in the draft.
- Do NOT add a Related Links section.
- If no major gaps exist, write only: "NO GAPS FOUND"
- Start writing sections IMMEDIATELY. No planning, no preamble.

=== EXTRACTION ===

PASS3_HEADER

cat "$EXTRACTION_FILE" >> "$PASS3_PROMPT_FILE"

cat >> "$PASS3_PROMPT_FILE" <<'PASS3_MID'

=== SUMMARY DRAFT ===

PASS3_MID

cat "$SUMMARY_FILE" >> "$PASS3_PROMPT_FILE"

cat >> "$PASS3_PROMPT_FILE" <<'PASS3_FOOTER'

=== END ===

Now write the missing sections. Remember: ONLY topics not covered in the draft.
PASS3_FOOTER

log_info "Checking for coverage gaps..."

if ! ollama_generate "$REVIEW_MODEL" "$PASS3_PROMPT_FILE" "$GAPFILL_FILE" "2048" "0.5" "600" "false"; then
    log_warn "Pass 3 gap fill failed. Proceeding with draft as-is."
else
    GAPFILL_WORDS=$(wc -w < "$GAPFILL_FILE" | tr -d ' ')

    if ! grep -qi "NO GAPS FOUND" "$GAPFILL_FILE" && [ "$GAPFILL_WORDS" -gt 50 ]; then
        # Strip Related Links and meta-commentary from gap fill
        python3 -c "
import re, sys
with open('${GAPFILL_FILE}') as f:
    text = f.read()
text = re.sub(r'\n## Related Links.*', '', text, flags=re.DOTALL)
# Remove extraction-copy sections (ALL-CAPS headings the model copies from extraction)
text = re.sub(r'## (?:SPEAKERS|SPECIFIC DETAILS|STRUCTURED DATA|RECOMMENDATIONS AND RESOURCES|CHRONOLOGICAL OUTLINE|CLAIMS AND ARGUMENTS|DIRECT QUOTES|ENTITY CHECKLIST)\b.*?(?=\n## |\Z)', '', text, flags=re.DOTALL)
# Remove meta-commentary about the draft
text = re.sub(r'[^\n]*(?:SUMMARY DRAFT|summary draft|draft\'s|DRAFT)[^\n]*\n?', '', text)
text = re.sub(r'[^\n]*(?:missing from|omission of|fails to mention)[^\n]*\n?', '', text, flags=re.IGNORECASE)
print(text.rstrip())
" > "${GAPFILL_FILE}.clean"

        # Insert gap-fill sections before the Related Links in the summary
        python3 -c "
import re
with open('${SUMMARY_FILE}') as f:
    summary = f.read()
with open('${GAPFILL_FILE}.clean') as f:
    gapfill = f.read()
# Find the Related Links section and insert gap fill before it
match = re.search(r'\n---\s*\n\s*## Related Links', summary)
if match:
    merged = summary[:match.start()] + '\n\n---\n\n' + gapfill.strip() + summary[match.start():]
else:
    merged = summary.rstrip() + '\n\n---\n\n' + gapfill.strip()
print(merged)
" > "${SUMMARY_FILE}.merged"
        mv "${SUMMARY_FILE}.merged" "$SUMMARY_FILE"

        log_success "Pass 3 added $GAPFILL_WORDS words of gap-fill content"
    else
        log_info "No significant gaps found — draft is comprehensive"
    fi
fi

PASS3_END=$(date +%s)
PASS3_ELAPSED=$((PASS3_END - PASS3_START))
SUMMARY_WORDS=$(wc -w < "$SUMMARY_FILE" | tr -d ' ')

log_success "Pass 3 complete in $(fmt_elapsed $PASS3_ELAPSED)"
log_info "Summary after gap fill: $SUMMARY_WORDS words"

# ── PASS 4: Hallucination validation ────────────────────────────────────
# Cross-check the summary against the ORIGINAL transcript to catch fabricated claims
log_step "PASS 4: Validation — $REVIEW_MODEL"

PASS4_START=$(date +%s)
PASS4_PROMPT_FILE="$TEMP_DIR/${BASENAME}-pass4-prompt.txt"
VALIDATION_FILE="$TEMP_DIR/${BASENAME}-validation.txt"

cat > "$PASS4_PROMPT_FILE" <<'PASS4_HEADER'
You are a strict fact-checker. You have two inputs:
1. ORIGINAL TRANSCRIPT: The raw source material (ground truth)
2. SUMMARY: A summary written from the transcript

Your job: Find every claim in the SUMMARY that is NOT supported by the ORIGINAL TRANSCRIPT.

RULES:
- A "hallucination" is any factual claim, name, number, tool, quote, or attribution in the summary that cannot be verified from the transcript.
- Minor paraphrasing is OK — focus on factual errors, wrong attributions, invented details, and fabricated quotes.
- For each hallucination found, output EXACTLY this format:

HALLUCINATION: "[the incorrect text from the summary]"
CORRECTION: "[what should replace it, based on the transcript, or REMOVE if it should be deleted]"
SECTION: "[the ## section heading where it appears]"

- If NO hallucinations are found, write only: "NO HALLUCINATIONS FOUND"
- Be thorough but precise. Only flag genuine errors, not stylistic choices.

=== ORIGINAL TRANSCRIPT ===

PASS4_HEADER

cat "$TRANSCRIPT_FILE" >> "$PASS4_PROMPT_FILE"

cat >> "$PASS4_PROMPT_FILE" <<'PASS4_MID'

=== SUMMARY ===

PASS4_MID

cat "$SUMMARY_FILE" >> "$PASS4_PROMPT_FILE"

cat >> "$PASS4_PROMPT_FILE" <<'PASS4_FOOTER'

=== END ===

Now list every hallucination you find. Be strict — if you cannot verify a claim from the transcript, flag it.
PASS4_FOOTER

log_info "Cross-checking summary against original transcript..."

if ! ollama_generate "$REVIEW_MODEL" "$PASS4_PROMPT_FILE" "$VALIDATION_FILE" "4096" "0.2" "600" "false" "true"; then
    log_warn "Pass 4 validation failed. Proceeding with unvalidated summary."
    PASS4_FIXES=0
else
    PASS4_FIXES=0

    if ! grep -qi "NO HALLUCINATIONS FOUND" "$VALIDATION_FILE"; then
        # Apply corrections to the summary
        python3 -c "
import re, sys

with open('${VALIDATION_FILE}') as f:
    validation = f.read()

with open('${SUMMARY_FILE}') as f:
    summary = f.read()

# Parse HALLUCINATION/CORRECTION pairs
fixes = re.findall(
    r'HALLUCINATION:\s*\"([^\"]+)\"\s*CORRECTION:\s*\"([^\"]+)\"',
    validation
)

applied = 0
for bad, fix in fixes:
    if bad.strip() in summary:
        if fix.strip().upper() == 'REMOVE':
            # Remove the sentence containing the hallucination
            # Try to remove the full sentence/line
            pattern = re.escape(bad.strip())
            # Remove the hallucinated text and any surrounding whitespace/bullets
            summary = re.sub(r'[^\n]*' + pattern + r'[^\n]*\n?', '', summary)
        else:
            summary = summary.replace(bad.strip(), fix.strip())
        applied += 1

with open('${SUMMARY_FILE}', 'w') as f:
    f.write(summary)

print(applied)
" > "$TEMP_DIR/fix_count.txt"
        PASS4_FIXES=$(cat "$TEMP_DIR/fix_count.txt" 2>/dev/null || echo "0")
    fi
fi

PASS4_END=$(date +%s)
PASS4_ELAPSED=$((PASS4_END - PASS4_START))
SUMMARY_WORDS=$(wc -w < "$SUMMARY_FILE" | tr -d ' ')

if [ "$PASS4_FIXES" -gt 0 ]; then
    log_success "Pass 4 fixed $PASS4_FIXES hallucination(s)"
else
    log_info "No hallucinations detected (or none fixable)"
fi
log_success "Pass 4 complete in $(fmt_elapsed $PASS4_ELAPSED)"
log_info "Final summary: $SUMMARY_WORDS words"
log_info "Validation report: $VALIDATION_FILE"

# ── Final Report ─────────────────────────────────────────────────────────
TOTAL_ELAPSED=$((PASS1_ELAPSED + PASS2_ELAPSED + PASS3_ELAPSED + PASS4_ELAPSED))
COMPRESSION=$(python3 -c "print(f'{$SUMMARY_WORDS * 100 / $WORD_COUNT:.1f}')" 2>/dev/null || echo "N/A")

log_step "Pipeline Complete"

printf "${BOLD}┌─────────────────────────────────────────────────────┐${NC}\n"
printf "${BOLD}│  Transcript Summarization Pipeline — Results        │${NC}\n"
printf "${BOLD}├─────────────────────────────────────────────────────┤${NC}\n"
printf "│  %-22s %-28s│\n" "Title:" "$TITLE"
printf "│  %-22s %-28s│\n" "Input words:" "$WORD_COUNT"
printf "│  %-22s %-28s│\n" "Extraction words:" "$EXTRACTION_WORDS"
printf "│  %-22s %-28s│\n" "Summary words:" "$SUMMARY_WORDS"
printf "│  %-22s %-28s│\n" "Compression ratio:" "${COMPRESSION}%"
printf "${BOLD}├─────────────────────────────────────────────────────┤${NC}\n"
printf "│  %-22s %-28s│\n" "Pass 1 (extract):" "$(fmt_elapsed $PASS1_ELAPSED) — $EXTRACT_MODEL"
printf "│  %-22s %-28s│\n" "Pass 2 (compose):" "$(fmt_elapsed $PASS2_ELAPSED) — $COMPOSE_MODEL ($SECTIONS_GENERATED sections)"
printf "│  %-22s %-28s│\n" "Pass 3 (gap fill):" "$(fmt_elapsed $PASS3_ELAPSED) — $REVIEW_MODEL"
printf "│  %-22s %-28s│\n" "Pass 4 (validate):" "$(fmt_elapsed $PASS4_ELAPSED) — $REVIEW_MODEL"
printf "│  %-22s %-28s│\n" "Total time:" "$(fmt_elapsed $TOTAL_ELAPSED)"
printf "${BOLD}├─────────────────────────────────────────────────────┤${NC}\n"
printf "│  %-22s %-28s│\n" "Extraction file:" "$EXTRACTION_FILE"
printf "│  %-22s %-28s│\n" "Summary file:" "$SUMMARY_FILE"
printf "${BOLD}└─────────────────────────────────────────────────────┘${NC}\n"

echo ""
log_success "Done! Open the summary: $SUMMARY_FILE"
