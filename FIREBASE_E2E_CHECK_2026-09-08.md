# Firebase 雙帳號 E2E 前置檢查與測試報告

日期：2026-09-08（Asia/Taipei）

## 結論

**正式雙帳號端對端測試尚未執行，不能宣告通過。** 前置檢查發現正式 Firestore Rules 與本機版本不同，存在 Client 可自行建立 member 的安全問題，且缺少群組查詢部署、雲端任務載入、附件下載及完整刪除流程。

為避免在尚未符合安全要求的正式環境建立資料，本次停止正式資料建立與登入操作。沒有建立測試群組、任務、邀請碼或 A/B 的 member 文件；沒有以管理員身分代替 B 加入，也沒有以管理員下載當作成員權限測試。

已完成的工作是正式環境唯讀檢查、App 程式碼檢查、本機 Emulator 測試和 Xcode build。Emulator 結果與正式 App E2E 結果分開記錄。

## 分支與正式環境

| 項目 | 核對結果 |
|---|---|
| Git 分支 | `feature/attachments-widget`，開始及結束均相同 |
| Firebase Project | `group-bomb`，顯示名稱 `OopsBomb` |
| `joinGroupByInviteCode` | 已部署，`asia-east1`，Node.js 22，狀態 `ACTIVE` |
| `listMyGroups` | 在 App 呼叫的 `asia-east1` 區域未部署 |
| Firestore | `(default)`，`asia-east1`，沒有變更地區 |
| Firestore Rules | 已部署，但與本機最新版不一致；正式版本更新時間 `2026-09-08T08:30:43.745625Z` |
| Storage bucket | 已建立：`group-bomb.firebasestorage.app`，`ASIA-EAST1` |
| Storage Rules | 已部署且與本機完全一致；更新時間 `2026-09-08T10:10:46.313381Z` |
| `members.userID` 查詢索引 | 正式環境只有 COLLECTION 索引；缺少 `listMyGroups` 需要的 COLLECTION_GROUP ASCENDING 索引 |
| App plist | `PROJECT_ID=group-bomb`、`BUNDLE_ID=con.sylvia.group`、`STORAGE_BUCKET=group-bomb.firebasestorage.app` |

帳號 A、B 已由使用者指定，並用 Firebase 管理 API 僅查詢 Email、UID、停用狀態，確認兩者存在且未停用。這不代表已在 App 登入。帳號密碼沒有被要求提供、輸入或寫入任何檔案。帳號 C 尚未選定或登入。

## Emulator 與 build 結果

全部 Emulator 使用本機 `demo-group-bomb`，沒有連線正式資料庫執行測試寫入。

| 測試對象 | 通過 | 失敗 | 說明 |
|---|---:|---:|---|
| 本機最新版 Firestore Rules | 16 | 0 | 含本次新增的完整合法 member 自建繞過回歸案例 |
| 本機 Storage Rules | 10 | 0 | 與正式 Storage Rules 一致 |
| 本機 Functions | 8 | 0 | Emulator 載入 `joinGroupByInviteCode` 和 `listMyGroups` |
| 本機完整測試合計 | 34 | 0 | 指令退出碼 0 |
| 正式 Firestore Rules 的唯讀快照，載入本機 Emulator | 8 | 8 | 同一組 16 項 Firestore 測試，退出碼 1 |
| Xcode iOS Simulator build | 成功 | — | `xcodebuild` 退出碼 0；沒有執行 XCTest 或正式 App E2E |

Functions 的既有 Emulator 測試使用 Emulator 內的匿名測試身分；它能驗證 Callable 對 `request.auth.uid` 的處理，但不能代替正式 Email/Password 登入及 iOS UI 測試，也沒有在正式專案啟用匿名登入。

正式規則快照失敗的 8 組測試：

1. 不存在的 taskID 不可建立附件。
2. 偽造 createdAt 或非 ready 初始狀態不可建立。
3. 零位元、超過 20 MB 或不支援 MIME 不可建立。
4. 非 HTTPS URL、錯誤副檔名或不安全路徑不可建立。
5. 標題、說明、原始檔名與 URL 長度均有限制。
6. 原上傳者只能更新 title、detail 與 status。
7. leader 可以刪除其他成員的附件。
8. 非成員不可用完整合法資料替自己建立 member 繞過邀請碼。

複合測試會在第一個失敗斷言停止；上述結果不代表一組內的所有非法條件都被接受。例如正式規則仍有 createdAt 的 request.time 檢查，不能把該組失敗解釋成已成功偽造伺服器時間。

## 主要阻塞與建議處理

### 1. 正式 member 建立存在繞過邀請碼的路徑

正式規則允許已登入者對 `groups/{任意groupID}/members/{自己的UID}` 建立含 `userID`、`displayName`、`role: member`、`joinedAt: serverTimestamp()` 的文件。沒有要求邀請碼，也沒有可信任後端批准。

新增回歸測試用完整符合正式 schema 的資料證實：這種寫入在正式規則快照下成功，本機最新版規則則拒絕。Storage 雖然檢查 Firestore 成員資格，但若成員文件能自建，其存取保護也可能被間接繞過。

