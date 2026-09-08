# Firebase 後端部署紀錄 — 2026-09-08

## 範圍

- 分支：`feature/attachments-widget`。
- 唯一正式 Project ID：`group-bomb`，顯示名稱 `OopsBomb`。
- 僅部署 `listMyGroups`、Firestore 索引與合併版 Firestore Rules。
- 不切換／合併 main、不 commit、不 push。
- 不部署或修改 Storage Rules、Hosting、Analytics、Messaging；不啟用 App Check enforcement。
- 不建立正式測試帳號或測試資料，不保存帳號憑證或管理員金鑰。

## 本階段程式與測試變更

1. `functions/index.js`：補強 `listMyGroups`。除了以 `request.auth.uid` 查詢 `members.userID`，還核對 member 文件 ID 等於該 UID，而且父群組必須直接位於根層 `groups`；不接受同名欄位、其他 collection 或深層巢狀路徑冒充成員資格。
2. `firebase-rules-tests/join-group.test.mjs`：新增 3 個 `listMyGroups` 測試，涵蓋未登入、Client 指定身分、不同帳號隔離、錯誤文件 ID／路徑與不存在的群組。
3. 本紀錄。

既有未提交的 App、Authentication、附件、Rules、索引與設定修改全部保留；本階段未修改 Swift 或 UI。

## 部署前測試

全部在本機 Emulator 的 `demo-group-bomb` 執行，不使用正式資料。

| 測試 | 通過 | 失敗 |
|---|---:|---:|
| Callable Functions | 11 | 0 |
| Firestore 附件／member | 25 | 0 |
| Firestore 聊天室／presence | 18 | 0 |
| Storage 回歸（未部署 Storage） | 10 | 0 |
| 合計 | **64** | **0** |

```bash
firebase emulators:exec --project demo-group-bomb \
  --only auth,functions,firestore,storage \
  'cd firebase-rules-tests && npm run test:join && npm run test:firestore && npm run test:storage'
```

執行環境為 Node.js 22、Java 21 與既有 Firebase CLI。確認所有測試通過後才開始部署。

## Function 檢查與部署

- `functions/index.js` 正確匯出 `joinGroupByInviteCode` 與 `listMyGroups`。
- 兩者 region 都為 `asia-east1`；`GroupJoinRepository.swift` 的 Callable region 也為 `asia-east1`。
- `listMyGroups` 只使用 `request.auth.uid`，拒絕 Client 指定 userID／role／groupID；只回傳具有正確 member 文件且存在的群組。

執行的正式部署指令（未使用 `--force`）：

```bash
firebase deploy --only functions:listMyGroups --project group-bomb --non-interactive
```

`listMyGroups` 建立成功，正式 API 已確認 `ACTIVE`，runtime 為 `nodejs22`，更新時間為 `2026-09-08T11:01:53.128137638Z`。

CLI 在 Function 成功建立後，因 Artifact Registry 尚未設定容器映像清理政策而回傳 exit code 1。這不是 Emulator 測試失敗，也不是 Function 建立失敗；本次沒有擅自新增清理政策，改以正式 API 確認部署狀態。

### joinGroupByInviteCode 保持原版本

- 正式狀態：`ACTIVE`，region `asia-east1`，runtime `nodejs22`。
- 更新時間維持 `2026-09-08T08:22:46.653010052Z`，本階段未重新部署。
- 多種官方 API 讀取已部署來源壓縮檔皆回傳 HTTP 500，因此**無法完成正式來源與本機來源的逐字比對**，不能宣稱兩者完全相同。沒有因比對受阻就覆蓋正式版本。

## 索引與 Rules 狀態

依序執行：

```bash
firebase deploy --only firestore:indexes --project group-bomb --non-interactive
# 唯讀輪詢正式索引，直到 COLLECTION_GROUP ASCENDING 為 READY。
firebase deploy --only firestore:rules --project group-bomb --non-interactive
```

- 索引部署 exit code 0。正式 API 確認 `members.userID` 的 `COLLECTION_GROUP ASCENDING` 為 **READY**；原有 COLLECTION ASCENDING／DESCENDING／CONTAINS 也全部為 READY。
- 等待 READY 後才開始 Rules 部署，Rules 部署 exit code 0。
- 正式 Firestore release：`projects/group-bomb/releases/cloud.firestore`。
- 新 ruleset：`projects/group-bomb/rulesets/4fbbe73b-36b6-4fd4-95fe-b1460330ee17`。
- 正式更新時間：`2026-09-08T11:10:20.024566Z`（台灣時間 19:10:20）。
- 正式 API 讀回 Rules 內容與本機測試版**逐字一致**，SHA-256 為 `e1cddb2ef71d40b84b79778a9d9de32fa7866ccfd443cda973cf3bb008c80c46`。
- 部署後再次執行完整 Firestore Emulator 測試：**43 通過、0 失敗**。這是部署版內容比對與 Emulator 驗證，沒有對正式資料執行 Client 寫入攻擊或雙帳號 App E2E。
- 最後再次查詢兩個 Function：`listMyGroups` 與 `joinGroupByInviteCode` 皆為 ACTIVE；兩者更新時間均與前述相同。

