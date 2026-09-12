# Firestore Rules 安全整合紀錄（未部署）

## 範圍與備份來源

- 日期：2026-09-08，Asia/Taipei。
- 分支：`feature/attachments-widget`；沒有切換、合併、commit 或 push。
- 唯一正式 Firebase Project：`group-bomb`（顯示名稱 `OopsBomb`）。
- 正式環境只做 GET 查詢，沒有部署 Rules、Functions、索引或其他服务，沒有建立測試資料。
- 未修改 App UI、Swift 程式碼、Storage Rules、Functions 或 Firebase target 設定。

`production.firestore.rules` 為正式 API 回傳內容的原樣備份，已逐字核對一致。**它保留歷史漏洞，只供比較，不能當成新版本部署。**

```text
release: projects/group-bomb/releases/cloud.firestore
ruleset: projects/group-bomb/rulesets/bf72a533-a059-4837-bb71-31a8283833e5
updateTime: 2026-09-08T08:30:43.745625Z
production SHA-256: 6a57982ce7d5c457defaa8a0b064619c26e7ca062181d43d0f7a56aa6469a1b5
```

`local-before-merge.firestore.rules` 為修改前的本機附件規則備份。

```text
local-before-merge SHA-256: a645d5e8e9c50bf6be252e15c900a4cac5cba4a64ae085a5edfb77aac6953442
merged firestore.rules SHA-256: e1cddb2ef71d40b84b79778a9d9de32fa7866ccfd443cda973cf3bb008c80c46
```

合併結果在專案根目錄 `firestore.rules`。`firebase.json` 仍只指向根目錄的規則，沒有指向備份。本次沒有把任何本機檔案覆蓋到正式 Firebase。

## 主要差異與整合方式

| 項目 | 原正式 Rules | 原本機 Rules | 本次整合 |
|---|---|---|---|
| messages | 有 member 讀取／傳送與 schema 驗證 | 無，落入拒絕 | 原樣保留正式權限与驗證 |
| presence | 有自己的上線／離線更新和清理 | 無，落入拒絕 | 原樣保留正式權限与驗證 |
| Client 建立 member | 可替自己建立 member，繞過邀請碼 | 全面拒絕 member 寫入 | 全面拒絕 Client create，包括自己、他人、leader |
| member 非權限資料 | 可讀取自己、只改自己的 displayName、自己離開 | 全部寫入拒絕 | 保留上述操作；不得修改 role、userID、joinedAt 或他人文件 |
| task 存在性 | 建立附件未驗證 | 必須存在 | 保留本機驗證 |
| attachment 初始 status | 允許多種狀態 | 必須 ready | 必須 ready，符合 AttachmentUploadService 正式流程 |
| 附件欄位、MIME、路徑與長度 | 驗證較寬鬆 | 嚴格限制 | 保留本機限制 |
| 修改附件 | 可改路徑／檔案資訊等 | 只能 title、detail、status | 保留本機不可變欄位限制 |
| leader 刪除附件 metadata | 不允許 | 允許同群組 leader | 保留本機權限 |

### 聊天室相容性

- 保留 `message`、`botReply`、`botAnalysis` 既有格式、文字與分數範圍驗證。
- `senderID` 必須等於登入 UID，`createdAt` 必須等於 request.time；訊息送出後不可由 Client 更新或刪除。
- 成員可讀取訊息／presence，非成員不可讀取或傳送訊息，也不可建立或更新 presence。
- 成員只能建立或更新自己的 presence，不能偽造其他人的 userID。
- 保留離開群組後刪除自己舊 presence 的清理權限；不能因此重新建立 presence 或重新加入。
- 保留修改自己 displayName（1–60 字）與自行刪除自己 member 以離開群組。這些不是加入／升權入口；刪除後無法自行重建 member。
- `hasValidMemberShape` 已移除，因為 Client create 一律拒絕，不再需要讓 Client 滿足一個可授予身分的 schema。

### 附件安全限制

- 身分檢查先要求 request.auth 不為 null，再確認 groups/{groupID}/members/{uid} 存在。
- 未登入／非成員不能讀取群組、任務或附件。
- 建立附件必須使用自己的 uploaderID，且 task 文件存在、createdAt 等於 request.time、初始 status 為 ready。
- 僅允許指定欄位；title 1–100、detail 最多 1,000、originalFilename 1–255、HTTPS URL 最多 2,048。
- 檔案 byteSize 為正整數，最大 20 × 1024 × 1024 bytes。
- JPEG／PNG／PDF／DOCX／XLSX／PPTX／ZIP 的 kind、MIME 與安全副檔名相符。
- storagePath 必須指向同一 group/task/attachment，最後一段只能是安全檔名，不允許額外子路徑。
- 更新僅開放 title、detail、status；UID、createdAt、檔案路徑與其他檔案 metadata 不可修改。
- 同群組 uploader 或 leader 可刪除附件；普通 member 不可刪別人的附件。離開群組的 uploader 失去存取權，leader 仍可清理該群組的舊附件。
- 沒有 `allow read, write: if true`。未列出的路徑維持拒絕。

