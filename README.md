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
| Download and verify the models | the ~547 MB speech model and the ~0.9 MB Silero VAD model, one time, into `~/.cache/whisper-models/`; pinned upstream revisions and SHA-256 are checked |
| Create a symlink | `~/bin/vid` → the `vid` in your clone |
| Check your PATH and `swiftc` | if `~/bin` isn't on it, the installer **prints** the line to add and leaves you to run it; if `swiftc` is missing, it says OCR will be skipped and how to get it |

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
| `swiftc` (Xcode Command Line Tools) | reading on-screen text with macOS Vision | OCR skipped, everything else runs |

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
├── ocr.json           text found on each frame (macOS)
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

If Whisper fails, or the file has no audio track, a short Chinese note is appended to the `逐字稿` heading explaining why. A Whisper failure leaves `audio.wav` (16 kHz mono) in the folder so you can retry by hand. Any other failure midway, such as a model download that breaks, removes the half-built folder instead.

Audio-only files work too: a podcast episode, a voice memo. There is no picture to sample, so you get the transcript, and the header reads `解析度: 無畫面` ("resolution: no picture"). If a single frame can't be extracted, it's skipped with a warning and the run carries on. The `影格` heading then says how many were lost.

On macOS, `vid` also reads the text on every frame: burned-in captions, title cards, slide bullets. It goes under each frame in the generated README, so the agent learns what the screen says without opening a single image. Burned-in captions tend to stay put for several frames, so when a frame shows exactly the same text as the one before it, the README says `（同上一張）` ("same as previous") instead of repeating it. A frame with no text at all says `（無）` ("none"), which is shorter than pointing back and needs no lookup. The raw results are kept in `ocr.json`.

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
| `--no-ocr` | don't read on-screen text | reads it on macOS |
| `--no-vad` | send the whole audio track to Whisper, silence included | filters silence first |
| `--uniform` | sample frames at even intervals only, ignoring scene changes | mixes in scene changes |
| `--keep-video` | keep the downloaded video | already the default |
| `--no-keep` | delete the downloaded video when done | keeps it |
| `-h, --help` | usage | — |

A few things worth knowing:

- `--keep-video` and `--no-keep` **only apply to videos downloaded from a URL**. On a local file both are no-ops; `vid` never modifies or deletes your own file.
- `--model` is interpolated into `ggml-<NAME>.bin` and fetched from a pinned revision of [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp). The checksum is checked once, at download time: the default model against its upstream SHA-256, a custom model against `WHISPER_MODEL_SHA256` if you set it. Without that variable a custom model still downloads, with a warning that it went unverified. A model already on disk is trusted and never re-hashed. Hashing 547 MB on every run would cost about a second each time.
- `-c` is passed straight through to `yt-dlp --cookies-from-browser`, so anything `yt-dlp` supports works, not just the four listed above.
- Output directories are named `<title slug>-<YYYYMMDD-HHMMSS>`. The slug keeps ASCII alphanumerics and Han characters (U+4E00–U+9FFF), collapses everything else into a single `-`, and is cut off at 50 characters. Note that this drops Japanese kana, Hangul, Cyrillic, and accented Latin: `アニメの作り方` becomes `作-方`, and a title made only of such characters falls back to `video`. If two runs start in the same second, an exclusive numeric suffix is added rather than reusing an existing directory.

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
  scene-change + even frames             16 kHz mono WAV
     (JPEG, ≤768 px wide)                         │
              │                     Silero VAD (drops silence)
     macOS Vision OCR                             │
     (text on screen)        whisper.cpp (local; Metal on Apple Silicon)
              │                                   │
              │                     transcript.txt / transcript.srt
              │                                   │
              │              opencc s2twp (Simplified → Traditional Chinese)
              └─────────────────┬─────────────────┘
                                │
   generated README.md (metadata + full transcript + frames with their text)
