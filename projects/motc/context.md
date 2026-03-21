# 人類提供的專案背景 — 2026-03-18 更新

## 專案現況
- **Git tag `v0.90`** 已鎖定於 commit `6f46941`，所有後續改動用 `git diff v0.90` 追蹤
- **目前狀態**：279 passed / 15 skipped tests，162/162 deploy checks，系統穩定
- **15 skipped** 全是 `TestL3_Integration`（需 `INTEGRATION=1`），設計意圖非 bug
- **3/31 目標**：展示 demo 給交通部政府官員，部署在可外部連線的網頁端

## 技術棧
- FastAPI + OpenAI GPT-4.1-mini + ChromaDB (1,074 文件) + NetworkX (1,036 節點 × 7,538 邊)
- 前端 15 頁 vanilla JS + CSS RWD，SSE 串流
- Hybrid Search (Vector + BM25 RRF)，RAG golden test 30/30 PASS
- Port 8001，host 0.0.0.0

## 今晚任務清單（按順序執行）

| # | 任務 | 改動範圍 | 驗收條件 |
|---|------|----------|----------|
| 0 | start_demo.sh bug fix | start_demo.sh | `bash start_demo.sh --setup` 不報 unbound variable，正常啟動 |
| 1 | Docker 容器化 | Dockerfile, docker-compose.yml | `docker compose up` 能啟動，localhost:8001 可連 |
| 2 | Email SMTP 寄送 | src/api/reporting.py, .env | 報告頁點寄送能發 email（SMTP 設定在 .env） |
| 3 | 擬稿版本歷史追蹤 | src/api/drafting.py, static/drafting.html | 擬稿後可查歷史版本列表，可回溯 v1→v2→final |
| 4 | 官方詞庫 + 勘誤表 CRUD | src/api/app.py, static/knowledge.html | 後台可新增/編輯/刪除詞彙和勘誤條目 |
| 5 | 訂閱推播排程 | src/api/app.py, static/index.html | 用戶可訂閱主題，系統可排程產生推播內容 |
| 6 | OpenID Connect 對接 | src/api/auth.py, src/config.py | 支援 OIDC provider 設定，token 驗證流程可走通 |
| 7 | 跨資料源一致性稽核 | src/api/data_governance.py | API 可觸發稽核，回傳各資料源一致性/完整性報告 |
| 8 | 多語言術語驗證 | scripts/verify_terminology.py | 跑腳本自動測 8 語言 ×20 組交通術語，輸出通過率報告 |
| 9 | UI mockup 文件 | docs/ui-mockup.md | 各頁面線框圖 + RWD 斷點說明 |

## 🚫 禁止詢問/嘗試取得的資源（得標後才有）

以下資源不存在，遇到時用 Mock/模擬/佔位處理，不要停下來問：

1. 監理資訊系統 API（車籍/汽燃費/定檢/違規）— 公路局內部系統
2. 現行客服系統 API 欄位定義 — 現行廠商持有
3. 10GB 局內業務文件 — 公路局內部
4. 1 億筆監理歷史結構化資料 — 涉及個資
5. 5000 通客服錄音檔 — 涉及個資
6. 臺語微調語料 — 需從錄音檔萃取
7. LINE 官方帳號 — 需機關身份申請
8. 智能小鹿完整 UX 規格 — 得標前無存取權
9. 客服系統/工程養護/防災平臺 API — 各平臺需機關協調
10. 生產級硬體（100Core/512GB/4×GPU）— 得標後採購
11. SIP 語音線路 + 擷取設備 — 需 CTI 廠商
12. ISO27001 認證 — 需合作夥伴
13. 監理服務網頁面 URL 清單 — 內部系統未公開

## 開發規則

- **每完成一個任務就 commit + 跑 `test_all.py` + `verify_deploy.py`**
- 不能讓既有測試退化（279 passed 是底線）
- 用 Mock/佔位處理所有需要外部資源的功能
- 大資料先用小資料跑一遍確認方向正確
- 不要一次讀超過 3 個檔案，按需讀取
- Context rot 警訊：單次讀取超過 100K token 就要拆開

## API Keys
openai: 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

## 已知踩坑紀錄
1. 換 LLM provider 是全系統連鎖反應
2. 前端 bug 修一處要全站搜同 pattern
3. macOS 上 `<input accept="...">` 會卡死 Finder — 移除 accept 改 JS 驗證
4. 前後端 API 欄位名不一致 → [object Object] — 用 curl 先測
5. 0.0.0.0 不是 secure context，語音/camera 要用 localhost
6. Port 統一 8001，啟動前 lsof 檢查
7. 靜態檔加 no-cache header
8. TDX API 免費版有 rate limit — 2 秒間隔 + 429 保護
9. `requirements.txt` 用 `>=版本,<下一個major` pin 法（不用 `==` 也不用 `>=`）
10. start_demo.sh 在 `set -u` 下變數要確保已定義，避免中文括號造成 bash 解析問題
