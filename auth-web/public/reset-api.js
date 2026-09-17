export function validatePasswords(password, confirmation) {
  if (password.length < 6) return '密碼至少需要 6 個字元。';
  if (password !== confirmation) return '兩次輸入的密碼不一致。';
  return null;
}

export function errorMessage(code) {
  if (['INVALID_OOB_CODE', 'EXPIRED_OOB_CODE'].includes(code)) return '這個連結已失效或已使用。請回到 App 重新寄送重設信，並開啟最新一封。';
  if (code === 'USER_DISABLED') return '這個帳號已停用，請聯絡管理員。';
  if (['WEAK_PASSWORD', 'PASSWORD_DOES_NOT_MEET_REQUIREMENTS'].includes(code)) return '密碼強度不足，請使用更長的密碼，並包含大小寫字母、數字及符號。';
  if (['TOO_MANY_ATTEMPTS_TRY_LATER', 'RESET_PASSWORD_EXCEED_LIMIT'].includes(code)) return '嘗試次數過多，請稍後再試。';
  if (code === 'NETWORK_ERROR') return '目前無法連線，請確認網路後再試。';
  return '暫時無法完成，請稍後再試。';
}

// The production origin is fixed. Neither a return URL nor an API endpoint is taken from the link.
export async function resetRequest(apiKey, payload, fetcher = fetch) {
  let response;
  try {
    response = await fetcher(`https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=${encodeURIComponent(apiKey)}`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(payload), credentials: 'omit', referrerPolicy: 'no-referrer',
      signal: AbortSignal.timeout(20000),
    });
  } catch {
    throw Object.assign(new Error('NETWORK_ERROR'), {code: 'NETWORK_ERROR'});
  }
  let result;
  try { result = await response.json(); }
  catch { throw Object.assign(new Error('INVALID_RESPONSE'), {code: 'INVALID_RESPONSE'}); }
  if (!response.ok) {
    const code = (result.error?.message ?? 'UNKNOWN').split(' : ')[0];
    throw Object.assign(new Error(code), {code});
  }
  if (result.requestType !== 'PASSWORD_RESET' || typeof result.email !== 'string' || !result.email) {
    throw Object.assign(new Error('INVALID_RESPONSE'), {code: 'INVALID_RESPONSE'});
  }
  return result;
}
