# Auto_Claude 三階段 Pipeline 架構報告 v1

> **日期**：2026-04-13（首次 smoke test 完成後）
> **版本**：step1 v1.0 / step2 wrapper / attack_loop v1.0 + v2.0
> **狀態**：EXPERIMENTAL — 僅在 ~70 行的 smoke 專案上驗證過，尚未在正式專案跑過。

---

## 1. 三階段分工原理

### 1.1 為什麼要把單一 loop 拆成三段

Auto_Claude 原有的 `loop.sh`（v3.1）是一個 Dev <-> AI Reviewer 雙角色循環，設計目標是「Dev 寫、Reviewer 挑毛病、Dev 修、循環到收斂」。這套流程在短 spec（< 100 行）和小修改時運作良好，但在長 spec / 大型 phase（多個 checkbox items 要一路完成）的場景下，出現兩個已觀察到的退化模式：

**退化模式 A：Reviewer 打斷建造心流。** Dev 還沒做完一個 item，Reviewer 就開始質疑設計決定、要求補測試、修 style。Dev 被迫花 context window 在解釋和回應上，反而比不開 Reviewer 還慢。這個問題的根源是 loop.sh 在每一輪 Dev 輸出後都會丟給 Reviewer，沒有「Dev 正在建造中，不要打擾」的概念。

**退化模式 B：Reviewer 視角太窄。** Dev 和 Reviewer 是同一個模型（opus）、同樣的 system prompt 語境、看同樣的 context。兩邊很容易收斂到「都覺得沒問題」的共識，但真正的 bug 需要外部視角 -- 不同的模型、不同的 prompt 意圖、不同的檢查角度 -- 才能找到。單一 loop 下 Reviewer 和 Dev 存在共同認知偏見（shared cognitive bias），使得某些類別的 bug 系統性地逃逸。

### 1.2 核心洞察："build mode" 和 "fix mode" 需要不同的 context 環境

三階段的切分基於這個觀察：

| 模式 | 需要的環境 | 會被什麼干擾 |
|------|-----------|-------------|
| Build（建造新功能） | 乾淨 context、只看 spec 和 plan、不被回饋打斷 | Reviewer 的 style nit、測試失敗的 noise |
| Fix（修 bug / 補測試） | Reviewer 的挑戰、測試結果、diff-level 回饋 | 新功能需求 |
| Attack（找 edge case） | 完全不同的模型/prompt、read-only 約束、spec 對照 | 跟 Dev 共用的認知框架 |

三階段把這三種需求按時序拆開：

```
Stage 1 (Focus)  ──>  Stage 2 (Review)  ──>  Stage 3 (Attack)
Dev ↔ dumb Trigger    Dev ↔ AI Reviewer      GPT ↔ Claude cross-fire
建造                   打磨                    攻擊
```

每一段結束時產出的 artifact 成為下一段的輸入：Stage 1 結束時 Curator 壓縮 -> `progress.md`；Stage 2 結束時 auto-commit -> clean SHA for git lock。

---

## 2. Stage 1: Focus Loop 設計決策

### 2.1 為什麼用 dumb bash Trigger 而不是 haiku / 任何 LLM

Stage 1 的對手是一個純 bash 函數 `dumb_trigger()`（`step1_focus_loop.sh` 第 209-213 行），從 7 個罐頭字串裡循環選一個輸出：

```bash
TRIGGER_RESPONSES=(
    "好，繼續 phase_plan.md 的下一項。"
    "繼續。"
    "好，下一個 item。"
    "繼續推進。"
    "好。下一步。"
    "繼續工作。"
    "OK。下一項。"
)
```

選擇零 LLM 而非 haiku 或 sonnet 做 Trigger 的理由：

1. **零 token 成本。** Stage 1 可能跑 10-40 輪，每輪一次 Trigger。用 haiku 每輪 ~200 tokens 的成本雖然不高，但重點不是省錢，而是——
2. **消除任何可能的回饋干擾。** 即使是最弱的 LLM，只要看到 Dev 的輸出，就可能產出「你是不是忘了 X」「建議加 Y」這類回饋。Dev 的 context window 會被這些回饋汙染，開始出現「解釋設計決定」的行為。dumb Trigger 的回應是完全可預測的「繼續」，Dev 知道不用理它。
3. **單邊停工語意明確。** 如果 Trigger 是 LLM，它可能自作主張發 stop signal。dumb Trigger 永遠不會停，停止的決定 100% 在 Dev 手上。

### 2.2 Dev 被誠實告知 Trigger 是假的 -- 為什麼這很重要

`stage1_prompt.md` 第 8-9 行明確告訴 Dev：

> 另一個 AI 不是 Reviewer，是 dumb NLP bot。它每輪只會回類似「好」「繼續」「下一項」的固定字串，完全沒有技術判斷能力......所以：它說的話你不用當真。

這段誠實說明的必要性來自一個觀察：如果 Dev 認為對面是真 Reviewer，它會產生三種不必要的行為：

- **說服行為**：花 context 解釋「為什麼我選這個 library」「為什麼用這個 schema」。
- **等待行為**：「我做完了，等你 review 後再做下一步」。
- **回應行為**：把 Trigger 的「繼續」解讀成「Reviewer 認可了我的做法」，產生虛假的正面回饋循環。

告訴 Dev 真相後，Dev 知道自己要看 `phase_plan.md` 判斷進度，而不是依賴 Trigger 的回應。

### 2.3 單邊停工 vs 雙邊停工

| 屬性 | Stage 1（單邊） | Stage 2（雙邊） |
|------|----------------|----------------|
| 誰能發 stop signal | 只有 Dev | Dev + Reviewer 都要發 |
| 停止條件 | phase_plan.md 全勾完 or 全 blocked | Dev + Reviewer 共識「沒事可做了」 |
| Trigger/Reviewer 的角色 | 心跳信號，沒有判斷權 | 有挑毛病的權力，也有叫停的權力 |
| 失敗模式 | Dev 不 honor 規則 -> max_rounds 硬上限 | 其中一方堅持不停 -> max_rounds |

Stage 1 用單邊停工的原因：Trigger 是 dumb 的，沒有判斷能力，不該有叫停的權力。Dev 自己看 phase_plan 全勾完就停。

實測觀察：Dev（opus 4.6）在 smoke test 中能正確 honor 單邊停工規則，在所有 items 勾完後輸出 `<!JOB_STOP_NOTHINGS_CAN_DO!>`。但這只是 70 行的小專案；大型專案中 Dev 是否可能「忘記」停止仍未驗證。`--max-rounds` 是硬上限安全網。

### 2.4 Curator 在 stage 邊界運行

Stage 1 的 Curator（sonnet）只在 Stage 1 結束時跑一次（`step1_focus_loop.sh` 第 344-389 行），不像 loop.sh 那樣每 8 輪跑一次。原因：

