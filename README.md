# vid

> Turn any video into things an AI agent can actually read — sampled frames + a transcript.

**AI 讀不懂影片。** Claude、Cursor 這類 coding agent 能看圖、能讀文字，但沒辦法「播放」一支影片——所以你丟一個 Reels 連結給它，它只能跟你說抱歉。

`vid` 就是那道翻譯層：**一行指令，把影片（或 Instagram Reels / TikTok / YouTube 連結）拆成 AI 讀得懂的東西**——依時間均勻抽樣的影格圖 + 全程逐字稿 + 原始貼文文字，全部整理進一個資料夾。你只要跟 AI 說「讀這個資料夾」，它就等於看過了。

全程**在本機跑、$0**，不呼叫任何雲端 API，影片不會離開你的電腦。

---

## 解決的具體問題

| 你想做的事 | 沒有 vid | 有 vid |
|---|---|---|
| 「幫我看這支 Reels 在講什麼」 | AI：我沒辦法看影片 | 讀逐字稿 + 12 張影格，直接摘要 |
| 「這支教學影片的步驟整理成筆記」 | 自己看完自己打字 | 逐字稿含時間軸，AI 直接整理 |
| 「這個 UI 影片裡的畫面長怎樣」 | 截圖給它 | 影格已經抽好，含時間戳檔名 |
| 存證 / 歸檔別人的貼文 | 手動存 | 影片 + 文案 + metadata 一次留存 |

---

## 安裝

macOS（Apple Silicon / Intel，需要 [Homebrew](https://brew.sh)）：

```bash
git clone https://github.com/seanlu2006/vid-for-agents.git
cd vid-for-agents
./install.sh
```

`install.sh` 會裝好相依套件、下載語音模型（約 547 MB，一次性）、把 `vid` 連到 `~/bin` 並提示你加進 PATH。

---

## 用法

```bash
# 本機影片
vid ~/Downloads/clip.mp4

# Instagram Reels（需登入的內容要借瀏覽器 cookie）
vid "https://www.instagram.com/reel/XXXXXXX/" -c chrome

# 中文影片、抽 30 張影格（畫面資訊密集時調高）
vid "https://youtu.be/XXXXXXX" -l zh -n 30

# 只要逐字稿，不抽圖
vid clip.mp4 --no-frames
```

### 選項

| 選項 | 說明 | 預設 |
|---|---|---|
| `-n, --frames N` | 抽幾張影格 | `12` |
| `-l, --lang CODE` | 逐字稿語言（`zh` / `en` / `auto`） | `auto` |
| `-c, --cookies BROWSER` | 借用瀏覽器 cookie（`chrome`/`safari`/`firefox`/`edge`） | 無 |
| `-o, --outdir DIR` | 輸出根目錄 | `~/media-out` |
| `--no-frames` / `--no-audio` | 只要逐字稿 / 只要影格 | 都做 |
| `--no-keep` | 處理完刪掉原始影片 | 保留 |
| `--model NAME` | whisper 模型 | `large-v3-turbo-q5_0` |

---

## 輸出長這樣

```
~/media-out/<標題>-<時間戳>/
├── README.md         ← 給 AI 讀的入口：metadata + 逐字稿全文 + 影格清單
├── meta.json         ← 原始貼文 metadata（標題／作者／讚數／原文）
├── frames/
│   ├── f001_00m01s.jpg   ← 檔名含時間點
│   └── ...
├── transcript.txt    ← 純文字逐字稿
├── transcript.srt    ← 帶時間軸
└── source.mp4        ← 原始影片
```

**用法就一句**：跟你的 AI 說「讀 `~/media-out/xxx/README.md`」。逐字稿和 metadata 都在裡面，要看畫面再叫它讀 `frames/` 的圖。

---

## 運作原理

```
URL ──yt-dlp──► 影片 + 貼文文字
                   │
                   ├──ffmpeg──► 均勻抽樣影格 (JPG, 寬度 ≤768) ──► AI 看圖
                   │
                   └──ffmpeg──► 16kHz 單聲道音軌
                                    │
                              whisper.cpp (Metal 加速, 本機)
                                    │
                              opencc s2twp ──► 台灣正體逐字稿 ──► AI 讀字
```

| 元件 | 角色 |
|---|---|
| `yt-dlp` | 抓影片 + 貼文文字（支援 1700+ 平台） |
| `ffmpeg` | 抽影格、轉音軌 |
| `whisper-cpp` + `large-v3-turbo` | 本機語音轉文字，Apple Silicon 走 Metal |
| `opencc` | 簡體 → 台灣正體（whisper 中文原生輸出是簡體，必轉） |

**實測**：17 秒影片全程處理約 10 秒（M 系列晶片），逐字稿與原始旁白逐字吻合。

---

## 支援平台

✅ Instagram（含 Reels、Stories）、TikTok、YouTube、Facebook Reel、Twitter/X，以及 yt-dlp 支援的其餘 1700+ 站台。

⚠️ **Threads 沒有專屬支援** — yt-dlp 目前沒有 Threads extractor。腳本會自動 fallback 到 generic 模式去撈網頁的 `og:video`，但**不保證成功**。

---

## 已知限制（先講清楚，別踩雷）

1. **這不是「看影片」，是抽樣。** AI 拿到的是 N 張靜態影格，不是連續畫面。短影片（15–60 秒）抽 12 張幾乎等於看完；但**畫面快速閃過重點字卡**的影片會漏，那種請調 `-n 30` 以上。
2. **需登入的內容一定要 `-c chrome`。** Instagram 大部分貼文不給匿名抓。
3. **首次執行會下載 547 MB 模型**，之後不再下載。
4. **長影片轉逐字稿要等。** 本機跑，約為影片長度的 0.5–1 倍時間。
5. **僅測試於 macOS。** Linux 理論上可行（把 `brew` 換成 apt/pacman），但未驗證。

---

## 請合理使用

抓取的內容著作權屬於原作者。這工具的用途是**個人理解、研究、存證**——不是拿去重製散布。請遵守各平台服務條款。

---

## License

MIT
