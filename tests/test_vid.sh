#!/usr/bin/env bash
# vid 回歸測試。需要真的 ffmpeg/ffprobe/python3；whisper 與 curl 用假的替身，
# 所以不必下載 547 MB 模型，CI 也跑得動。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VID="${VID_UNDER_TEST:-$ROOT/vid}"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

PASS=0
pass() { echo "  ✅ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $*" >&2; [[ -f "$TMPD/stderr" ]] && sed 's/^/     | /' "$TMPD/stderr" >&2; exit 1; }

# ── 假的 whisper-cli：把參數記下來，照 -of 寫出 txt/srt ──────────────────
FAKE="$TMPD/fakebin"; mkdir -p "$FAKE"
cat > "$FAKE/whisper-cli" <<'SH'
#!/usr/bin/env bash
echo "$*" > "$FAKE_WHISPER_ARGS"
of=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-of" ]] && of="$2"; shift; done
if [[ "${FAKE_WHISPER_MODE:-}" == "repeat" ]]; then
  for i in $(seq 1 20); do printf '%d\n00:00:%02d,000 --> 00:00:%02d,500\nthank you\n\n' "$i" "$i" "$i"; done > "$of.srt"
  for i in $(seq 1 20); do echo "thank you"; done > "$of.txt"
else
  printf '1\n00:00:00,000 --> 00:00:02,000\nhello from fake whisper\n\n' > "$of.srt"
  echo "hello from fake whisper" > "$of.txt"
fi
SH
# 假的 curl：把固定內容寫到 -o 指定的路徑；FAKE_CURL_FAIL=1 模擬下載失敗
cat > "$FAKE/curl" <<'SH'
#!/usr/bin/env bash
[[ "${FAKE_CURL_FAIL:-}" == "1" ]] && exit 22
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && out="$2"; shift; done
echo "fake-model-bytes" > "$out"
SH
chmod +x "$FAKE/whisper-cli" "$FAKE/curl"
FAKE_MODEL_SHA=$(echo "fake-model-bytes" | shasum -a 256 | awk '{print $1}')

export FAKE_WHISPER_ARGS="$TMPD/whisper-args"

# 每個案例用獨立的 HOME，模型目錄互不干擾
new_home() { local h="$TMPD/home-$1"; mkdir -p "$h/.cache/whisper-models"; echo "$h"; }
with_model() { echo "fake" > "$1/.cache/whisper-models/ggml-$2.bin"; }
run_vid() { local home="$1"; shift; HOME="$home" PATH="$FAKE:$PATH" "$VID" "$@" >"$TMPD/stdout" 2>"$TMPD/stderr"; }
only_outdir() { find "$1" -mindepth 1 -maxdepth 1 -type d | head -1; }

# ── 測試素材 ───────────────────────────────────────────────────────────────
ffmpeg -nostdin -loglevel error -f lavfi -i "sine=frequency=440:duration=3" -c:a aac -y "$TMPD/audio-only.m4a"
ffmpeg -nostdin -loglevel error -f lavfi -i "testsrc2=size=320x568:rate=30:duration=3" \
       -f lavfi -i "sine=frequency=440:duration=10" -c:v libx264 -pix_fmt yuv420p -c:a aac -y "$TMPD/av-mismatch.mp4"

echo "vid tests"

# 0. 語法與 --help
bash -n "$VID" "$ROOT/install.sh"
"$VID" --help >/dev/null
pass "語法檢查與 --help"

# 1. ffprobe 失敗 → 非零退出、不建立輸出目錄
BROKEN="$TMPD/brokenbin"; mkdir -p "$BROKEN"
ln -s "$(command -v python3)" "$BROKEN/python3"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BROKEN/ffmpeg"
printf '#!/usr/bin/env bash\necho "simulated ffprobe failure" >&2\nexit 1\n' > "$BROKEN/ffprobe"
chmod +x "$BROKEN/ffmpeg" "$BROKEN/ffprobe"
touch "$TMPD/video.mp4"
if PATH="$BROKEN:$PATH" "$VID" "$TMPD/video.mp4" --no-frames --no-audio -o "$TMPD/out1" >"$TMPD/stdout" 2>"$TMPD/stderr"; then
  fail "ffprobe 失敗時應該退出"
fi
grep -q "ffprobe 讀取影片時長失敗" "$TMPD/stderr" || fail "錯誤訊息不對"
[[ ! -d "$TMPD/out1" ]] || fail "ffprobe 失敗後不該留下輸出目錄"
pass "ffprobe 失敗 → 退出且不留輸出"

# 2. 純音訊檔 → 成功、有逐字稿、沒有影格、README 標註無畫面
H=$(new_home a); with_model "$H" large-v3-turbo-q5_0
run_vid "$H" "$TMPD/audio-only.m4a" -o "$TMPD/out2" || fail "純音訊檔應該成功"
D=$(only_outdir "$TMPD/out2")
[[ -s "$D/transcript.txt" ]] || fail "純音訊檔應該有逐字稿"
[[ ! -d "$D/frames" ]] || fail "純音訊檔不該有 frames/"
grep -q "無畫面" "$D/README.md" || fail "README 應標註無畫面"
pass "純音訊檔：只做逐字稿"

