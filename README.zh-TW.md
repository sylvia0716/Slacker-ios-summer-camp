# Oops! Bomb · 雷包點點名

**少一點「Oops」，多一點「完成」。**

Oops! Bomb 是一款協助團隊在共同截止期限前完成工作的 iOS 協作 App。它串起專案開始前、進行中與結束後的工作：選擇隊友、分配職責、準備會議、分享成果證明，以及從合作經驗中學習。

團體專案的重要資訊經常散落在聊天訊息、檔案和個人的待辦清單中。Oops! Bomb 將這些資訊整合在一起，讓成員掌握哪些工作待完成、哪些成果已提交，以及哪些事項仍需要團隊關注。黃黑配色的美式復古設計、炸彈主題倒數計時與趣味提醒，讓負責任的團隊合作也能充滿個性。

由 **Oops Lab** 打造。

## 功能

### 1. 團隊合作檔案（Teamwork Profile）

> 每一次合作，都留下紀錄。

專案雖然會結束，一起工作的經驗卻能成為下次合作的參考。團隊合作檔案將成員已公布的同儕評價與專案歷程，彙整成個人的合作紀錄。

- 查看涵蓋**任務完成、討論參與、主動協助、問題解決與可靠度**五個面向的個人檔案。
- 同時查看各專案的評價結果與過往合作概況。
- 將個人表現報告匯出為 PDF。
- 申請加入群組時，組長可在核准前查看已公布的表現摘要與專案歷程。此畫面不會揭露原始評價資料、私人評語或評分者身分。

這讓**專案回饋 → 合作歷程 → 更有依據的組隊決策**形成連結。檔案反映收到的同儕回饋，並不保證未來的表現。

### 2. 我的任務（My Tasks）

> 所有任務、所有專案，一目瞭然。

「我的任務」彙整登入成員在各專案中的工作，讓你不必逐一開啟群組，就能決定接下來要做什麼。

- 切換查看依截止時間排序的待完成與已完成任務。
- 開啟任務，查看需求、更新子任務並管理交付成果。
- 勾選或取消勾選子任務即可更新完成狀態。系統依子任務權重計算顯示的任務完成百分比，並納入成員與專案進度。
- 查看每項任務所屬的專案，清楚知道是哪個團隊需要這份成果。

**「我的任務」小工具**讓你在 App 外也能掌握進度。它會依任務分組，以精簡清單顯示待完成工作，並支援主畫面、鎖定畫面與待機顯示，同時提供返回「我的任務」的連結。直接在小工具上勾選即可完成子任務：勾選記錄會先存進共用的 App Group，待 App 下次啟用時再送往後端。小工具讀取的是 App 寫入的資料快照。

> 下一件該做的事，就在看得見的地方。

### 3. 自動化議程（Smart Agenda）

> 有備而來，討論不離題。

Smart Agenda 在繁體中文介面中顯示為**自動化議程**，結合會前準備與分配好時間的討論計畫，協助團隊帶著內容參與討論，並在每個階段產出具體成果。

**會議設定**：組長可以在同一個專案中建立、編輯與刪除多場會議。每場會議都有自己的主題、日期、時間、時長、準備資料、連結與議程計畫。

**準備與規劃**：

1. 組長設定會議主題、日期、時間與時長。
2. 每位成員新增準備筆記、附件，或同時提供兩者。成員只能編輯自己的準備內容。
3. 議程會統計已完成準備的人數，包含組長。同一人新增多筆內容不會重複計算人數。
4. 所有人都準備完成後，支援的裝置會使用 Apple Intelligence 產生 **3–4 個階段**，每個階段都有時間區間、討論主題與具體目標。各階段時長加總等於會議總時長。
5. Firebase 會驗證並儲存計畫，讓其他成員也能查看，包括使用無法自行產生 AI 內容的裝置的成員。

例如，20 分鐘的會議可以分配 5 分鐘檢視資料、7 分鐘決定功能優先順序，以及 8 分鐘確認後續行動。這只是示意計畫；實際內容會依團隊的準備資料產生。