建議先整合正式規則中的聊天室 `messages`、`presence` 功能與本機最新版附件限制，並讓 member 建立與角色變更只由可信任後端處理。**不能直接用本機整份規則覆蓋正式版本，否則可能破壞現有聊天室。** 本次沒有部署任何規則，也未嘗試在正式環境重現繞過。

### 2. 加入成功後的群組更新缺少正式依賴

`group/Shared/Services/GroupJoinRepository.swift:68` 在 Callable 加入成功後繼續呼叫 `listMyGroups`；第 89 行呼叫的該 Function 未在 `asia-east1` 部署。即使後端成功建立 B 的 member，整個 App 加入流程仍會因後续群組讀取失敗而回報失敗，不執行列表合併與關閉視窗。

`listMyGroups` 所用 `members.userID` collection-group 查詢索引也未正式建立。本機 `firestore.indexes.json` 已有設定，但 Emulator 通過不代表正式索引已部署。

建議經授權後部署 `listMyGroups` 與必要索引，等待索引 READY；同時分開處理「已加入」與「重新讀取群組失敗」的狀態，避免讓使用者誤認加入未成功。

### 3. 正式群組和任務尚未完整接進畫面

`group/Store/AppStore.swift:651` 只合併群組摘要，新群組的 `memberIDs`、`taskIDs` 仍是空陣列；沒有讀取 Firestore tasks 並合併進 `projectTasks`。`group/App/AppRootView.swift:22` 只啟動 Auth session，登入後也沒有讀取可存取的群組。

因此即使在 Console 建立全新群組與任務，A 登入後不能可靠地看到它，B 新加入後也沒有該雲端任務可開啟上傳。不能用硬塞 Mock UUID 的方式宣稱跨手機同步成功。

建議在 Auth UID 切換時重新載入有權限的群組，並透過 Repository 載入群組成員和任務，接入既有 AppStore 單一資料來源。需要清理舊帳號的 listener 和快取狀態。

### 4. App 尚未提供真正的雲端附件下載

`group/Features/Groups/GroupDetail/MemberProgressCard.swift:414` 僅能預覽本機快取照片；沒有快取時只顯示圖示和檔名。現有 Firebase Storage 呼叫只有上傳與失敗清理，沒有供 A 下載的 SDK 流程。

建議新增受 Firebase Auth／Storage Rules 保護的 SDK 下載與本機預覽，不使用永久 download token URL。需驗證下載內容與 B 上傳內容相符，而非只看到附件名稱。

### 5. leader 刪除目前有 Client 與 Rules 雙重阻塞

`group/Shared/Services/AttachmentRepository.swift:119` 呼叫 `validateCurrentUser(as: uploaderID)`；第 147 行要求登入者等於上傳者，會在送出 Firestore 請求前擋住 leader。正式 Firestore Rules 也只允許 uploader 刪除 attachment metadata，與 Storage Rules 的 leader 權限不同。

目前 Repository.delete 只刪 Firestore 文件，沒有正常刪除 Storage object 的協調流程，UI 也未提供完整雲端刪除入口。不能透過把 uploaderID 改成 leader UID 來避開此限制。

建議新增統一刪除服務，確認登入但不要把 uploader 相等作為 leader 的先決條件；最終授權由群組角色 Rules 決定。處理 Storage／Firestore 任一步失敗與重試，不得把部分刪除宣告成功。Storage 與 Firestore 不是單一原子交易，必須明確規劃部分失敗狀態。

### 6. Snapshot Listener 尚不足以證明跨手機完整成果同步

`group/Store/AppStore.swift:741` 只為已在本機 `projectTasks` 裡的任務註冊附件 listener；新雲端任務缺失時不會註冊。第 763 行只取最新 ready 附件，而且清單變空時直接 return，不會清掉已刪除成果。listener 的錯誤目前也被忽略。

建議在任務載入後綁定 listener，呈現需要的附件集合、處理移除和錯誤，並在帳號切換時解除舊訂閱。

## 正式端對端 23 項逐項結果

「未執行」不是「通過」，也不是聲稱已發生真機操作失敗。下列程式碼／Emulator 證據獨立於正式 E2E 結果。

