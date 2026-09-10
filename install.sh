#!/usr/bin/env bash
# vid 安裝腳本 — 裝相依套件、下載語音模型、把 vid 放進 PATH
set -euo pipefail

MODEL="large-v3-turbo-q5_0"
MODEL_DIR="$HOME/.cache/whisper-models"
BIN_DIR="$HOME/bin"

ok()   { echo "✅ $*"; }
info() { echo "→  $*"; }
die()  { echo "❌ $*" >&2; exit 1; }

echo "── vid 安裝 ──────────────────────────────"

# 1. 環境檢查
[[ "$(uname -s)" == "Darwin" ]] || die "目前只測試過 macOS。Linux 請自行把 brew 換成你的套件管理器。"
command -v brew >/dev/null || die "需要 Homebrew，先裝: https://brew.sh"

# 2. 相依套件
NEED=()
for pkg in ffmpeg yt-dlp whisper-cpp opencc; do
  case "$pkg" in
    ffmpeg)      command -v ffmpeg      >/dev/null || NEED+=("$pkg") ;;
    yt-dlp)      command -v yt-dlp      >/dev/null || NEED+=("$pkg") ;;
    whisper-cpp) command -v whisper-cli >/dev/null || NEED+=("$pkg") ;;
    opencc)      command -v opencc      >/dev/null || NEED+=("$pkg") ;;
  esac
done

if [[ ${#NEED[@]} -gt 0 ]]; then
  info "安裝相依套件: ${NEED[*]}（ffmpeg 依賴多，可能要幾分鐘）"
  brew install "${NEED[@]}"
else
  ok "相依套件都已存在"
fi

# 3. 語音模型
MODEL_FILE="$MODEL_DIR/ggml-${MODEL}.bin"
if [[ -f "$MODEL_FILE" ]]; then
  ok "語音模型已存在 ($(du -h "$MODEL_FILE" | cut -f1))"
else
  mkdir -p "$MODEL_DIR"
  info "下載語音模型 ggml-${MODEL}.bin（約 547 MB，一次性）…"
  curl -L --fail --progress-bar \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${MODEL}.bin" \
    -o "$MODEL_FILE.part" \
    && mv "$MODEL_FILE.part" "$MODEL_FILE" \
    || { rm -f "$MODEL_FILE.part"; die "模型下載失敗"; }
  ok "模型下載完成"
fi

# 4. 安裝指令
mkdir -p "$BIN_DIR"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vid"
ln -sf "$SRC" "$BIN_DIR/vid"
chmod +x "$SRC"
ok "已連結 $BIN_DIR/vid → $SRC"

# 5. PATH
echo ""
if [[ ":$PATH:" == *":$BIN_DIR:"* ]]; then
  ok "$BIN_DIR 已在 PATH 中"
  echo ""
  echo "🎉 裝好了。試試看:  vid --help"
else
  echo "⚠️  $BIN_DIR 不在 PATH 中。執行這行加進去："
  echo ""
  RC="$HOME/.zshrc"; [[ "${SHELL:-}" == *bash* ]] && RC="$HOME/.bashrc"
  echo "    echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> $RC && source $RC"
  echo ""
  echo "之後試試看:  vid --help"
fi