**會議開始前**：成員可以開啟共享的會議連結，系統也會在會議開始前 30 分鐘內，於群組聊天室發布排程摘要，列出主題、時間、已準備的成員、尚未完成的準備，以及可討論的主題。

產生議程時會使用會議主題、時長、準備筆記與附件檔名，**不會**分析附件內容。模型推論在裝置上執行；準備資料與產生的計畫則透過 Firebase 共享。

### 4. AI 偵探（AI Detective）

> 從雜亂對話中，找出清楚目標。

AI 偵探將協作助理帶進群組對話。當想法、問題與不同提案不斷累積時，成員可以請助理協助理解討論內容，找出有幫助的下一步。

- 在聊天室中提及助理，或使用快捷功能，針對近期對話提問。
- 請助理整理分歧、釐清選項，或建議共同目標。建議會出現在對話中，供團隊討論。
- 使用團隊的任務紀錄與近期對話，請助理分析專案。結果包含摘要、優點、改善建議，以及五項專案層級評分。
- 透過群組聊天室分享產生的回覆或分析，讓團隊依據相同資訊協作。

助理使用支援裝置上的 Apple Intelligence。系統會要求它依據提供的證據回答，並指出缺少的資訊。它的建議用來輔助團隊決策，不會自動指派任務、解決爭議或更改截止日期。

### 5. 戳一下（Nudge）

> 沒辦法隔著螢幕拍肩膀？那就戳一下。

「戳一下」讓成員用有趣的方式引起隊友注意，不必再往聊天室多打一則提醒。

- 從成員進度介面，戳一下同群組的其他成員。
- 選擇適合當下情境的提醒風格，包括輕鬆的迷因式提醒。
- 透過 Firebase 傳送提醒，並在 App 內顯示接收效果；完成設定且取得授權後，也會傳送推播通知。
- 在通知偏好設定中控制是否接收戳一下提醒。

這項功能將 Oops! Bomb 的幽默帶進日常協調，也讓接收者保有通知的控制權。

### 6. 成果驗收（Verified Submission）

> 團隊確認完成，才算真正完成。

勾完清單與讓隊友接受成果，是兩個不同的步驟。成果驗收將交付成果與需要審閱它的成員連結起來。

1. 任務負責人完成子任務，並上傳成果證明，或附上外部成果連結。
2. 其他群組成員可以開啟或下載共享的提交成果。
3. 每位符合資格的隊友確認成果。**任務負責人不會審核自己的任務。**
4. 後端會針對目前提交的成果記錄驗收狀態，並在收到所需確認後，將其標記為審核完成。

審核者頭像讓確認狀態一目瞭然：尚未確認的頭像會變暗，已確認的則會醒目顯示。修改清單或替換目前提交的成果後，必須重新確認，避免先前的核准直接沿用到不同的工作內容。

清單完成百分比與成果驗收分開追蹤：百分比顯示工作進度，確認紀錄則代表團隊已接受交付成果。

> 沒有成果證明，就不算過關。

### 7. 匿名 AI 評價（Anonymous AI Review）

> 坦誠回饋，一起進步。

專案結束時，系統結合兩種觀點：**隊友提供的匿名回饋**，以及 **AI 對專案工作紀錄與討論的分析**。

**匿名同儕評價**

- 成員依五個合作面向評價隊友，也可以留下文字回饋。
- App 會追蹤本輪評價的完成狀態，並在所有參與成員完成後公布結果。
- 成員能查看自己收到的回饋，但不會看到評分者身分。已公布的個人結果會納入團隊合作檔案與專案歷程。

**AI 專案分析**

- Apple Intelligence 根據任務事實與團隊對話，產生專案層級評分、摘要、優點與改善建議。
- 提示詞要求分析以證據為依據，並明確指出資訊不足的情況。
- AI 分析與同儕評價的計算彼此獨立：私人匿名回饋不會傳送給模型，用來產生這些專案評分。

這兩種觀點協助團隊回顧合作過程，並將有用的經驗帶進下一個專案。AI 輸出是討論的參考，並非對個人的權威判定。

### 8. AI 專案迷因（AI Project Meme）

> 把專案的混亂，變成一張迷因。

