#!/usr/bin/env bash
# asr_via_docker.sh — 把 yt-dlp→切段→預檢→ASR→取回→清乾淨 包成一行
#
# 原則：只用 docker exec / docker cp，絕不 start/stop/restart/kill 容器。
# 容器是產線服務，本 script 碰到它沒在跑就直接 fail，等人處理。
#
# 用法：
#   tools/asr_via_docker.sh --url <URL>   [--start S] [--duration S] [--round N]
#   tools/asr_via_docker.sh --audio <FILE> [--start S] [--duration S] [--round N]
#
# stdout:  KEY=<key>         （只這行，給 pipeline 讀）
# stderr:  進度訊息
# 輸出檔: .auto_claude/workspace/transcripts/<KEY>.txt
#
# 退出碼:
#   0  成功
#   1  參數錯誤
#   2  容器沒在跑（不要擅自啟動）
#   3  音量 < -40 dB（建議換 --start 或換來源）
#   4  ASR 沒產出逐字稿（container /tmp 空）

set -euo pipefail

URL=""
AUDIO=""
START=0
DURATION=900
ROUND=0
OUT=".auto_claude/workspace/transcripts"
CONTAINER="meetlingo-worker-transcribe"

usage() { sed -n '3,20p' "$0" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)       URL="$2"; shift 2 ;;
        --audio)     AUDIO="$2"; shift 2 ;;
        --start)     START="$2"; shift 2 ;;
        --duration)  DURATION="$2"; shift 2 ;;
        --round)     ROUND="$2"; shift 2 ;;
        --out)       OUT="$2"; shift 2 ;;
        --container) CONTAINER="$2"; shift 2 ;;
        -h|--help)   usage ;;
        *) echo "unknown: $1" >&2; usage ;;
    esac
done

[[ -z "$URL" && -z "$AUDIO" ]] && usage
[[ -n "$URL" && -n "$AUDIO" ]] && { echo "❌ --url / --audio 擇一" >&2; exit 1; }

# --- 容器存活檢查（不自動啟動）---
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "❌ container 未運行: $CONTAINER" >&2
    echo "   產線服務不要擅自啟動；檢查: docker ps -a | grep $CONTAINER" >&2
    exit 2
fi

mkdir -p "$OUT"
KEY="bbs_dict_r${ROUND}_$(date +%s)"
HOST_AUDIO="/tmp/${KEY}.m4a"
HOST_TRANSCRIPT="${OUT}/${KEY}.txt"

# 任何 exit（含錯誤）都嘗試清 host + container /tmp；transcript 已 docker cp 出來就留著
cleanup() {
    rm -f "$HOST_AUDIO" "/tmp/${KEY}.raw"
    docker exec "$CONTAINER" rm -f "/tmp/${KEY}.m4a" "/tmp/${KEY}.txt" 2>/dev/null || true
}
trap cleanup EXIT

echo "🔑 KEY=$KEY" >&2

# --- 取得音檔到 host /tmp ---
if [[ -n "$URL" ]]; then
    echo "⬇️  yt-dlp $URL" >&2
    RAW="/tmp/${KEY}.raw"
    if ! ~/.local/bin/yt-dlp -q -f "bestaudio[ext=m4a]/bestaudio" -o "$RAW" "$URL" 2>&1 | tee /dev/stderr | grep -v "^$" >/dev/null; then
        echo "❌ yt-dlp 失敗" >&2
        rm -f "$RAW"
        exit 1
    fi
    echo "✂️  ffmpeg -ss $START -t $DURATION" >&2
    ffmpeg -y -v error -ss "$START" -i "$RAW" -t "$DURATION" -c:a aac -b:a 128k "$HOST_AUDIO" 2>&1 >&2
    rm -f "$RAW"
else
    [[ -f "$AUDIO" ]] || { echo "❌ 音檔不存在: $AUDIO" >&2; exit 1; }
    echo "✂️  ffmpeg $AUDIO -ss $START -t $DURATION" >&2
    ffmpeg -y -v error -ss "$START" -i "$AUDIO" -t "$DURATION" -c:a aac -b:a 128k "$HOST_AUDIO" 2>&1 >&2
fi

# --- 音量預檢 ---
VOL=$(ffmpeg -hide_banner -i "$HOST_AUDIO" -af volumedetect -f null - 2>&1 \
      | grep -oE 'mean_volume: -?[0-9.]+' | awk '{print $2}' || true)
if [[ -n "$VOL" ]]; then
    echo "🔊 mean_volume=$VOL dB" >&2
    if awk "BEGIN {exit !($VOL < -40)}"; then
        echo "❌ 靜音 < -40 dB（換 --start 或換來源）" >&2
        rm -f "$HOST_AUDIO"
        exit 3
    fi
else
    echo "⚠️  音量偵測失敗，照送" >&2
fi

# --- 進 container → ASR → 出 container ---
docker cp "$HOST_AUDIO" "${CONTAINER}:/tmp/${KEY}.m4a" >&2
echo "🎙️  ASR running..." >&2
docker exec -e TRANSCRIPT_DIR=/tmp "$CONTAINER" \
    python tests/test_transcript_api.py "$KEY" \
    --audio_file "/tmp/${KEY}.m4a" >&2

if ! docker cp "${CONTAINER}:/tmp/${KEY}.txt" "$HOST_TRANSCRIPT" 2>/dev/null; then
    echo "❌ /tmp/${KEY}.txt 不存在（ASR 失敗？）" >&2
    exit 4
fi

CHARS=$(wc -c < "$HOST_TRANSCRIPT")
echo "✅ $HOST_TRANSCRIPT ($CHARS chars)" >&2
echo "KEY=$KEY"
