# Auto_Claude 已知陷阱筆記

這些是 Claude 在建構這套系統時犯過的錯誤，或容易遺漏的問題。
記錄下來是因為 **Claude 會重複犯同樣的錯**，每次新 session 都沒有上次的教訓。

---

## 1. Bash for loop 整塊載入記憶體

**現象**：改了 loop.sh，以為下一輪會自動生效，但跑的還是舊版。

**原因**：Bash 把整個 `for`/`while` loop body 載入記憶體後才開始執行。修改磁碟上的檔案不影響正在跑的 process。

**Claude 的錯誤**：跟人類說「bash 逐行讀取，下一輪自動生效」— 這是錯的。

**正確做法**：kill process → 重啟。沒有 hot reload。

---

## 2. Server 跑舊版本 code（靜默錯誤）

**現象**：Dev 改了 `app.py`，跑 `curl` 測試回 200，報告「通過」。但測到的其實是改動前的舊版本。

**原因**：uvicorn 預設不開 `--reload`。Dev 改了 code，server 不會自動重載。測試結果是假的，而且不會報任何 error。

**Claude 的錯誤**：沒有意識到 server 需要重啟才能測到新 code。寫了 `verify_ui_vision.py` 會檢查 server 是否在跑，但沒檢查 server 跑的是不是最新 code。

**修復**：loop.sh 啟動時用 `python3 run.py --dev`（reload=True），uvicorn 自動偵測 `.py` 變動並重載。

---

## 3. `--resume` 需要正確的工作目錄

**現象**：`claude --print --resume <session-id>` 報 "No conversation found with session ID"。

**原因**：Claude Code 的 session 檔案存在 `~/.claude/projects/<encoded-path>/` 下，路徑是根據工作目錄編碼的。如果 `--resume` 時的 `pwd` 跟建立 session 時不同，找不到 session 檔案。

**Claude 的錯誤**：新 session 的分支有 `cd "$PROJECT_DIR"`，但 resume 分支忘了加。

**修復**：resume 分支也加 `cd "$PROJECT_DIR" &&`。

---

## 4. Port 衝突只 warn 不處理

**現象**：啟動新 server 失敗，port 被佔。腳本繼續跑但 curl 全部 connection refused。

**原因**：`start_demo.sh` 偵測到 port 佔用後只 warn「將嘗試複用」，沒有殺掉舊 process 也沒有 exit。

**Claude 的傾向**：對衝突選擇「warn + 繼續」而不是「解決 + 繼續」。人類不在場時 warn 沒人看。

**修復**：loop.sh 啟動 server 前先 `lsof -ti:$PORT | xargs kill -9`。

---

## 5. Reviewer 空回覆靜默傳遞

**現象**：Reviewer 回覆 0 chars，Dev 收到空白的「審查回饋」，等於沒有方向裸奔。連續 6 輪空回覆（Round 2-7）。

**原因**：Rate limit 或模型回傳空字串。loop.sh 沒有檢查回覆是否為空就直接傳給 Dev。

**Claude 的錯誤**：只對 rate limit pattern 做了 guard，沒想到「回覆成功但內容為空」的情況。

**修復**：加空回覆 guard，<5 chars 時替換為 fallback 訊息。

---

## 6. Agent/Reviewer 命名混淆

**現象**：代碼裡、文件裡、prompt 裡混用 "agent"，跟 Claude Code 內建的 `Agent` 工具名衝突。

**原因**："agent" 在 AI 領域太泛，代表的東西太多。Reviewer 實際上只讀 + 審查，沒有 autonomous action 的能力。

**Claude 的傾向**：預設用 "agent" 稱呼一切 AI 角色。

**修復**：改名為 "reviewer"。`--disallowed-tools "Agent"` 裡的 Agent 是 Claude Code 工具名，不能改。

---

## 7. 人類插話的寫入權限問題

**現象**：Dev 無法寫入 human_reply.md（如果檔案在 Auto_Claude 目錄下）。

**原因**：Claude Code 的 Write/Edit 工具受 `--project-dir` 限制。Dev 的 project-dir 是目標專案（如 AI交通部客服），不能用 Write 工具寫 Auto_Claude 目錄下的檔案。

**Claude 的錯誤**：一開始把 human_message.md 放在 Auto_Claude/agent/ 下，Dev 寫不了。

**修復**：comms 檔案放在 Auto_Claude/projects/xxx/comms/，Dev 改用 Bash echo 寫入（Bash 不受 project-dir 限制）。loop.sh 注入後自動清除 human_message.md（Dev 不需要手動清）。

---

## 8. 任務清單在 prompt 裡浪費 token

**現象**：任務清單佔 reviewer prompt 一半篇幅，每輪作為 system prompt 完整送出。Reviewer 無狀態，每輪都送一次。

**Claude 的傾向**：把所有資訊塞進一個大 prompt，不考慮 token 成本。

**修復**：任務清單搬到 `comms/todo.md`，動態注入 stdin 而不是 system prompt。雙方都能改。

---

## 9. Context rot 導致品質下降但不報錯

**現象**：Dev 跑到第 20+ 輪，回覆品質明顯下降 — 忘記之前做過什麼、重複同樣的錯誤、回覆變得冗長。

**原因**：Claude Code context window 接近上限（~200K tokens），auto-compact 壓縮後丟失細節。

**Claude 的錯誤**：自己不知道自己在 context rot。不會主動說「我可能因為 context 太長而變笨了」。

**修復**：Curator 每 8 輪壓縮 + 重置 session。但壓縮本身也會丟資訊。沒有完美解法。

---

## 10. LLM-as-Judge 對精確內容不可靠

**現象**：用 LLM 判斷另一個 LLM 的回答是否正確，對法規、數字、金額類內容會出錯。

**原因**：
- 「汽燃費 100 元」vs「汽燃費 1000 元」embedding 幾乎一樣
- LLM judge 和被測 LLM 有同樣的盲點
- 回答可以「忠實於檢索結果」但檢索結果本身是錯的

**Claude 的傾向**：建議用 DeepEval 等 LLM-as-Judge 工具做自動評分，沒考慮到方法論的根本缺陷。

**正確做法**：精確內容用 golden test（input → expected output 完全比對）。LLM 判斷只適合模糊的定性評估。

---

## 模式總結：Claude 容易犯的系統性錯誤

| 模式 | 例子 | 對策 |
|------|------|------|
| **假設 hot reload** | bash loop、uvicorn、config | 改了就要重啟，沒有例外 |
| **warn 代替 fix** | port 衝突、空回覆 | 人類不在場，warn 沒人看。要 fix 或 fallback |
| **靜默假通過** | 測舊版 server、覆蓋率 100% 但 0 assertion | 測試要驗證「對的東西」而不是「有東西」 |
| **命名太泛** | agent、tool、helper | 用精確的名字，避免跟框架內建名衝突 |
| **塞爆 prompt** | 任務清單、完整 spec | 分離靜態 vs 動態，按需注入 |
| **不知道自己在退化** | context rot | 外部機制強制重置（curator），不靠 AI 自我判斷 |
| **過度信任自動評估** | LLM-as-Judge | 精確內容用程式化檢查，不用 LLM 判斷 |