- Stage 1 的 Dev 用 `--resume` 保持 session，context 不需要中途壓縮重注入。
- Curator 的價值在於給 Stage 2 一個乾淨的 handoff artifact（`progress.md`），不在於讓 Stage 1 Dev 自己讀壓縮後的歷史。

Curator 壓縮指引（第 350-357 行）要求保留：
1. 每個已完成 item 對應的關鍵檔案和函數
2. 哪些 item 已勾、哪些沒勾
3. Blocked items 的 blocker 原因
4. Stage 2 Reviewer 需要知道的 known issue / technical debt

---

## 3. Stage 2: Review Loop + 已知的 bash 多進程陷阱

### 3.1 為什麼是薄 wrapper 而不是重寫 loop.sh

`step2_rev_loop.sh` 只有 119 行，做三件事：
1. 解析自己的 flags（`--chain-stage3`、`--no-auto-commit`）
2. 把剩餘 args 透傳給 `loop.sh`
3. `loop.sh` 退出後，auto-commit + chain to Stage 3

沒有重寫 loop.sh 的原因：

- **loop.sh 已經穩定。** v3.1 經過 motc 和 baphiq 兩個專案的實戰驗證，Dev <-> Reviewer 的核心循環不需要改。
- **向後相容。** 既有專案可以繼續直接跑 `loop.sh`，不需要遷移到新的三段流程。loop.sh 會優先找 `stage2_prompt.md`，找不到 fallback 回舊的 `prompt.md`。
- **關注點分離。** step2_rev_loop.sh 只負責 pipeline 級別的關注點（auto-commit、chain），不介入 loop.sh 的 round-level 邏輯。

### 3.2 `kill 0` process group 問題

這是 smoke test 中遇到的第一個嚴重 bash 陷阱，修復紀錄在 commit `91174e4`。

**問題描述：**

`loop.sh` 第 29 行和第 46 行的 EXIT trap 包含 `kill 0`：

```bash
trap 'rm -f "$_EARLY_LOCK_FILE" "${LOCK_FILE:-}" 2>/dev/null; kill 0 2>/dev/null' EXIT SIGINT SIGTERM
```

`kill 0` 發送 SIGTERM 到當前 process group 的所有進程。當 `step2_rev_loop.sh` 在前景呼叫 `loop.sh` 時，兩者在同一個 process group。`loop.sh` 正常退出 -> EXIT trap 觸發 -> `kill 0` 發 SIGTERM -> `step2_rev_loop.sh` 也收到 SIGTERM 被殺死 -> auto-commit 和 chain-to-stage3 的 post-hook 代碼永遠不會執行。

**修復方式（`step2_rev_loop.sh` 第 73-76 行）：**

```bash
trap '' TERM
"$LOOP_SH" "${FORWARD_ARGS[@]}"
LOOP_EXIT=$?
trap - TERM  # Restore default TERM handling
```

在呼叫 `loop.sh` 之前忽略 SIGTERM，讓 `loop.sh` 的 `kill 0` 無法殺死 step2。`loop.sh` 退出後恢復 TERM handler。SIGINT（Ctrl-C）保持正常，人類手動中斷仍然有效。

**設計反思：** `kill 0` 在 loop.sh 裡的原始用途是「確保子進程（claude --print）在 loop.sh 退出時被清理」。這個需求合理，但 `kill 0` 太暴力 -- 它殺的是 process group 而不是 children。更乾淨的做法是追蹤子 PID 然後 `kill $child_pid`，但這需要重構 loop.sh 的進程管理，暫時用 step2 端的 `trap '' TERM` 作為 workaround。

### 3.3 Auto-commit WIP

Stage 2 結束時（`step2_rev_loop.sh` 第 82-103 行），如果 working tree 有未 commit 的變動，自動執行：

```bash
git add -A
git commit -m "stage2: auto-commit at loop exit ..."
```

目的是讓 Stage 3 的 git lock 從一個乾淨的 SHA 開始。如果 auto-commit 失敗（例如 pre-commit hook 拒絕），會打印警告但不阻塞 pipeline。

**已知問題：** `git add -A` 會把所有 untracked 檔案（包括暫存檔、log、test output）一起 commit 進去。改善方向是用 `.gitignore` 擋掉 `.auto_claude/logs/` 等路徑，但目前暫時接受這個行為。

---

## 4. Attack Loop: v1 -> v2 架構演進

### 4.1 v1: 9-round serial（`attack_loop.sh`）

v1（commit `0ff4152`）的流程是嚴格序列化的：

```
Phase 1: GPT x 3 rounds (codex exec -s read-only)
Phase 2: Claude x 3 rounds (--print, --disallowed-tools Write Edit)
Phase 3: Cross-verify x 3
  R1: Claude verifies GPT findings
  R2: GPT verifies Claude findings
  R3: Claude compiles final dedup report
```

每一輪都是獨立的 LLM 呼叫，前一輪的 findings 以 `PREVIOUS ATTACKS` 的形式注入下一輪的 prompt。dedup 機制是 prompt-based 的：prompt 裡寫「you must pick a different category」（attacker/prompt.md 第 28 行的規則），依賴模型遵守指令來避免重複。

**v1 的問題：**

- **慢。** 9 個 sequential LLM calls，每個 GPT call ~10-20 分鐘（codex exec 啟動慢）。Wall time 約 1.5-2 小時。
- **Prompt-based dedup 不可靠。** GPT 和 Claude 各自的 3 輪之間，只靠 prompt 裡注入的 previous attacks 文字來避免重複。模型可能 ignore 這個指令，尤其是當 previous attacks 文字很長時。
- **Cross-verify 的 R1/R2 是冗餘的。** R1 讓 Claude 驗 GPT 的、R2 讓 GPT 驗 Claude 的、R3 讓 Claude 做 final merge。其中 R3 已經包含了 R1 和 R2 的工作（讀所有 findings，逐條驗證），R1+R2 的獨立驗證在實測中沒有提供額外價值。

v1 保留為 fallback（`engine/attack_loop.sh`），在 v2 不穩定時可以退回。

### 4.2 v2: Pipelined relay（`attack_loop_v2.sh`）

v2（commit `dfce994`）重新設計了流程，核心改進是 **parallel preload + session resume relay**：

```
Step 0 (PARALLEL):
  GPT  -> reads spec + code + prompt -> attacks -> writes findings.md
  Claude -> reads spec + code + prompt -> preloads context (no attack)

Step 1: Claude resumes -> reads findings.md -> attacks for NEW bugs -> appends findings.md
Step 2: GPT   resumes  -> reads updated findings.md -> attacks for NEW bugs -> appends findings.md
Step 3: Cross-verify   -> Claude reads all findings -> CONFIRMED / HALLUCINATED
```

**Wall-time 分析：**

