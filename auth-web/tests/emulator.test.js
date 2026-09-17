import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {resetRequest} from '../public/reset-api.js';

const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
test('emulator: a real reset code changes the password once, and the old password no longer works', {skip: !host}, async () => {
  // Do not allow this integration test to target a remote service or a real project.
  assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/);
  const origin = `http://${host}`;
  const project = 'demo-group-bomb';
  const email = `reset-${randomUUID()}@example.test`;
  const oldPassword = randomUUID();
  const newPassword = randomUUID();
  const api = async (method, payload) => {
    const response = await fetch(`${origin}/identitytoolkit.googleapis.com/v1/accounts:${method}?key=fake-api-key`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload),
    });
    return {status: response.status, body: await response.json()};
  };
  const created = await api('signUp', {email, password: oldPassword, returnSecureToken: true});
  assert.equal(created.status, 200);
  let idToken = created.body.idToken;
  try {
    assert.equal((await api('sendOobCode', {requestType: 'PASSWORD_RESET', email})).status, 200);
    const codes = await (await fetch(`${origin}/emulator/v1/projects/${project}/oobCodes`)).json();
    const oobCode = codes.oobCodes.find(entry => entry.email === email).oobCode;
    const emulatorFetch = (url, options) => fetch(`${origin}/identitytoolkit.googleapis.com${new URL(url).pathname}${new URL(url).search}`, options);
    const verified = await resetRequest('fake-api-key', {oobCode}, emulatorFetch);
    assert.equal(verified.email, email);
    // Verification must not consume the code; confirmation is a separate operation.
    await resetRequest('fake-api-key', {oobCode, newPassword}, emulatorFetch);
    assert.notEqual((await api('signInWithPassword', {email, password: oldPassword, returnSecureToken: true})).status, 200);
    const signedIn = await api('signInWithPassword', {email, password: newPassword, returnSecureToken: true});
    assert.equal(signedIn.status, 200);
    idToken = signedIn.body.idToken;
    await assert.rejects(resetRequest('fake-api-key', {oobCode}, emulatorFetch), {code: 'INVALID_OOB_CODE'});
  } finally {
    await api('delete', {idToken});
  }
});
