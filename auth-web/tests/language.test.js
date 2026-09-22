import test from 'node:test';
import assert from 'node:assert/strict';
import {resolveLanguage, translate, english} from '../public/language.js';
import {readFile} from 'node:fs/promises';

test('email link language takes priority over browser, unsupported languages use English', () => {
  assert.equal(resolveLanguage('zh-TW', 'en-US'), 'zh-Hant');
  assert.equal(resolveLanguage('en', 'zh-TW'), 'en');
  assert.equal(resolveLanguage(null, 'zh-HK'), 'zh-Hant');
  assert.equal(resolveLanguage(null, 'fr-FR'), 'en');
});

test('all displayed Chinese keys have English translations', async () => {
  const app = await readFile(new URL('../public/app.js', import.meta.url), 'utf8');
  const api = await readFile(new URL('../public/reset-api.js', import.meta.url), 'utf8');
  const html = await readFile(new URL('../public/index.html', import.meta.url), 'utf8');
  const keys = [...(app + api).matchAll(/'([^'\n]*[\u3400-\u9fff][^'\n]*)'/g)].map(m => m[1]);
  keys.push(...[...html.matchAll(/data-i18n="([^"]+)"/g)].map(m => m[1]));
  for (const key of keys) assert.ok(english[key], `Missing English translation: ${key}`);
  assert.equal(translate('雷包點點名', 'en'), 'Oops Bomb');
});