| 版本 | Sequential calls | Wall time (理論) |
|------|-----------------|-----------------|
| v1   | 9               | ~9 x avg_call   |
| v2   | 3 (+1 parallel) | ~3 x avg_call   |

Step 0 的 GPT 和 Claude 是真並行的（bash `&` + `wait`），所以 Step 0 的 wall time 是 max(GPT, Claude) 而不是 sum。

### 4.3 Shared findings.md vs prompt-based dedup

v2 用一個共享的 `findings.md` 檔案做結構化 dedup，取代 v1 的 prompt-based「pick different category」：

```
findings.md:
  ## GPT -- Step 0 (first attacker)
  <GPT 第一輪的完整輸出>

  ## Claude -- Step 1 (relay)
  <Claude 的完整輸出>

  ## GPT -- Step 2 (relay)
  <GPT 第二輪的完整輸出>
```

每個 attacker 在攻擊前會讀完整的 findings.md，prompt 裡明確說：

> Find ONE failure that is NOT already on the list above.

這比 v1 的「pick a different category」更精確，因為 attacker 看到的不是前一輪的 category 標籤，而是前一輪的完整 finding 內容，可以判斷 scenario 級別的重複而非 category 級別。

### 4.4 Session resume 與 Claude preload

v2 的關鍵架構特性是 Claude 的 session resume：

1. Step 0：Claude 用 `--session-id $CLAUDE_SESSION_ID` 建立新 session，preload context（讀 spec + codebase + prompt），不攻擊。
2. Step 1：Claude 用 `--resume $CLAUDE_SESSION_ID` 恢復 session，直接攻擊。

Preload 的價值在於：Claude 在 Step 0 就已經用 Read/Grep/Glob 讀完整個 codebase，context window 裡已經有代碼。Step 1 resume 時，它不需要重新讀代碼，可以直接開始分析，節省了一整輪的檔案 I/O 時間。

GPT（codex）目前沒有 session resume 機制（`codex exec` 是 stateless 的），所以 GPT 每次呼叫都是獨立的，要重新讀代碼。這是 GPT 那邊效能較差的原因之一。

### 4.5 Git lock 機制

兩個版本的 git lock 機制相同：

1. **鎖定 SHA：** 啟動時 `git rev-parse HEAD` 記錄 `LOCKED_SHA`，寫入 `logs/attack_locked.sha`。
2. **Dirty baseline：** 同時記錄 `INITIAL_DIRTY=$(git status --porcelain)`，允許啟動時已有的 uncommitted changes 保持。
3. **每輪驗證：** 每個 attacker 跑完後呼叫 `verify_git_lock()`，比較 current SHA 和 current dirty state 與啟動時的 baseline。
4. **違規處理：** 如果 SHA 或 dirty state 變了，記錄違規到 `$ATTACK_WORK/violations/`，然後 `git reset --hard $LOCKED_SHA && git clean -fd` 回復。
5. **Attacker 的 read-only 約束：**
   - GPT：`codex exec -s read-only`（OS-level sandbox）
   - Claude：`--disallowed-tools "Write Edit NotebookEdit Agent"`（tool-level restriction）+ `git diff` post-check

Git lock 是 defense-in-depth：tool restriction 是第一道防線，git verify 是第二道。即使 Claude 找到方法繞過 tool restriction（例如透過 Bash tool 的 `echo > file`），git verify 會抓到並 revert。

---

## 5. 雙模型攻擊行為實測（Smoke Test 數據）

### 5.1 Smoke Test 專案

測試對象是一個 Word Counter API，約 70 行 Python：
- `POST /count`：接收 text，回傳 `word_count`、`character_count`、`unique_word_count`
- `GET /history`：回傳歷史紀錄列表

Spec 是人類故意削減過的（見第 6 節分析）。Dev 在 Stage 1+2 完成了完整的功能實作。

### 5.2 GPT 的攻擊結果（gpt-5.4 via codex）

GPT 在 Step 0（第一個攻擊者）找到了以下 findings：

**Finding 1（CONFIRMED by cross-verify）：text_preview truncation 長度不符**

- **Scenario：** `POST /count` 回傳的 `text_preview` 欄位截斷在 20 字元，但 spec 寫的是 30 字元。
- **Category：** Spec-code mismatch
- **嚴重度：** medium -- 原始 text 只存 preview，截斷後永久遺失。
- **分析：** 這是典型的 spec-vs-code 落差。Dev 在 Stage 1 寫 `text[:20]` 而非 `text[:30]`，Stage 2 Reviewer 沒抓到這個數字差異。

**Finding 2（HALLUCINATED, cross-verify 正確拒絕）：lower() vs casefold() 的德文 sharp-s 處理**

- **GPT 聲稱：** `lower()` 不處理德文 eszett（ß/SS），應該用 `casefold()`。
- **Cross-verify 判定：** spec 沒有要求 Unicode full case folding。`lower()` 對 spec 定義的行為來說是正確的。
- **分析：** GPT 找了一個「技術上真的是差異但 spec 沒要求」的 finding。這是 attacker prompt 裡「spec 沒要求的事不算 bug」規則的正確應用場景。

**Finding 3（HALLUCINATED, cross-verify 正確拒絕）：len() counts code points not grapheme clusters**

- **GPT 聲稱：** `character_count` 用 `len()` 計算的是 code points 而非 grapheme clusters，emoji 組合字元會算出不符使用者直覺的值。
- **Cross-verify 判定：** 同樣，spec 沒有定義「character」是 grapheme cluster。`len()` 的行為對 spec 來說是可接受的。

### 5.3 Claude 的攻擊結果（opus 4.6）

Claude 在 Step 1（第二個攻擊者，讀了 GPT 的 findings 後）找到：

**Finding（CONFIRMED by cross-verify）：/history 只存 word_count，丟失 character_count 和 unique_word_count**

- **Scenario：** `POST /count` 回傳三個欄位（`word_count`、`character_count`、`unique_word_count`），但 `GET /history` 的紀錄裡只存了 `word_count`。查歷史時只能看到 word_count，另外兩個欄位永久遺失。
- **Category：** Silent data corruption / cross-endpoint consistency
- **嚴重度：** high -- 資料永久遺失，且沒有任何錯誤訊息。
- **Claude 的推理路徑：** Claude 用 spec 裡的自然語言描述（「每一次得出的答案是什麼」）交叉比對 `POST /count` 和 `GET /history` 的 code。`POST` 算出三個欄位，但存進 history list 時只 append 了 `{"word_count": count}`。這是 code 內部的 cross-endpoint 一致性 bug，不是 spec-vs-code mismatch。

### 5.4 關鍵觀察

**Claude 找到的不是 spec-vs-code mismatch，而是 code-vs-code internal consistency bug。**

Attacker prompt（`templates/agent/attacker/prompt.md`）的優先順序是：