| # | 使用者要求 | 正式 E2E 結果 | 已有證據／尚缺條件 |
|---|---|---|---|
| 1 | A 在裝置 A 登入 | 未執行 | 帳號存在且未停用；前置安全檢查未過，尚未請使用者手動登入 |
| 2 | B 在另一裝置 B 登入 | 未執行 | 同上；沒有代填密碼或取出使用者登入 Token |
| 3 | B 從 App 輸入邀請碼加入 | 未執行 | 正式群組與邀請碼未建立；`listMyGroups` 部署缺失 |
| 4 | 建立 B 的 member 文件 | 未執行 | 嚴格保留由 B 透過 App 加入；沒有手動建立 |
| 5 | B 文件 ID、userID 等於真實 UID | 未執行 | Functions Emulator 有對應通過案例，不能代替正式驗證 |
| 6 | B role 固定為 member | 未執行 | Callable 程式碼固定 member；正式 Rules 仍存在自建 member 問題 |
| 7 | joinedAt 是 server timestamp | 未執行 | Callable 使用 FieldValue.serverTimestamp；Emulator 有時間型別與冪等檢查 |
| 8 | 加入後列表立即更新 | 未執行／程式與部署阻塞 | 缺 `listMyGroups`、索引及登入後載入流程 |
| 9 | B 上傳照片 | 未執行 | Sheet 與 upload service 存在；新雲端任務未接進 App |
| 10 | B 上傳 PDF／Office／ZIP | 未執行 | 同上；Storage Emulator 支援格式案例通過 |
| 11 | Storage object 路徑正確 | 未執行 | 上傳服務組成指定 group/task/attachment/safeFilename 路徑，尚無正式 object 可核對 |
| 12 | metadata.uploaderID 是 B UID | 未執行 | upload service 取 Auth.currentUser.uid；沒有正式上傳結果 |
| 13 | A 不重啟即時看到成果 | 未執行／程式阻塞 | 新雲端任務未載入，listener 只訂閱現有本機任務且只保留最新成果 |
| 14 | A 用 Storage SDK 下載 | 未執行／程式阻塞 | 缺少雲端下載服務及 UI 入口 |
| 15 | 不用永久 download token URL 繞過 | 未執行；靜態檢查未見使用 | 未找到 getDownloadURL／downloadURL 下載流程；不代表授權下載已完成 |
| 16 | 非成員 C 不可讀取、下載、上傳 | 未執行；安全前提失敗 | Storage 及本機 Firestore 非成員拒絕測試通過，但正式 member 可自建使保護可能被绕過 |
| 17 | B 刪除自己的檔案 | 未執行／程式阻塞 | Storage 規則測試通過；App 尚無完整 Storage＋metadata 刪除流程 |
| 18 | leader A 刪除 B 檔案 | 未執行／程式與正式 Rules 阻塞 | Client uploader 相等檢查會擋住；正式 Firestore leader 刪除測試失敗 |
| 19 | member 不可刪除他人檔案 | 未執行 | Storage／Firestore 本機規則對應案例通過 |
| 20 | 超過 20 MB 拒絕 | 未執行 | 本機 Storage 規則測試通過；尚未做正式 App／SDK 嘗試 |
| 21 | 不支援格式拒絕 | 未執行 | 本機 Storage 對應案例通過；正式 Firestore MIME 限制未與本機一致 |
| 22 | MIME 與副檔名不符拒絕 | 未執行 | 本機 Storage 對應案例通過；正式 Firestore 檔名/MIME 規則較寬鬆 |
| 23 | metadata 寫入失敗清理孤立檔案 | 未執行 | AttachmentUploadService 第 77–87 行有清理邏輯，但本次沒有故障注入測試，不能宣告清理成功 |

## 本次新增與修改

本次沒有修改 App、Functions、正式 Rules 或 Firebase 設定；也沒有部署、commit、push、切換或合併分支。

1. 修改 `firebase-rules-tests/firestore.rules.test.mjs`（工作開始前已是未追蹤檔）：新增合法 member 自建繞過案例，並加入只供本機測試的 `FIRESTORE_RULES_FILE` 規則快照路徑覆寫。測試 Project ID 仍固定 `demo-group-bomb`。
2. 新增本報告 `FIREBASE_E2E_CHECK_2026-09-08.md`。

所有原有未提交成果均保留。開始時的 Git 狀態如下：

```text
 M .gitignore
 M firebase-rules-tests/package.json
 M firebase.json
 M firestore.indexes.json
 M firestore.rules
 M group.xcodeproj/project.pbxproj
 M group/App/GroupBombApp.swift
 M group/Features/Groups/GroupListView.swift
 M group/Store/AppStore.swift
 M group/group.entitlements
?? .firebaserc
?? firebase-rules-tests/firestore.rules.test.mjs
?? firebase-rules-tests/join-group.test.mjs
?? functions/
?? group/Shared/Services/GroupJoinRepository.swift
```

`functions/` 的專案檔為 `index.js`、`package.json`、`package-lock.json`。本次沒有改動它們。測試生成的忽略日誌不提交；唯讀查詢輔助腳本與正式規則快照只在暫存目錄使用。

## 下一步需要授權的修正

1. 與聊天室負責人確認正式 Rules 來源；整合保留 messages/presence，封住 member 自建入口，補齊附件 immutable/MIME/path/leader 等限制，加上聊天室回歸測試。
2. 測試成功後，只部署經確認的 Firestore Rules、`listMyGroups` 和必要索引，不動其他服務；不能在尚未整合聊天室前直接部署本機 Rules。
3. 補齊登入後群組／任務／成員載入、真實 UID 與既有 UI 模型的對應、SDK 下載與安全刪除，以及 listener 的刪除同步與帳號生命週期。
4. 重新 build／測試後，才建立最小正式測試資料：A leader、B 不預建 member，再請使用者在兩台裝置各自手動登入。
5. 執行並記錄上述 23 項正式 E2E，包括第三個非成員帳號與孤立檔案故障注入。

本次沒有完成正式 E2E，也沒有推送任何分支。
