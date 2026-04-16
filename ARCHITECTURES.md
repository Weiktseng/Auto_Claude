# Auto_Claude 架構選擇指南

Auto_Claude 同時支援兩種正式架構，根據專案特性擇一使用。兩者都是 first-class 支援，沒有「哪個比較新就用哪個」。

| | **Classic** | **Pipeline** |
|---|---|---|
| Git tag | `classic-v1` | `pipeline-v1` |
| 核心腳本 | `engine/loop.sh` | `engine/step1_focus_loop.sh` → `engine/step2_rev_loop.sh` → `engine/attack_loop_v3.sh` |
| 結構 | 單迴圈 Dev ↔ Reviewer | 三階段 Focus → Review → Attack |
| 模板路徑 | `templates/classic/` | `templates/pipeline/` |

## 什麼時候用 Classic

- **已存在的專案補 feature 或修 bug** — 不需要 phase 切分，直接 Dev + Reviewer 就能推進
- **短 spec（小於 500 行）或 spec 已經很成熟**
- **人類可以每隔一段時間回來看一次** — 不需要三階段最終驗收
- **修改範圍局部** — 不涉及整個 code base 重構
- **已經有測試覆蓋的成熟專案** — Reviewer 每輪都會跑測試，Attack 是多餘的
- **需要即時 human hotline** — classic 的 `human_message.md` 可以隨時打斷，pipeline 三階段之間插話時機比較受限

範例：motc（交通部客服）、baphiq（犬貓晶片）、perma_ai 之類的在建專案。

## 什麼時候用 Pipeline

- **從零開始的新專案，spec 很長（1000+ 行）**
- **人類真的會睡一整晚** — 希望醒來看到 attack report 而不是中途狀態
- **專案規模大（2000-5000 行以上）** — Stage 3 的雙模型攻擊能抓到 Reviewer 漏掉的 edge case
- **Phase 之間要有明確交接點** — 每個 phase 做完有 attack report 驗收再進下一個
- **spec 模糊地帶多** — attack 能找出 spec vs code 的落差和 code 內部不一致

範例：一個長規格書從零建造的交付型專案。smoke_3stage、perma_ai_stage123 之類的 clean-room 建置。

## 兩者共用的東西

- `engine/loop.sh`（classic 的主迴圈，也是 pipeline 的 Stage 2）
- `engine/cleanup.sh`（殭屍進程清理）
- `engine/check_except_patterns.py`（except anti-pattern hook）
- `templates/agent/{reviewer,curator,comms}/`（Reviewer 和 Curator prompt、溝通管道）
- `templates/agent/context.md`、`spec.txt`
- `settings.local.json`（工具權限）

## 兩者不共用的東西

**Classic 獨有：**
- `templates/classic/agent/dev/prompt.md`（乾淨版 Dev 規則，不含任何 Stage 或 pipeline 相關內容）

**Pipeline 獨有：**
- `engine/step1_focus_loop.sh` — Stage 1 Dev ↔ dumb Trigger
- `engine/step2_rev_loop.sh` — Stage 2 wrapper
- `engine/attack_loop_v3.sh` — Stage 3 GPT fire-and-forget + Claude main（v2、v1 保留作為 fallback）
- `templates/pipeline/agent/dev/stage1_prompt.md`
- `templates/pipeline/agent/dev/stage2_prompt.md`（含 Stage 2 心智狀態說明）
- `templates/pipeline/agent/attacker/prompt.md`
- `templates/pipeline/agent/phase_plan.md`（未填警示模板）

## 怎麼切換

**新專案啟動時選架構：**

```bash
# Classic — 單迴圈 Dev ↔ Reviewer
cd /path/to/new_project
mkdir -p .auto_claude
cp -r /Users/henry/Desktop/公司/Auto_Claude/templates/classic/* .auto_claude/

# Pipeline — 三階段 Focus → Review → Attack
cd /path/to/new_project
mkdir -p .auto_claude
cp -r /Users/henry/Desktop/公司/Auto_Claude/templates/pipeline/* .auto_claude/
# phase_plan.md 已經在裡面（模板帶有未填警示，人類必填）
```

兩份模板是**完全獨立**的子資料夾，classic 裡不會出現任何 pipeline 的檔案（`stage1_prompt.md`、`attacker/`、`phase_plan.md` 等），反之亦然。複製哪個資料夾就是什麼架構，不會混進去。

**已存在的 classic 專案升級到 pipeline：**

不推薦。pipeline 的前提是「從零開始切 phase」。已進行中的 classic 專案繼續用 classic 最清楚。

**引擎版本鎖定：**

兩個 tag 都可以固定：
```bash
# 在專案的 .auto_claude/run.sh 裡把 ENGINE_TAG 設成想固定的版本
ENGINE_TAG="classic-v1"   # 或 "pipeline-v1"
```
Auto_Claude 會自動 checkout 對應 tag 再跑 loop。

## 參考文件

- Classic 細節：[`ARCHITECTURE.md`](ARCHITECTURE.md)（系統架構、prompt 組裝、三層抓 bug 機制）
- Pipeline 細節：[`references/3_stage_pipeline_guide.md`](references/3_stage_pipeline_guide.md)（實驗性使用說明）、[`references/3_stage_architecture_report_v1.md`](references/3_stage_architecture_report_v1.md)（設計報告、smoke test 數據）
- 設定教學：[`SETUP.md`](SETUP.md)（兩套都適用）
- Phase 切分方法論：[`SETUP.md`](SETUP.md) §5.5（pipeline 必讀）