專案結尾也有視覺笑點。當專案成功完成，或到了截止時間卻仍有未完成工作時，Oops! Bomb 會呈現專屬迷因，讓結果呼應 App 的炸彈主題風格。

- 在結果圖片中顯示專案名稱。
- 依成功完成或尚未完成，呈現不同的畫面。
- 從結算畫面重新開啟結果迷因，並分享產生的圖片。

**目前實作**：這項展示功能使用內建圖片素材，並由程式組合專案文字。雖然展示章節名稱包含 AI，目前版本並未使用 AI 模型產生新的迷因圖片。

### 9. 專案基本功能（Project Essentials）

> 團隊需要的工具，集中在一起。

日常協作工具將上述重點功能串成完整可用的專案流程：

- **建立與加入**：建立群組並設定截止日期，分享群組代碼或 QR 邀請，並管理加入申請。建立者會成為第一任組長。
- **指派與整理**：發布任務、選擇負責人、新增有權重的子任務，並編輯任務細節。在進度清單中釘選成員卡片，隨時掌握專案倒數。
- **上傳與分享**：新增多個附件、管理標題與說明、替換或刪除檔案，以及分享外部連結。Firebase Storage 儲存檔案內容，Firestore 則儲存共享的中繼資料。
- **維護成員狀態**：移交組長、在需要時投票選出接任者，並決定是否將離開成員的封存工作納入專案進度。重新加入的成員不會自動取回原本的任務。
- **保持聯繫**：使用群組聊天、已讀回條、釘選訊息、截止提醒與通知收件匣。
- **個人化設定**：設定暱稱與照片、使用英文或繁體中文，並選擇通知偏好。介面也能跟隨系統語言。

這些功能使用同一套專案與成員資料，因此任務細節、附件、準備內容與審核狀態，都能透過 Firebase 在不同帳號與裝置間共享。

#### 支援的附件

| 使用位置 | 格式 |
| --- | --- |
| 任務交付成果 | PNG、JPG/JPEG、PDF、DOCX、PPTX、XLSX、ZIP，以及外部連結 |
| 議程準備資料 | PNG、JPG/JPEG、PDF、DOCX、PPTX、XLSX、ZIP、MOV 與 MP4 |

檔案不得為空，且大小不得超過 **20 MB**。任務中的 PNG 與 JPEG 上傳會保留原始格式與位元組內容。個人照片則會調整尺寸，並另外儲存為 JPEG。

## 技術架構

| 領域 | 技術 |
| --- | --- |
| iOS App | Swift、SwiftUI、Swift Observation |
| 裝置端 AI | 透過 Foundation Models 框架使用 Apple Intelligence |
| 身分驗證 | Firebase Authentication：電子郵件／密碼與匿名工作階段 |
| 共享資料與檔案 | Cloud Firestore、Firebase Storage、Security Rules |
| 後端 | Cloud Functions for Firebase、Node.js 22、排程會議提醒 |
| 通知 | Firebase Cloud Messaging、APNs、UserNotifications |
| App 驗證 | Firebase App Check：Debug 使用偵錯提供者，Release 使用 App Attest |
| 小工具 | WidgetKit 與共用 App Group |
| 相依套件 | Swift Package Manager 與 npm |

目前 App 未整合 RevenueCat 或訂閱付費牆。執行此版本不需要 RevenueCat 設定，也不需要 OpenAI API 金鑰。

## 設定說明

### 環境需求

- 一台安裝 **Xcode 26.5 或更新版本**及 iOS 26.5 SDK 的 Mac。App 與小工具目前的最低支援版本為 **iOS 26.5+**。
- iOS 26.5+ 模擬器或相容的 iPhone。請使用實體裝置驗證 Apple Intelligence 內容產生功能與推播通知。
- AI 功能需要裝置支援 Apple Intelligence，且已啟用並完整下載。議程產生功能會檢查英文與繁體中文的支援狀態。請參閱 [Apple 的 Foundation Models 文件](https://developer.apple.com/documentation/FoundationModels)。
- 自行建立並啟用 Authentication、Firestore 與 Storage 的 Firebase 專案。部署後端需要 [Firebase Blaze 方案](https://firebase.google.com/docs/functions/get-started)；雲端用量費用會計入該專案。
- 後端設定需要 **Node.js 22**、npm 與 Firebase CLI。本機模擬器測試請使用 **JDK 21+**。
- 在實體裝置執行時，需要具備必要權限的 Apple 開發團隊，以簽署 App 與小工具。

### 1. 複製儲存庫

```sh
git clone --branch main https://github.com/sylvia0716/Slacker-ios-summer-camp.git OopsBomb
cd OopsBomb
```

### 2. 設定 Xcode 簽署與識別碼

開啟 `group.xcodeproj`，選擇 **group** scheme，並讓 Xcode 解析 Swift Package Manager 相依套件。

在 **Signing & Capabilities** 中，為 `group` 與 `GroupBombWidget` 選擇你的開發團隊，並使用已註冊於該團隊的 Bundle Identifier。儲存庫目前使用 `con.sylvia.group` 與 `con.sylvia.group.widget`。

註冊共用的 App Group，並在以下三個位置使用相同的識別碼：

- `group/group.entitlements`
- `GroupBombWidget/GroupBombWidget.entitlements`
- `WidgetShared/WidgetTodoSnapshot.swift`（`WidgetSharedConfig.appGroupIdentifier`）

目前的 App Group 識別碼為 `group.con.sylvia.group`。兩個 target 都必須能存取同一個群組，小工具才能接收 App 的資料快照。

### 3. 設定你的 Firebase 專案

1. 在 Firebase Console 中，使用上一步的 App Bundle Identifier 註冊 iOS App。
2. 下載其 `GoogleService-Info.plist`，並替換 `group/GoogleService-Info.plist`。確認該檔案屬於 **group** App target。
3. 在 Authentication 中啟用 **Email/Password** 與 **Anonymous** 登入。匿名登入支援使用者在沒有電子郵件帳號的情況下進入 App。
4. 建立預設的 Firestore 資料庫與預設的 Storage bucket。
5. 為 iOS App 設定 App Check。模擬器／Debug 版本請將 Xcode 印出的偵錯權杖註冊至你自己的 Firebase 專案。Release 版本使用 App Attest。請參閱 [Firebase 偵錯提供者設定](https://firebase.google.com/docs/app-check/ios/debug-provider)。

儲存庫內的 Firebase 設定與 `.firebaserc` 指向團隊的專案。請替換用戶端設定，並在部署時明確指定你自己的專案。

### 4. 安裝並部署後端

在儲存庫根目錄執行：

```sh
npm install -g firebase-tools
npm ci --prefix functions
firebase login

FIREBASE_PROJECT_ID="your-firebase-project-id"
firebase deploy --project "$FIREBASE_PROJECT_ID" \
  --only firestore:rules,firestore:indexes,storage,functions
```

使用現有的 `firebase.json` 即可，不需要在此儲存庫中初始化新的後端。App 會呼叫 **`asia-east1`** 區域的 Functions，與後端原始碼的設定一致。請部署所有匯出的函式，讓成員管理、任務、帳號通知清理、議程與提醒功能一併可用。

此次部署包含排程會議提醒。Firestore 索引可能需要一段時間才能準備完成。檔案存取與資料異動依賴隨附的 Security Rules，以及後端的身分驗證檢查。

### 5. 設定推播通知與密碼重設

- **推播通知**：為 App 識別碼啟用 Push Notifications，並將 APNs 驗證金鑰上傳至 Firebase Cloud Messaging。使用你所屬團隊的簽署設定建置，並在裝置上允許通知。請參閱 [Firebase 的 Apple 平台訊息設定](https://firebase.google.com/docs/cloud-messaging/ios/get-started)。
- **密碼重設**：App 透過 Firebase Authentication 傳送重設郵件。可以直接使用 Firebase 預設的密碼重設頁面，不必另外部署網站。
- **選用的品牌密碼重設頁面**：`auth-web/` 包含雙語重設頁面與郵件範本。在託管自己的版本前，請替換 `auth-web/public/config.js` 中的專案 API 設定，以及 `auth-web/public/app.js` 中備用的 Firebase 操作頁面網域。依照 [auth-web 設定說明](auth-web/README.md)操作，並設定你自己的 Firebase 電子郵件操作網址。

### 6. 建置並試用 App

在 Xcode 中選擇 iOS 26.5+ 執行目的地，使用 `group` scheme 按下 **Run**。

若要體驗協作流程：

1. 在你的 Firebase 專案中註冊兩個測試帳號。
2. 使用第一個帳號建立群組。第二個帳號透過邀請碼提出加入申請，再由組長核准。
3. 指派任務與子任務、上傳交付成果，並確認另一個帳號可以查看。
4. 開啟「分享」旁的議程管理圖示，建立會議，並由兩個帳號提交準備資料。
5. 在符合條件的裝置上產生會議計畫，確認另一個帳號收到已儲存的結果。

模擬器可用來操作介面與測試 Firebase 流程。若系統語言模型不可用，就無法驗證實際的 AI 內容產生功能，但仍可讀取既有的共享計畫。僅供開發者使用的範例資料工具需要管理員授予的宣告（claim），不屬於一般註冊流程；普通測試帳號可以建立自己的專案。

### 執行測試

選定完整的 Xcode 工具鏈後，在儲存庫根目錄執行：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Swift 模型、資料存取層、在地化與狀態測試
swift test

# 後端單元測試
npm ci --prefix functions
node --test functions/*.test.js functions/*.test.cjs

# Firebase 整合與 Security Rules 測試
npm ci --prefix firebase-rules-tests
firebase emulators:exec --project demo-group-bomb \
  --only auth,functions,firestore,storage \
  'npm --prefix firebase-rules-tests run test:rules'
```

整合測試套件使用本機的 **`demo-group-bomb`** 模擬器專案。連線端點由測試設定；啟動模擬器不會自動讓 iOS App 改連其他專案，App 仍會使用其 plist 指定的專案。

## 儲存庫結構

```text
OopsBomb/
├── README.md              # 專案概覽與設定說明
├── LICENSE                # MIT 授權條款
├── group/                 # SwiftUI App、模型、資料儲存、服務與資源
├── group.xcodeproj/       # App 與小工具 target；Swift 套件相依性
├── GroupBombWidget/       # 「我的任務」小工具與其 App Intent
├── WidgetShared/          # 兩個 target 共用的快照資料結構
├── functions/             # Firebase 後端與單元測試
├── firebase-rules-tests/  # 模擬器整合與存取控制測試
├── ios-cloud-tests/       # Swift 測試
├── auth-web/              # 選用的密碼重設網站與郵件範本
├── firebase.json          # 後端部署與模擬器設定
├── firestore.rules
├── firestore.indexes.json
└── storage.rules
```

## 展示

**YouTube 展示影片**：即將推出，團隊會在此補上影片連結。

展示依照上述九個功能章節進行，並特別聚焦於以下四個情境：

| 重點功能 | 展示內容 |
| --- | --- |
| AI 偵探 | 將熱絡的團隊對話整理成更清楚的問題、討論摘要，或共同目標提案。 |
| 成果驗收 | 成員提交成果證明，隊友檢視後確認，並清楚呈現確認狀態。 |
| 匿名 AI 評價＋團隊合作檔案 | 專案結束後的回饋累積成合作紀錄，並成為未來群組審核加入申請的參考。 |
| 戳一下 | 成員送出趣味提醒，隊友收到提醒。 |

[建置並試用 App](#6-建置並試用-app) 中的操作流程涵蓋核心協作與自動化議程功能。

## 團隊

**Oops Lab** — **Oops! Bomb／雷包點點名**的開發團隊。

## 授權條款

本專案的原創程式碼採用 **MIT 授權條款**。完整內容請參閱 [LICENSE](LICENSE)。

第三方相依套件與素材仍適用各自的授權條款。內建的 DSEG 字型採用 SIL Open Font License 1.1；授權聲明收錄於 [DSEG-LICENSE.txt](group/Resources/SmartAgendaPreview/DSEG-LICENSE.txt)。
