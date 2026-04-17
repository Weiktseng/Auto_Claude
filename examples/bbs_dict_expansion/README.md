# BBS Dict Expansion — 真實專案範例

用 Auto_Claude 把一個**工具鏈任務**（下載公開音檔 → ASR → 挑 ASR 錯字 → 擴充校正字典 → commit）做成 24 小時自動迴圈。零人類介入，跑到 `max-rounds` 為止。

**這份 example 存在的目的**：示範 Auto_Claude 如何應用在「不需要 AI Reviewer、只要一個 Dev 反覆執行確定性任務」的場景。關鍵技法：

1. **DUMB_REVIEWER=1**：engine 裡新的環境變數，把 Reviewer / Curator 的 Claude 呼叫全部 stub 化。每輪只剩 **Dev 一次 API call**，省 ~70% quota
2. **沒有 STOP 協議**：終止完全靠 `--max-rounds`，Dev 不能自宣「做完了」早收
3. **pre-flight gate in `run.sh`**：強制驗 container 在跑、max-rounds 顯式指定、工具就位
4. **一行 ASR wrapper**（`tools/asr_via_docker.sh`）把 yt-dlp → ffmpeg → docker cp → docker exec → 清乾淨包成一個指令，trap 保證髒檔不留

---

## 檔案結構

```
bbs_dict_expansion/
├── README.md                     ← 你在看的這份
├── ARCHITECTURE_PROPOSAL.md      ← 未來升級方向（Aho-Corasick、GPU 80%、validator）
├── run.sh                        ← 啟動器；pre-flight gate + exec engine/loop.sh
├── agent/
│   ├── spec.txt                  ← 任務規格（WHAT）：流程、納入規則、candidates schema、紅線
│   ├── context.md                ← 環境參考（HOW env）：路徑、ASR、底層原理 debug 用
│   ├── reviewer_stub.md          ← 1 行；DUMB 模式每輪注入 Dev prompt
│   ├── dev/prompt.md             ← Dev 通用守則（行為規則，任務無關）
│   └── comms/                    ← 執行時 Dev ↔ 人類雙向通道
└── tools/
    └── asr_via_docker.sh         ← ASR 一行包裝（docker exec/cp 零容器重啟）
```

## 功能切分原則（避免重複維護）

| 檔案 | 負責 | 載入頻率 |
|---|---|---|
| `spec.txt` | WHAT to do（任務規則） | 每輪 Dev prompt 1 次 |
| `context.md` | HOW env works（環境/工具/原理） | 每輪 Dev prompt 1 次 |
| `dev/prompt.md` | HOW Dev behaves（通用守則） | 每輪 Dev prompt 1 次 |
| `reviewer_stub.md` | 每輪替身（砍到 1 行） | 每輪都注入 |

每類資訊**單一來源**。不要四個檔塞重複內容。

## 用法（本 example 的原使用情境）

```bash
# 前提：meetlingo-worker-transcribe 容器已在跑（產線 ASR 服務）
./run.sh --max-rounds 50 --model-dev opus \
    --initial-prompt "照 agent/spec.txt 開工"
```

`run.sh` 會驗三件事：
1. `--max-rounds` 顯式指定（沒給直接 exit 1）
2. `meetlingo-worker-transcribe` 容器在跑（沒跑 exit 2，不自動啟動）
3. `tools/asr_via_docker.sh` 存在可執行（exit 3）

全過才 `exec engine/loop.sh`。

## 要改到你的專案用，需要動的地方

- **`run.sh`**：`ENGINE_REPO` 路徑、pre-flight 的容器名 / 工具名
- **`tools/asr_via_docker.sh`**：容器名 `meetlingo-worker-transcribe`、`tests/test_transcript_api.py` 的 ASR 呼叫格式（你家 ASR 肯定不同）
- **`agent/spec.txt`**：任務目標、納入規則、輸出 schema
- **`agent/context.md`**：路徑、script 用法、你家環境限制

**`agent/reviewer_stub.md` 和 `agent/dev/prompt.md`** 幾乎通用，直接抄即可。

## 關鍵設計決策（從失敗學來的）

- **錯字不確定就跳過**。false positive（把真詞改壞）比 false negative（漏抓錯字）嚴重太多——盲 replace 下游會污染摘要輸入
- **2 字 `wrong` key 不該禁**。很多真實 ASR 錯（桃圓→桃園、減包→簡報）都是 2 字。真正該過濾的是「`wrong` 是否在乾淨語料出現」，不是字數
- **LLM 只留給真需要語意理解的事**。字典 validation / dedupe / 壓縮 / 編譯全部 Python 代碼做，出貨環境只有一個小地端模型
- **hotwords ≠ public dict**。hotwords 是客戶每場會議自填的 domain 專名（pre-processing），public dict 是跨客戶通用錯字（post-processing 盲 replace）。兩個不同層的機制

詳見 `ARCHITECTURE_PROPOSAL.md`。

## Engine 需求

需要 `engine/loop.sh` 支援 `DUMB_REVIEWER=1`（本 branch 已 patch）。
