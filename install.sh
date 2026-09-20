#!/usr/bin/env bash
# vid 安裝腳本 — 裝相依套件、下載語音模型、把 vid 放進 PATH
set -euo pipefail

MODEL="large-v3-turbo-q5_0"
MODEL_DIR="$HOME/.cache/whisper-models"
BIN_DIR="$HOME/bin"
MODEL_REVISION="5359861c739e955e79d9a303bcbc70fb988958b1"
# Hugging Face LFS oid (SHA-256) for the default model at MODEL_REVISION.
DEFAULT_MODEL_SHA256="394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
VAD_MODEL="silero-v6.2.0"
VAD_REVISION="9ffd54a1e1ee413ddf265af9913beaf518d1639b"
VAD_SHA256="2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987"

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
verify_model() {
  local actual
  actual=$(shasum -a 256 "$1" | awk '{print $1}') || return 1
  [[ "$actual" == "$DEFAULT_MODEL_SHA256" ]]
}
if [[ -f "$MODEL_FILE" ]] && verify_model "$MODEL_FILE"; then
  ok "語音模型已存在且驗證通過 ($(du -h "$MODEL_FILE" | cut -f1))"
else
  [[ -f "$MODEL_FILE" ]] && info "既有模型 checksum 不符（可能下載不完整），重新下載"
  mkdir -p "$MODEL_DIR"
  info "下載語音模型 ggml-${MODEL}.bin（約 547 MB，一次性）…"
  curl -L --fail --progress-bar \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/${MODEL_REVISION}/ggml-${MODEL}.bin" \
    -o "$MODEL_FILE.part" || { rm -f "$MODEL_FILE.part"; die "模型下載失敗"; }
  if ! verify_model "$MODEL_FILE.part"; then
    rm -f "$MODEL_FILE.part"
    die "模型下載後 checksum 驗證失敗"
  fi
  mv "$MODEL_FILE.part" "$MODEL_FILE"
  ok "模型下載並驗證完成"
fi

# 3b. VAD 模型（約 0.9 MB）：先把靜音段濾掉，長片不容易鬼打牆。
#     失敗不中止安裝，vid 執行時會再試，真的沒有就不用 VAD 照常轉錄
VAD_FILE="$MODEL_DIR/ggml-${VAD_MODEL}.bin"
if [[ -f "$VAD_FILE" ]]; then
  ok "VAD 模型已存在"
elif curl -L --fail -sS \
       "https://huggingface.co/ggml-org/whisper-vad/resolve/${VAD_REVISION}/ggml-${VAD_MODEL}.bin" \
       -o "$VAD_FILE.part" \
     && [[ "$(shasum -a 256 "$VAD_FILE.part" | awk '{print $1}')" == "$VAD_SHA256" ]]; then
  mv "$VAD_FILE.part" "$VAD_FILE"
  ok "VAD 模型下載並驗證完成"
else
  rm -f "$VAD_FILE.part"
  echo "⚠️  VAD 模型下載失敗，先略過（vid 執行時會再試）"
fi

# 3c. 畫面文字 OCR 需要 swiftc（Xcode Command Line Tools）。沒有也能用 vid，只是不做 OCR
if command -v swiftc >/dev/null 2>&1; then
  ok "swiftc 已存在，可以辨識畫面文字"
else
  echo "⚠️  沒有 swiftc，vid 會跳過畫面文字辨識。要的話執行: xcode-select --install"
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