### 聊天室與 member 權限

- 保留 `messages` 的 member 讀取／傳送、既有 botReply／botAnalysis 格式，以及 `presence` 的成員讀取、自己的狀態更新與清理權限；18 項聊天室回歸測試通過。
- Client 不能建立自己或別人的 member，不能自行設定 leader，不能修改既有 role／UID／joinedAt；包括批次 member＋attachment 繞過案例均被拒絕。
- member 建立由可信任 Callable 的 Admin SDK 執行，並不需要放寬 Client Rules。
- 保留原本只更新自己 displayName、自行離開群組與清理舊 presence 的必要權限；離開後不能自行重建 member。

### 未改動的服務

正式 Storage release 的 ruleset、更新時間 `2026-09-08T10:10:46.313381Z` 與 SHA-256 均未改變。沒有部署 Storage Rules、Hosting、Analytics 或 Messaging，也沒有啟用 App Check enforcement。

## 仍需留意

1. 原先 `joinGroupByInviteCode` 來源讀取 HTTP 500 已於使用者授權後續處理時解決，來源比對結果見下節。
2. 原先未設定的 Artifact Registry 容器映像清理政策，已於使用者授權後續處理時設為 7 天，詳見下節。
3. 新規則不會自動刪除以前建立的 member 文件；尚未稽核／清理可能透過舊規則建立的成員。
4. 本次沒有執行正式雙帳號 App E2E 或 Xcode build；本階段僅修改後端 Function 與測試，沒有修改 App UI。

所有部署與核對已完成；不 commit、不 push，停下等待使用者確認。

## 使用者授權的後續處理：来源比對與 7 天清理

- 分支再次確認為 `feature/attachments-widget`；保留全部未提交修改。
- 透過正式 Function 的來源下載 API 取得短期連結，僅在記憶體下載與解壓比對；未輸出或保存連結、Token 或來源壓縮檔。
- 本次來源下載成功。`joinGroupByInviteCode` 與其之前所有共用初始化／helper 程式碼和本機一致；`package.json`、`package-lock.json` 也逐字一致。
- 整份 `index.js` 不完全一致，差異位於 `listMyGroups` 區段；前次單獨部署 `listMyGroups` 不會更新 `joinGroupByInviteCode` 的歷史來源封存檔。沒有把整份來源不一致誤判為 join 本身不同，也沒有重新部署 Function。
- `joinGroupByInviteCode` 仍為 ACTIVE，更新時間維持 `2026-09-08T08:22:46.653010052Z`。
- 先唯讀確認 Artifact Registry 沒有既有清理政策，再使用 Firebase CLI 內建的政策設定實作套用 7 天，最後讀回確認。

```text
repository: projects/group-bomb/locations/asia-east1/repositories/gcf-artifacts
policy ID: firebase-functions-cleanup
action: DELETE
tagState: ANY
olderThan: 604800s (7 days)
cleanupPolicyDryRun: false
sevenDayPolicy: true
```

此政策會自動清理超過 7 天的部署映像，不是立刻手動清空存放區。依 Firebase 官方說明，部署構件的保留不是既有 Function 運行的必要條件：https://firebase.google.com/docs/functions/manage-functions#clean_up_deployment_artifacts

本次後續沒有重新部署 Function／Rules，沒有改動 App UI、Storage Rules 或 App Check，沒有 commit 或 push。只更新本紀錄；暫存操作工具已移除。

## 部署前正式版本識別

- Firestore 舊 ruleset：`projects/group-bomb/rulesets/bf72a533-a059-4837-bb71-31a8283833e5`。
- Firestore 舊內容 SHA-256：`6a57982ce7d5c457defaa8a0b064619c26e7ca062181d43d0f7a56aa6469a1b5`。
- 合併版 Firestore SHA-256：`e1cddb2ef71d40b84b79778a9d9de32fa7866ccfd443cda973cf3bb008c80c46`。
- Storage ruleset：`projects/group-bomb/rulesets/bd1ca69c-47ec-4b37-b1e5-a87833be13e8`。
- Storage SHA-256：`1824afa5845e592cdc4ef989b46d1c7714900b06ac4e823ff0b6045d2c3ef891`。

前階段未部署時的 Rules 差異、原正式備份與聊天室相容性紀錄保留在 `firebase-rules-tests/backups/2026-09-08/README.md`；該檔是歷史紀錄，不代表本次部署後的最新狀態。
