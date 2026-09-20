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
# vid 會先看 --help 判斷支不支援 VAD；FAKE_WHISPER_NO_VAD=1 模擬舊版
if [[ "${1:-}" == "--help" ]]; then
  echo "usage: whisper-cli [options] file"
  [[ "${FAKE_WHISPER_NO_VAD:-}" == "1" ]] || echo "  --vad   enable Voice Activity Detection (VAD)"
  exit 0
fi
echo "$*" > "$FAKE_WHISPER_ARGS"
# FAKE_WHISPER_VAD_FAIL=1：模擬 VAD 模型壞掉，帶 --vad 就執行失敗
if [[ "${FAKE_WHISPER_VAD_FAIL:-}" == "1" && " $* " == *" --vad "* ]]; then exit 1; fi
of=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-of" ]] && of="$2"; shift; done
if [[ "${FAKE_WHISPER_MODE:-}" == "zh" ]]; then
  # 簡體輸出，用來驗證 opencc 轉換與用詞修正
  printf '1\n00:00:00,000 --> 00:00:02,000\n这个类型的设置和视频内存\n\n' > "$of.srt"
  echo "这个类型的设置和视频内存" > "$of.txt"
elif [[ "${FAKE_WHISPER_MODE:-}" == "repeat" ]]; then
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

# 11. VAD 預設開：VAD 模型在 → whisper 帶 --vad 和 -vm
H=$(new_home vad1); with_model "$H" large-v3-turbo-q5_0; with_model "$H" silero-v6.2.0
run_vid "$H" "$TMPD/audio-only.m4a" -o "$TMPD/out11" || fail "應該成功"
grep -q -- "--vad -vm $H/.cache/whisper-models/ggml-silero-v6.2.0.bin" "$FAKE_WHISPER_ARGS" \
  || fail "預設應帶 --vad：$(cat "$FAKE_WHISPER_ARGS")"
pass "VAD 預設開啟"

# 12. --no-vad → 不帶 --vad
H=$(new_home vad2); with_model "$H" large-v3-turbo-q5_0; with_model "$H" silero-v6.2.0
run_vid "$H" "$TMPD/audio-only.m4a" --no-vad -o "$TMPD/out12" || fail "應該成功"
if grep -q -- "--vad" "$FAKE_WHISPER_ARGS"; then fail "--no-vad 不該帶 --vad"; fi
pass "--no-vad 關閉 VAD"

# 13. whisper 太舊不支援 --vad → 不帶、警告、照常轉錄
H=$(new_home vad3); with_model "$H" large-v3-turbo-q5_0; with_model "$H" silero-v6.2.0
FAKE_WHISPER_NO_VAD=1 run_vid "$H" "$TMPD/audio-only.m4a" -o "$TMPD/out13" || fail "舊版 whisper 應該照常成功"
if grep -q -- "--vad" "$FAKE_WHISPER_ARGS"; then fail "舊版 whisper 不該被塞 --vad"; fi
grep -q "不支援 --vad" "$TMPD/stderr" || fail "應該警告不支援 VAD"
pass "whisper 不支援 VAD：略過並照常轉錄"

# 14. VAD 模型下載後 checksum 不符 → 警告、不用 VAD、照常轉錄、不留 .part
#     （假 curl 寫出的內容 SHA 一定對不上）
H=$(new_home vad4); with_model "$H" large-v3-turbo-q5_0
run_vid "$H" "$TMPD/audio-only.m4a" -o "$TMPD/out14" || fail "VAD 下載失敗不該讓整個失敗"
if grep -q -- "--vad" "$FAKE_WHISPER_ARGS"; then fail "VAD 驗證失敗不該帶 --vad"; fi
grep -q "VAD 模型下載或驗證失敗" "$TMPD/stderr" || fail "應該警告 VAD 下載失敗"
[[ ! -e "$H/.cache/whisper-models/ggml-silero-v6.2.0.bin" && ! -e "$H/.cache/whisper-models/ggml-silero-v6.2.0.bin.part" ]] \
  || fail "VAD 驗證失敗不該留下檔案"
pass "VAD 模型驗證失敗：略過並照常轉錄"

# 14b. VAD 模型在但 whisper 帶 --vad 執行失敗（檔案壞掉、版本讀不了）
#      → 拿掉 VAD 重跑，逐字稿不能消失
H=$(new_home vad5); with_model "$H" large-v3-turbo-q5_0; with_model "$H" silero-v6.2.0
FAKE_WHISPER_VAD_FAIL=1 run_vid "$H" "$TMPD/audio-only.m4a" -o "$TMPD/out14b" || fail "VAD 執行失敗應該重跑成功"
D=$(only_outdir "$TMPD/out14b")
[[ -s "$D/transcript.txt" ]] || fail "拿掉 VAD 重跑後應該有逐字稿"
if grep -q -- "--vad" "$FAKE_WHISPER_ARGS"; then fail "重跑那次不該再帶 --vad"; fi
grep -q "改成不用 VAD 重跑" "$TMPD/stderr" || fail "應該警告改成不用 VAD 重跑"
if grep -q "whisper 執行失敗" "$D/README.md"; then fail "重跑成功就不該標示 whisper 執行失敗"; fi
pass "VAD 執行失敗：拿掉 VAD 重跑"

