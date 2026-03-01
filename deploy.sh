#!/bin/bash
# Tesla P40 Ollama Optimization — Deployment Script
# Run from the server (10.80.4.228) or adapt paths for remote execution.
# Each step prints what it's doing. Ctrl-C safe — idempotent operations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_DIR="$HOME/my.models"
BACKUP_DIR="$HOME/my.models/backup-$(date +%Y%m%d-%H%M%S)"

echo "=== Tesla P40 Ollama Optimization Deployment ==="
echo ""

# ------------------------------------------------------------------
# STEP 0: Pre-flight checks
# ------------------------------------------------------------------
echo "[0/7] Pre-flight checks..."
if ! command -v ollama &>/dev/null; then
    echo "  ERROR: ollama not found"; exit 1
fi
if ! nvidia-smi &>/dev/null; then
    echo "  ERROR: nvidia-smi not found"; exit 1
fi
echo "  Ollama: $(ollama --version)"
echo "  GPU: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader)"
echo "  OK"
echo ""

# ------------------------------------------------------------------
# STEP 1: Backup current config
# ------------------------------------------------------------------
echo "[1/7] Backing up current config to $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
cp /etc/systemd/system/ollama.service.d/override.conf "$BACKUP_DIR/override.conf.bak" 2>/dev/null || true
cp "$MODEL_DIR"/*.modelfile "$BACKUP_DIR/" 2>/dev/null || true
echo "  Backup complete"
echo ""

# ------------------------------------------------------------------
# STEP 2: Set vm.swappiness=10 (one-time sysctl)
# ------------------------------------------------------------------
echo "[2/7] Setting vm.swappiness=10..."
CURRENT_SWAP=$(cat /proc/sys/vm/swappiness)
if [ "$CURRENT_SWAP" != "10" ]; then
    echo "  Current: $CURRENT_SWAP → Setting to 10"
    sudo sysctl -w vm.swappiness=10
    if ! grep -q "vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
        echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf >/dev/null
    else
        sudo sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
    fi
else
    echo "  Already set to 10"
fi
echo ""

# ------------------------------------------------------------------
# STEP 3: Add nvidia-smi to sudoers (if not already)
# ------------------------------------------------------------------
echo "[3/7] Checking sudoers for nvidia-smi..."
if sudo -n nvidia-smi -ac 3615,1531 &>/dev/null; then
    echo "  nvidia-smi sudoers already working"
    # Reset clocks for now — the override ExecStartPre will set them on restart
    sudo -n nvidia-smi -rac &>/dev/null || true
else
    echo "  WARNING: Cannot run 'nvidia-smi -ac' via sudo."
    echo "  Add to /etc/sudoers.d/ollama-tuning:"
    echo "    myron ALL=(ALL) NOPASSWD: /usr/bin/nvidia-smi"
    echo "  Then re-run this script."
    echo ""
    echo "  Continuing without clock boost (other optimizations will still apply)..."
fi
echo ""

# ------------------------------------------------------------------
# STEP 4: Deploy systemd override
# ------------------------------------------------------------------
echo "[4/7] Deploying systemd override..."
cp "$SCRIPT_DIR/override.conf" /tmp/ollama-override.conf
sudo -n update-ollama-override
sudo -n systemctl daemon-reload
echo "  Override deployed"
echo ""

# ------------------------------------------------------------------
# STEP 5: Deploy modelfiles
# ------------------------------------------------------------------
echo "[5/7] Deploying modelfiles..."
for f in "$SCRIPT_DIR"/c_*.modelfile; do
    fname=$(basename "$f")
    cp "$f" "$MODEL_DIR/$fname"
    echo "  Copied $fname"
done
echo ""

# ------------------------------------------------------------------
# STEP 6: Restart Ollama and create models
# ------------------------------------------------------------------
echo "[6/7] Restarting Ollama..."
sudo -n systemctl restart ollama
echo "  Waiting for Ollama to start..."
for i in $(seq 1 30); do
    if curl -s http://localhost:11434/ | grep -q "Ollama"; then
        echo "  Ollama is running"
        break
    fi
    sleep 1
done
echo ""

echo "  Creating custom models from modelfiles..."
MODELS=(
    "c_gemma3-27b-128k"
    "c_qwen25-coder-32b-32k"
    "c_glm47-flash-198k"
    "c_glm47-flash-128k"
    "c_phi4-reasoning-plus-32k"
    "c_nemotron-3-nano-30b-128k"
    "c_medgemma-27b-128k"
    "c_glm47-flash-extract"
    "c_qwen3-30b-a3b-200k"
    "c_qwen3-30b-a3b-144k"
    "c_qwen3-14b-40k"
    "c_lfm2-24b-a2b-32k"
)

for model in "${MODELS[@]}"; do
    mfile="$MODEL_DIR/${model}.modelfile"
    if [ -f "$mfile" ]; then
        echo "  Creating $model..."
        ollama create "$model" -f "$mfile" 2>&1 | tail -1
    else
        echo "  WARNING: $mfile not found, skipping"
    fi
done
echo ""

# ------------------------------------------------------------------
# STEP 7: Verify
# ------------------------------------------------------------------
echo "[7/7] Verification..."
echo ""
echo "  Systemd override:"
systemctl show ollama --property=Environment | tr ' ' '\n' | grep -E "OLLAMA_|GGML_|CUDA_" | sed 's/^/    /'
echo ""
echo "  LimitMEMLOCK:"
systemctl show ollama --property=LimitMEMLOCKSoft | sed 's/^/    /'
echo ""
echo "  GPU clocks:"
nvidia-smi --query-gpu=clocks.sm,clocks.mem,clocks.max.sm,clocks.max.mem --format=csv,noheader | sed 's/^/    /'
echo ""
echo "  Custom models:"
ollama list | grep "^c_" | sed 's/^/    /'
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run benchmark: python3 $SCRIPT_DIR/benchmark.py"
echo "  2. Compare results with previous benchmarks"
echo "  3. If issues: restore from $BACKUP_DIR"
echo ""
echo "Rollback command:"
echo "  cp $BACKUP_DIR/override.conf.bak /tmp/ollama-override.conf && \\"
echo "  sudo update-ollama-override && sudo systemctl daemon-reload && \\"
echo "  sudo systemctl restart ollama && \\"
echo "  cp $BACKUP_DIR/*.modelfile $MODEL_DIR/"
