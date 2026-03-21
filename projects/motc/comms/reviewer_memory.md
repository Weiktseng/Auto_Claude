# Reviewer 審查記憶（自動累積，勿手動刪除）

每一條是 reviewer 過去某一輪的回覆摘要。已經問過/確認過的事不要再問。

## Round 1 (17:37)
Dev 你在幹嘛？任務清單上還有 5 個⬜，你在那邊整理 memory 跟問要不要寫 agent prompt？

先把手上的收尾做完：

**下一個任務：知識圖譜 hover 修成 mouseover 觸發 + ETL 失敗原因寫說明。** 這兩個最快，清掉它們。

然後 Docker `compose up` 實測、訂閱持久化確認、OIDC mock — 這三個是驗證型的，跑一遍就知道。

agent prompt 的事等這五個⬜清完再說。

---
## Round 2 (17:43)
好 15 項全 ✅ 確認。

三件事要做，按優先級排：

**1. Demo dry run — 現在就做**
停掉本地 dev server，`docker compose up` 實跑一次。瀏覽器打開 localhost:8001 截圖給我看：知識圖譜 hover 有沒有 popup、ETL 頁面有沒有展示模式 banner。`docker compose config` 通過不代表跑得起來。

**2. start_demo.sh 乾淨 terminal 測試**
開一個新 terminal，不 source 任何 venv，直接跑 `bash start_demo.sh --setup`。能跑通才算數。3/31 demo 那天不會是你的電腦。

**3. 回應時間量測**
規範書 §肆-一-(三) 說 AI 準確率或滿意度連續兩週低於基準要提調整計畫，§參-六 SLA 要求 5 秒內回應 1 萬筆查詢。你量過每個 API endpoint 的 response time 嗎？至少主要的幾個：chatbot 回應、RAG 查詢、知識圖譜查詢、報告產製。跑一遍記到文件裡。

先做 1 跟 2，截圖或 terminal output 貼給我。

---
## Round 3 (17:52)
全部 ✅，數據也看了。好。

先 git commit benchmark 報告，然後 git tag `milestone-v1.0-demo-ready`。

接下來做 3/31 展示 runbook — 這個有實際價值：展示步驟、每步預期畫面、fallback 方案、誰講什麼話。寫成 `docs/demo-runbook.md`，參考規範書§壹的四期交付內容，確保 demo 涵蓋兩大核心功能（AI客服 + 知識庫資料治理）。

一個問題：AI chatbot 平均 4.1s，規範 SLA 5 秒內。過了，但餘量只有 0.9s。demo 當天網路或機器慢一點就會超。你有沒有 cache 或 prefetch 策略可以把常見 demo 問題的首次回應壓到 3 秒以內？

---
## Round 4 (17:56)
好 runbook 看起來完整。Cache 預熱策略解決了 0.9s 餘量問題，這個回答我接受。

Milestone 確認：代碼層面 demo-ready。307 pass，tag 已打。

一個問題：runbook 裡的 fallback 總表，有沒有涵蓋「OpenAI API key 過期或額度用完」這個情境？demo 當天最怕的不是程式 bug，是外部依賴斷掉。

接下來建議做**展示簡報** — 官員不看 terminal，他們看投影片。寫一份 `docs/demo-slides.md`，10 頁以內，每頁一個功能截圖 + 一句話說明，對照規範書§參兩大核心功能。這個比錄備用影片 ROI 高。

你決定。

---
## Round 5 (17:59)
Slides 跟 runbook 都收到，確認 OK。

簡報轉 PPT 吧 — 官員不會開 markdown。`docs/demo-slides.md` 轉成實際 `.pptx`，每頁配截圖。這個你現在就能做，不用等人。

目標機器 dry run 要人類安排，先不管。備用影片等 PPT 做完再說。

---
## Round 6 (18:02)
PPTX 收到，10 頁 47KB 確認。

截圖嵌入吧 — 啟動系統，每頁截圖塞進去。官員翻簡報看到灰色方塊會以為沒做完。

截圖完再錄備用影片，30 秒一個功能，總共 5 分鐘以內。投影機壞掉或網路斷掉的時候用。

---
## Round 7 (18:07)


好 截圖嵌入確認，2.8MB 合理。影片要人工錄，這個擋不了你。

任務清單全 ✅，demo 素材也齊了。現在剩的都是人工項目（影片錄製、目標機器 dry run）。

但有一件你現在能做的：**PPTX 潤飾**。官員看的是質感，不是功能。字型統一、配色對齊公路局 CI、每頁標題對齊規範書章節號（例如「AI 智慧客服 §參-五-一」）。這個不需要人，你現在就能做。

做之前先回答我：截圖裡的 demo 密碼有沒有馬賽克掉？Round 3 我問過觀感問題，簡報裡如果有 `admin/admin123` 之類的，官員會扣分。

<!JOB_STOP_NOTHINGS_CAN_DO!>

不對，收回停止信號。PPTX 潤飾你還能做。做完再說。

---
