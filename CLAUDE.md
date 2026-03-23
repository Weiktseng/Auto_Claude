# Auto_Claude — 開發注意事項

## 路徑規則

此 session 的 cwd 是 `Auto_Claude/`（引擎本身），但大部分工作是操作**其他專案**的檔案。
那些檔案是用auto_claude 自動化的正式專案，使用專案資料夾下的.auto_claude/ 進行自動化，自動化則是user Lance 你的人類夥伴開發的商業機密工作流，不會交給那些專案的客戶。
此 session 的 cwd 是 `Auto_Claude/`（引擎本身）則是乾淨的，不含任何專案且可單獨上github(private)的Auto_Claude建置模板，新專案可用這裡作為基底創建。

**規則：修改專案相關檔案前，先確認你操作的是專案的 `.auto_claude/` 目錄，不是 Auto_Claude 引擎目錄。**

| 要改什麼 | 正確路徑 | 錯誤路徑 |
|---------|---------|---------|
| 專案 comms/logs/prompts | `<專案>/.auto_claude/` | `Auto_Claude/projects/` |
| 引擎 loop.sh | `Auto_Claude/engine/loop.sh` | — |
| 通用參考資料 | `Auto_Claude/references/` | — |

### 已知專案路徑
- **motc（交通部客服）**: `/Users/henry/Desktop/公司/AI交通部客服/.auto_claude/`

操作前自問：「這個檔案屬於引擎還是專案？」專案的東西永遠在專案目錄下。
