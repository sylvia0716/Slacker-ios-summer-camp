# Oops Bomb 密碼重設頁與信件

沿用 `group/Shared/UI/Theme.swift` 的黃／黑／奶油色、粗框卡片、硬陰影及膠囊按鈕。無建置工具、無新增套件、無密碼儲存或自建驗證後端。

## 本機檢視

```sh
node auth-web/tools/preview.js
```

用 `xcrun simctl openurl booted '<URL>'` 開啟下列本機網址，再透過 serve-sim 的 App 內瀏覽器檢視：

- `http://127.0.0.1:3210/?preview=ready`：表單
- `http://127.0.0.1:3210/?preview=success`：成功
- `http://127.0.0.1:3210/?preview=invalid`：失效
- `http://127.0.0.1:3210/email-preview`：信件

預覽限 loopback 主機且不能帶 `oobCode`；不會呼叫 Firebase。請勿在預覽中輸入真實密碼。

## 驗證

```sh
node --test auth-web/tests/*.test.js
firebase emulators:exec --only auth --project demo-group-bomb 'node --test auth-web/tests/emulator.test.js'
```

Emulator 測試會建立並清理暫存帳號，驗證：驗證碼不因讀取而消耗、密碼可更新、舊密碼失效、新密碼可登入及驗證碼不可重用。沒有 emulator 環境變數時會略過這項整合測試。

2026-09-17 驗證：7 項測試全部通過（含 Auth Emulator 整合測試）；serve-sim 中檢查表單、成功、失效及信件畫面；以無效測試碼呼叫正式驗證端點，收到預期的 `INVALID_OOB_CODE`，未修改正式帳號。尚未驗證正式寄信版型或正式密碼變更。

## 部署狀態（2026-09-17）

後續確認：使用者成功儲存寄件者名稱「Oops Bomb 雷包點點名」。再次透過 Console 同時更新雙語主旨與 HTML 內容仍遭限制，原始主旨、內容與 action URL 保留；尚未單獨測試主旨與內容哪個欄位觸發限制。

- 網站已部署至 https://group-bomb.web.app/。部署前確認 Hosting 沒有既有 release；僅部署 Hosting，未變更 Functions、Rules 或 Storage。
- 正式站的 6 個檔案均回應 HTTP 200，SHA-256 與本機檔案一致。透過 serve-sim 檢查正式英文失效連結畫面；Auth Emulator 完整測試 10/10 通過，未修改正式使用者密碼。
- **郵件範本與 action URL 尚未套用。** Admin API 回傳 `EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED`；Firebase Console 同樣顯示「這項專案目前無法更新電子郵件範本」，並要求聯絡 Firebase 支援。控制台仍顯示原始信件與 `https://group-bomb.firebaseapp.com/__/auth/action`。
- 使用者選擇中英雙語信件，待套用檔案為 `email/password-reset.bilingual.html` 與 `email/template.bilingual.json`。尚未驗證實際收信樣式，未新增 SMTP 或寄送正式測試信。
- 解除限制後的支援資料見 `deployment-support.md`。部署前設定備份保留在本機 `/private/tmp/oops-auth-config-before.json`（不納入版本控制）。

## 正式套用流程

1. 先確認 `group-bomb` Hosting 目前沒有需要保留的網站內容；部署會替換該站台的檔案。若已有網站，請整合目錄與部署設定，勿直接覆蓋。
2. 使用獨立設定 `firebase.auth-hosting.json`，只部署 Hosting，不改 Functions、Rules 或 Storage：`firebase deploy --only hosting --config firebase.auth-hosting.json --project group-bomb`。
3. 先確認部署的頁面與 Firebase API key 能正常運作，再將 Firebase Authentication 的自訂 action URL 設成 `https://group-bomb.web.app/`。
4. 將 `email/template.json` 的寄件者顯示名稱與主旨、`email/password-reset.html` 的 HTML 套入密碼重設範本。保留 `%EMAIL%`、`%LINK%`。Firebase 內建郵件的自訂能力有限，必須檢查儲存後的 HTML 與實際收信版型；不可把本機預覽當成 Gmail 實寄驗收，也不要自行增設 SMTP 服務。
5. 經使用者授權寄送測試信，確認新信導向新頁面，並由使用者自行輸入新密碼與完成變更。保留原設定以便回復。

Firebase 自訂 action URL 可能套用到所有郵件；非 `resetPassword` 動作會轉交固定的 Firebase 內建處理頁，不跟隨任意 `continueUrl`。網頁只將驗證碼與新密碼送到 Firebase 官方端點，不儲存、不記錄，也不載入外部追蹤資源。頁面不會寄送郵件；要重寄請回 App 操作。

正式網頁沒有 App deep link（目前專案尚未提供），成功畫面會請使用者回 App 登入。

參考：[Firebase 自訂郵件操作頁](https://firebase.google.com/docs/auth/custom-email-handler)、[Firebase Auth REST API](https://firebase.google.com/docs/reference/rest/auth)、[Firebase 郵件範本](https://support.google.com/firebase/answer/7000714)。

## 第一階段雙語（2026-09-17）

- iOS 登入／註冊／忘記密碼使用 `group/Resources/{en,zh-Hant}.lproj/Authentication.strings`，由 `AuthSessionStore.language` 共用語言選擇。預設依裝置語言，未支援語言使用英文。本階段不新增偏好持久化；重新啟動後依裝置語言決定。
- 中文品牌／標語為「雷包點點名／一起拆彈，一起過關。」；英文為「Oops Bomb／Defuse the chaos. Win together.」。登入後其他功能尚未納入本階段翻譯。
- Firebase 寄信前設定 `languageCode` 為 `zh-TW` 或 `en`；網頁優先使用信件 `lang`，否則依瀏覽器語言。網頁切換不重載，不清除密碼或重新驗證連結。
- 預覽網址加 `&lang=en` 或 `&lang=zh-Hant`；信件預覽使用 `/email-preview?lang=en` 或 `/email-preview?lang=zh-Hant`。
- 英文信件稿為 `email/password-reset.en.html` 與 `email/template.en.json`，中文保留原檔名。兩版品牌信件仍未部署；Firebase 內建範本可由寄信語系本地化，但自訂 HTML 的分語言套用能力須在正式設定時核對，不能直接輪流覆寫全域範本來處理不同使用者。
- 本階段：iOS 編譯成功，中英文登入頁、英文網頁與英文信件於 serve-sim 檢視；9 項 Node 測試通過（包含保留表單值的語言切換、完整英文翻譯與語言優先次序），本輪未啟動 emulator 整合測試，未寄出測試信。
