# Auto_Claude 共用權限設定

Claude Code 的 `settings.local.json` 共用維護檔。

## 用途

蒐集所有未知又安全的指令允許命令，統一團隊的 Claude Code 自動化權限，讓瑣碎命令（版本檢查、檔案操作等）不再跳確認，同時封鎖危險操作。

## 使用方式

```bash
# 複製到你的 Claude 設定目錄
cp settings.local.json ~/.claude/settings.local.json
```

> **重要：** 複製完成後必須**重新開啟 Claude Code session** 才會生效。

## 注意事項

- 此設定控制的是 Claude Code 的工具權限（allow/deny 清單）
- 部分安全提示是 Claude Code 內建的（如 brace expansion `{}`、compound `cd && git` 命令），**無法透過此設定關閉**，屬正常行為，選 Yes 即可

## 結構

- **allow**: 已開放自動執行的工具與命令
- **deny**: 封鎖的危險命令（刪除根目錄、force push 等）

## 貢獻

歡迎 PR 新增 deny 規則或調整 allow 範圍，請附上原因說明。