1. Spec-code 落差
2. Silent data corruption
3. State leak
4. Boundary / type coercion
5. Concurrency

Claude 的 finding 屬於 #2（silent data corruption），但它的推理路徑是先從 spec 裡的自然語言「每一次得出的答案」推斷出 history 應該包含所有 count 結果，然後用 Grep 對比 `POST` 和 `GET` 兩個 endpoint 的 data flow，發現不一致。

Attacker prompt 沒有明確要求「檢查 cross-endpoint data consistency」-- Claude 自己推斷出這是一個值得檢查的維度。這表明 attacker prompt 的「silent data corruption」類別描述夠寬泛，模型能在框架內自行展開合理的檢查策略。

**GPT 的 2/3 findings 是 hallucination，但 hallucination 的模式很有參考價值。**

GPT 的兩個 hallucinated findings 都是「技術上真的是差異，但 spec 沒有定義相關行為」的模式。Cross-verify 正確拒絕了它們。這表明：
- GPT 傾向找「可能有問題」而非「spec 明確說了但 code 沒做到」的 bug。
- Cross-verify 階段對過濾這類 hallucination 有效。
- Attacker prompt 裡的「anti-gaming」段落（第 70-72 行）和 VERDICT 格式的嚴格性有助於讓模型自我約束，但 GPT 仍然傾向把「我覺得可疑」包裝成 ATTACK 而非放到 CLEAN 的 Note 段。

---

## 6. Spec 品質與產出品質的關係

### 6.1 Smoke test 的 spec 問題

使用者在 smoke test 中故意削減了 spec 的細節，測試「模糊 spec 下 pipeline 的表現」。具體來說：

- **刪除了 response format 定義。** Spec 只描述了「POST /count 分析文字並回傳結果」，沒有明確列出回傳的 JSON schema（哪些欄位、型別、是否 nullable）。
- **刪除了範例。** 沒有提供 request/response 的範例 JSON。
- **保留了自然語言描述。** Spec 保留了「每一次得出的答案是什麼」「包含文字的預覽（前 30 字元）」這類自然語言描述。

### 6.2 連鎖效應

1. **Dev 做了合理但不完整的設計判斷。** Dev 根據自然語言描述實作了 `POST /count`（回傳 3 個欄位），但在 `GET /history` 只存了 1 個欄位。沒有 response schema 可對照，Dev 自己沒意識到這是 bug -- 在 Dev 的心智模型裡，「history 存 word_count 就夠了」是合理的。
2. **Reviewer 沒抓到。** Reviewer（同一個 opus 模型）看同一份 spec、同一份 code，跟 Dev 有同樣的認知框架。沒有明確的 response schema 可對照，Reviewer 也覺得「存 word_count 就夠了」是合理的。這正是退化模式 B（shared cognitive bias）的實證。
3. **Attacker 抓到了。** Claude attacker 用不同的 prompt（adversarial 視角而非建設性視角）、不同的檢查策略（cross-endpoint consistency），找到了 Dev 和 Reviewer 共同 miss 的 bug。GPT attacker 也找到了一個 CONFIRMED bug（text_preview 截斷長度），這是 spec 裡有明確數字但 Dev 寫錯了的情況。

### 6.3 教訓

**Spec 不需要鉅細靡遺，但 response STRUCTURE 必須明確。**

- 自然語言描述 behavior 是夠的 -- attacker 能從自然語言推理出預期行為。
- 但 response format（JSON schema、欄位列表、型別）必須明確寫出來。否則 Dev 會做「合理的設計判斷」，而這些判斷可能跟使用者的期望不一致。
- 換句話說：spec 可以省略「為什麼」的解釋，但不能省略「回傳什麼」的定義。

---

## 7. Bash Orchestrator 的已知陷阱（踩過的坑）

以下是 smoke test 期間遇到的 bash-level bug，均已修復。記錄在此作為未來 bash orchestration 開發的參考。

### 7.1 `kill 0` in EXIT trap kills parent process group

**檔案：** `engine/loop.sh` 第 29/46 行
**修復 commit：** `91174e4`
**影響：** step2_rev_loop.sh 呼叫 loop.sh 後被 loop.sh 的 EXIT trap kill 掉，post-hook 不執行。

**詳情：** 見本報告 3.2 節。

**修復：** step2_rev_loop.sh 在呼叫 loop.sh 前 `trap '' TERM`。

**根本原因與更好的做法：** EXIT trap 和 SIGINT/SIGTERM trap 應該分開。EXIT trap 只做檔案清理，不做 `kill 0`。SIGINT/SIGTERM trap 做 `kill 0` + 清理。這樣正常退出時不會殺死 process group，只有收到信號時才會。

目前 step1_focus_loop.sh 已採用分離式 trap：
```bash
trap 'rm -f "${_session_ref:-}" 2>/dev/null' EXIT
trap 'rm -f "${_session_ref:-}" 2>/dev/null; kill 0 2>/dev/null' SIGINT SIGTERM
```

但 loop.sh 和 attack_loop*.sh 仍然在 EXIT trap 裡做 `kill 0`。這是待修項目。

### 7.2 `set -u` + 空 bash array

**檔案：** `engine/attack_loop.sh` 第 311/316 行
**修復 commit：** `91174e4`

**問題：** `set -u`（treat unset variables as errors）下，引用一個空的 bash array 會觸發 "unbound variable" 錯誤：

```bash
local model_flag=()                      # 空 array
"$CODEX_BIN" ${model_flag[@]} ...       # ERROR: unbound variable
```

**修復：** 使用 bash 4.x 的 `${arr[@]+"${arr[@]}"}` 語法：

```bash
${gpt_model_flag[@]+"${gpt_model_flag[@]}"}
```

這個語法的含義是：如果 `gpt_model_flag` 有元素，展開它；否則展開為空（不觸發 `set -u`）。

attack_loop_v2.sh 的第 238 行和第 429 行都使用了這個修正後的寫法。

### 7.3 `rm` input files before background subshells read them

**檔案：** `engine/attack_loop_v2.sh`
**修復 commit：** `72d7b34`

**問題：** Step 0 同時起兩個 background 進程（GPT 和 Claude），都從 `mktemp` 建立的 input file 讀取 prompt。原始代碼在 `&` 之後立即 `rm -f` input file，造成 race condition：如果 subshell 還沒開始讀檔案，檔案就被刪了。

**修復：** 把 `rm` 移到 `wait` 之後（第 296 行）：

```bash
wait $GPT_PID 2>/dev/null || true
wait $CLAUDE_PID 2>/dev/null || true
rm -f "$GPT_R1_INPUT" "$CLAUDE_PRELOAD_INPUT"  # 現在安全了
```

### 7.4 nohup stdout buffering

**觀察（未造成 bug，但影響 debug 體驗）：**