## Cloud Function / Admin SDK

已檢查 `functions/index.js`：使用 `firebase-admin/app` 與 `firebase-admin/firestore`，Callable 從 request.auth.uid 取得 UID，再用 Admin SDK transaction.create 建立固定 role: member 與 FieldValue.serverTimestamp()。

Admin SDK 的伺服器存取由 IAM 授權，不依賴 Client Security Rules。因此禁止 Client create member 不會阻止這個可信任加入流程。[Firebase 官方說明](https://firebase.google.com/docs/firestore/security/rules-conditions)

本次也以 Functions Emulator 的 8 項測試驗證 Admin 建立 member、冪等性與角色不可偽造仍正常，沒有修改 Function 程式碼。

## 測試結果

| 測試 | 通過 | 失敗 |
|---|---:|---:|
| 整合版附件／member Firestore 測試 | 25 | 0 |
| 整合版聊天室 Firestore 回歸 | 18 | 0 |
| 全部 Firestore Rules | **43** | **0** |
| 原有 Storage Rules | 10 | 0 |
| 原有 Callable Functions | 8 | 0 |
| 整合版完整 Emulator 合計 | **61** | **0** |
| 正式 Rules 備份的聊天室相容性比較 | 18 | 0 |

聊天室 18 項案例在「原正式備份」與「整合版」均通過；這不代表原正式版本的附件／member 安全問題已修正。

新增／補強案例包括完整合法 member 自建、替他人建立、建立 leader、修改既有角色、批次 member＋attachment 繞過、跨群組存取、所有支援 MIME、20 MB 邊界、不可變欄位，以及聊天室正常／拒絕操作。

執行使用 Node.js 22、Java 21、既有 Firebase CLI，所有測試指向本機 `demo-group-bomb`。不同 Firestore 測試檔以 `--test-concurrency=1` 依序執行，避免共用 Emulator 清除資料或載入規則時互相干擾。

```bash
firebase emulators:exec --project demo-group-bomb \
  --only auth,functions,firestore,storage \
  'cd firebase-rules-tests && npm run test:rules && FIRESTORE_RULES_FILE=backups/2026-09-08/production.firestore.rules node --test firestore.chat.rules.test.mjs'
```

`FIRESTORE_RULES_FILE` 只影響 Emulator 測試讀取哪份規則檔，不改變 Firebase 專案或部署目標。`git diff --check` 通過。此次只改規則與測試，沒有重新 build App，也不沿用先前 build 宣稱本階段執行過。

## 修改與保留檔案

本次修改：

- `firestore.rules`
- `firebase-rules-tests/firestore.rules.test.mjs`（原先已為未追蹤檔，保留原有案例後補強）
- `firebase-rules-tests/package.json`（讓 test:firestore 同時執行聊天室測試並序列化）

本次新增：

- `firebase-rules-tests/firestore.chat.rules.test.mjs`
- `firebase-rules-tests/backups/2026-09-08/production.firestore.rules`
- `firebase-rules-tests/backups/2026-09-08/local-before-merge.firestore.rules`
- 本紀錄 `firebase-rules-tests/backups/2026-09-08/README.md`

開始時已有的其他未提交修改均未覆蓋：

```text
 M .gitignore
 M firebase.json
 M firestore.indexes.json
 M group.xcodeproj/project.pbxproj
 M group/App/GroupBombApp.swift
 M group/Features/Groups/GroupListView.swift
 M group/Store/AppStore.swift
 M group/group.entitlements
?? .firebaserc
?? FIREBASE_E2E_CHECK_2026-09-08.md
?? firebase-rules-tests/join-group.test.mjs
?? functions/
?? group/Shared/Services/GroupJoinRepository.swift
```

## 尚未解決／不在本階段範圍

1. **正式環境尚未部署本次修正，原 member 自建漏洞仍存在於正式 Rules。** 等使用者確認後才能安排部署。
2. 規則修正不會自動刪除以前已存在的 member 文件；尚未查核或清理可能透過舊入口建立的成員。
3. 若現有聊天室 Client 曾依賴直接建立 member 來加入，該入口將刻意被拒絕；必須改用可信任 Callable。既有合法成員的訊息／presence 功能保留。
4. 為相容既有聊天室，仍允許成員以自己 UID 寫入 botReply／botAnalysis；這只驗證結構與權限，不證明内容確實出自 AI。需要更強的 AI 來源保證時另行設計後端驗證。
5. `listMyGroups`／索引部署、App 雲端任務載入、附件 SDK 下載、Client leader 刪除檢查及正式雙帳號 E2E 均未在本階段修改或執行。

下一步等待使用者確認；本紀錄不代表部署授權。
