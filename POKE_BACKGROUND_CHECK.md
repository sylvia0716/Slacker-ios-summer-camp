# 戳戳背景檢查

目前以 `BGAppRefreshTask` 申請最快 15 分鐘後執行。這不是定時器，也不是 iOS 保證的最短間隔；實際執行時間可能延後，或沒有背景執行機會。

## 行為

- 前景沿用 Firestore 即時通知；背景向伺服器查詢每個群組最新一筆戳戳。
- 每個群組彙整新增次數，透過本機通知提醒，不需要 APNs。
- 第一次收到該帳號／群組的伺服器快照時建立基準，不補發歷史通知。
- 已處理的累積次數保存在裝置 UserDefaults，依 Firebase UID、群組 ID 分開。前景與背景共用此紀錄。
- 背景只有在通知成功交給系統後才推進紀錄；離線、讀取失敗、工作逾時會保留待處理次數。
- 關閉 App 內通知開關會取消待排程工作；登出時亦取消。下次登入／回到前景／進入背景時會按目前設定重新申請。
- 查詢需要 `pokes` 的 `recipientID ASC, createdAt DESC` 索引，已加入 `firestore.indexes.json`。

## 真機驗證

1. B 安裝新版，登入、允許通知、開啟「背景 App 重新整理」，關閉低耗電模式。
2. 等待群組同步完成，建立首次通知基準，再返回主畫面或鎖屏；不要從多工畫面滑掉 App。
3. A 戳 B 數次，等待系統給予背景執行時間。15 分鐘到了沒通知，不代表程式沒有排程。
4. B 應收到各群組新增次數的通知。再回到 App，不應重新顯示同一批已通知戳戳。
5. 再戳一次，確認只計入新的次數；也測試關閉通知、登出、換帳號後不會沿用其他帳號紀錄。

在實體 iPhone 的 Xcode 除錯工作階段，可依 Apple 的 BackgroundTasks 除錯流程手動觸發已註冊的 `con.sylvia.group.poke-refresh`。手動觸發只能驗證處理流程，不能證明 iOS 自動排程頻率。

## 此次驗證

- App 編譯成功，產出的 Info.plist 包含背景 fetch 模式及允許的工作識別碼。
- 7 項本機去重／帳號隔離／重試／設定保存測試通過。
- Firebase 接收者權限測試（含降冪、只取一筆）通過。
- 已透過 serve-sim 的內建瀏覽器確認新版 App 可啟動。
- 新索引已部署並確認 READY；重新啟動後，伺服器同步已建立 2 個群組的通知基準，未再出現戳戳索引錯誤。
- 目前模擬器回報 `BGTaskScheduler is not available on this platform`，尚未驗證真機自動喚醒與背景通知送達。

Apple 文件：https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate
