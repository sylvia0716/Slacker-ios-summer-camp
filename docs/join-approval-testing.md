# 入群申請與組長審核

正式模式由 `requestGroupJoin` 建立待審核申請；只有當下組長可用
`decideGroupJoinRequest` 核准或拒絕。核准和建立成員在同一 Firestore
transaction 中完成。一般組員沒有同意權。

`groupJoinRequests` 是後端管理的集合，沿用 Firestore 預設拒絕規則，
客戶端不能直接讀寫。`listGroupJoinRequests` 只回傳自己的申請，或組長所管理
群組的申請；互評摘要僅回傳給組長，不含原始互評或評分者身份。

申請人的「我的群組」會顯示申請中、已核准、未通過或已失效。
畫面在前景時每十秒更新，重新開啟也會讀取雲端結果。這是 App 內狀態通知，
沒有背景推播。組長在進行中的群組頁面看到待審核列表。

重複送出保留同一申請；拒絕後須確認重新申請。每次重新申請都有新版本，
舊畫面不能處理新的申請。兩個裝置同時處理只會採用第一個成功的決定。
群組截止、結算、刪除或邀請码失效時，待審核申請會在讀取或審核時標為失效。
組長更換後只有新組長可以處理。沒有組長時需先透過既有選舉流程產生組長。

## 上線

需要部署以下四個 functions 後，新版 App 才能使用正式審核：

```sh
firebase deploy --project group-bomb --only functions:requestGroupJoin,functions:listGroupJoinRequests,functions:decideGroupJoinRequest,functions:joinGroupByInviteCode
```

舊 `joinGroupByInviteCode` 只允許既有成員查詢，不再直接增加成員。
請協調測試者更新 App；舊 App 的新成員加入會收到需更新的錯誤。
Firestore 規則不需變更。部署後既有成員不受影響。

## 雙帳號驗收

兩個模擬器都安裝同一新版 App，關閉測試模式，登入不同帳號。

1. A 建立尚未截止的群組，取得六位邀請碼。
2. B 輸入邀請碼。確認 B 顯示「申請中」，尚不能讀取群組內容。
3. A 進群組，於「入群審核」查看 B。沒有歷史互評時顯示「尚無互評資料」。
4. A 拒絕。B 的「我的群組」十秒內顯示「申請未通過，未加入群組」。
5. B 再輸入同一代碼，確認重新申請；A 核准。B 顯示已核准並載入群組。
6. B 現在是一般成員，不能看到組長的審核清單或審核第三人的申請。
7. 用另一個測試群組重測待審核時結算、換組長、重複點擊和關閉重開 App。

## 自動驗證

整合測試需 Java 21 以上、Firebase CLI，以及 `firebase-rules-tests` 的測試依賴
（首次執行 `npm ci --prefix firebase-rules-tests`）。

```sh
node --test functions/*.test.js functions/*.test.cjs
firebase emulators:exec --project demo-group-bomb --only auth,firestore,functions \
  'node --test --test-concurrency=1 firebase-rules-tests/join-group.test.mjs firebase-rules-tests/join-approval.test.mjs'
```

整合測試使用本機 Auth、Firestore 和 Functions emulator，不寫入正式專案。
