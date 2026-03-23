# Claude Code 權限設定完整教學

## 權限層級總覽

Claude Code 有 **5 層**權限設定，優先級由高到低：

```
┌──────────────────────────────────────────────────────────────┐
│ 1. MANAGED SETTINGS（最高優先級，IT 部署，不可覆寫）            │
│    macOS: /Library/Application Support/ClaudeCode/           │
│           managed-settings.json                              │
│    Linux: /etc/claude-code/managed-settings.json             │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│ 2. SERVER-MANAGED SETTINGS（組織級，雲端部署）                  │
│    Claude.ai Admin Settings > Claude Code > Managed settings │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│ 3. LOCAL PROJECT SETTINGS（個人，專案級）                       │
│    .claude/settings.local.json                               │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│ 4. SHARED PROJECT SETTINGS（團隊共享，專案級）                  │
│    .claude/settings.json                                     │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│ 5. USER SETTINGS（最低優先級，全域）                            │
│    ~/.claude/settings.json                                   │
└──────────────────────────────────────────────────────────────┘
```

**核心規則：高層級的 deny 不能被低層級的 allow 覆寫。**

---
# 啟動命令範例
cd /Users/henry/Desktop/公司/AI交通部客服 && nohup /Users/henry/Desktop/公司/Auto_Claude/engine/loop.sh --project-dir /Users/henry/Desktop/公司/AI交通部客服 --max-rounds 50 > .auto_claude/logs/loop_stdout.log 2>&1 &

out:[1] 70931

## 每一層的詳細說明

### 第 1 層：Managed Settings（系統級）

| 項目 | 說明 |
|------|------|
| 路徑 | macOS: `/Library/Application Support/ClaudeCode/managed-settings.json` |
|      | Linux/WSL: `/etc/claude-code/managed-settings.json` |
|      | Windows: `C:\Program Files\ClaudeCode\managed-settings.json` |
| 誰設定 | IT 管理員，透過 MDM 或系統政策部署 |
| 用途 | 企業級強制規則，例如禁止所有人 `sudo`，任何人都無法覆寫 |
| Git 共享 | 否，由 IT 獨立部署 |

**何時會用到：** 大型企業、有 IT 部門的組織。個人或小團隊通常不需要。

### 第 2 層：Server-Managed Settings（雲端組織級）

| 項目 | 說明 |
|------|------|
| 設定位置 | Claude.ai 管理後台 > Admin Settings > Claude Code |
| 誰設定 | 組織管理員 |
| 用途 | Teams/Enterprise 方案的組織級設定，認證時自動下發 |
| Git 共享 | 否，雲端管理 |

**何時會用到：** 使用 Claude Teams 或 Enterprise 方案的組織。

### 第 3 層：Local Project Settings（個人專案級）

| 項目 | 說明 |
|------|------|
| 路徑 | `<專案根目錄>/.claude/settings.local.json` |
| 誰設定 | 開發者個人 |
| 用途 | 個人對特定專案的偏好，例如臨時開放某些測試用的命令 |
| Git 共享 | **否，應加入 .gitignore** |

**何時會用到：** 你想對某個專案有個人化設定，但不影響團隊其他人。

### 第 4 層：Shared Project Settings（團隊專案級）

| 項目 | 說明 |
|------|------|
| 路徑 | `<專案根目錄>/.claude/settings.json` |
| 誰設定 | 團隊共同維護 |
| 用途 | 專案的標準權限規則，所有人 pull 下來就自動套用 |
| Git 共享 | **是，提交到 git** |

**何時會用到：** 團隊希望統一某個專案的 Claude Code 行為。例如這個專案需要 `uvicorn` 自動允許，就寫在這裡。

### 第 5 層：User Settings（全域）

| 項目 | 說明 |
|------|------|
| 路徑 | `~/.claude/settings.json` |
| 誰設定 | 開發者個人 |
| 用途 | 所有專案通用的設定，如啟用的 plugins |
| Git 共享 | 否 |

**何時會用到：** 你希望所有專案都套用某些預設行為。

---

## 實際搭配建議

### 個人開發者

```
~/.claude/settings.json          ← 放你的 allow/deny（本 repo 提供的設定）
```

只需要一層，用本 repo 的 `settings.local.json` 複製過去即可。

### 小團隊（2-10 人）

```
~/.claude/settings.json          ← 個人全域偏好
<專案>/.claude/settings.json     ← 團隊共享規則（git 追蹤）
```

把本 repo 的設定拆成兩份：
- 通用 allow/deny → `~/.claude/settings.json`
- 專案特有的 → `<專案>/.claude/settings.json`

### 企業團隊

```
managed-settings.json            ← IT 強制的安全底線
Server-managed                   ← 組織級政策
<專案>/.claude/settings.json     ← 團隊共享
.claude/settings.local.json      ← 個人微調
~/.claude/settings.json          ← 個人全域
```

---

## settings.json vs settings.local.json 差異

| 面向 | `settings.json` | `settings.local.json` |
|------|-----------------|----------------------|
| 用途 | 共享的團隊設定 | 個人的本地覆寫 |
| Git | 提交 | 不提交 |
| 存在層級 | User 級、Project 級、Managed 級 | **僅 Project 級** |
| 優先級 | 較低 | 覆寫同層級的 `settings.json` |
| 典型內容 | 團隊標準 allow/deny | 個人測試用的臨時規則 |

---

## allow/deny 的合併邏輯

各層級的 allow 和 deny 是**合併（concatenate + deduplicate）**而非替換：

```
最終 allow = Managed allow + Server allow + Local Project allow + Shared Project allow + User allow
最終 deny  = Managed deny  + Server deny  + Local Project deny  + Shared Project deny  + User deny
```

**但如果某個工具同時出現在 allow 和 deny 中，deny 永遠勝出。**

### 範例

User settings（`~/.claude/settings.json`）:
```json
{ "permissions": { "allow": ["Bash(curl *)"] } }
```

Project settings（`.claude/settings.json`）:
```json
{ "permissions": { "deny": ["Bash(curl *)"] } }
```

結果：`Bash(curl *)` 被 **deny**，因為 deny 永遠勝出。

---

## 本 Repo 的定位

本 repo 維護的 `settings.local.json` 設計為複製到 `~/.claude/settings.json`（第 5 層，全域 User Settings）使用。

它提供一套經過實測的 allow/deny 基礎規則，讓你：
- 不用從零開始摸索哪些命令需要 allow
- 有一個安全的 deny 底線
- 透過 PR 持續累積團隊的踩坑經驗

各專案可以在自己的 `.claude/settings.json`（第 4 層）追加專案特有的規則，與本 repo 的全域設定互補。

---

## 常見問題

### Q: 我設了 `Bash(*)` 為什麼還會被問？

因為 Claude Code 有**內建的安全檢查**，與 settings 無關：
- Brace expansion `{}`
- Compound `cd && git` 命令（防 bare repository attack）
- 首次存取某個專案目錄

詳見 [README.md](README.md#實戰案例為什麼需要明確列出每個模式) 中的實戰案例。

### Q: 我可以用低層級覆寫高層級的 deny 嗎？

不行。如果 Managed Settings deny 了某個工具，其他任何層級都無法 allow 它。

### Q: settings.local.json 只能放在專案目錄？

是的，`settings.local.json` 只存在於 Project 級（`.claude/settings.local.json`）。全域級只有 `settings.json`，沒有 local 變體。

### Q: 修改設定後要怎麼生效？

**必須重新開啟 Claude Code session。** 設定在啟動時載入，修改後不會即時生效。