在用 `nohup` 背景執行 pipeline 時（通常的使用方式），nohup 的 stdout 有 kernel-level 的 buffering，不是 line-buffered 的。結果是 `tail -f nohup.out` 看到的進度更新有很大的延遲，甚至整個 step 跑完才刷一大塊出來。

Stage 1 的應對方式是每輪寫一個獨立的 live log 檔案（`$LOG_DIR/stage1_dev_live_round${round}.log`，第 409 行），人類可以 `tail -f` 這個檔案看即時輸出。但 attack_loop 沒有類似機制，只能看 nohup.out 的延遲輸出。

### 7.5 `$VAR` 後跟全形 Unicode 字元的 bash 解析問題

**觀察（防禦性修正）：**

在 bash string 裡，`$VAR` 後面如果緊跟全形 Unicode 字元（例如中文逗號「，」），bash 在某些版本下可能把 Unicode 字元的 byte sequence 解讀為變數名的一部分，導致 mis-parse。

修正方式：所有 variable reference 在有全形字元跟隨時使用 `${VAR}` 而非 `$VAR`。例如：

```bash
echo "${DEV_CHARS} chars"    # 安全
echo "$DEV_CHARS chars"      # 安全（空格隔開了）
echo "$DEV_CHARS，完成"       # 可能有問題
echo "${DEV_CHARS}，完成"     # 安全
```

此問題在 macOS 的 bash 3.2（`/bin/bash`）和 zsh 上觀察到的行為不同。Auto_Claude 的 shebang 是 `#!/bin/bash`，在 macOS Ventura+ 上實際執行的是系統 bash 3.2。考慮在 step1/step2/attack_loop 的 shebang 改為明確指定 `#!/opt/homebrew/bin/bash`（bash 5.x）以避免此類問題，但目前尚未執行。

---

## 8. 效能分析與並行化路線圖

### 8.1 Smoke test 時間分解

| 階段 | Wall time（估計） | 備註 |
|------|------------------|------|
| Stage 1 (Dev ↔ Trigger, ~5 rounds) | ~10 min | 70 行專案，快速完成 |
| Stage 2 (Dev ↔ Reviewer, ~5 rounds) | ~10 min | 同上 |
| Stage 3 v2 Step 0 (GPT ‖ Claude) | ~20 min | GPT 是瓶頸（codex exec 啟動慢） |
| Stage 3 v2 Step 1 (Claude attack) | ~10 min | Session resume，不需重讀代碼 |
| Stage 3 v2 Step 2 (GPT relay) | ~20 min | GPT 重新讀代碼 |
| Stage 3 v2 Step 3 (cross-verify) | ~10 min | Claude 讀 findings + 驗證 |
| **Bash bug debugging + reruns** | **~3 hr** | **一次性成本，now fixed** |

**結論：** 在 70 行專案上，actual productive time 約 80 分鐘，其中 GPT/codex 佔了約 50 分鐘（最大瓶頸）。Bash bug debugging 佔了絕大多數的 wall time，但這是一次性成本 -- 修復後不會再發生。

### 8.2 已識別的並行化機會（按影響排序）

**Priority 1: GPT 作為 fire-and-forget 背景攻擊者（最高優先）**

GPT/codex 的 round 是整個 pipeline 最慢的環節（每次 ~20 分鐘），但 GPT 不需要跟 Claude 有嚴格的序列依賴。可以在 Stage 2 進行到後半段時就啟動 GPT attacker 作為背景進程：

```
Stage 2 round 5...6...7...
         \--> GPT Step 0 starts (background, fire-and-forget)
Stage 2 exits
Stage 3 starts: GPT already has findings, Claude attacks directly
```

預估節省：30-60 分鐘（消除 GPT 的等待時間）。

風險：Stage 2 可能在 GPT 攻擊的同時還在改 code。解法是 GPT 用 Stage 2 某個 mid-point commit 的 SHA 開始攻擊，而非 final commit。這增加了 GPT 可能找到「已經被 Stage 2 後面的 rounds 修掉」的 bug 的機率，但 cross-verify 會過濾掉這些。

**Priority 2: Stage 2 + preliminary attack overlap**

類似 Priority 1 但更激進：在 Stage 2 的 Reviewer 輪次裡，Claude attacker 也開始 preload context。這需要修改 step2_rev_loop.sh 在 loop.sh 仍在跑的時候就啟動 attack_loop 的 preload phase。

預估節省：10-15 分鐘。
複雜度：高，需要處理 loop.sh 和 attack_loop 的進程管理衝突。

**Priority 3: Curator 背景壓縮**

Stage 1 結束時的 Curator 壓縮目前是 blocking 的（Stage 2 要等 Curator 產出 progress.md 才能開始）。可以改成：Stage 2 在 Round 1 用 Stage 1 的 raw log 啟動，同時背景跑 Curator；Curator 完成後，Stage 2 從 Round 2 開始用壓縮後的 progress.md。

預估節省：2-5 分鐘。
複雜度：中等，需要 Stage 2 的 Round 1 能在沒有 progress.md 的情況下啟動。

**Priority 4: Reviewer + except-hook parallel**

loop.sh 目前在 Dev 輸出後 sequentially 跑 except-hook（掃 git diff 裡的 exception anti-pattern）再跑 Reviewer。這兩個可以並行。

預估節省：~30 秒/輪。
風險：低。

**Priority 5: Multi-item parallel Dev（不推薦）**

讓 Dev 同時做多個 phase_plan items。

預估節省：理論上可以 2-3x Stage 1 速度。
風險：**極高。** 多個 Dev session 同時修改同一個 repo 會造成 merge conflict、file corruption、依賴關係錯亂。除非有非常精確的檔案級鎖或 worktree 隔離，否則不值得嘗試。**不推薦實作。**

### 8.3 效能基線（待正式專案驗證）

以上數據來自 70 行的 smoke 專案，不具備對正式專案的預測力。正式專案（2000-5000 行）的預期變化：

- Stage 1 rounds 數量會大幅增加（從 ~5 到 20-40）
- 每輪 Dev 的 token 使用量和 wall time 會增加
- Stage 3 attacker 的 codebase 讀取時間會增加
- GPT/codex 的 bottleneck 效應會更加明顯

---

## 9. 已知限制與待驗證項目

### 9.1 僅在小型 smoke 專案上驗證過

Pipeline 的所有行為都只在 ~70 行的 Word Counter API 上觀察過。以下行為在正式專案上可能不同：

- **Dev 的單邊停工遵守度。** 70 行的專案 items 少，Dev 很容易判斷「全做完了」。2000+ 行的專案有 15-20 個 items，Dev 可能在做完大部分後「忘記」檢查剩餘的 blocked items，不發 stop signal。
- **Curator 壓縮品質。** 70 行專案的 Stage 1 session 很短，Curator 壓縮沒壓力。大型專案的 Stage 1 可能跑 30+ 輪，session transcript 巨大，sonnet 的壓縮可能遺漏關鍵的 technical debt 資訊。
- **Attacker 的有效性。** 70 行的 codebase 模型一輪就能全部讀完。2000+ 行的 codebase 可能超出 attacker 的 effective attention span，導致 attack quality 下降。

