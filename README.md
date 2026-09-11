# vid

[繁體中文](README.zh-TW.md)

> One command turns a video into the two things an AI agent can actually read: sampled frames and a full transcript. The processing runs on your own machine, so every video costs $0.

---

## The problem

Coding agents like Claude Code and Cursor read images and they read text. They cannot play video. Paste a Reel link into one and it tells you, politely, that it can't watch it.

So every time you want an agent to digest a tutorial, a competitor's UI walkthrough, or a post you want archived, you end up doing the slow part yourself — watching it, screenshotting it, typing out what was said. The part the agent can't help with is exactly the part that takes the time.

## The idea

An agent doesn't need to *watch* a video. It needs what's in the video, and that splits cleanly into two tracks:

- **Picture** → stills sampled at even intervals along the timeline. Most videos change far more slowly than 30 times a second; for a short clip, 12 frames covers essentially every scene.
- **Sound** → a full transcript. Every word of the narration, none of it dropped.

Both are things an agent can already read. `vid` takes any video — a local file, or any URL `yt-dlp` handles (YouTube, Instagram, TikTok, and so on) — splits it into those two tracks, adds the original post's metadata, and puts everything in one folder. The `README.md` it writes there is **designed to be the agent's entry point**.

Transcription runs locally through `whisper.cpp`. The video never leaves your laptop, and the hundredth video costs the same as the first. The only network traffic is `yt-dlp` fetching the video and a one-time model download.

---

## Install

