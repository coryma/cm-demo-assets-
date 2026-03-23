# AI Installation Playbook

這份文件是給 AI/Agent 直接讀取並執行安裝的操作手冊。

## Source of Truth

- 機器可讀安裝規格：`docs/install-plan.json`
- 安裝執行腳本：`scripts/install-by-plan.sh`
- 安裝規格驗證：`scripts/verify-install-plan.sh`

## Preflight

1. 進到 repo 根目錄。
2. 驗證 CLI 與登入狀態：
   - `sf --version`
   - `sf org display --target-org <target-org-alias>`
3. 驗證安裝規格：
   - `./scripts/verify-install-plan.sh docs/install-plan.json`

## Execution

先做 dry-run（建議）：

```bash
./scripts/install-by-plan.sh <target-org-alias> --dry-run
```

正式安裝：

```bash
./scripts/install-by-plan.sh <target-org-alias>
```

若目標 org 不是全新 org，先同步共享頁面再安裝（避免覆蓋既有客製）：

```bash
./scripts/install-by-plan.sh <target-org-alias> --sync-shared-pages
```

## Guardrails

- 禁止直接用 `sf project deploy start --source-dir force-app` 做全量部署當 baseline。
- 只能按照 `docs/install-plan.json` 的 `installOrder` 執行。
- 若任一步驟失敗，停止後回報「module id + sf error output」，不要跳過繼續。

## Functional Checks

安裝完成後至少做以下驗證：

1. `CM_Demo_Setup` 可開啟並可儲存 Demo target account。
2. Account page (`MFG_ACCOUNT_DISCRETE_ALL`) 可看到：
   - `Prepare QBR` 按鈕
   - Activity Scorecard 元件
3. Home page (`MFG_HOME_DISCRETE_MCO`) 可看到：
   - Activity Scorecard
   - Lead scoring list
4. 後台頁面可開啟：
   - `CM_Account_Role_Setup`
   - `CM_Email_Simulation`
   - `CM_QBR_Setup`

## Notes

- 目前 `qbr-preparation` 這個 feature pack 同時涵蓋：
  - QBR Meeting Preparation
  - Account Plan Enhancement（含 SWOT）