### 9.2 Session resume 在 --print 模式的可靠性

Claude 的 `--resume` 在 smoke test 中正確運作（Step 0 preload -> Step 1 attack resume），但以下情況未驗證：

- **長時間間隔後的 resume。** 如果 Step 0 和 Step 1 之間隔了 30+ 分鐘（因為 GPT 很慢），session 是否仍然可 resume。
- **Resume 後 context window 的完整性。** Resume 時 Claude 是否真的記得 preload 階段讀過的所有檔案內容，還是只記得摘要。
- **Multiple resume。** v2 只 resume 一次（Step 0 -> Step 1）。如果未來擴展到更多 relay rounds，多次 resume 的行為是否穩定。

### 9.3 Round count 應隨專案大小調整

目前的固定值：

| 參數 | 當前預設 | 適用場景 |
|------|---------|---------|
| Stage 1 max_rounds | 40 | 大型 phase 可能不夠 |
| Stage 3 v2 攻擊 rounds | 3 (固定) | 小專案太多，大專案太少 |
| Stage 3 v1 rounds_per_phase | 3 | 同上 |

建議方向：根據 codebase 的 LOC 或 phase_plan 的 item 數量動態調整 round count。例如：
- < 200 LOC：v2 的 3 rounds 夠用
- 200-1000 LOC：v2 的 3 rounds + 可能需要 Step 2 GPT 的額外 round
- > 1000 LOC：考慮回到 v1 的 per-phase 多 round 模式，或在 v2 裡加更多 relay rounds

### 9.4 Dev server 管理的跨 stage 問題

`loop.sh` 的 Dev 可能在 Stage 2 中啟動 dev server（例如 `python app.py` 跑在 port 8000）。Stage 2 結束後 `loop.sh` 的 EXIT trap 會 `kill 0`，理論上會殺死 dev server。但：

- 如果 dev server 是 background process 且不在 loop.sh 的 process group 裡，它可能存活下來。
- Stage 3 的 Claude attacker 有 Playwright/Chrome MCP 權限，可能需要 dev server running 來測 UI bug。
- 目前沒有機制在 Stage 3 自動啟動 dev server。

解法方向：
1. Stage 3 的 attacker prompt 裡加一條「如果需要測試 HTTP endpoint，先用 Bash 啟動 dev server」。
2. 或者在 step2_rev_loop.sh 的 post-hook 裡啟動 dev server 並記錄 PID。

### 9.5 v1 和 v2 的 attacker prompt 相容性

`attack_loop.sh`（v1）和 `attack_loop_v2.sh` 使用同一個 attacker prompt（`templates/agent/attacker/prompt.md`）。但 v2 的 relay 流程對 prompt 有額外的語意要求（例如「Find ONE failure that is NOT already on the list」這段是 v2 的 orchestrator 在 prompt 外注入的，不在 attacker prompt 裡）。

如果 attacker prompt 被客製化（例如某個專案在 `.auto_claude/agent/attacker/prompt.md` 裡 override），客製化的 prompt 需要跟 v2 的注入邏輯相容。目前沒有文件說明這個相容性要求。

### 9.6 Error recovery 和重試

Pipeline 使用 `exec` 串接三個 stage。如果任何一段 crash（例如 Claude CLI 版本不對、codex login 過期），後面的 stages 不會執行，也沒有自動重試。

目前的人類 workaround：
1. 看 log 確認哪個 stage crash 了
2. 手動從那個 stage 重跑（每個 stage 都可以獨立啟動）

自動重試不建議加入 -- pipeline 的失敗模式太多樣化，自動重試可能導致無限循環或資料狀態不一致。保持「crash-and-tell-human」的策略。

### 9.7 Rate limit handling 的差異

三個 stage 的 rate limit 處理方式不一致：

- **Stage 1：** 有完整的 rate limit detection + smart wait（解析 "resets Xam" 時間戳算出等待秒數，fallback 到 300 秒固定等待）。Rate limit 後重試同一輪（`round--; continue`）。這段邏輯從 loop.sh 複製過來，經過實戰驗證。
- **Stage 2：** 透傳給 loop.sh，loop.sh 有自己的 rate limit handling（同樣的邏輯）。
- **Stage 3 v1/v2：** 沒有 rate limit handling。如果 attacker call 遇到 rate limit，`codex exec` 或 `claude --print` 會回傳 rate limit error message，但 script 只是 `|| true` 跳過，把 error message 當作 finding 寫進 log。

Stage 3 缺少 rate limit handling 的原因：smoke test 沒有觸發 rate limit（呼叫次數少，且 GPT 和 Claude 用不同的 API quota）。但在正式專案上，如果 Stage 1+2 消耗了大量 Claude quota，Stage 3 的 Claude attacker 可能遇到 rate limit。待修。

### 9.8 Log 體系與可觀測性

Pipeline 的 log 分散在多個位置：

| Log | 位置 | 內容 |
|-----|------|------|
| Stage 1 round log | `logs/<timestamp>_stage1.md` | 每輪 Dev 輸出全文 |
| Stage 1 session CSV | `logs/<timestamp>_stage1_sessions.csv` | round, role, session_uuid, timestamp |
| Stage 1 live log | `logs/stage1_dev_live_round${N}.log` | Dev 的即時 streaming 輸出 |
| Stage 1 heartbeat | `logs/heartbeat` | JSON，包含 pid, stage, round, time |
| Stage 2 | loop.sh 自己的 log 體系 | 見 loop.sh 的 log 說明 |
| Stage 3 attack log | `logs/<timestamp>_attack_v2.md` | 每一步的完整 transcript |
| Stage 3 final report | `logs/<timestamp>_attack_v2_report.md` | cross-verify 後的 CONFIRMED/HALLUCINATED |
| Stage 3 violations | `/tmp/auto_claude_attack_v2_$$/violations/` | git lock violation 的 diff |

**可觀測性 gap：**

- 沒有統一的 pipeline-level dashboard。人類要看三個 stage 的 log 才能了解完整 pipeline 的狀態。
- Heartbeat 只有 Stage 1 寫。Stage 2（loop.sh）有自己的 heartbeat，Stage 3 沒有。
- Session CSV 只有 Stage 1 記錄。Stage 3 的 session UUID 沒有被追蹤（GPT/codex 沒有 session UUID 概念，Claude 的 session ID 在 script 裡但沒寫進 CSV）。

改善方向：加一個 pipeline-level 的 `pipeline_status.json`，每個 stage 寫入自己的狀態，人類只需看一個檔案。

