# 任務清單（Dev + Reviewer 共用）

狀態標記：⬜ 待做 | 🔄 進行中 | ✅ 完成 | ❌ 被擋住

## 自我檢查工具（建置完再做任務）

- ⬜ Browser MCP Server (`npx @anthropic-ai/mcp-puppeteer`)
- ⬜ browser-use (`pip install browser-use`)
- ⬜ Lighthouse CI (`npm install -g @lhci/cli`)

## 主任務清單

| # | 任務 | 改動範圍 | 驗收條件 | 狀態 |
|---|------|----------|----------|------|
| 0 | start_demo.sh bug fix | start_demo.sh | `--setup` 不報 unbound variable | ✅ |
| 1 | Docker 容器化 | Dockerfile, docker-compose.yml | `docker compose up` 能啟動，localhost:8001 可連 | ✅ 實際 dry run 通過 |
| 2 | Email SMTP 寄送 | src/api/reporting.py, .env | 報告頁點寄送收到 email | ✅ 代碼完成 |
| 3 | 擬稿版本歷史追蹤 | src/api/drafting.py, static/drafting.html | 可查看歷史版本，可回溯 v1→v2→final | ✅ |
| 4 | 官方詞庫 + 勘誤表 CRUD | src/api/app.py, static/knowledge.html | 後台可 CRUD 詞彙和勘誤，API + UI 都通 | ✅ |
| 5 | 訂閱推播排程 | src/api/subscription.py, static/index.html | 用戶可訂閱主題，系統可排程推播 | ✅ 持久化確認 |
| 6 | OpenID Connect 對接 | src/api/auth.py, src/config.py | 支援 OIDC provider，token 驗證可走通 | ✅ mock 測試確認 |
| 7 | 跨資料源一致性稽核 | src/api/data_governance.py | API 可觸發稽核，回傳一致性報告 | ✅ |
| 8 | 多語言術語驗證 | scripts/verify_terminology.py | 8 語言 × 20 術語，輸出通過率報告 | ✅ 160/160 offline |
| 9 | UI mockup 文件 | docs/ui-mockup.md | 線框圖 + RWD 斷點說明 | ✅ |

建議執行順序：0 → 1 → 2 → 3 → 4 → 7 → 8 → 5 → 6 → 9

## 額外要修的

- ✅ 知識圖譜 hover 顯示 — 改為 mouseover 觸發 popup，blurNode 延遲 300ms 關閉
- ✅ ETL 執行紀錄都失敗 — 修正：(1) law 資料路徑從 laws/ 改為 laws/json_files/ (2) 前端攤平嵌套 API 回應 (3) 加展示模式說明 banner
- ✅ Docker `compose up` 驗證 — 實際 dry run 通過：1074 docs, 1036 nodes, chatbot 正常回答, 所有頁面 200 OK
- ✅ 訂閱排程持久化確認 — SQLite WAL 模式，conversations.db 磁碟持久化，重啟不丟資料
- ✅ OIDC mock 測試確認 — demo mode 全流程通過：get_oidc_config → authorize → callback → session，不需外部 HTTP 呼叫

## 完成紀錄

- 2026-03-19 Round 1: 10 項主任務代碼層全部完成，307 tests pass
- 2026-03-21 Round 2: 5 項額外任務全部完成，307 tests pass，commit 32eb04e
- 2026-03-21 Round 3: Reviewer 三項驗收完成 — Docker dry run OK, start_demo.sh 乾淨 terminal OK, API benchmark 報告產出 (docs/api-benchmark-report.md)
- 2026-03-21 Round 4: benchmark 報告 committed, git tag `milestone-v1.0-demo-ready`, 3/31 展示 runbook 完成 (docs/demo-runbook.md)

- 2026-03-21 Round 5: OpenAI API fallback 強化 (runbook), 展示簡報 10 頁完成 (docs/demo-slides.md), 307 tests pass, commit bc5a26c
- 2026-03-21 Round 6: demo-slides.md → demo-slides.pptx 轉換完成 (10 頁, 47KB), 含截圖佔位框, commit 841149e
- 2026-03-21 Round 7: 截圖嵌入 PPTX 完成 (10 頁 10 張實際截圖, 47KB→2.8MB), 影片錄製指引完成 (scripts/record_demo.sh), 307 tests pass
- 2026-03-21 Round 8: PPTX 潤飾完成 — 公路局 CI 配色 (navy+gold)、統一字型 PingFang TC、每頁標題對齊規範書章節號 (§參-二-一 等)、截圖無密碼曝露確認、307 tests pass