# 20. 簡轉繁：保留 s2twp 的台灣用詞，但把偏程式領域的「型別」改回「類型」
if command -v opencc >/dev/null 2>&1; then
  H=$(new_home zh); with_model "$H" large-v3-turbo-q5_0; with_model "$H" silero-v6.2.0
  FAKE_WHISPER_MODE=zh run_vid "$H" "$TMPD/audio-only.m4a" -l zh -o "$TMPD/out20" || fail "應該成功"
  D=$(only_outdir "$TMPD/out20")
  grep -q "類型" "$D/transcript.txt" || fail "「类型」應轉成「類型」"
  if grep -q "型別" "$D/transcript.txt"; then fail "不該出現寫程式才用的「型別」"; fi
  grep -q "設定" "$D/transcript.txt" || fail "s2twp 的「设置→設定」應保留"
  grep -q "影片" "$D/transcript.txt" || fail "s2twp 的「视频→影片」應保留"
  grep -q "記憶體" "$D/transcript.txt" || fail "s2twp 的「内存→記憶體」應保留"
  grep -q "類型" "$D/transcript.srt" || fail "srt 也要一起修"
  pass "簡轉繁：保留台灣用詞，修掉過度轉換"
else
  echo "  ⏭  跳過簡轉繁測試（沒裝 opencc）"
fi

# 15–17. 畫面文字 OCR（macOS Vision）。需要 macOS + swiftc；
#        CI 設 VID_REQUIRE_OCR=1，缺工具就算失敗，避免測試被默默跳過
if [[ "$(uname -s)" == "Darwin" ]] && command -v swiftc >/dev/null 2>&1; then
  # 用 AppKit 畫兩張有中英文字的直式字卡，接成 6 秒影片（前 3 秒 A、後 3 秒 B）
  cat > "$TMPD/card.swift" <<'SWIFT'
