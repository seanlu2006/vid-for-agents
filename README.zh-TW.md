# vid

[English](README.md)

> 把影片變成 AI agent 讀得懂的東西：抽樣影格 + 本機逐字稿，一行指令，零 API 成本。

---

## 問題

Claude Code、Cursor 這類 coding agent 能看圖、能讀文字，但沒辦法「播放」影片。你把一個 Reels 連結貼給它，它只能回你「我沒辦法看影片」。

於是每次想讓 AI 幫你消化一支教學影片、一支競品的 UI 展示、一則你想存證的貼文，你都得自己看完、自己截圖、自己打逐字稿——AI 幫不上忙的那段，剛好是最花時間的那段。

## 怎麼解決

核心觀察是：**agent 不需要真的「看影片」，它只需要影片裡的資訊。**

而一支影片的資訊，幾乎都能拆成兩軌：

- **畫面** → 沿時間軸均勻抽樣的靜態影格。多數影片的畫面變化遠比 30fps 慢，12 張圖就能涵蓋一支短影片的所有場景。
- **聲音** → 完整逐字稿。旁白講的每個字都在，一個字都沒少。

這兩樣 agent 都吃得下。`vid` 就是把任意影片（本機檔案，或 YouTube / Instagram / TikTok 等 yt-dlp 支援的連結）自動拆成這兩軌，加上原始貼文 metadata，整理成一個資料夾，並產生一份**給 agent 讀的入口 `README.md`**。

轉錄全程在本機跑，影片不會離開你的電腦，也不呼叫任何雲端轉錄 API，處理幾支都是 $0。唯一的連外流量是 yt-dlp 抓影片，以及第一次下載語音模型。

---

## 安裝

