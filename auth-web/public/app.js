import {errorMessage, resetRequest, validatePasswords} from './reset-api.js';
import {resolveLanguage, translate} from './language.js';
import {apiKey} from './config.js';

const $ = (id) => document.getElementById(id);
const card = document.querySelector('.card');
const params = new URLSearchParams(location.search);
const code = params.get('oobCode');
const mode = params.get('mode');
// Preview works only on loopback hosts, uses no real code and never sends a request.
const preview = ['localhost', '127.0.0.1'].includes(location.hostname) && !code ? params.get('preview') : null;
let language = resolveLanguage(params.get('lang'), navigator.language);
const t = key => translate(key, language);
let currentState = ['loading', '正在確認連結', '請稍候，馬上就好。'];
let currentError = '';
let verified = false;
let submitting = false;
let hasConfirmedPassword = false;

function showState(state, title, description, nextStep = '') {
  currentState = [state, title, description, nextStep];
  card.dataset.state = state;
  card.setAttribute('aria-busy', 'false');
  $('title').textContent = t(title);
  $('description').textContent = t(description);
  $('reset-form').hidden = state !== 'ready';
  $('account').hidden = state !== 'ready';
  $('next-step').textContent = t(nextStep);
  $('next-step').hidden = !nextStep;
  $('retry').hidden = state !== 'retry';
}

function showFailure(error) {
  const invalid = ['INVALID_OOB_CODE', 'EXPIRED_OOB_CODE', 'USER_DISABLED'].includes(error.code);
  verified = false;
  const title = error.code === 'USER_DISABLED' ? '無法重設密碼' : invalid ? '重設連結已失效' : '暫時無法重設密碼';
  showState(invalid ? 'invalid' : 'retry', title, errorMessage(error.code), invalid && error.code !== 'USER_DISABLED' ? '回到雷包點點名 → 忘記密碼 → 寄送重設信' : '');
}

function showSuccess() {
  verified = false;
  $('reset-form').reset();
  $('account').textContent = '';
  showState('success', '密碼更新，解除危機！', '你的新密碼已設定完成。', '回到雷包點點名，使用新密碼登入。');
  $('title').focus();
}

async function verify() {
  $('retry').hidden = true;
  card.setAttribute('aria-busy', 'true');
  try {
    const result = preview ? {email: 'demo@example.com'} : await resetRequest(apiKey, {oobCode: code});
    verified = true;
    $('account').textContent = result.email;
    showState('ready', '換個密碼，繼續拆彈。', '設定新密碼，回到你的任務基地。');
  } catch (error) { showFailure(error); }
}

$('toggle-password').addEventListener('click', () => {
  const visible = $('password').type === 'password';
  for (const id of ['password', 'confirmation']) $(id).type = visible ? 'text' : 'password';
  $('toggle-password').setAttribute('title', t(visible ? '隱藏密碼' : '顯示密碼'));
  $('toggle-password').setAttribute('aria-label', t(visible ? '隱藏密碼' : '顯示密碼'));
  $('toggle-password').setAttribute('aria-pressed', String(visible));
});

$('retry').addEventListener('click', verify);
function showPasswordMismatch() {
  const mismatch = $('confirmation').value !== '' && $('password').value !== $('confirmation').value;
  currentError = mismatch ? '兩次輸入的密碼不一致。' : '';
  $('form-error').textContent = t(currentError);
  $('form-error').hidden = !mismatch;
  if (mismatch) $('confirmation').setAttribute('aria-invalid', 'true');
  else $('confirmation').removeAttribute('aria-invalid');
}
$('confirmation').addEventListener('blur', () => {
  hasConfirmedPassword = true;
  showPasswordMismatch();
});
$('reset-form').addEventListener('input', () => {
  $('form-error').hidden = true;
  $('confirmation').removeAttribute('aria-invalid');
  if (hasConfirmedPassword) showPasswordMismatch();
});
$('reset-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!verified || submitting) return;
  hasConfirmedPassword = true;
  const validation = validatePasswords($('password').value, $('confirmation').value);
  if (validation) {
    currentError = validation;
    $('form-error').textContent = t(currentError);
    $('form-error').hidden = false;
    $('confirmation').setAttribute('aria-invalid', 'true');
    $('confirmation').focus();
    return;
  }
  submitting = true;
  $('submit').disabled = true;
  $('submit').textContent = t('正在更改密碼…');
  card.setAttribute('aria-busy', 'true');
  try {
    if (!preview) await resetRequest(apiKey, {oobCode: code, newPassword: $('password').value});
    showSuccess();
  } catch (error) {
    if (['INVALID_OOB_CODE', 'EXPIRED_OOB_CODE', 'USER_DISABLED'].includes(error.code)) {
      $('reset-form').reset();
      showFailure(error);
    } else {
      currentError = errorMessage(error.code);
      $('form-error').textContent = t(currentError);
      $('form-error').hidden = false;
    }
  } finally {
    submitting = false;
    $('submit').disabled = false;
    $('submit').textContent = t('確認更改密碼 ↗');
    card.setAttribute('aria-busy', 'false');
  }
});

function applyLanguage() {
  document.documentElement.lang = language;
  document.title = `${t('重設密碼')} · ${t('雷包點點名')}`;
  $('language').value = language;
  document.querySelectorAll('[data-i18n]').forEach(element => {
    element.textContent = t(element.dataset.i18n);
  });
  $('submit').textContent = t(submitting ? '正在更改密碼…' : '確認更改密碼 ↗');
  const label = t($('password').type === 'text' ? '隱藏密碼' : '顯示密碼');
  $('toggle-password').setAttribute('title', label);
  $('toggle-password').setAttribute('aria-label', label);
  $('form-error').textContent = t(currentError);
  showState(...currentState);
  card.setAttribute('aria-busy', String(submitting || currentState[0] === 'loading'));
}
$('language').addEventListener('change', () => {
  language = resolveLanguage($('language').value);
  applyLanguage();
});
applyLanguage();

if (mode && mode !== 'resetPassword') {
  // Firebase may apply the action URL to all email templates. Keep other actions on its built-in handler.
  const fallback = new URL('https://group-bomb.firebaseapp.com/__/auth/action');
  for (const key of ['mode', 'oobCode', 'lang']) if (params.has(key)) fallback.searchParams.set(key, params.get(key));
  fallback.searchParams.set('apiKey', apiKey);
  location.replace(fallback.href);
} else if (preview === 'success') {
  showSuccess();
} else if (preview === 'invalid') {
  showFailure({code: 'EXPIRED_OOB_CODE'});
} else if (preview || (mode === 'resetPassword' && code)) {
  // Remove credentials from the address bar before handling the form; never store them locally.
  if (code) history.replaceState(null, '', location.pathname);
  verify();
} else {
  showState('invalid', '從重設信開始', '請從最新一封重設密碼信件，開啟專屬連結。', '還沒收到信？請查看垃圾郵件，或回到 App 重新寄送。');
}
