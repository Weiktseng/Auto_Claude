# 字典自動擴建 Loop 架構建議書

> 撰寫：2026-04-16，Claude Code（Auto_Claude loop 實作討論後留存）
> 狀態：**建議 / 未實作**。當下動作是 `git checkout` 回 baseline 78 條乾淨字典。
> 適用：`meeting_summarizerV9/config/terminology_public.json` 的長期擴建策略

---

## 1. 設計約束（出貨環境）

1. **只有一個小地端 LLM**（Gemma3 27B 等級、有限 context、慢、不準）負責所有 LLM 工作
2. 設計原則：**能走傳統代碼就別叫 LLM**；叫了就接受「慢 + 不準」的代價
3. 字典用途：摘要 pipeline 上游做**盲 replace**——小模型吃修好的逐字稿，不吃原始 ASR garbage
4. **False positive 比 False negative 嚴重**：誤改一個真詞 → 污染整份輸入；少改一個錯字 → 小模型勉強還能猜
5. 字典會一直長大（10K+ 條是預期），查找速度不能退化

---

## 2. 為什麼 `len(wrong) >= 3` 不是對的過濾

直覺上 2 字 key 危險，但 baseline 78 條裡 2 字合理 entry 佔大宗：
`桃圓→桃園`、`減包/間報/建包→簡報`、`背標/被標→備標`、`報院/報研/報鹽→報驗`...

**真正的判準：`wrong` 是不是乾淨書面語料裡的詞**，跟字數無關。
- `桃圓` 維基「桃園」條目不會出現 → 安全
- `展演` 維基很多 → 危險
- `開心率` 行銷文章存在 → 危險

## 3. Validator 規則（取代 len 限制）

```python
def is_safe_entry(wrong, correct, clean_corpus, asr_corpus):
    if wrong == correct:        return "identity"             # 無意義
    if wrong in clean_corpus:   return "reject_fp_proven"     # FP 鐵證
    if jieba.dt.FREQ.get(wrong, 0) > 500:  return "reject_common_word"
    if asr_corpus and wrong not in asr_corpus:  return "pending"  # 沒證據，待觀察
    return "accept"
```

**乾淨語料來源（優先順序）：**
1. 維基百科中文 dump（抓前 10 MB 構 set）
2. 台大 ASBC / Sinica CWB（學術標準）
3. 短期替代：手寫 blacklist（展演/開心率/抒發/豪產/外坪 …）

**ASR 語料來源：**
- `BSS_1013.txt`, `BSS251027.txt`, `SYNTHETIC_*.txt`
- 未來：Loop 累積的所有 round transcripts（`.auto_claude/workspace/transcripts/`）

---

## 4. 查找效能（字典臃腫時）

**現狀**（`terminology_corrector.py:115-118`）：
```python
for wrong, correct in sorted_terms:
    if wrong in corrected:
        corrected = corrected.replace(wrong, correct)
```
O(N × L) ：N=字典大小、L=文本長度。10K 條撞牆。

**建議**：改用 Aho-Corasick 或 flashtext——O(L + matches)

| 方案 | 速度 | 相依 | 備註 |
|---|---|---|---|
| `pyahocorasick` | 最快（C） | 需 C 編譯環境 | 學術標準 |
| `flashtext` | 稍慢 | 純 Python | 零相依，ops 友善 |
| 保留現方案 | 慢 | 無 | 只在 < 500 條時可用 |

**建議做法**：
- Loop 每次 commit 前編譯 `terminology_compiled.pkl`（pyahocorasick automaton）
- `terminology_corrector.py` 啟動時優先 load pkl，缺檔才 fallback 現行 loop
- pkl **gitignore**，pipeline 啟動 script 會檢查 JSON mtime > pkl mtime 就自動 rebuild

---

## 5. Loop 最終工作流程（建議版）

```
每輪：
  1. 選來源（yield 高的類型優先，spec.txt §6）
  2. yt-dlp 下載音檔（預檢音量 mean_volume > -30 dB 才跑）
  3. WhisperX 轉逐字稿
  4. Dev 挑候選——只填三欄 {wrong, correct, category}
  5. validator.py 自動過濾：
     - identity / fp_proven / common_word → reject
     - pending → 堆到 candidates/pending.json，隔週人工 review
     - accept → merge 進 terminology_public.json
  6. 重編 terminology_compiled.pkl
  7. 跑 pytest + benchmark（1000 行逐字稿 corrector 處理 < 500 ms）
  8. git commit
```

**Dev 職責縮到最小**：只管「從逐字稿挑錯字」；格式、去重、FP 過濾、壓縮、編譯全部 validator.py 做。

---

## 6. Candidate 檔 schema 精簡

**現狀**（`round_N.json`）：每條 entry 有 `reason`, `evidence`, `accepted`, `category`, `source_type`, ... 這些是 LLM pad token 的產物。

**建議**：
- Final dict (`terminology_public.json`)：只 `{category: {wrong: correct}}`，**乾淨到底**
- Candidate audit trail：`{wrong, correct, category}` + 該輪 commit hash 指向 source，其餘靠 git 反查

---

## 7. GPU 利用率拉到 80% 的方向（跨素材量產）

目前 Loop 是 serial：**下載 → 單檔 WhisperX → Dev 處理 → commit → 下一輪**。GPU 平均 < 5% 使用率。

**升級路徑：**

1. **WhisperX batch 模式**：一次塞 N 個音檔到同一個 pipeline call，共享模型 load / GPU memory
2. **Producer / Consumer 分離**：
   - Producer worker：持續 yt-dlp 下載，填 audio queue
   - Consumer worker：WhisperX 從 queue 抓音檔，batch 轉錄
   - Dev：從 transcript queue 挑錯字
3. **多卡平行**：2× RTX 6000 → 一張跑 transcription、一張跑 alignment/diarization
4. **監控**：nvidia-smi + dcgm-exporter → Grafana 看板，目標平均 ≥ 80%

---

## 8. 跟主管確認的開放問題

1. **ASR 模型**：出貨版用哪個？(WhisperX large-v3 / faster-whisper / 其他本地？) → 決定字典「wrong 側」的錯字模式
2. **字典交付形式**：JSON 可編譯 or 必須純 JSON？（影響能否引入 Aho-Corasick）
3. **FP 容忍度**：一份 1 萬行逐字稿，誤改幾個字可接受？（決定 validator 嚴格度）
4. **量產目標**：每天處理幾小時音檔？→ GPU 配置決策

---

## 9. 當下決議（2026-04-16）

- 字典 `git checkout 6306252 -- meeting_summarizerV9/config/terminology_public.json` 回 baseline 78 條
- 156 版（Dev 擴充版）當參考材料，不進主線
- Loop 暫停，等 ASR 模型確認 + GPU 架構方向後再啟動
- 本文件作為下次啟動的實作藍圖