**環境需求**：macOS（Apple Silicon 或 Intel）、[Homebrew](https://brew.sh)、`python3`。

> macOS 沒有內建 `python3`。沒有的話跑 `xcode-select --install`，或 `brew install python`。

### 一鍵安裝

```bash
git clone https://github.com/seanlu2006/vid-for-agents.git
cd vid-for-agents
./install.sh
```

`install.sh` 會做四件事，**只有這四件**：

| 動作 | 細節 |
|---|---|
| 用 `brew install` 裝缺少的套件 | `ffmpeg`、`yt-dlp`、`whisper-cpp`、`opencc`（已裝的會跳過） |
| 下載並驗證語音模型 | 約 547 MB，存到 `~/.cache/whisper-models/`，一次性；會檢查固定的上游版本與 SHA-256 |
| 建立 symlink | `~/bin/vid` → 你 clone 下來的 `vid` |
| 檢查 PATH | 若 `~/bin` 不在 PATH，**只印出**該加的那行給你自己執行 |

它**不會**改你的 `.zshrc` / `.bashrc`，不會用 `sudo`，也不會下載執行任何遠端腳本。因為第 3 步是 symlink，**別在裝完後刪掉或搬走這個 repo 資料夾**，不然 `vid` 會失效。

### 手動安裝

不想跑腳本就自己來：

```bash
brew install ffmpeg yt-dlp whisper-cpp opencc
git clone https://github.com/seanlu2006/vid-for-agents.git
cd vid-for-agents && chmod +x vid
mkdir -p ~/bin && ln -s "$PWD/vid" ~/bin/vid   # 或任何已在你 PATH 上的目錄
```

語音模型不用手動抓——第一次需要轉逐字稿時 `vid` 會自己下載。

### 相依套件各自負責什麼

| 套件 | 用途 | 缺了會怎樣 |
|---|---|---|
| `ffmpeg` / `ffprobe` | 抽影格、轉音軌、讀影片資訊 | 直接中止 |
| `python3` | 影格時間點計算、metadata 轉 Markdown | 直接中止 |
| `yt-dlp` | 下載網路影片 + 貼文文字 | 只在給 URL 時需要；處理本機檔不用 |
| `whisper-cpp` | 本機語音轉文字 | 跳過逐字稿，影格照抽 |
| `opencc` | 簡體轉台灣正體 | 中文逐字稿會停在簡體 |

---

## 用法

```
vid <URL 或本機檔案路徑> [選項]
```

### 範例一：本機影片

```bash
vid ~/Downloads/demo.mp4
```

```
→ 時長 83s / 解析度 1280x720
→ 抽 12 張影格…
→ 轉逐字稿中（本機跑，長片要等）…

✅ 完成 → /Users/you/media-out/demo-20260911-004512
   叫 Claude 讀: /Users/you/media-out/demo-20260911-004512/README.md（逐字稿都在裡面），要看畫面就讀 frames/ 底下的圖
```

產出：

```
~/media-out/demo-20260911-004512/
├── README.md          給 agent 讀的入口
├── frames/
│   ├── f001_00m03s.jpg
│   ├── f002_00m10s.jpg
│   ├── …
│   └── f012_01m19s.jpg
├── transcript.txt     純文字逐字稿
└── transcript.srt     帶時間軸
```

整包大約 200 KB。注意處理本機檔案時**不會**產生 `meta.json`（沒有貼文可抓），也**不會**複製一份 `source.mp4`（你原本的檔案就在那，不動它）。

### 範例二：YouTube

```bash
vid "https://www.youtube.com/watch?v=XXXXXXXXXXX" -l zh -n 30
```

`-l zh` 指定中文（比 auto 準），`-n 30` 抽 30 張影格（畫面資訊密集時調高）。多出兩個檔案：

```
~/media-out/影片標題-20260911-004512/
├── README.md
├── meta.json          yt-dlp 抓到的完整 metadata
├── frames/            30 張
├── transcript.txt
├── transcript.srt
└── source.mp4         下載回來的原始影片（副檔名跟著實際下載走）
```

下載會優先挑 1080p 以下的最佳串流，合併成 mp4。但格式字串最後有一段沒有畫質上限的 fallback（`/b`）——如果站台只提供單一已合流的格式，yt-dlp 會退回去抓它的 best，這時解析度可能超過 1080p，容器也可能不是 mp4，上面那個檔案的副檔名就會跟著變。

網址如果是「影片 + 播放清單」那種（`…&list=…`），只會拿到你指到的那一支；但純播放清單網址（`playlist?list=…`）不支援，yt-dlp 仍會展開整串，而且每一支都寫到同一個暫存樣板互相覆蓋，結果無法預期。

### 範例三：Instagram Reels

需要登入才看得到的內容，得借你瀏覽器的 cookie：

```bash
vid "https://www.instagram.com/reel/XXXXXXXXXXX/" -c chrome
```

`-c chrome` 會讓 yt-dlp 讀取 Chrome 的 cookie 資料庫，macOS 上可能跳出鑰匙圈授權視窗。這件事完全在本機發生，cookie 不會被送去任何地方——但你如果不放心，用 `-c safari` 或乾脆手動下載影片再餵本機檔案也行。

### 產出的 `README.md` 長這樣

```markdown
# 影片內容包

- 來源: `https://www.youtube.com/watch?v=XXXXXXXXXXX`
- 時長: 83s ｜ 解析度: 1280x720
- 產生時間: 2026-09-11 00:45:14

## 貼文 / 影片 metadata

- **title**: 如何用 AI 讀影片
- **uploader**: Sean Lu
- **upload_date**: 20260901
- **view_count**: 1234
- **webpage_url**: https://www.youtube.com/watch?v=XXXXXXXXXXX

### 原始貼文文字

（貼文內文，最多 4000 個字元）

## 逐字稿

（全文直接內嵌在這裡）

帶時間軸版本: `transcript.srt`

## 影格（用 Read 工具逐張看）

- `frames/f001_00m03s.jpg` (t=00m03s)
- `frames/f002_00m10s.jpg` (t=00m10s)
- …
```

whisper 執行失敗或檔案根本沒有音軌時，`## 逐字稿` 標題後面會多一段括號說明原因。whisper 失敗的話，`audio.wav`（16kHz 單聲道）會留在資料夾裡，讓你手動重試。其他中途失敗，例如模型下載到一半斷掉，則會把這次建的資料夾整個清掉。

純音訊檔也能丟，像 podcast 或語音備忘錄。沒有畫面可抽，所以只有逐字稿，開頭的解析度會寫「無畫面」。某張影格抽不出來時會印警告並跳過，其他照跑。`影格` 標題後面會註明少了幾張。

### 選項

| 選項 | 說明 | 預設 |
|---|---|---|
| `-n, --frames N` | 抽幾張影格 | `12` |
| `-l, --lang CODE` | 逐字稿語言：`zh`、`en`、`ja`… 或 `auto` 自動偵測 | `auto` |
| `-c, --cookies BROWSER` | 借瀏覽器 cookie 抓需登入的內容：`chrome` / `safari` / `firefox` / `edge` | 不使用 |
| `-o, --outdir DIR` | 輸出根目錄 | `~/media-out` |
| `--model NAME` | whisper 模型名稱 | `large-v3-turbo-q5_0` |
| `--no-frames` | 不抽影格（只要逐字稿） | 兩者都做 |
| `--no-audio` | 不轉逐字稿（只要影格） | 兩者都做 |
| `--keep-video` | 保留下載回來的原始影片 | 已是預設 |
| `--no-keep` | 處理完刪掉下載回來的影片，省空間 | 保留 |
| `-h, --help` | 說明 | — |

幾點補充：

- `--keep-video` 和 `--no-keep` **只影響從 URL 下載的影片**。處理本機檔案時兩者都是空操作，`vid` 永遠不會動你原本的檔案。
- `--model` 的值會被拼成 `ggml-<NAME>.bin`，從 [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) 的固定版本下載。checksum 只在下載當下驗一次：預設模型比對上游的 SHA-256，自訂模型比對你設的 `WHISPER_MODEL_SHA256`。沒設也照樣下載，只會印警告說沒驗證。已經在硬碟上的模型直接信任，不會每次重算。547 MB 每跑一次都重算，就要多花約 1 秒。
- `-c` 的值原封不動傳給 `yt-dlp --cookies-from-browser`，所以 yt-dlp 支援的瀏覽器都能用，不限上面列的四個。
- 輸出目錄名稱是 `<標題 slug>-<YYYYMMDD-HHMMSS>`；如果同一秒啟動兩次，會加上獨占的數字尾綴，不會重用既有資料夾。slug 保留英數字與漢字（U+4E00–U+9FFF），其餘字元一律收斂成單一 `-`，並截斷在 50 個字元。所以日文假名、韓文、西里爾字母、帶重音的拉丁字母都會被吃掉：`アニメの作り方` 會變成 `作-方`，整個標題都是這類字元的話會退回預設名 `video`。

---

## 搭配 AI agent 使用

這是這個工具存在的理由。以 Claude Code 為例：

```bash
# 1. 在 terminal 跑
vid "https://www.youtube.com/watch?v=XXXXXXXXXXX" -l zh
# → 完成 → /Users/you/media-out/如何用-AI-讀影片-20260911-004512
```

```
# 2. 在 Claude Code 裡直接說
> 讀 ~/media-out/如何用-AI-讀影片-20260911-004512/README.md，
  把這支影片講的步驟整理成一份筆記
```

agent 一次 Read 就拿到 metadata + 完整逐字稿，可以立刻開始整理。需要確認畫面時再補一句：

```
> 第 4 分鐘他在展示什麼？看一下對應的影格
```

它會從影格清單挑出時間最接近的那張去 Read。

### 為什麼入口檔要這樣設計

產出的 `README.md` 有個刻意的取捨：**逐字稿全文直接內嵌，影格只列檔名不內嵌。**

因為文字便宜、圖片貴。逐字稿內嵌代表 agent 一次 Read 就掌握影片講了什麼，不用摸索；而 12 張圖如果全部塞進 context 會吃掉大量 token，其中大部分根本用不到。所以影格只列出「檔名 + 時間戳」，讓 agent 自己判斷該看哪張、要不要看——通常讀完逐字稿後，它只需要一兩張圖就能回答問題。

同樣的邏輯也適用於其他 agent（Cursor、Codex、任何有讀檔和讀圖能力的工具）——`vid` 產出的就是一般的資料夾和一般的檔案，沒有綁定任何特定平台。

---

## 技術架構

```
輸入 ─┬─ URL ──► yt-dlp ──► 影片檔 + info.json（標題/作者/貼文原文/讚數）
      │
      └─ 本機檔案 ──► 直接使用

                 影片檔
                    │
      ┌─────────────┴─────────────┐
      │                           │
   ffmpeg                      ffmpeg
      │                           │
  均勻抽樣影格               16kHz 單聲道 WAV
  (JPEG, 寬 ≤768px)               │
      │                    whisper.cpp（本機，Apple Silicon 走 Metal）
      │                           │
      │                     transcript.txt / .srt
      │                           │
      │                    opencc s2twp（簡體 → 台灣正體）
      └─────────────┬─────────────┘
                    │
        產生 README.md（metadata + 逐字稿全文 + 影格索引）
```

### 各階段的設計取捨

**抽樣**：第 i 張影格取在 `t = 畫面長度 × (i − 0.5) / N`，也就是每個等分區間的中點，而不是端點——這樣自然避開開頭和結尾常見的黑畫面或轉場。這裡的長度是畫面串流的長度，不是整個檔案的。Reels 常把 3 秒的畫面配上 10 秒的音樂，照檔案長度抽，大部分影格會落在畫面已經結束的地方。影格縮到寬度 768px（原本就更窄就不放大），JPEG 品質 `-q:v 4`。這個尺寸剛好在多數 vision 模型的處理解析度附近，再大只是浪費 token。

**轉錄用本機 whisper 而不是雲端 API**，理由有三個：

1. **成本**：本機跑一次和跑一百次都是 $0，不用擔心「這支影片值不值得花錢轉」。
2. **隱私**：私人錄影、會議記錄、還沒公開的東西不用上傳給第三方。
3. **無上限**：沒有檔案大小限制、沒有 rate limit、離線也能用。

代價是第一次要下載 547 MB 模型，而且長影片得等——但在 Apple Silicon 上 whisper.cpp 走 Metal 加速，實際上比想像中快很多（見下）。

**簡繁轉換**：whisper 的中文輸出一律是簡體，而且用詞是中國大陸慣用語。`opencc -c s2twp` 不只做字形轉換，還會處理詞彙差異（软件 → 軟體、视频 → 影片），對台灣使用者來說這步驟是必要的。

**清理暫存**：下載的檔案放在 `mktemp -d` 開的暫存目錄，由 `EXIT` trap 負責刪掉，所以下載失敗或中途 Ctrl-C 都不會把一整支影片留在 `/var/folders`。另外 whisper 的執行檔名在各版本不一樣，`vid` 會依序找 `whisper-cli`、`whisper-cpp`、`whisper`、`main`。

### 實測

在 Apple M5 上，一支 83 秒、1280×720 的影片，抽 12 張影格 + 英文逐字稿：

```
real 4.43s
```

輸出整包 204 KB。這 4.43s 是**整條流程**（抽影格 + 轉錄 + 產生 README）的總時間，約影片長度的 0.05 倍，遠快於即時。不過這高度取決於晶片世代和模型大小——舊機器或改用 `large-v3` 非量化模型會慢上數倍。

---

## 已知限制

1. **這是抽樣，不是「看影片」。** agent 拿到的是 N 張靜態影格。短影片抽 12 張大致等於看完，但**快速閃過的字卡、連續動作的細節、逐格變化的動畫**一定會漏。這類影片請把 `-n` 調到 30 以上，或者接受逐字稿才是主要資訊來源。

2. **Threads 不支援。** yt-dlp 目前沒有 Threads 專屬 extractor。`vid` 會自動 fallback 到 generic 模式去撈網頁的 `og:video`，但成功率不高，別依賴它。

3. **需登入的內容一定要 `-c`。** Instagram 大部分貼文、部分 YouTube 影片不給匿名抓取，沒加 `-c chrome` 會直接下載失敗。而各平台的反爬蟲策略時常改動，`yt-dlp` 沒定期 `brew upgrade` 就容易壞。

4. **中文逐字稿會有錯字。** whisper 對中文的專有名詞、人名、英文夾雜的段落辨識率明顯低於英文，opencc 也只能修字形不能修辨識錯誤。當草稿看，別當引用來源。另外沒裝 `opencc` 的話輸出會停在簡體。

5. **長影片可能讓 whisper 鬼打牆。** 超過 15 分鐘左右的錄音，whisper 偶爾會卡住，同一句重複好幾百行。我跑過 8 支長的教學影片，有 2 支中招。`vid` 預設加 `-mc 0`，每一段辨識都不沿用前文，那 2 支就都好了。另外還有一道保險：同一句連續出現 15 次以上，`逐字稿` 標題就會加上警告。看到警告，那一段別信。

6. **只在 macOS 測試過。** 核心邏輯是標準 POSIX 工具，Linux 理論上把 `brew` 換成 `apt` / `pacman` 就能跑，但沒驗證過，`install.sh` 也會直接拒絕在非 macOS 執行。Windows 沒測過。

---

## 開發

```bash
tests/test_vid.sh
```

測試用真的 `ffmpeg` 產生測試影片，`whisper-cli` 和 `curl` 則換成假的替身，所以幾秒就跑完，也不用下載模型。涵蓋的都是曾經壞過的情境：純音訊檔、音軌比畫面長、沒給 checksum 的自訂模型、checksum 錯誤、下載失敗，還有重複句偵測。每次 push，CI 都會跑 ShellCheck 和這支測試。

---

## 請合理使用

抓下來的內容著作權屬於原作者。這個工具的設計用途是**個人理解、學習研究、內容存證**，不是拿來重製散布別人的作品。請遵守各平台的服務條款。

---

## License

MIT — 見 [LICENSE](LICENSE)。
