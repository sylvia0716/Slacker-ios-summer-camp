# 入群審核

## 行為

- 邀請碼送出後建立待審核申請，核准前不建立 membership、不顯示群組內容。
- 申請頁告知組長可查看申請者的個人戰力檔案。
- 組長在「我的群組」與群組詳細頁收到即時更新的 App 內待審核訊息，可查看五項能力平均、專案紀錄，再核准或拒絕。此版本未新增背景推播。
- 沒有歷史紀錄會顯示空狀態，仍可核准。
- 申請者可查看結果；核准後自動重新載入群組。拒絕後可重新輸入邀請碼申請。
- 重複送出保留同一份待審核申請；重新申請使用新的 requestID，防止舊畫面誤審新申請。

## 資料與權限

`groups/{groupID}/joinRequests/{uid}` 為組長收件匣，只有現任組長可讀。
`users/{uid}/groupJoinRequests/{groupID}` 為申請者自己的狀態，只有本人可讀。
兩份資料只能由後端寫入，申請及審核均在交易中同步更新。

`getJoinApplicantProfile` 在交易內驗證現任組長及待審核 requestID，只回傳已發布的 `peerReviewProjects` 分數與專案摘要，不回傳原始互評、評語或評分者身分。審核結束後不再開放此 API 存取。原始個人歷史的 Firestore 規則仍只開放本人。

## 2026-09-28 驗證

- Xcode iOS 編譯成功。
- Swift Package：96 項測試通過。
- Functions 單元測試：79 項通過，包含新增的 5 項審核測試。
- Auth / Firestore / Functions 模擬器：56 項整合及規則測試通過。涵蓋跨帳號申請、核准、拒絕、重新申請、併發重複申請、非組長拒絕存取與歷史資料隔離。
- 本機測試使用 `demo-group-bomb`，未寫入正式專案。
- 本機 Java 為 17，測試工具使用暫存下載的 Firebase CLI 14.17.0。該版 CLI 對 Functions SDK 7 已移除的 `functions.config()` 呼叫不相容；僅在 `/private/tmp/group-admission-npm-cache` 的 emulator runtime 跳過此舊 helper。未更動專案相依套件或應用程式 SDK。
- 尚無可用 serve-sim 預覽環境，未完成畫面操作驗證。

## 上線

已於 2026-09-28 部署至正式 `group-bomb`（`asia-east1`）。測試者需使用新版 iOS；舊版 App 不理解待審核回傳狀態，但後端仍要求核准後才建立成員資格。

已部署的項目：

- `functions:joinGroupByInviteCode`（改為申請）
- `functions:reviewGroupJoinRequest`
- `functions:getJoinApplicantProfile`
- `firestore:rules`

不需要新的複合索引。既有成員資格保持不變。

## 正式部署驗證（2026-09-28）

- 先建立審核與戰力摘要服務、發布申請權限規則，成功後才更新邀請碼入群 API。
- 三個 Functions 都為 `ACTIVE`；各端點的未登入請求均回應 HTTP 401 / `UNAUTHENTICATED`。
- 已讀回正式規則並逐字比對預定內容，確認一致。
- 正式 ruleset：`projects/group-bomb/rulesets/bffcd751-3de3-4e4f-9376-7eb13279edca`。
- 保留正式既有議程權限條件；細節與前後規則位於 `firebase-rules-tests/backups/2026-09-28-admission/`。
- 未建立、刪除或修改正式帳號及群組資料；本次正式驗證不包含登入後雙帳號操作。畫面操作驗證仍待 serve-sim 環境。
