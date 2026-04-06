## Round 17 指派

人類主管次要任務尚未完成，請處理：

1. **快速按鈕驗證** — 首頁的犬貓進口/出口、狂犬病檢測、晶片與疫苗按鈕，點擊後是否正確觸發對話或導航
2. **語言切換驗證** — 切換各語系後 UI 文字是否正確替換，快速按鈕文字是否跟著換
3. **跑人類指定的測試**：
   - `uv run python tests/test_petq_api.py`
   - `HEADLESS=1 uv run python tests/test_petq_e2e.py`
   - 回報每支的 pass/fail 數量
4. 有問題就修，修完再跑一次

Round 16 的 confirm/cache/RWD 改動已驗收通過 ✅