---

## 10. v1 vs v2 決策矩陣

在選擇使用 `attack_loop.sh`（v1）或 `attack_loop_v2.sh`（v2）時，以下矩陣可供參考：

| 維度 | v1 (9-round serial) | v2 (pipelined relay) |
|------|---------------------|---------------------|
| Wall time | ~9 x avg_call | ~3 x avg_call |
| Token 總用量 | 較高（9 次獨立 context load） | 較低（Claude session resume 省去重讀） |
| Dedup 可靠性 | 低（prompt-based「pick different category」） | 中（shared findings.md，scenario-level dedup） |
| Cross-verify 深度 | 高（R1+R2 各自獨立驗證 + R3 merge） | 中（只有 Step 3 一次 verify） |
| 除錯便利性 | 高（每輪獨立，可以只重跑某一輪） | 低（session resume 依賴前輪 state） |
| codex session 支援 | 不需要（每輪獨立） | 不需要（GPT 仍然是 stateless） |
| Claude session resume 依賴 | 不依賴 | 依賴（Step 0 preload -> Step 1 resume） |

**推薦選擇規則：**

- 正式專案、需要速度：用 v2
- 第一次在新專案跑、需要穩定性和可除錯性：用 v1
- Claude CLI 的 `--resume` 行為不穩定時：fallback 到 v1
- 需要最大化 attack coverage（不怕慢）：用 v1 + `--rounds-per-phase 5`

---

## 11. Pipeline 各階段的 prompt 注入結構

理解每個 stage 的 prompt 如何組裝，對除錯和客製化很重要。

### 11.1 Stage 1 Dev prompt 組裝流程

`step1_focus_loop.sh` 的 `build_dev_prompt()` 函數（第 241-297 行）按以下順序拼接 prompt：

```
[1] stage1_prompt.md 的完整內容         <- role + rules
[2] main_content（Round 1 = initial-prompt, 後續 = Trigger 的 canned text）
[3] spec.txt 的路徑提示（不注入內容，叫 Dev 自己用 Read 去看）
[4] phase_plan.md 的完整內容            <- 核心工作清單
[5] dev/memory.md 的最後 80 行          <- Dev 的跨 round 筆記
[6] human_message.md 的內容（如果有人類插話）
[7] context.md 的完整內容               <- 專案背景
```

設計重點：

- **Spec 不直接注入 prompt。** 只給路徑，讓 Dev 用 Read tool 按需讀取。原因是 spec 可能很長（1000+ 行），全塞進 prompt 會擠壓 Dev 的 output context。
- **Phase plan 全文注入。** Phase plan 通常很短（20-50 行），是 Dev 每輪必看的工作清單，值得佔用 prompt 空間。
- **Memory 只注入最後 80 行。** Dev memory 可能隨 session 越來越長，只取尾部避免 prompt 膨脹。
- **Human message 讀後即清。** 讀取 `human_message.md` 後立即覆寫為「目前沒有人類插話」，避免同一條訊息被重複注入。

### 11.2 Stage 3 attacker prompt 組裝流程

v2 的每一步的 prompt 組裝方式不同：

**Step 0 GPT（首攻）：**
```
[1] attacker/prompt.md           <- role + rules + output format
[2] SPEC（全文注入）
[3] PROJECT CONTEXT（全文注入）
[4] SHARED FINDINGS = "(none yet)"
[5] Root directory + 任務指令
```

**Step 0 Claude（preload）：**
```
[1] attacker/prompt.md
[2] SPEC
[3] PROJECT CONTEXT
[4] 特殊指令："This is a PRELOAD round. Do NOT attack yet."
[5] 要求列出 attack surface notes
```

**Step 1 Claude（resume attack）：**
```
[1] （resume，context 來自 Step 0 session）
[2] findings.md 的當前內容（包含 GPT Step 0 的結果）
[3] "Find ONE failure that is NOT already on the list"
```

**Step 2 GPT（relay attack）：**
```
[1] findings.md 的當前內容（包含 GPT Step 0 + Claude Step 1）
[2] "Find ONE additional failure NOT already on the list"
```

**Step 3 Cross-verify：**
```
[1] 驗證指令 + report format template
[2] SPEC（再次全文注入 -- verifier 需要對照 spec 判斷 finding 是否合理）
[3] findings.md 完整內容
```

值得注意的是 Step 3 的 verifier 重新注入了 SPEC，而非依賴 Claude 的 session memory。原因：verifier 是新 session（沒有 resume），它需要看到 spec 原文才能判斷「GPT 說的 bug 是不是 spec 真的要求的行為」。

### 11.3 Attacker prompt 的類別優先順序 vs 實際攻擊行為

Attacker prompt 定義了 5 個類別的優先順序（由嚴重到輕微）：

1. Spec-code 落差
2. Silent data corruption
3. State leak
4. Boundary / type coercion
5. Concurrency

Prompt 裡的規則要求 attacker「不可重複 PREVIOUS ATTACKS 的類別」。這個規則在 v1 的多 round 場景下比較有效（每個 attacker 跑 3 輪，每輪被迫選不同類別）。在 v2 裡，每個 attacker 只跑一輪攻擊，類別限制的實際效果降低。

Smoke test 觀察：GPT 選了 #1（spec-code mismatch），Claude 選了 #2（silent data corruption）。但 Claude 的 finding 本質上也涉及 spec-code 關係（history endpoint 應該存所有欄位），只是 Claude 的推理路徑是「cross-endpoint consistency」而非「spec says X but code does Y」。兩者的類別區分在實際操作中沒有那麼清晰。

---

## 12. 安全性考量

### 12.1 Stage 3 的 read-only 約束深度

Stage 3 的 attacker 有兩層 read-only 約束：

**Layer 1: Tool-level restriction**

- GPT（codex）：`codex exec -s read-only` -- OS-level sandbox，filesystem writes 被 kernel 攔截
- Claude：`--disallowed-tools "Write Edit NotebookEdit Agent"` -- Claude CLI 層面禁止呼叫 write 類 tools

**Layer 2: Git-level verification**

每輪 attacker 跑完後，`verify_git_lock()` 比較 current working tree state 和 baseline。任何差異都被視為 violation。

**Gap analysis（待驗證）：**

- Claude 的 Bash tool 有寫入能力（`echo "x" > file`）。`--disallowed-tools` 裡沒有列 Bash。Claude 如果決定用 Bash 寫檔案，Layer 1 不會攔截，但 Layer 2 會抓到。
- 如果 Claude 用 Bash 寫的是 /tmp 或其他 repo 外的路徑，Layer 2 也不會抓到（git 只追蹤 repo 內檔案）。但這不算 violation -- attacker 在 /tmp 寫暫存檔做分析是合理行為。
- GPT 的 OS-level sandbox 理論上是更強的約束，但具體的 sandbox 實現取決於 codex CLI 的版本和配置。

