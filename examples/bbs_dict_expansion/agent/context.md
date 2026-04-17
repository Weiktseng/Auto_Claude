# 環境與工具參考

> 本檔是**環境/工具單一來源**（HOW the environment works）。任務規則、流程、紅線、schema 全看 `spec.txt`；Dev 通用行為看 `dev/prompt.md`。

## 主專案
`BBS_meet` 會議摘要系統。工作暫存檔放 `.auto_claude/workspace/`（已 gitignore audio / transcript）。

## 關鍵路徑
- 擴充目標：`/home/henry/BBS_meet/meeting_summarizerV9/config/terminology_public.json`
- pytest：`cd /home/henry/BBS_meet/meeting_summarizerV9 && python -m pytest tests/ -v -x --timeout=60 --ignore=tests/test_full_pipeline.py`
- Candidates 落地：`.auto_claude/workspace/candidates/round_N.json`
- Transcripts 落地：`.auto_claude/workspace/transcripts/<KEY>.txt`

## ASR：MeetLingo Docker Worker

公司真實 ASR 在 `meetlingo-worker-transcribe` 容器（常駐、單 GPU、faster-whisper large-v3 + diarization）。**不**用本地 WhisperX（`speaker_diarization/` 那份是沙盒實驗，別碰）。

### 一行呼叫：`.auto_claude/tools/asr_via_docker.sh`
把 yt-dlp → ffmpeg 切段 → 音量預檢 → `docker cp` 進 → ASR → `docker cp` 出 → 清乾淨 全包了。trap 確保任何 exit 都清 host + container `/tmp`。

```bash
# URL 模式
KEY_OUT=$(.auto_claude/tools/asr_via_docker.sh --url "<URL>" --round $ROUND --duration 600 --start 300)
# local 檔模式
KEY_OUT=$(.auto_claude/tools/asr_via_docker.sh --audio /tmp/some.m4a --round $ROUND --duration 600)

KEY="${KEY_OUT#KEY=}"
TRANSCRIPT=".auto_claude/workspace/transcripts/${KEY}.txt"
```

**退出碼：**
- `0` 成功
- `2` 容器沒在跑 → 寫 `comms/human_reply.md` 回報人類；**不自動啟動**
- `3` 靜音（mean_volume < -40 dB）→ 換 `--start 600/900/1200` 重試，仍靜音就換素材
- `4` ASR 沒產出 → 換素材
- `1` 其他錯誤

**先看標題時長再下載**（省時間 + 避免無關內容）：
```bash
~/.local/bin/yt-dlp --get-duration --get-title "<URL>"
```

### Script 內部 7 步（壞了看這裡手動重跑 debug）

1. **容器存活檢查**：`docker ps --format '{{.Names}}' | grep -qx meetlingo-worker-transcribe`；沒跑 → exit 2
2. **取音檔到 host `/tmp`**：
   ```bash
   # URL：先 raw 再切段
   ~/.local/bin/yt-dlp -f "bestaudio[ext=m4a]/bestaudio" -o /tmp/${KEY}.raw "<URL>"
   ffmpeg -y -ss $START -i /tmp/${KEY}.raw -t $DURATION -c:a aac -b:a 128k /tmp/${KEY}.m4a
   # audio：直接切
   ffmpeg -y -ss $START -i "$AUDIO" -t $DURATION -c:a aac -b:a 128k /tmp/${KEY}.m4a
   ```
   ⚠️ 用 `-c:a aac` 重編（不用 `-c copy`），否則 mp3-in-m4a 的檔會炸
3. **音量預檢**：
   ```bash
   ffmpeg -hide_banner -i /tmp/${KEY}.m4a -af volumedetect -f null - 2>&1 \
     | grep -oE 'mean_volume: -?[0-9.]+' | awk '{print $2}'
   ```
   - `-hide_banner` 保留 info 層級（`-v error` 會把 volumedetect 壓掉）
   - `|| true` 收尾，避免 pipefail + grep 0 match 誤殺整個 script
4. **docker cp 進 container**：`docker cp /tmp/${KEY}.m4a meetlingo-worker-transcribe:/tmp/`
   - 走 container `/tmp`（非 volume mount）因為 sam 的 `/home/sam/MeetLingo/output/` henry 無寫權限
5. **docker exec 跑 ASR**：
   ```bash
   docker exec -e TRANSCRIPT_DIR=/tmp meetlingo-worker-transcribe \
       python tests/test_transcript_api.py "$KEY" --audio_file "/tmp/${KEY}.m4a"
   ```
   - `TRANSCRIPT_DIR=/tmp` 覆蓋容器預設 `output/.transcripts`，讓輸出也落 container `/tmp`
   - `test_transcript_api.py` 吃 `--audio_file` 就走 `transcript_local_flow()`，直接叫 `process_transcription_job()`，跳過 API/下載
6. **docker cp 取回**：`docker cp meetlingo-worker-transcribe:/tmp/${KEY}.txt .auto_claude/workspace/transcripts/`
7. **清乾淨（trap EXIT）**：
   ```bash
   rm -f /tmp/${KEY}.m4a /tmp/${KEY}.raw
   docker exec meetlingo-worker-transcribe rm -f /tmp/${KEY}.m4a /tmp/${KEY}.txt
   ```

### 容器限制
- `TRANSCRIBE_PARALLEL=1`、單 GPU → 平行跑 script 只會在 GPU 排隊，**不加速**
- 10 min 音檔約 1-2 分鐘轉完
- 容器是**產線服務**，絕不 `start/stop/restart/kill`

## Reviewer / Curator 機制（DUMB_REVIEWER=1）
`run.sh` 啟動時 `export DUMB_REVIEWER=1`。engine loop 會：
- Reviewer `claude --print` 替換成 `cat agent/reviewer_stub.md`（0 API call）
- Curator 整段跳過
- Dev session 跨輪保留（不 reset context）

所以每輪只有 Dev 一次 Claude call。Dev 看到的「Reviewer 回覆」就是 `reviewer_stub.md` 裡的固定文字。

## Git 規則
- 每輪必 commit，格式 `round N: +X entries (<short-topic>)`
- 破測試 → `git checkout meeting_summarizerV9/config/terminology_public.json` 回上輪
- audio/transcript 在 `.gitignore`（不會誤 commit）
- **不 push**

## 人類溝通
- Dev → 人類：寫 `agent/comms/human_reply.md`（追加）
- 人類 → Dev：寫 `agent/comms/human_message.md`（engine 下一輪讀入當「最高優先插話」，讀完自動清空）
- Dev **不要寫** `human_message.md`，會造成自言自語迴圈