**Requirements:** macOS (Apple Silicon or Intel), [Homebrew](https://brew.sh), and `python3`.

> macOS doesn't ship `python3`. If you don't have it: `xcode-select --install`, or `brew install python`.

### One command

```bash
git clone https://github.com/seanlu2006/vid-for-agents.git
cd vid-for-agents
./install.sh
```

`install.sh` does four things, and only these four:

| Step | Detail |
|---|---|
| `brew install` what's missing | `ffmpeg`, `yt-dlp`, `whisper-cpp`, `opencc` — anything already installed is skipped |
| Download the speech model | ~547 MB, one time, into `~/.cache/whisper-models/` |
| Create a symlink | `~/bin/vid` → the `vid` in your clone |
| Check your PATH | if `~/bin` isn't on it, the installer **prints** the line to add and leaves you to run it |

It doesn't edit your `.zshrc` or `.bashrc`, doesn't use `sudo`, and doesn't pipe a remote script into a shell. Step 3 is a symlink, so don't delete or move the cloned folder afterwards — `vid` points back into it.

### Manual install

```bash
brew install ffmpeg yt-dlp whisper-cpp opencc
git clone https://github.com/seanlu2006/vid-for-agents.git
cd vid-for-agents && chmod +x vid
mkdir -p ~/bin && ln -s "$PWD/vid" ~/bin/vid   # or any directory already on your PATH
```

No need to fetch the speech model by hand — `vid` downloads it the first time it has something to transcribe.

### What each dependency is for

| Package | Used for | If it's missing |
|---|---|---|
| `ffmpeg` / `ffprobe` | extracting frames, converting audio, reading video properties | hard stop |
| `python3` | frame timestamp arithmetic, metadata → Markdown | hard stop |
| `yt-dlp` | downloading videos and post text | only needed for URLs; local files never touch it |
| `whisper-cpp` | local speech-to-text | transcript skipped, frames still extracted |
| `opencc` | Simplified → Traditional Chinese | Chinese transcripts stay in Simplified |

---

## Usage

```
vid <URL or path to a local file> [options]
```

### A local file

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

The CLI itself speaks Traditional Chinese; the flags are in English. That last line says: *tell Claude to read `…/README.md` — the transcript is in there — and look at the images under `frames/` when you need the picture.* See [Known limitations](#known-limitations).

What you get:

```
~/media-out/demo-20260911-004512/
├── README.md          the entry point for the agent
├── frames/
│   ├── f001_00m03s.jpg
│   ├── f002_00m10s.jpg
│   ├── …
│   └── f012_01m19s.jpg
├── transcript.txt     plain text
└── transcript.srt     with timecodes
```

Roughly 200 KB in total. A local file produces no `meta.json` (there's no post to read) and no copy of the source video — your file is already on disk and `vid` never touches it.

### YouTube

```bash
vid "https://www.youtube.com/watch?v=XXXXXXXXXXX" -l zh -n 30
```

`-l zh` pins the transcript language; pinning it is more accurate than leaving Whisper to auto-detect. `-n 30` takes 30 frames instead of 12 — worth doing when there's a lot on screen. Two extra files appear:

```
~/media-out/How-to-make-an-agent-read-a-video-20260911-004512/
├── README.md
├── meta.json          the full metadata yt-dlp collected
├── frames/            30 of them
├── transcript.txt
├── transcript.srt
└── source.mp4         the downloaded video (extension follows the actual download)
```

Downloads prefer the best stream at 1080p or below and are merged into an MP4. When a site offers only a single pre-muxed stream, `yt-dlp` falls back to its best available format, which may exceed 1080p and may not be an MP4 — so the saved file takes the extension of whatever actually came down, and isn't always `source.mp4`. A URL pointing at a video *inside* a playlist (`…&list=…`) gives you just that one video; a bare playlist URL is not supported, and pointing `vid` at one gives unpredictable results.

### Instagram Reels

Anything behind a login needs your browser's cookies:

```bash
vid "https://www.instagram.com/reel/XXXXXXXXXXX/" -c chrome
```

`-c chrome` has `yt-dlp` read Chrome's cookie database; on macOS that may trigger a Keychain prompt. It happens entirely on your machine and the cookies aren't sent anywhere — but if you'd rather not, use `-c safari`, or just download the video yourself and hand `vid` the local file.

### The `README.md` it generates

```markdown
# 影片內容包

- 來源: `https://www.youtube.com/watch?v=XXXXXXXXXXX`
- 時長: 83s ｜ 解析度: 1280x720
- 產生時間: 2026-09-11 00:45:14

## 貼文 / 影片 metadata

- **title**: How to make an agent read a video
- **uploader**: Sean Lu
- **upload_date**: 20260901
- **view_count**: 1234
- **webpage_url**: https://www.youtube.com/watch?v=XXXXXXXXXXX

### 原始貼文文字

(the post's own text, first 4,000 characters)

## 逐字稿

(the whole transcript, inline, right here)

帶時間軸版本: `transcript.srt`

## 影格（用 Read 工具逐張看）

- `frames/f001_00m03s.jpg` (t=00m03s)
- `frames/f002_00m10s.jpg` (t=00m10s)
- …
```

The headings are Chinese — `影片內容包` is "video content pack", `逐字稿` is "transcript", `影格` is "frames". The shape is what matters, and every agent I've tried has read it without complaint.

If Whisper fails, or the video has no audio track, a short Chinese note is appended to the `逐字稿` heading explaining why. A failed run also leaves `audio.wav` (16 kHz mono) in the folder so you can retry by hand.

### Options

| Option | What it does | Default |
|---|---|---|
| `-n, --frames N` | how many frames to sample | `12` |
| `-l, --lang CODE` | transcript language: `zh`, `en`, `ja`, and so on, or `auto` to detect | `auto` |
| `-c, --cookies BROWSER` | borrow browser cookies for login-gated content: `chrome` / `safari` / `firefox` / `edge` | off |
| `-o, --outdir DIR` | output root | `~/media-out` |
| `--model NAME` | Whisper model | `large-v3-turbo-q5_0` |
| `--no-frames` | transcript only | does both |
| `--no-audio` | frames only | does both |
| `--keep-video` | keep the downloaded video | already the default |
| `--no-keep` | delete the downloaded video when done | keeps it |
| `-h, --help` | usage | — |

A few things worth knowing:

- `--keep-video` and `--no-keep` **only apply to videos downloaded from a URL**. On a local file both are no-ops; `vid` never modifies or deletes your own file.
- `--model` is interpolated into `ggml-<NAME>.bin` and fetched from [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp). For speed try `base` or `small`; for accuracy try `large-v3`. That repo has the full list.
- `-c` is passed straight through to `yt-dlp --cookies-from-browser`, so anything `yt-dlp` supports works, not just the four listed above.
- Output directories are named `<title slug>-<YYYYMMDD-HHMMSS>`. The slug keeps ASCII alphanumerics and Han characters (U+4E00–U+9FFF), collapses everything else into a single `-`, and is cut off at 50 characters. Note that this drops Japanese kana, Hangul, Cyrillic, and accented Latin: `アニメの作り方` becomes `作-方`, and a title made only of such characters falls back to `video`. The timestamp means two runs never overwrite each other.

---

## Using it with an agent

This is the reason the tool exists. With Claude Code:

```bash
# 1. in your terminal
vid "https://www.youtube.com/watch?v=XXXXXXXXXXX" -l en
# → ✅ 完成 → /Users/you/media-out/How-to-make-an-agent-read-a-video-20260911-004512
```

```
# 2. in Claude Code
> read ~/media-out/How-to-make-an-agent-read-a-video-20260911-004512/README.md and turn
  the steps in this video into notes
```

One `Read` gets the agent the metadata and the entire transcript, so it can start immediately. When you need the picture, ask for it:

```
> what's he demoing around the four-minute mark? look at the matching frame
```

It picks the closest timestamp from the frame list and reads that one image.

### Why the entry file is shaped this way

The generated `README.md` makes one deliberate trade: **the transcript is embedded in full; the frames are listed by filename and never embedded.**

Text is cheap and images are expensive. Inlining the transcript means a single read tells the agent what the video is about — no hunting. Inlining 12 images would burn a large amount of context on pictures that mostly go unused. So the frames appear as a filename plus a timestamp, and the agent decides which ones are worth opening. In practice, once it has the transcript, one or two frames are enough to answer the question.

Nothing here is specific to Claude Code. The output is an ordinary folder of ordinary files — any agent that can read a file and look at an image works the same way.

---

## How it works

```
input ─┬─ URL ──────────► yt-dlp ──► video file + info.json
       │                             (title / uploader / post text / likes)
       └─ local file ────► used in place

                           video file
                                │
              ┌─────────────────┴─────────────────┐
              │                                   │
           ffmpeg                              ffmpeg
              │                                   │
     evenly sampled frames               16 kHz mono WAV
     (JPEG, ≤768 px wide)                         │
              │              whisper.cpp (local; Metal on Apple Silicon)
              │                                   │
              │                     transcript.txt / transcript.srt
              │                                   │
              │              opencc s2twp (Simplified → Traditional Chinese)
              └─────────────────┬─────────────────┘
                                │
        generated README.md (metadata + full transcript + frame index)
```

### The decisions behind each stage

**Sampling.** Frame *i* is taken at `t = duration × (i − 0.5) / N` — the midpoint of each equal slice rather than its edge, which sidesteps the black frames and transitions that tend to sit at the very beginning and end. Frames are scaled to 768 px wide (never upscaled beyond their original width) at JPEG quality `-q:v 4`. That size sits near the processing resolution of most vision models; anything larger just wastes tokens.

**Local Whisper rather than a cloud API**, for three reasons:

1. **Cost.** One video and a hundred videos both cost $0, so you never have to decide whether a clip is worth paying to transcribe.
2. **Privacy.** Personal recordings, meeting notes, and unreleased material don't get handed to a third party.
3. **No ceilings.** No file size limit, no rate limit, works offline.

The price is a 547 MB download the first time, and a genuine wait on long videos — though `whisper.cpp` uses Metal on Apple Silicon, which makes it quicker than you'd expect (numbers below).

**Simplified to Traditional.** Whisper's Chinese output is always Simplified, with mainland vocabulary. `opencc -c s2twp` converts word choice as well as glyphs (软件 → 軟體, 视频 → 影片), which for a Taiwanese reader isn't optional.

**Cleanup.** Downloads go to a `mktemp -d` directory that an `EXIT` trap removes, so a failed download or a Ctrl-C doesn't strand a full video in `/var/folders`. `vid` looks for the Whisper binary under every name it has shipped under: `whisper-cli`, `whisper-cpp`, `whisper`, then `main`.

### Measured on my machine

An 83-second 1280×720 clip, 12 frames plus an English transcript, on an Apple M5:

```
real 4.43s
```

Output is 204 KB in total. That 4.43s covers the whole pipeline — frame extraction, transcription, and README generation — which works out to about 0.05× the length of the video, or roughly 20× faster than real time. That ratio depends heavily on chip generation and model size: an older machine, or the unquantised `large-v3`, will be several times slower.

---

## Known limitations

1. **This is sampling, not watching.** The agent gets N stills. Twelve frames of a short clip is roughly equivalent to having seen it, but **fast-cut title cards, the details within a continuous action, and frame-by-frame animation will be missed**. For that kind of video, push `-n` above 30, or accept that the transcript is the primary source.

2. **Threads doesn't work.** `yt-dlp` has no Threads extractor. `vid` falls back to the generic extractor and tries to pull `og:video` from the page, but the success rate is low — don't build on it.

3. **Login-gated content needs `-c`.** Most Instagram posts and some YouTube videos refuse anonymous downloads and will simply fail without `-c chrome`. Platform anti-scraping measures also change constantly, so a `yt-dlp` you haven't `brew upgrade`d in a while is a common cause of breakage.

4. **Chinese transcripts contain errors.** Whisper is noticeably weaker on Chinese proper nouns, names, and passages that mix in English, and `opencc` only fixes characters, not misrecognition. Treat the output as a draft, not as something to quote. Without `opencc` installed, the output stays in Simplified.

5. **The interface is in Traditional Chinese.** `vid --help`, the progress lines, the error messages, and the section headings of the generated `README.md` are all in Chinese. The flags are in English and agents read the output fine, but nothing else is translated yet.

6. **Only tested on macOS.** It's all standard POSIX tooling, so Linux should work if you swap `brew` for `apt` or `pacman`, but I haven't verified that, and `install.sh` refuses to run anywhere other than macOS. Windows is untested.

---

## Please use this responsibly

What you download belongs to whoever made it. This tool is built for understanding things yourself, for study, and for keeping a record — not for reproducing and redistributing other people's work. Respect the terms of the platforms you pull from.

---

## License

MIT — see [LICENSE](LICENSE).
