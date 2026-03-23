# Reduce File Creation — 減少暫存檔案

來源：Claude 4 Best Practices — Reduce file creation in agentic coding
適用：Dev prompt

## 問題

Claude 最新模型在迭代時會建立暫存檔案（特別是 Python script）當作 scratchpad。
這有時能改善結果，但會留下一堆垃圾檔案。

## 官方片段

```text
If you create any temporary new files, scripts, or helper files for iteration, clean up
these files by removing them at the end of the task.
```

## Auto_Claude 備註

簡短但有效。Dev 在長回合跑完後經常留下 test_*.py、debug_*.sh 等檔案。
加這句可以讓 Dev 自己清理。
