# Auto_Claude

全自動 Dev ↔ Reviewer 開發迴圈 + Claude Code 權限自動化。

> 詳細系統架構、Prompt 組裝、權限標示 → **[ARCHITECTURE.md](ARCHITECTURE.md)**
> 權限 5 層教學 → **[GUIDE.md](GUIDE.md)**

## 30 秒看懂

```
  Reviewer（審查者）          Dev（開發者）
  ┌──────────┐              ┌──────────┐
  │ 讀 spec  │── 回饋 ──→   │ 寫程式    │
  │ 讀 todo  │              │ 跑測試    │
  │ 只讀工具  │←── 結果 ──   │ 全工具    │
  └──────────┘              └──────────┘
       ↑                         ↑
  engine/loop.sh 每輪自動串接，人類可隨時插話
```

兩個 AI 對話推進專案。Reviewer 審查 + 派任務，Dev 動手做。人類睡覺，AI 工作。

## 快速開始

### 用現有專案（交通部）

```bash
./projects/motc/run.sh --max-rounds 50
```

### 新增專案

```bash
# 1. 複製模板
cp -r templates projects/moa

# 2. 改 projects/moa/run.sh 裡的 --project-dir
# 3. 放入 spec.txt（規範書）
# 4. 改 prompts/reviewer.prompt.md（角色 + 任務清單）
# 5. 改 context.md（API keys + 開發規則）
# 6. 確保目標專案有 .claude/settings.local.json

# 7. 跑
./projects/moa/run.sh --max-rounds 50
```

### 常用指令

```bash
# 背景執行
nohup ./projects/motc/run.sh --max-rounds 50 > projects/motc/logs/overnight.log 2>&1 &

# 檢查活著沒
cat projects/motc/logs/heartbeat

# 看即時 log
tail -f projects/motc/logs/*_loop.md

# 人類插話（下一輪 dev 會讀到，讀完自動清）
echo "先把測試補齊" > projects/motc/comms/human_message.md

# 看 dev 的回覆
cat projects/motc/comms/human_reply.md

# 停止
kill $(cat projects/motc/logs/heartbeat | python3 -c "import sys,json;print(json.load(sys.stdin)['pid'])")
```

### 參數

| 參數 | 預設 | 說明 |
|------|------|------|
| `--project-dir` | 必填 | 目標專案路徑 |
| `--spec` | 必填 | 規範書路徑 |
| `--prompt-template` | 必填 | Reviewer prompt 路徑 |
| `--context` | 向後相容 | context.md 路徑 |
| `--comms-dir` | PROJECT_DIR | 非同步溝通目錄 |
| `--log-dir` | engine/logs | log 目錄 |
| `--model-reviewer` | opus | Reviewer 模型 |
| `--model-dev` | opus | Dev 模型 |
| `--max-rounds` | 10 | 最大輪數 |
| `--initial-prompt` | 無 | 第一輪 dev 起始指令 |

## 權限自動化（settings.local.json）

減少 Claude Code 不必要的授權確認。實測一個 session 觸發 150+ 次提示，累積近 1 小時等待。

```bash
# 安裝到專案
mkdir -p your-project/.claude
cp settings.local.json your-project/.claude/settings.local.json
# ⚠️ 重開 Claude Code session 才生效
```

或直接跟 Claude 說：「從 Auto_Claude/settings.local.json 複製到 .claude/settings.local.json，完成後提醒我重開 session」

> 詳細的 allow/deny 規則、5 層架構、實戰案例 → **[GUIDE.md](GUIDE.md)**
