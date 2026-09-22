const { test } = require('node:test');
const assert = require('node:assert/strict');
const { pokeNotification } = require('./poke-notification');

test('push uses receiving device language and preserves a mixed-language group name', () => {
  const poke = { groupName: 'English 中文 {0} 👩🏽‍💻', pokeCount: 1 };
  for (const language of ['en', 'zh-Hant', undefined]) {
    assert.ok(pokeNotification(poke, language).body.includes(poke.groupName));
  }
  assert.equal(pokeNotification(poke, 'en').title, 'Someone is looking for you');
  assert.ok(pokeNotification(poke, 'en').body.endsWith('1 time!'));
  assert.equal(pokeNotification(poke).title, '有人在找你');
});
test('all poke escalation levels have English copy', () => {
  for (const pokeCount of [2, 4, 5, 9, 10, 20]) {
    const text = pokeNotification({ groupName: 'Team', pokeCount }, 'en');
    assert.ok(text.body.length > 0);
    assert.ok(!/[\u3400-\u9fff]/u.test(text.body));
  }
});
