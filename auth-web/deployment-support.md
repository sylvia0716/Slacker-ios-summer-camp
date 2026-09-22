# Firebase 郵件自訂限制

2026-09-17：網站部署成功，信件範本與 action URL 更新被 Firebase 拒絕。須先由 Firebase 支援處理專案限制。

支援表單：https://firebase.google.com/support/troubleshooter/auth/email/help

可填資訊：Project `group-bomb`；Language `Swift`；Environment `Console UI`；Urgency `I'm running into issues while testing`。

## Summary

EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED when customizing password reset email and action URL

## Description

Our Firebase project is group-bomb (display name OopsBomb). We are deploying a branded password reset experience for our iOS app, Oops Bomb / 雷包點點名.

The custom action handler is deployed at https://group-bomb.web.app/ using Firebase Hosting. However, updates to both the password reset email template and the custom action URL are rejected. The Identity Toolkit Admin API returns HTTP 400 EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED. The Firebase Authentication Console also states that this project currently cannot update email templates and directs us to this support form.

Updating only the sender display name to “Oops Bomb 雷包點點名” succeeded. However, a subsequent Console attempt to save the bilingual subject and HTML body together was rejected with the same project restriction message. The original subject, body, and action URL remain unchanged. We have not isolated whether the subject or body triggers the rejection. We use the default Firebase email delivery service, with no custom SMTP or custom email domain.

Please explain the project restriction and help enable email template and custom action URL updates. We can provide further project information if required.

## 解除限制後

1. 套用 `email/template.bilingual.json` 與 `email/password-reset.bilingual.html`，保留 `%EMAIL%`、`%LINK%`。
2. 自訂 action URL 設為 `https://group-bomb.web.app/`。
3. 重新讀取確認設定已儲存，檢查 HTML 是否被修改。
4. 由使用者在 App 寄送新重設信、確認信件樣式與網址，並自行輸入新密碼完成測試；舊信件不會自動換成新網址。
