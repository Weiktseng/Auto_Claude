# Auto_Claude

Claude Code `settings.local.json` 團隊共用設定。

> **完整的 5 層權限架構教學請看 [GUIDE.md](GUIDE.md)**

## 為什麼需要自動化

蒐集所有未知又安全的指令允許命令，統一團隊的 Claude Code 自動化權限，讓瑣碎命令不再跳確認，同時封鎖危險操作。實測一個 session 可觸發 **150+ 次授權提示**，累積接近 **1 小時的等待時間**。

## 安裝

```bash
git clone git@github.com:Weiktseng/Auto_Claude.git
cp Auto_Claude/settings.local.json ~/.claude/settings.local.json
```

重新開啟 Claude Code session 即生效。

## 設定結構

### allow（自動允許）

| 類別 | 涵蓋範圍 |
|------|---------|
| `Bash(*)` | 基礎萬用匹配 |
| `Bash(python3 *\|*)` 等 | 管道、鏈式命令（`Bash(*)` 不一定覆蓋） |
| `Bash(curl *)`, `Bash(wget *)` | 下載資料 |
| `Bash(git *)`, `Bash(git *\|*)` | 版本控制 |
| `Bash(uvicorn *)` | 開發伺服器 |
| `Read`, `Write`, `Edit`, `Glob`, `Grep` | 檔案操作工具 |
| `WebSearch`, `WebFetch` | 網路查詢 |
| `NotebookEdit` | Jupyter notebook |

### deny（封鎖）

每條 deny 規則都有明確的不可逆破壞理由：

| 規則 | 原因 |
|------|------|
| `Bash(rm -rf /)`, `rm -rf /*` | 刪除整台電腦 |
| `Bash(rm -rf ~)`, `rm -rf ~/*` | 刪除整個家目錄 |
| `Bash(sudo *)` | 提權操作，風險不可控 |
| `Bash(git push --force *)` | 覆蓋遠端歷史，團隊其他人的工作會丟失 |
| `Bash(git push * --force *)` | 同上（flag 位置不同的變體） |
| `Bash(git reset --hard *)` | 丟棄所有未提交變更，無法復原 |

> deny 規則只加不可逆的破壞性操作。`rm -rf node_modules` 這類正常開發操作不在封鎖範圍。新增 deny 規則必須附上具體的破壞場景說明。

## 已知限制

以下安全提示是 Claude Code **內建的**，無法透過設定關閉：

- **Brace expansion** `{}` — 如 `mkdir -p dir/{a,b,c}`，改寫成 `mkdir -p dir/a dir/b dir/c` 可避開
- **部分 compound 命令** — 即使有 `Bash(*)` 仍可能觸發，需在 allow 中明確列出模式（如 `Bash(cd *&&*)`）

## 專案級設定

此檔案是全域設定（`~/.claude/settings.local.json`）。各專案可在自己的 `.claude/settings.local.json` 中追加針對該專案的 allow 規則，補充全域設定覆蓋不到的模式。

## 貢獻規則

### allow：只增不刪

- **新增**：直接 PR，說明哪個命令模式會觸發不必要的授權提示
- **刪除**：必須有**非常嚴重的安全問題**才能移除現有 allow 規則，並附上具體的攻擊場景說明

### deny：必須附上破壞場景

- 新增 deny 必須附上**具體的不可逆破壞場景**，否則不合併
- `rm -rf node_modules` 這類正常開發操作不在封鎖範圍

### 不要相信 `Bash(*)` 能解決一切

`Bash(*)` 看起來是萬用匹配，但實測中它**無法覆蓋所有情況**。以下是真實的踩坑紀錄：

## 實戰案例：為什麼需要明確列出每個模式

以下案例來自一個真實的 Claude Code session，即使已經設定 `Bash(*)` 仍然觸發了授權提示：

### 案例 1：Brace expansion 觸發確認

```
Bash command
  mkdir -p data/{exam_questions,laws,materials,stations,news,highway,tdx,statistics}
  Create data subdirectories for all sources

Command contains brace expansion that could alter command parsing

Do you want to proceed?
❯ 1. Yes
  2. No
```

**原因：** Claude Code 內建安全檢查，偵測到 `{}` brace expansion 就會攔截，與 settings 無關。
**解法：** 改寫成展開形式 `mkdir -p data/exam_questions data/laws data/materials ...`

### 案例 2：Compound commands with cd + git

```
Bash command
  cd /path/to/repo && git init && git remote add origin ... && git add . && git status
  Init repo, add remote, stage files

Compound commands with cd and git require approval to prevent bare repository attacks

Do you want to proceed?
❯ 1. Yes
  2. No
```

**原因：** Claude Code 內建防護，`cd` + `git` 的組合命令會觸發 bare repository attack 的安全檢查。
**解法：** 在 allow 中明確加入 `Bash(cd *&&*)` 可減少部分觸發，但此類內建檢查無法完全關閉。

### 案例 3：cp 檔案觸發專案存取確認

```
Bash command
  cp source.csv data/faq_raw.csv && wc -l data/faq_raw.csv
  Copy FAQ CSV to data directory

Do you want to proceed?
❯ 1. Yes
  2. Yes, and always allow access to AI交通部客服/ from this project
  3. No
```

**原因：** 這是**專案目錄存取權限**的確認，不是命令類型的問題。首次存取某個專案路徑時會觸發。
**解法：** 選 "Yes, and always allow access" 後該專案路徑就不會再問。這個也無法透過 settings 預先設定。

### 案例 4：Claude 自己也會觸發

即使是 Claude Code 自己生成的命令，也會被自己的內建安全檢查攔截。這不是 bug，是 feature。

> **結論：** `Bash(*)` 只是基礎，必須搭配明確的模式匹配（如 `Bash(cd *&&*)`、`Bash(git *|*)`）才能最大程度減少不必要的提示。但部分內建安全檢查（brace expansion、bare repo 防護）是無法關閉的。
