# iOS 雲端群組載入 — 2026-09-08

## 範圍與結果

- 分支：`feature/attachments-widget`。沒有切換／合併 main、commit、push、Firebase 部署或建立正式測試資料。
- 保留既有版面、黃黑米白風格與 `@Observable AppStore`。新增同步錯誤／重試提示與群組列表下拉重新整理，沒有重新設計 UI。
- Firebase 正式介接維持 `group-bomb`；Callable region 維持 `asia-east1`。本階段沒有修改 plist、Firebase Rules、Functions 或 Xcode target 設定。
- 本階段測試：**18 通過、0 失敗**。Xcode iOS Simulator **Debug／Release build 均成功**。
- 沒有執行正式雙帳號 App E2E；建置與離線測試不能當成正式資料格式及跨手機操作已驗收。

## UID 與 UI UUID

- `Member.firebaseUID` 保留完整 Firebase UID。Firestore `members/{uid}` 文件 ID 必須和 `userID` 相同。
- `FirebaseMemberIdentity.uiID(for:)` 從 UID 與固定 namespace 計算穩定 UI UUID；同一 UID 在不同裝置／群組對應同一 UI ID。
- `AppStore.currentUserID` 現在由登入 UID 映射，不再使用初始化的 Mock 使用者。未登入時的全零 UUID 只是非授權 UI 佔位值，不能送到後端。
- 群組角色存在 `Group.memberRoles`，避免同一使用者在不同群組的 leader／member 角色互相覆蓋。群組詳細頁使用該群組的角色。
- 群組與任務文件 ID 必須可解析為 UUID；另外保存原始 document ID，避免大小寫轉換讀到不同路徑。既有附件 Security Rules 限制小寫路徑，因此建立正式 group/task 時仍應採用小寫 UUID 字串。

## 資料流程

1. `AuthSessionStore` 發布新 UID 前，同步呼叫 `AppStore.changeCloudAccount(to:)` 清除舊資料。
2. App 根畫面在前景時啟動 `GroupRepository.load()`。
3. `listMyGroups` 只取得可存取群組摘要，不負責下載 members/tasks。
4. `FirebaseGroupDataSource` 對每個群組從 server 讀取 `members`、`tasks`，以 Firestore Codable 解碼。
5. Repository 驗證文件 ID、UID、成員與任務關係，回傳同一批 group/member/task；不存在的 owner 不會用 Mock UUID 補上。
6. `AppStore` 一次更新既有 `groups`、`members`、`projectTasks` 單一資料來源。群組頁與我的任務仍讀取這份 `projectTasks`。
7. tasks 載入完成後才註冊附件 listeners；空 task collection 保持空，不產生假任務。

### Firestore 文件欄位約定

`members/{Firebase UID}`：

- 必填：`userID`（與文件 ID 相同）、`role`（member／leader）、`joinedAt`（Firestore Timestamp）。
- 選填：`displayName`、`avatarSymbol`。沒有名稱時顯示「組員」，不冒用 Mock 人名。

`tasks/{有效 UUID}`：

- 必填：`title`。
- 選填：`groupID`（如有，須等於實際群組文件 ID）、`detail`、正整數 `weight`、`ownerMemberID`、`createdByMemberID`、`subtasks`、`deadline`、`createdAt`、`status`。
- 雲端 `ownerMemberID`／`createdByMemberID` 是 **Firebase UID**；Repository 才將它們映射成 UI UUID。不存在的成員對應會回報格式錯誤，不猜測本機身分。
- `subtasks` 是 Codable 陣列，每項包含 UUID `id`、`title`、`isComplete`、正整數 `weight`。
- 沒有 subtasks 時為空；沒有 owner 時未認領；沒有任務 deadline 時使用群組期限。缺少 group deadline 時保留無已知期限語意，不捏造「七天後」。
- 舊正式資料若缺少 member 必填欄位、使用 Mock owner UUID 或不合法 task ID，需要後續由可信任後端補齊；本階段沒有修改正式資料。

## 登入／登出／切換帳號

- 帳號變更時先取消載入、移除所有附件 listener，並更換 generation。
- 清除 AppStore 中的群組、成員、任務、附件集合、錯誤、聊天時間軸、互評、分析及個人顯示快取，並清空 Widget snapshot。
- 再綁定新 Firebase UID，依前景狀態重新載入。
- 每個 await 後確認 UID 與取消狀態；AppStore 回寫時額外確認 generation。舊請求即使稍後回來，也不能回寫新帳號。
- AppRootView 的 authenticated subtree 以 UID 作為 identity；UID 不匹配不呈現舊內容，帳號切換也重置舊導航／sheet。
- 不使用 Firestore 舊磁碟快取作為新帳號的群組載入或授權來源：members/tasks 強制 server read，附件忽略初始 cache snapshot，等待 server 確認。不呼叫全域 Firestore terminate/clearPersistence，以免破壞既有聊天室連線；清除的是 AppStore／Widget 的帳號資料，並非宣稱抹除 SDK 的所有磁碟快取。

