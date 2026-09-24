const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function fixture(confirmed, members = ['owner', 'peer'], done = true, departureID = null) {
  let update;
  const task = { departureID, ownerMemberID: 'owner', subtasks: [{ id: 's', isComplete: done }],
    confirmedAttachmentID: 'attachment', confirmedMemberUIDs: confirmed };
  const ref = path => ({ path, collection: name => ref(`${path}/${name}`), doc: id => ref(`${path}/${id}`) });
  const db = { collection: name => ref(name), runTransaction: body => body({
    get: async r => r.path.endsWith('/members')
      ? { docs: members.map(id => ({ id, data: () => ({ userID: id }) })) }
      : r.path.endsWith('/attachments')
        ? { docs: [{ id: 'attachment', data: () => ({ status: 'ready' }) }] }
        : { exists: true, data: () => task },
    update: (_, value) => { update = value; }
  }) };
  const context = { exports: {}, require: name => {
    if (name === 'firebase-admin/firestore') return { getFirestore: () => db, FieldValue: { serverTimestamp: () => 0 } };
    if (name === 'firebase-functions/v2/https') return { onCall: (_, fn) => fn, HttpsError: class extends Error {
      constructor(code, message) { super(message); this.code = code; }
    } };
    if (name === 'firebase-functions/v2/firestore') return { onDocumentWritten: (_, fn) => fn };
    throw new Error(name);
  } };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(`${__dirname}/task-progress.js`, 'utf8'), context);
  return { run: actor => context.reconcile('g', 't', actor), value: () => update };
}

test('peer confirmation completes a task without owner confirmation', async () => {
  const f = fixture(['peer']); await f.run();
  assert.equal(f.value().status, 'completed');
});
test('old owner confirmation is removed and does not count as peer approval', async () => {
  const f = fixture(['owner']); await f.run();
  assert.equal(f.value().status, 'submitted');
  assert.equal(f.value().confirmedMemberUIDs.length, 0);
});
test('owner cannot confirm own task', async () => {
  const f = fixture([]);
  await assert.rejects(f.run({ action: 'confirm', uid: 'owner', attachmentID: 'attachment' }), /Owner does not review/);
});
test('single-member group does not wait for self-confirmation', async () => {
  const f = fixture([], ['owner']); await f.run();
  assert.equal(f.value().status, 'completed');
});
test('peer confirmation does not bypass incomplete subtasks', async () => {
  const f = fixture(['peer'], ['owner', 'peer'], false); await f.run();
  assert.equal(f.value().status, 'submitted');
});

test('archived departure never changes on reconciliation or accepts progress edits', async () => {
  const f = fixture(['peer'], ['owner','peer'], true, 'departure');
  await f.run(); assert.equal(f.value(), undefined);
  await assert.rejects(f.run({action:'setSubtask',uid:'owner',subtaskID:'s',isComplete:false}), /archived/);
});
