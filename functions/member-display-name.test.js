const {test} = require('node:test');
const assert = require('node:assert/strict');
const {memberDisplayName} = require('./member-display-name');

test('nickname takes priority over email', () => {
  assert.equal(memberDisplayName({uid: 'abc', displayName: ' Peach ', email: 'a@example.com'}), 'Peach');
});
test('missing or whitespace nickname uses full email', () => {
  for (const displayName of [undefined, '', '  ']) {
    assert.equal(memberDisplayName({uid: 'abc', displayName, email: 'person+02@example.com'}), 'person+02@example.com');
  }
});
test('email is not truncated to nickname length', () => {
  const email = `${'a'.repeat(60)}@example.com`;
  assert.equal(memberDisplayName({uid: 'abc', email}), email);
});
test('account without email or nickname retains safe fallback', () => {
  assert.equal(memberDisplayName({uid: 'abcdefghijk'}), '成員 abcdefgh');
});
