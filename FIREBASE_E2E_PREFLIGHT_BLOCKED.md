# 正式雙帳號 E2E 前置檢查：尚未開始

日期：2026-09-08。分支 `feature/attachments-widget`；正式專案只唯讀查核 `group-bomb`。

## 阻塞

1. 目前 Debug Xcode build 失敗：`group/Shared/Services/FirebaseAttachmentOperations.swift:17` 的 `FirestoreErrorCode(rawValue:)` 不符合目前 SDK 型別，產生 extraneous argument label／Int 型別轉換錯誤。
2. 前一輪下載／刪除 Service 實作尚未完成測試；目前 `Package.swift` 沒有收錄這些 Service，也沒有其獨立測試。既有 Emulator 64 項通過不代表這一階段已完成。
3. 依使用者叫停 UI 的要求，本輪沒有補上 App 的下載／刪除／預覽／重試接線。目前 App 畫面沒有呼叫新服務，不能宣稱在 App 內完成正式下載／刪除驗收。

因此不建立正式測試群組、task、邀請碼或 member，也沒有要求使用者輸入密碼。本輪沒有修正程式或擅自修改 UI，先回報前提未成立。

## 後端唯讀查核

| 項目 | 本次結果 |
|---|---|
| joinGroupByInviteCode | ACTIVE，asia-east1，更新時間 2026-09-08T08:22:46.653010052Z |
| listMyGroups | ACTIVE，asia-east1，更新時間 2026-09-08T11:01:53.128137638Z |
| members.userID COLLECTION_GROUP ASCENDING | READY |
| Firestore Rules | 已部署；正式內容與本機逐字一致，ruleset 4fbbe73b-36b6-4fd4-95fe-b1460330ee17 |
| Storage Rules | 已部署；正式內容與本機逐字一致，ruleset bd1ca69c-47ec-4b37-b1e5-a87833be13e8 |
| Storage bucket | group-bomb.firebasestorage.app，ASIA-EAST1 |
| Authentication App Check | API 明確回傳 UNENFORCED |
| Firestore／Storage App Check | GET 成功但僅回傳 service name，未回傳 enforcementMode；不能把缺少欄位當成已明確核實關閉，後續需 Console／完整設定查核 |

本輪未修改任何 App Check 設定。Callable 是否強制 App Check 仍需在正式驗收時核對；不能用尚未進行的請求結果推斷。

## 本機驗證（不是正式 E2E）

- Firestore Emulator：43 通過、0 失敗。
- Storage Emulator：10 通過、0 失敗。
- Functions Emulator：11 通過、0 失敗。
- 合計：64 通過、0 失敗；專案 `demo-group-bomb`，退出碼 0。
- Xcode Debug build：BUILD FAILED，退出碼 65；原因如上。

## 23 項正式測試逐項狀態

「未執行」不是成功，也不是已觀察到功能失敗；共同原因是前置 build／服務驗證／App 接線尚未齊備。

| # | 正式測試 | 結果 |
|---|---|---|
| 1 | A 登入並看到測試群組／任務 | 未執行 |
| 2 | B 在另一裝置登入 | 未執行 |
| 3 | B 從 App 輸入邀請碼加入 | 未執行 |
| 4 | B member 文件 ID／userID 等於 Firebase UID | 未執行 |
| 5 | B role 為 member | 未執行 |
| 6 | B 立即看到群組／任務 | 未執行 |
| 7 | B 上傳照片 | 未執行 |
| 8 | B 上傳 PDF | 未執行 |
| 9 | B 上傳 Office／ZIP | 未執行 |
| 10 | A 不重啟即可看到附件 | 未執行 |
| 11 | A 透過 Storage SDK 下載並核對內容 | 未執行；App 尚未接下載服務 |
| 12 | 非成員 C 不可讀取／下載／上傳 | 未執行；不能以 Emulator 結果替代 |
| 13 | B 刪除自己的附件 | 未執行；App 尚未接刪除服務 |
| 14 | A leader 刪除 B 附件 | 未執行 |
| 15 | 普通 member 不可刪除別人附件 | 未執行 |
| 16 | 超過 20 MB 拒絕 | 未執行 |
| 17 | 不支援格式拒絕 | 未執行 |
| 18 | MIME／副檔名不符拒絕 | 未執行 |
| 19 | 上傳部分失敗清理孤立檔案 | 未執行；未對正式環境注入故障 |
| 20 | 刪除部分失敗安全重試 | 未執行；Service 測試／App 接線尚未完成 |
| 21 | 登出／換帳號無舊資料 | 未執行正式裝置驗收 |
| 22 | messages／presence 正常 | 未執行正式裝置驗收 |
| 23 | App Check enforcement 維持關閉 | 未變更設定；Auth 明確 UNENFORCED，Firestore／Storage 尚待完整確認 |

## 正式測試識別值

- groupID：未建立。
- taskID：未建立。
- 邀請碼：未建立。
- B member：未預先建立。

## 修改與待人工確認

- 本轮只新增本檢查報告，未修改 App、UI、Rules 或 Functions。前一輪未提交的 Service 與其他既有修改均保留。
- 已執行 git status，仍在 feature/attachments-widget；沒有 commit、push、切換／合併 main 或部署。
- 下一步先修正附件錯誤碼轉換、完成 Service 測試並重新 build。UI 接線仍需遵守使用者不改 UI 的限制，與同學協調後再驗收。
- 前提齊備後才建立正式最小測試資料；A／B 登入時由使用者在装置上手動輸入密碼，不寫進程式、終端或報告。
