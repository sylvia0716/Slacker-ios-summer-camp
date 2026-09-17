import test from 'node:test';
import assert from 'node:assert/strict';
import {errorMessage, resetRequest, validatePasswords} from '../public/reset-api.js';

test('verification only verifies the code and never includes a password', async () => {
  let request;
  const result = await resetRequest('project-key', {oobCode: 'test-code'}, async (url, options) => {
    request = {url, options};
    return new Response(JSON.stringify({email: 'test@example.com', requestType: 'PASSWORD_RESET'}));
  });
  assert.equal(result.email, 'test@example.com');
  assert.equal(request.url, 'https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=project-key');
  assert.deepEqual(JSON.parse(request.options.body), {oobCode: 'test-code'});
  assert.equal(request.options.referrerPolicy, 'no-referrer');
  assert.equal(request.options.credentials, 'omit');
});

test('confirmation preserves password whitespace and sends the code with the password', async () => {
  await resetRequest('project-key', {oobCode: 'test-code', newPassword: ' secret '}, async (_, options) => {
    assert.deepEqual(JSON.parse(options.body), {oobCode: 'test-code', newPassword: ' secret '});
    return new Response(JSON.stringify({email: 'test@example.com', requestType: 'PASSWORD_RESET'}));
  });
});

test('expired or consumed codes do not become successful results', async () => {
  for (const code of ['EXPIRED_OOB_CODE', 'INVALID_OOB_CODE']) {
    await assert.rejects(resetRequest('key', {oobCode: 'bad'}, async () =>
      new Response(JSON.stringify({error: {message: code}}), {status: 400})), {code});
    assert.match(errorMessage(code), /最新一封/);
  }
});

test('wrong action types and incomplete success responses fail closed', async () => {
  for (const data of [{}, {email: 'test@example.com', requestType: 'VERIFY_EMAIL'}, {requestType: 'PASSWORD_RESET'}]) {
    await assert.rejects(resetRequest('key', {oobCode: 'code'}, async () => new Response(JSON.stringify(data))), {code: 'INVALID_RESPONSE'});
  }
});

test('network failure is retryable and weak-password details are localized', async () => {
  await assert.rejects(resetRequest('key', {}, async () => {throw new TypeError('offline');}), {code: 'NETWORK_ERROR'});
  await assert.rejects(resetRequest('key', {}, async () => new Response(JSON.stringify({error: {message: 'WEAK_PASSWORD : Password should be stronger'}}), {status: 400})), {code: 'WEAK_PASSWORD'});
  assert.match(errorMessage('WEAK_PASSWORD'), /密碼強度不足/);
});

test('short and mismatched passwords are rejected; matching passwords are accepted', () => {
  assert.ok(validatePasswords('12345', '12345'));
  assert.ok(validatePasswords('123456', '123457'));
  assert.equal(validatePasswords('123456', '123456'), null);
});
