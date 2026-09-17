export function resolveLanguage(requested, browserLanguage = 'en') {
  const value = (requested || browserLanguage).toLowerCase();
  return value.startsWith('zh') ? 'zh-Hant' : 'en';
}

export const english = {
  '雷包點點名': 'Oops Bomb',
  '一起拆彈，一起過關。': 'Defuse the chaos. Win together.',
  '重設密碼': 'Reset password', '帳號安全': 'Account security',
  '正在確認連結': 'Checking your link', '請稍候，馬上就好。': 'Just a moment.',
  '新密碼': 'New password', '再次輸入新密碼': 'Confirm new password',
  '至少 6 個字元': 'At least 6 characters', '顯示密碼': 'Show passwords', '隱藏密碼': 'Hide passwords',
  '確認更改密碼 ↗': 'Reset password ↗', '重新連線': 'Try again',
  '請開啟瀏覽器的 JavaScript，才能設定新密碼。': 'Enable JavaScript in your browser to reset your password.',
  '無法重設密碼': 'Unable to reset password', '重設連結已失效': 'This link is no longer valid',
  '暫時無法重設密碼': 'Unable to reset right now',
  '回到雷包點點名 → 忘記密碼 → 寄送重設信': 'Open Oops Bomb → Forgot password? → Send reset link',
  '密碼更新，解除危機！': 'New password. Crisis defused!',
  '你的新密碼已設定完成。': 'Your password has been updated.',
  '回到雷包點點名，使用新密碼登入。': 'Return to Oops Bomb and sign in with your new password.',
  '換個密碼，繼續拆彈。': 'New password. Fresh start.',
  '設定新密碼，回到你的任務基地。': 'Set a new password and get back to your team.',
  '兩次輸入的密碼不一致。': 'The passwords do not match.',
  '正在更改密碼…': 'Updating password…',
  '從重設信開始': 'Open your reset email',
  '請從最新一封重設密碼信件，開啟專屬連結。': 'Open the link in your most recent password reset email.',
  '還沒收到信？請查看垃圾郵件，或回到 App 重新寄送。': 'No email? Check your spam folder or request another link in the app.',
  '密碼至少需要 6 個字元。': 'Use at least 6 characters.',
  '這個連結已失效或已使用。請回到 App 重新寄送重設信，並開啟最新一封。': 'This link has expired or has already been used. Request a new link in the app and open the most recent email.',
  '這個帳號已停用，請聯絡管理員。': 'This account is disabled. Contact the administrator.',
  '密碼強度不足，請使用更長的密碼，並包含大小寫字母、數字及符號。': 'Choose a longer password with uppercase and lowercase letters, numbers, and symbols.',
  '嘗試次數過多，請稍後再試。': 'Too many attempts. Please try again later.',
  '目前無法連線，請確認網路後再試。': 'Check your connection and try again.',
  '暫時無法完成，請稍後再試。': 'Unable to complete this action. Please try again later.',
};

export function translate(key, language) {
  return language === 'en' ? (english[key] ?? key) : key;
}
