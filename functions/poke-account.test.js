const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

function setup() {
  const documents = new Map();
  const sent = [];
  function collection(path) {
    return {
      doc: id => ({
        path: `${path}/${id}`,
        collection: name => collection(`${path}/${id}/${name}`),
        set: async (data, options) => documents.set(`${path}/${id}`, { ...(options?.merge ? documents.get(`${path}/${id}`) : {}), ...data }),
        delete: async () => documents.delete(`${path}/${id}`),
      }),
      get: async () => ({ docs: [...documents.entries()]
        .filter(([key]) => key.startsWith(`${path}/`))
        .map(([key, data]) => ({ data: () => data, ref: { delete: async () => documents.delete(key) } })) }),
    };
  }
  class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
  const context = { exports: {}, require: name => {
    if (name === 'firebase-admin/app') return { initializeApp() {} };
    if (name === 'firebase-admin/firestore') return { getFirestore: () => ({ collection }), FieldValue: { serverTimestamp: () => 1 }, Timestamp: class {} };
    if (name === 'firebase-admin/auth') return { getAuth: () => ({}) };
    if (name === 'firebase-admin/messaging') return { getMessaging: () => ({ sendEach: async messages => {
      sent.push(...messages); return { responses: messages.map(() => ({ success: true })) };
    } }) };
    if (name === 'firebase-functions/v2/https') return { onCall: (_, fn) => fn, HttpsError };
    if (name === 'firebase-functions/v2/firestore') return { onDocumentCreated: (_, fn) => fn };
    if (name === './join-requests' || name === './group-membership' || name === './peer-review') return {};
    return require(name);
  } };
  vm.runInNewContext(fs.readFileSync(__dirname + '/index.js', 'utf8'), context);
  const api = context.exports;
  return { documents, sent,
    register: (uid, deviceID, token, preferences = {}) => api.registerPokeDevice({ auth: { uid }, data: { deviceID, token, ...preferences } }),
    unregister: request => api.unregisterPokeDevice(request),
    push: uid => api.deliverPokePush({ data: { data: () => ({ recipientID: uid, groupName: 'Team', pokeCount: 15, style: '輕敲' }) } }),
  };
}

test('switching accounts removes the old device but preserves other devices', async () => {
  const s = setup();
  await s.register('A', 'phone', 'old-token');
  await s.register('A', 'tablet', 'tablet-token');
  await s.unregister({ auth: { uid: 'A' }, data: { deviceID: 'phone' } });
  await s.register('B', 'phone', 'new-token');
  await s.push('A');
  assert.deepEqual(s.sent.map(m => m.token), ['tablet-token']);
  s.sent.length = 0;
  await s.push('B');
  assert.deepEqual(s.sent.map(m => m.token), ['new-token']);
  assert.equal(s.sent[0].data.recipientUID, 'B');
});

test('unregister cannot delete another account registration', async () => {
  const s = setup();
  await s.register('A', 'phone', 'a-token');
  await s.unregister({ auth: { uid: 'B' }, data: { deviceID: 'phone' } });
  assert(s.documents.has('users/A/devices/phone'));
  await assert.rejects(s.unregister({ auth: { uid: 'B' }, data: { deviceID: 'phone', userID: 'A' } }), e => e.code === 'invalid-argument');
});

test('unregister is authenticated, validated, and safe to retry', async () => {
  const s = setup();
  await assert.rejects(s.unregister({ data: { deviceID: 'phone' } }), e => e.code === 'unauthenticated');
  for (const deviceID of ['', '../other', 42]) {
    await assert.rejects(s.unregister({ auth: { uid: 'A' }, data: { deviceID } }), e => e.code === 'invalid-argument');
  }
  await s.unregister({ auth: { uid: 'A' }, data: { deviceID: 'phone' } });
  await s.unregister({ auth: { uid: 'A' }, data: { deviceID: 'phone' } });
});


test('muting one device suppresses its push without muting the other device', async () => {
  const s = setup();
  await s.register('A', 'phone', 'phone-token', { pokesEnabled: false });
  await s.register('A', 'tablet', 'tablet-token', { pokesEnabled: true });
  await s.push('A');
  assert.deepEqual(s.sent.map(m => m.token), ['tablet-token']);
  s.sent.length = 0;
  await s.register('A', 'phone', 'phone-token', { pokesEnabled: true });
  await s.push('A');
  assert.deepEqual(s.sent.map(m => m.token).sort(), ['phone-token', 'tablet-token']);
});

test('token refresh and legacy registration preserve an explicit opt-out', async () => {
  const s = setup();
  await s.register('A', 'phone', 'old-token', { pokesEnabled: false });
  await s.register('A', 'phone', 'new-token');
  await s.push('A');
  assert.equal(s.sent.length, 0);
  assert.equal(s.documents.get('users/A/devices/phone').token, 'new-token');
});

test('only boolean notification preferences are accepted', async () => {
  const s = setup();
  for (const pokesEnabled of ['false', 0, null, {}]) {
    await assert.rejects(s.register('A', 'phone', 'token', { pokesEnabled }), e => e.code === 'invalid-argument');
  }
  assert.equal(s.documents.size, 0);
});