```

### The decisions behind each stage

**Sampling.** A quarter of the frames go to the sharpest scene changes; the rest are spread evenly across the timeline. `ffmpeg`'s `scdet` filter scores every frame at 6 fps and 320 px wide, which took 0.8 s on a 5-minute video, and the highest-scoring moments are taken 0.35 s after the cut so the frame lands past the transition. Each even-interval frame sits at `t = video duration × (i − 0.5) / N`, the midpoint of its slice rather than its edge, which sidesteps the black frames that tend to open and close a video. "Video duration" means the video stream, not the container: Reels often pair a 3-second clip with a 10-second soundtrack, and measuring the container would put most frames after the picture has ended.

The mix is there because neither half wins alone. I tested both on a card that flashes for 0.6 seconds: even sampling missed it and spent two of its four frames on the same shot, while scene detection caught it. On a 5-minute slide recording the result reversed, because the picture changes as annotations are drawn and scene picks bunch up around them. At a quarter, the flash card is still caught and the slide recording keeps all 11 distinct screens it had before. `--uniform` turns the scene half off.

Frames are scaled to 768 px wide (never upscaled beyond their original width) at JPEG quality `-q:v 4`. That size sits near the processing resolution of most vision models; anything larger just wastes tokens.

**On-screen text.** Apple's Vision framework ships with macOS, so OCR needs no download and no extra package. The Swift code that calls it is embedded in `vid` and compiled once into `~/.cache/vid/` the first time it's needed, which keeps the script a single file. Recognition languages are pinned to Traditional Chinese, then English, instead of being left to auto-detect. On a 5-minute trading tutorial, 12 frames came back as 118 lines of text (1,286 characters), and those lines included the step-by-step rules written on the slides. For comparison, opening 12 images would cost the agent far more context than that.

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

1. **This is sampling, not watching.** The agent gets N stills. Twelve frames of a short clip is roughly equivalent to having seen it, but **the details within a continuous action and frame-by-frame animation will be missed**. Scene detection catches most title cards, including one that was on screen for 0.6 seconds in my test, but a card that appears without a clear cut can still slip between two samples. For that kind of video, push `-n` above 30, or accept that the transcript is the primary source.

2. **Threads doesn't work.** `yt-dlp` has no Threads extractor. `vid` falls back to the generic extractor and tries to pull `og:video` from the page, but the success rate is low — don't build on it.

3. **Login-gated content needs `-c`.** Most Instagram posts and some YouTube videos refuse anonymous downloads and will simply fail without `-c chrome`. Platform anti-scraping measures also change constantly, so a `yt-dlp` you haven't `brew upgrade`d in a while is a common cause of breakage.

4. **Chinese transcripts contain errors.** Whisper is noticeably weaker on Chinese proper nouns, names, and passages that mix in English, and `opencc` only fixes characters, not misrecognition. Treat the output as a draft, not as something to quote. Without `opencc` installed, the output stays in Simplified.

   `opencc`'s Taiwan phrase list also leans software: it turns 类型 into 型別, the word a programmer uses, which was wrong six times in one trading tutorial. `vid` puts that one back to 類型 and keeps the rest of the phrase conversions (軟體, 記憶體, 影片, 資訊, 網路). Add your own pairs with `VID_OPENCC_FIXES="型別=類型,專案=項目"`.

5. **Long videos can send Whisper into a loop.** On recordings longer than about 15 minutes, Whisper sometimes gets stuck and repeats one sentence for hundreds of lines. It happened on 2 of the 8 long tutorial videos I ran. `vid` passes `-mc 0`, so each segment is decoded without the previous text as context, and it runs Silero VAD first, so silent and music-only stretches never reach Whisper. I reran those two videos (21 and 23 minutes) with each setting. Either one stops the loop on its own. Together they also cut transcription time by about a quarter on an M5 (32 → 24 s and 34 → 25 s), the amount of text stays within 1%, and the timestamps still line up with the original video. As a backstop it also scans the transcript: if any line repeats 15 or more times in a row, the `逐字稿` heading gets a warning. Treat that stretch as unreliable.

6. **OCR misreads the odd character and mixes columns.** Expect single-character slips (`的` came back as `約` in one test). Lines are ordered top to bottom, so a slide with text on the left and a labelled chart on the right comes out interleaved. OCR only runs on macOS; elsewhere it's skipped.

7. **The interface is in Traditional Chinese.** `vid --help`, the progress lines, the error messages, and the section headings of the generated `README.md` are all in Chinese. The flags are in English and agents read the output fine, but nothing else is translated yet.

8. **Only tested on macOS.** It's all standard POSIX tooling, so Linux should work if you swap `brew` for `apt` or `pacman`, but I haven't verified that, and `install.sh` refuses to run anywhere other than macOS. Windows is untested.

---

## Development

```bash
tests/test_vid.sh
```

The tests run the real `ffmpeg` against generated clips and swap in stand-ins for `whisper-cli` and `curl`, so all 23 finish in seconds and never download the model. They cover the cases that have broken before: audio-only input, audio longer than the picture, custom models without a checksum, a wrong checksum, a failed download, the repeated-line check, VAD and its fallbacks, the phrase corrections after `opencc`, and a non-UTF-8 locale. The OCR tests are the exception to the stand-ins: they draw caption cards, turn them into a video, and run real Vision on it, so they need macOS with `swiftc`. CI runs ShellCheck and the same script on every push, with `VID_REQUIRE_OCR=1` so the OCR tests can't be skipped quietly.

---

## Related projects

[`claude-real-video`](https://github.com/HUANGCHIHHUNGLeo/claude-real-video) (2.1k stars, MIT) answers the same question and started three months before this one did. It does more: scene detection with sliding-window dedup, speaker diarization, an MCP server and a Claude Code plugin, a web viewer. If you want the fuller tool, use that one.

What's different here is narrow. `vid` is one bash file with no Python package to install, and the Traditional Chinese path is the part I actually use: Whisper's Simplified output converted for Taiwan with the software-flavoured phrases corrected, and OCR pinned to Traditional Chinese rather than left to auto-detect. That's the whole claim.

---

## Please use this responsibly

What you download belongs to whoever made it. This tool is built for understanding things yourself, for study, and for keeping a record — not for reproducing and redistributing other people's work. Respect the terms of the platforms you pull from.

---

## License

MIT — see [LICENSE](LICENSE).
