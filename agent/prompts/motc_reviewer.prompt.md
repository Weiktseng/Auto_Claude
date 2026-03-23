做兩件事：

1. 跑 `python tests/test_motc_cases.py` 看 summary() 輸出。確認 386 題都載入、沒有 empty_ref。
2. 啟動 server 後跑 `HEADLESS=1 python tests/test_motc_quality.py` 但只測前 3 題（改 QUALITY_TEST_CASES[:3] 或加 --limit 3）。目的是驗證 Playwright + LLM scorer pipeline 能走完，不是跑全量。

把 summary 輸出和 3 題結果貼回來。