## 邀請碼成功與更新失敗分離

- `GroupJoinRepository.join()` 只執行加入 Callable，不再將後续列表讀取放進同一個會拋出加入失敗的操作。
- 回傳成功後立即插入可信任摘要、關閉加入視窗，再重新載入完整資料。
- 重新載入失败顯示「已加入…，但列表更新失敗，請下拉重新整理」，不誤導為加入失敗；此路徑不另外彈出競爭的通用錯誤視窗。
- 回傳結果仍核對發出操作時的 Firebase UID，不能將 A 的加入結果塞給 B。

## 附件 Snapshot Listener

- 每個已載入雲端任務最多一個 listener，集中由 AppStore 管理，兩個任務頁不再各自啟動。
- 保存完整集合於 `attachmentsByTaskID`，包含非 ready 狀態；既有 UI 的單一 deliverable 是集合中最新 ready 附件的投影。
- 每次快照完整替換集合；刪除後剩餘集合／空集合都同步回寫，沒有「只有新增、不清空」問題。同一附件的標題更新也會反映。
- 驗證附件屬於正確 group/task；權限、解碼與網路錯誤透過 `attachmentErrors`／同步提示回報，不靜默吞掉；錯誤時清除該任務的舊成果。
- 開啟 metadata updates；忽略初始磁碟快取，收到 server snapshot 後若退回 cache 則回報連線問題。[Firebase SnapshotMetadata 說明](https://firebase.google.com/docs/reference/swift/firebasefirestore/api/reference/Classes/SnapshotMetadata)
- 登出、換帳號、重新載入前、App 進背景或根畫面消失時解除。回前景重新載入後重建；根畫面仍存在時跨群組／我的任務頁保留共用監聽。
- 上傳 Sheet 必須使用已載入 task 的正式 document path，不允許拿本機／Mock task ID 代替雲端任務。

## Debug Mock

原展示資料保留在 `#if DEBUG` 中，僅顯式使用 `AppStore(debugDemo: true)` 才建立。正式 App 的 `AppStore()` 從空資料啟動，Debug 正常登入流程也不自動混入 Mock；Release 不編譯 Mock 初始資料。這次没有將舊建立群組／發布任務的本機編輯功能改造成雲端寫入，亦不把它們當成已同步的雲端資料。

## 驗證

離線測試直接編譯正式 Model／Repository 原始檔，使用注入 read closures，不啟動 Firebase 或建立正式帳號。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --scratch-path /private/tmp/group-bomb-cloud-tests
```

18 項涵蓋：稳定 UID、members/tasks 映射、Mock owner 拒絕、member 文件 ID 不符、非法 task ID、Codable、可存取群組讀取順序、未登入不讀取、帳號切換丟棄舊請求、網路失敗、空列表、完整附件集合／更新／刪除、跨任務附件拒絕、分組角色、原始 ID 大小寫、重複群組、空列表期間帳號變更與取消載入。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project group.xcodeproj -scheme group -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/group-bomb-cloud-build CODE_SIGNING_ALLOWED=NO build
```

Debug 與同指令改為 `-configuration Release` 均為 **BUILD SUCCEEDED**。`git diff --check` 通過。沒有對正式 App 操作登入／上傳來宣稱 E2E 成功；Firestore adapter、Auth 畫面切換和實際斷線行為仍需後續雙帳號驗收。

## 本次新增檔案

- `group/Models/CloudGroupData.swift`
- `group/Models/CloudAttachmentCollection.swift`
- `group/Shared/Services/GroupRepository.swift`
- `group/Shared/Services/FirebaseGroupDataSource.swift`
- `Package.swift`
- `ios-cloud-tests/GroupRepositoryTests.swift`
- 本紀錄 `IOS_CLOUD_GROUP_LOADING.md`

## 本次修改檔案

- `group/Models/Member.swift`
- `group/Models/Group.swift`
- `group/Models/ProjectTask.swift`
- `group/Models/Subtask.swift`
- `group/Shared/Services/GroupJoinRepository.swift`（開始時已是未追蹤檔，保留其加入與錯誤處理）
- `group/Shared/Services/AttachmentRepository.swift`
- `group/Store/AppStore.swift`
- `group/Store/AuthSessionStore.swift`
- `group/App/AppRootView.swift`
- `group/Features/Groups/GroupListView.swift`
- `group/Features/Groups/GroupDetail/GroupDetailView.swift`
- `group/Features/Groups/GroupDetail/DeliverableSubmissionSheet.swift`
- `group/Features/MyTasks/MyTasksView.swift`

開始前已有的其他 dirty files 保留不覆蓋；沒有重新寫入既有 Rules／Functions／Firebase 設定。新 Swift 檔案由既有 Xcode synchronized group 收入主 App target，不更改 Widget target。