# 3. 配樂比畫面長 → 6 張全部抽到，而且都落在 3 秒畫面內
H=$(new_home b)
run_vid "$H" "$TMPD/av-mismatch.mp4" -n 6 --no-audio -o "$TMPD/out3" || fail "音畫長度不同應該成功"
D=$(only_outdir "$TMPD/out3")
N=$(find "$D/frames" -name '*.jpg' -size +0 | wc -l | tr -d ' ')
[[ "$N" -eq 6 ]] || fail "應抽到 6 張，實際 $N 張"
if find "$D/frames" -name '*.jpg' | grep -qvE '_00m0[0-2]s\.jpg$'; then fail "有影格落在畫面結束之後"; fi
pass "音畫長度不同：6/6 張都在畫面範圍內"

# 4. 已下載的自訂模型、沒給 SHA → 照常執行（不再硬擋）
H=$(new_home c); with_model "$H" base
run_vid "$H" "$TMPD/audio-only.m4a" --model base -o "$TMPD/out4" || fail "--model base 應該可以跑"
pass "自訂模型已存在：不要求 SHA"

# 5. 首次下載自訂模型、沒給 SHA → 警告但繼續
H=$(new_home d)
run_vid "$H" "$TMPD/audio-only.m4a" --model small -o "$TMPD/out5" || fail "沒給 SHA 應該警告後繼續"
grep -q "未驗證 checksum" "$TMPD/stderr" || fail "應該印出未驗證警告"
[[ -f "$H/.cache/whisper-models/ggml-small.bin" ]] || fail "模型應該已存好"
pass "首次下載自訂模型無 SHA：警告後繼續"

# 6. 首次下載、SHA 正確 → 通過；SHA 錯誤 → 退出、不留模型也不留輸出
H=$(new_home e)
WHISPER_MODEL_SHA256="$FAKE_MODEL_SHA" run_vid "$H" "$TMPD/audio-only.m4a" --model tiny -o "$TMPD/out6" \
  || fail "SHA 正確應該通過"
H=$(new_home f)
if WHISPER_MODEL_SHA256="$(printf '0%.0s' $(seq 1 64))" run_vid "$H" "$TMPD/audio-only.m4a" --model tiny -o "$TMPD/out6b"; then
  fail "SHA 錯誤應該退出"
fi
[[ ! -e "$H/.cache/whisper-models/ggml-tiny.bin" && ! -e "$H/.cache/whisper-models/ggml-tiny.bin.part" ]] \
  || fail "SHA 錯誤不該留下模型檔"
[[ -z "$(only_outdir "$TMPD/out6b")" ]] || fail "SHA 錯誤不該留下半成品輸出"
pass "下載時驗 checksum：對的通過、錯的清乾淨"

# 7. 模型下載失敗 → 退出，已建立的輸出目錄要收掉
H=$(new_home g)
if FAKE_CURL_FAIL=1 run_vid "$H" "$TMPD/av-mismatch.mp4" -n 2 --model tiny -o "$TMPD/out7"; then
  fail "下載失敗應該退出"
fi
[[ -z "$(only_outdir "$TMPD/out7")" ]] || fail "中途失敗不該留下半成品輸出目錄"
pass "中途失敗：不留半成品"

# 8. whisper 一定帶 -mc 0（防長片幻覺迴圈）
H=$(new_home h); with_model "$H" large-v3-turbo-q5_0
run_vid "$H" "$TMPD/audio-only.m4a" -o "$TMPD/out8" || fail "應該成功"
grep -q -- "-mc 0" "$FAKE_WHISPER_ARGS" || fail "whisper 參數沒有 -mc 0：$(cat "$FAKE_WHISPER_ARGS")"
pass "whisper 帶 -mc 0"

# 9. 同一句連續重複 → README 標警告
H=$(new_home i); with_model "$H" large-v3-turbo-q5_0
FAKE_WHISPER_MODE=repeat run_vid "$H" "$TMPD/audio-only.m4a" -o "$TMPD/out9" || fail "應該成功（只是加警告）"
D=$(only_outdir "$TMPD/out9")
grep -q "連續重複 20 次" "$D/README.md" || fail "README 應該有重複警告"
pass "偵測幻覺重複：README 加警告"

# 10. 變數後面不能直接接中文：非 UTF-8 locale（例如 CI）的 bash 會把
#     中文的位元組當成變數名的一部分，觸發 unbound variable
BAD=$(python3 - "$VID" "$ROOT/install.sh" <<'PY'
import re, sys
for f in sys.argv[1:]:
    for i, line in enumerate(open(f, encoding="utf-8"), 1):
        if re.search(r'\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]', line):
            print(f"{f}:{i}: {line.strip()}")
PY
)
[[ -z "$BAD" ]] || fail "變數後面直接接非 ASCII 字元，請改成 \${VAR}：$BAD"
pass "變數與中文之間都用大括號隔開"

echo "全部 $PASS 項通過"