### 12.2 Findings 的機密性

`findings.md` 包含 attacker 找到的 bug 細節（包括 reproduce steps、具體 line numbers）。這個檔案存在 `/tmp/auto_claude_attack_v2_$$`，EXIT trap 會清理。但：

- 如果 script crash 且沒觸發 EXIT trap（例如 `kill -9`），/tmp 下的 findings 會殘留。
- Final report 會寫入 `.auto_claude/logs/`，包含所有 CONFIRMED 和 HALLUCINATED 的完整描述。如果 `.auto_claude/logs/` 不在 `.gitignore` 裡，這些安全性相關的 findings 可能被不小心 commit 到 repo 裡。

建議：在 `.auto_claude/.gitignore` 裡加上 `logs/` 的 exclude 規則。

---

## 附錄 A: 關鍵檔案路徑索引

| 檔案 | 用途 |
|------|------|
| `engine/step1_focus_loop.sh` | Stage 1 主程式（Dev ↔ dumb Trigger） |
| `engine/step2_rev_loop.sh` | Stage 2 薄 wrapper（呼叫 loop.sh + auto-commit + chain） |
| `engine/loop.sh` | 核心 Dev ↔ Reviewer 循環（v3.1） |
| `engine/attack_loop_v2.sh` | Stage 3 v2 主程式（pipelined relay） |
| `engine/attack_loop.sh` | Stage 3 v1（9-round serial，fallback） |
| `templates/agent/dev/stage1_prompt.md` | Stage 1 Dev 的 system prompt |
| `templates/agent/dev/stage2_prompt.md` | Stage 2 Dev 的 system prompt |
| `templates/agent/attacker/prompt.md` | Attacker 的 role prompt |
| `references/3_stage_pipeline_guide.md` | 使用者導向的操作說明書 |

## 附錄 B: 相關 commit 歷史

| SHA | 說明 |
|-----|------|
| `77d8dfd` | feat: add 3-stage pipeline (focus -> review -> attack) |
| `0ff4152` | feat: add attack_loop.sh (GPT-5.3 + Claude adversarial testing) |
| `91174e4` | fix: step2 killed by loop.sh EXIT trap + empty array crash in attack_loop |
| `dfce994` | feat: attack_loop_v2 -- pipelined relay (GPT‖Claude preload -> relay -> verify) |
| `72d7b34` | fix: attack_loop_v2 rm input files before subshells read them |

## 附錄 C: Attacker prompt 的 anti-gaming 設計

Attacker prompt 包含三段 anti-gaming 規則（`templates/agent/attacker/prompt.md` 第 70-72 行）：

1. **「may cause issues under some conditions」是幻覺信號。** 如果 attacker 想寫這種模糊語句，應該停下來。要嘛找到具體 input/output 證明 failure，要嘛就 CLEAN。
2. **「I couldn't reproduce but it looks suspicious」歸類到 CLEAN 的 Note，不是 ATTACK。**
3. **禁止修改 code 來「測試假設」。** 用 `python3 -c` 或 `node -e` 跑獨立驗證，不動 repo 的檔案。

Smoke test 觀察：Claude 完全遵守了這些規則。GPT 的遵守度較差 -- 它的兩個 HALLUCINATED findings 本質上是「looks suspicious but spec doesn't require it」的情況，按規則應該歸到 CLEAN 的 Note，但 GPT 包裝成了 ATTACK。Cross-verify 階段有效地過濾了這些，但如果 GPT 是唯一的 attacker（沒有 cross-verify），這些 hallucination 會進入 final report。

---

## 附錄 D: Smoke Test 的 Pipeline 執行序列重建

以下是根據 commit history 和 log 重建的 smoke test 完整執行序列：

```
[T+0min]   step1_focus_loop.sh --project-dir <word-counter> --chain-stage3
[T+0min]   Stage 1 Round 1: Dev reads phase_plan.md, starts building POST /count
[T+2min]   Trigger: "好，繼續 phase_plan.md 的下一項。"
[T+2min]   Stage 1 Round 2: Dev implements GET /history, commits
[T+4min]   Trigger: "繼續。"
[T+4min]   Stage 1 Round 3: Dev adds input validation, commits
[T+6min]   Trigger: "好，下一個 item。"
[T+6min]   Stage 1 Round 4: Dev adds text_preview to response, commits
[T+8min]   Trigger: "繼續推進。"
[T+8min]   Stage 1 Round 5: Dev checks phase_plan -- all items [x] -- emits STOP
[T+9min]   Curator (sonnet) compresses -> progress.md
[T+10min]  exec step2_rev_loop.sh --chain-stage3

[T+10min]  Stage 2: loop.sh starts (Dev ↔ Reviewer)
[T+10min]  (Reviewer finds minor issues: missing error handling, no tests)
[T+12min]  Dev fixes, adds basic tests
[T+15min]  Reviewer + Dev bilateral stop
[T+15min]  loop.sh EXIT trap fires -- kill 0
[T+15min]  *** BUG: step2 killed by SIGTERM -- chain-to-stage3 never runs ***

[T+15min]  Manual restart: debug kill 0 issue
[T+...min] Commit 91174e4: fix step2 + empty array crash
[T+...min] Manual restart: step2_rev_loop.sh (now with trap '' TERM)

[T+...min] Stage 2 completes, auto-commit WIP
[T+...min] exec attack_loop_v2.sh --skip-dirty-check

[T+...min] Step 0: GPT attacks (parallel) + Claude preloads
[T+...min] *** BUG: rm input files before subshells read them ***
[T+...min] Manual restart after commit 72d7b34

[T+...min] Step 0 completes: GPT finds text_preview truncation (20 vs 30)
[T+...min] Step 1: Claude resumes, finds /history data loss
[T+...min] Step 2: GPT relay, finds lower() vs casefold() (later rejected)
[T+...min] Step 3: Cross-verify -- 2 CONFIRMED, 2 HALLUCINATED
[T+...min] Final report generated

Total elapsed: ~4.5 hours (including ~3 hours of bash debugging)
Productive pipeline time: ~80 minutes
```

注意事項：

- 上面的 `[T+...min]` 部分因為多次 crash 和重啟，精確時間無法重建。
- Bash bug 的發現順序是：先遇到 `kill 0` 問題（commit `91174e4`），修復後重跑，再遇到 rm race condition（commit `72d7b34`），修復後最終成功跑完。
- 空 array crash（`91174e4` 的另一個修復）是在 attack_loop v1 除錯時發現的，後來也同步修正到 v2。

---

*本報告基於 2026-04-13 的 smoke test 結果撰寫。所有關於效能和行為的描述均為觀察到的事實，除非明確標註為「推測」或「預期」。等正式專案驗證後，相關數據會更新到 v2 報告中。*
