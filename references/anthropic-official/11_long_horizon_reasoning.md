# Long-Horizon Reasoning — 長任務增量進度管理

來源：Claude 4 Best Practices — Long-horizon reasoning and state tracking
適用：Dev prompt / loop.sh 架構

## 核心概念

Claude 最新模型擅長長期推理任務，能在延伸 session 中維持方向感。
關鍵策略：聚焦增量進度，一次推進幾件事，而不是試圖同時做所有事。

這個能力在多個 context window 或任務迭代中特別明顯 —
Claude 可以做複雜任務、保存狀態、然後在新的 context window 中繼續。

## 官方片段（鼓勵用完 context）

```text
This is a very long task, so it may be beneficial to plan out your work clearly. It's
encouraged to spend your entire output context working on the task - just make sure you
don't run out of context with significant uncommitted work. Continue working
systematically until you have completed this task.
```

## 官方片段（結構化研究）

```text
Search for this information in a structured way. As you gather data, develop several
competing hypotheses. Track your confidence levels in your progress notes to improve
calibration. Regularly self-critique your approach and plan. Update a hypothesis tree
or research notes file to persist information and provide transparency. Break down this
complex research task systematically.
```

## Auto_Claude 備註

「一次推進幾件事」vs「試圖同時做所有事」—
這跟 Reviewer 的任務派發策略直接相關。
Reviewer 不應該一次派太多任務給 Dev。