import AppKit
let a = CommandLine.arguments
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1080, pixelsHigh: 1920, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(calibratedRed: 0.15, green: 0.2, blue: 0.3, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1080, height: 1920).fill()
let font = NSFont(name: "PingFangTC-Semibold", size: 56) ?? NSFont.boldSystemFont(ofSize: 56)
for (i, l) in a.dropFirst(2).enumerated() {
  (l as NSString).draw(at: NSPoint(x: 60, y: 420 - CGFloat(i) * 90), withAttributes: [.font: font, .foregroundColor: NSColor.white])
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[1]))
SWIFT
  swiftc -O "$TMPD/card.swift" -o "$TMPD/card" >/dev/null 2>&1 || fail "測試用字卡產生器編譯失敗"
  "$TMPD/card" "$TMPD/a.png" "回測支撐區才進場" "Wait for the retest"
  "$TMPD/card" "$TMPD/b.png" "停損放在結構低點下方" "Stop loss below the swing low"
  ffmpeg -nostdin -loglevel error -loop 1 -t 3 -i "$TMPD/a.png" -loop 1 -t 3 -i "$TMPD/b.png" \
         -filter_complex "[0][1]concat=n=2:v=1:a=0,format=yuv420p" -r 30 -c:v libx264 -y "$TMPD/cards.mp4"

  # 15. 辨識畫面文字，並把連續相同的標成「同上一張」
  H=$(new_home ocr)
  run_vid "$H" "$TMPD/cards.mp4" -n 4 --no-audio -o "$TMPD/out15" || fail "OCR 應該成功"
  D=$(only_outdir "$TMPD/out15")
  [[ -s "$D/ocr.json" ]] || fail "應該產生 ocr.json"
  grep -q "Wait for the retest" "$D/README.md" || fail "README 應有英文畫面文字"
  grep -q "停損放在結構低點下方" "$D/README.md" || fail "README 應有繁中畫面文字"
  [[ $(grep -c "同上一張" "$D/README.md") -eq 2 ]] || fail "4 張裡應有 2 張標成同上一張"
  pass "OCR：辨識中英文字並去掉重複"

  # 16. --no-ocr → 不做 OCR
  run_vid "$H" "$TMPD/cards.mp4" -n 2 --no-audio --no-ocr -o "$TMPD/out16" || fail "應該成功"
  D=$(only_outdir "$TMPD/out16")
  [[ ! -e "$D/ocr.json" ]] || fail "--no-ocr 不該產生 ocr.json"
  if grep -q "畫面文字" "$D/README.md"; then fail "--no-ocr 不該有畫面文字"; fi
  pass "--no-ocr 關閉 OCR"

  # 17. swiftc 編譯失敗 → 警告、跳過 OCR、影格照樣產生
  BADSWIFT="$TMPD/badswift"; mkdir -p "$BADSWIFT"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BADSWIFT/swiftc"; chmod +x "$BADSWIFT/swiftc"
  H=$(new_home ocrbad)
  HOME="$H" PATH="$BADSWIFT:$FAKE:$PATH" "$VID" "$TMPD/cards.mp4" -n 2 --no-audio -o "$TMPD/out17" \
    >"$TMPD/stdout" 2>"$TMPD/stderr" || fail "OCR 編譯失敗不該讓整個失敗"
  D=$(only_outdir "$TMPD/out17")
  grep -q "OCR 編譯失敗" "$D/README.md" || fail "README 應註明 OCR 編譯失敗"
  [[ $(find "$D/frames" -name '*.jpg' | wc -l | tr -d ' ') -eq 2 ]] || fail "影格應照樣產生"
  pass "OCR 編譯失敗：跳過並照常產出"

  # 18. 非 UTF-8 locale + 中文檔名 + 中文 OCR：python3 印中文不能崩潰
  #     （CI 的預設 locale 就不是 UTF-8）
  cp "$TMPD/cards.mp4" "$TMPD/中文字卡.mp4"
  H=$(new_home ocr)
  LC_ALL=en_US.ISO8859-15 run_vid "$H" "$TMPD/中文字卡.mp4" -n 2 --no-audio -o "$TMPD/out18" \
    || fail "非 UTF-8 locale 下處理中文應該成功"
  D=$(only_outdir "$TMPD/out18")
  grep -q "回測支撐區才進場" "$D/README.md" || fail "非 UTF-8 locale 下 README 應有中文畫面文字"
  pass "非 UTF-8 locale：中文檔名與 OCR 文字正常"

  # 21. 場景變化抽樣：抓得到只出現 0.6 秒的快閃字卡；--uniform 則會漏掉
  "$TMPD/card" "$TMPD/flashA.png" "第一段 AAA"
  "$TMPD/card" "$TMPD/flashB.png" "快閃重點 BBB"
  "$TMPD/card" "$TMPD/flashC.png" "最後結論 CCC"
  ffmpeg -nostdin -loglevel error -loop 1 -t 4 -i "$TMPD/flashA.png" -loop 1 -t 0.6 -i "$TMPD/flashB.png" \
         -loop 1 -t 5.4 -i "$TMPD/flashC.png" \
         -filter_complex "[0][1][2]concat=n=3:v=1:a=0,format=yuv420p" -r 30 -y "$TMPD/flash.mp4"
  H=$(new_home ocr)
  run_vid "$H" "$TMPD/flash.mp4" -n 4 --no-audio -o "$TMPD/out21" || fail "場景抽樣應該成功"
  D=$(only_outdir "$TMPD/out21")
  grep -q "BBB" "$D/README.md" || fail "場景抽樣應該抓到 0.6 秒的快閃字卡"
  grep -q "場景變化" "$TMPD/stderr" || fail "應該顯示有幾張來自場景變化"
  [[ $(find "$D/frames" -name '*.jpg' | wc -l | tr -d ' ') -eq 4 ]] || fail "應該剛好 4 張"
  run_vid "$H" "$TMPD/flash.mp4" -n 4 --no-audio --uniform -o "$TMPD/out21b" || fail "--uniform 應該成功"
  D=$(only_outdir "$TMPD/out21b")
  if grep -q "BBB" "$D/README.md"; then fail "--uniform 在這支片本來就該漏掉快閃卡（測試前提變了）"; fi
  grep -q "均勻抽樣" "$TMPD/stderr" || fail "--uniform 應該顯示均勻抽樣"
  pass "場景抽樣：抓到快閃字卡，--uniform 則漏掉"

  # 19. 完全沒有文字的影格寫「（無）」，不合併成「同上一張」：
  #     「（無）」比「（同上一張）」短，而且 agent 不用往回找
  ffmpeg -nostdin -loglevel error -f lavfi -i "color=c=gray:s=640x360:d=3" -r 30 -c:v libx264 -pix_fmt yuv420p -y "$TMPD/blank.mp4"
  H=$(new_home ocr)
  run_vid "$H" "$TMPD/blank.mp4" -n 3 --no-audio -o "$TMPD/out19" || fail "空白畫面應該成功"
  D=$(only_outdir "$TMPD/out19")
  [[ $(grep -c "畫面文字：（無）" "$D/README.md") -eq 3 ]] || fail "3 張空白影格都應寫（無）"
  if grep -q "同上一張" "$D/README.md"; then fail "空白影格不該寫成同上一張"; fi
  pass "OCR 沒有文字：每張寫（無）"
elif [[ "${VID_REQUIRE_OCR:-}" == "1" ]]; then
  fail "VID_REQUIRE_OCR=1 但這台沒有 macOS + swiftc，OCR 測試無法執行"
else
  echo "  ⏭  跳過 OCR 測試（需要 macOS + swiftc）"
fi

echo "全部 $PASS 項通過"
