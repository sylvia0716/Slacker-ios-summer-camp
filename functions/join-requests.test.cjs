const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

function setup() {
  class Timestamp { constructor(ms) {this.ms = ms;} toMillis() {return this.ms;} }
  const docs = new Map([
    ['groups/g', {name: 'Test', deadline: new Timestamp(Date.now() + 600000)}],
    ['groups/g/members/leader', {userID: 'leader', role: 'leader'}],
    ['groups/g/members/member', {userID: 'member', role: 'member'}],
    ['groupInviteCodes/ABC123', {groupID: 'g', isActive: true}],
  ]);
  const snap = ref => ({id: ref.id, exists: docs.has(ref.path), data: () => docs.get(ref.path)});
  function ref(path) {return {path, id: path.split('/').at(-1), collection: n => collection(`${path}/${n}`), get: async () => snap(ref(path))};}
  function collection(path, filter = () => true) {return {
    doc: id => ref(`${path}/${id}`),
    where: (key, _, value) => collection(path, data => filter(data) && data[key] === value),
    get: async () => ({docs: [...docs.keys()].filter(p => p.startsWith(path + '/') && !p.slice(path.length + 1).includes('/') && filter(docs.get(p))).map(p => snap(ref(p)))})
  };}
  // Serialize transactions and apply writes only after successful completion.
  let queue = Promise.resolve();
  const db = {collection, runTransaction(fn) {
    const run = queue.then(async () => {
      const writes = [];
      const result = await fn({get: r => r.get(),
        set: (r, d) => writes.push(() => docs.set(r.path, d)),
        create: (r, d) => {assert(!docs.has(r.path)); writes.push(() => docs.set(r.path, d));},
        update: (r, d) => writes.push(() => docs.set(r.path, {...docs.get(r.path), ...d}))});
      writes.forEach(w => w());
      return result;
    });
    queue = run.catch(() => {});
    return run;
  }};
  class HttpsError extends Error {constructor(code, message) {super(message); this.code = code;}}
  const context = {exports: {}, require(name) {
    if (name === 'firebase-admin/firestore') return {getFirestore: () => db, Timestamp, FieldValue: {serverTimestamp: () => new Timestamp(Date.now())}};
    if (name === 'firebase-admin/auth') return {getAuth: () => ({getUser: async () => ({displayName: 'Applicant'})})};
    if (name === 'firebase-functions/v2/https') return {onCall: (_, fn) => fn, HttpsError};
    return require(name);
  }};
  vm.runInNewContext(fs.readFileSync(__dirname + '/join-requests.js', 'utf8'), context);
  const api = context.exports;
  return {docs, Timestamp,
    send: (user = 'applicant', data = {}) => api.requestGroupJoin({auth: user ? {uid: user} : null, data: {inviteCode: 'ABC123', ...data}}),
    list: (user, groupID) => api.listGroupJoinRequests({auth: {uid: user}, data: groupID ? {groupID} : {}}),
    async decide(user = 'leader', approve = true, version) {
      const [path, data] = [...docs].find(([p]) => p.startsWith('groupJoinRequests/'));
      return api.decideGroupJoinRequest({auth: {uid: user}, data: {requestID: path.split('/')[1], version: version || data.version, approve}});
    }
  };
}
test('request remains pending without membership; duplicate concurrent requests converge', async () => {
  const s = setup();
  await Promise.all([s.send(), s.send()]);
  assert(!s.docs.has('groups/g/members/applicant'));
  const rows = (await s.list('applicant')).requests;
  assert.equal(rows.length, 1);
  assert.equal(rows[0].status, 'pending');
  assert(!('report' in rows[0]));
  assert.equal((await s.list('other')).requests.length, 0);
});
test('only current leader can list reports or decide, including malicious applicant', async () => {
  const s = setup(); await s.send();
  for (const user of ['applicant', 'member', 'outsider']) {
    await assert.rejects(s.list(user, 'g'), e => e.code === 'permission-denied');
    await assert.rejects(s.decide(user), e => e.code === 'permission-denied');
  }
  assert.equal((await s.list('leader', 'g')).requests[0].report.reviewCount, 0);
  s.docs.set('groups/g/members/leader', {role: 'member'});
  await assert.rejects(s.decide(), e => e.code === 'permission-denied');
});
test('approval creates member and durable result atomically, repeated decision is idempotent', async () => {
  const s = setup(); await s.send();
  await s.decide(); await s.decide();
  assert.equal(s.docs.get('groups/g/members/applicant').role, 'member');
  assert.equal((await s.list('applicant')).requests[0].status, 'approved');
});
test('pending application follows the current leader after a leadership transfer', async () => {
  const s = setup(); await s.send();
  s.docs.set('groups/g/members/leader', {role: 'member'});
  s.docs.set('groups/g/members/member', {role: 'leader'});
  await assert.rejects(s.list('leader', 'g'), e => e.code === 'permission-denied');
  await assert.rejects(s.decide('leader'), e => e.code === 'permission-denied');
  assert.equal((await s.list('member', 'g')).requests.length, 1);
  assert.equal((await s.decide('member')).status, 'approved');
});
test('competing approval and rejection have one committed outcome', async () => {
  const s = setup(); await s.send();
  const results = await Promise.all([s.decide('leader', false), s.decide('leader', true)]);
  assert(results.every(r => r.status === 'rejected'));
  assert(!s.docs.has('groups/g/members/applicant'));
});
test('rejection requires explicit resubmission; stale review cannot approve a new request', async () => {
  const s = setup(); await s.send();
  const old = (await s.list('applicant')).requests[0].version;
  await s.decide('leader', false);
  assert.equal((await s.send()).status, 'rejected');
  await s.send('applicant', {resubmit: true});
  await assert.rejects(s.decide('leader', true, old), e => e.code === 'failed-precondition');
  assert(!s.docs.has('groups/g/members/applicant'));
});
for (const condition of ['settled', 'expired', 'deleted', 'inactive-invite', 'expired-invite']) {
  test(`pending application becomes closed when ${condition}`, async () => {
    const s = setup(); await s.send();
    if (condition === 'settled') s.docs.get('groups/g').settledAt = new s.Timestamp(Date.now());
    if (condition === 'expired') s.docs.get('groups/g').deadline = new s.Timestamp(0);
    if (condition === 'deleted') s.docs.delete('groups/g');
    if (condition === 'inactive-invite') s.docs.get('groupInviteCodes/ABC123').isActive = false;
    if (condition === 'expired-invite') s.docs.get('groupInviteCodes/ABC123').expiresAt = new s.Timestamp(0);
    assert.equal((await s.list('applicant')).requests[0].status, 'closed');
    assert.equal((await s.decide()).status, 'closed');
    assert(!s.docs.has('groups/g/members/applicant'));
  });
}
test('invalid code, unauthenticated and closed group cannot create requests', async () => {
  const s = setup();
  await assert.rejects(s.send(null), e => e.code === 'unauthenticated');
  await assert.rejects(s.send('applicant', {inviteCode: '../bad'}), e => e.code === 'invalid-argument');
  s.docs.get('groups/g').deleting = true;
  await assert.rejects(s.send(), e => e.code === 'failed-precondition');
  assert.equal((await s.list('applicant')).requests.length, 0);
});
test('existing member does not create an application', async () => {
  const s = setup();
  assert.equal((await s.send('member')).alreadyMember, true);
  assert.equal((await s.list('member')).requests.length, 0);
});
test('report uses server-owned reviews and remains a submission-time snapshot', async () => {
  const s = setup();
  s.docs.set('users/applicant/peerReviewProjects/p', {reviewCount: 2, taskCompletionScore: 4, discussionScore: 3, collaborationScore: 5, ideaScore: 2, reliabilityScore: 4});
  await s.send('applicant', {report: {reviewCount: 999}});
  s.docs.delete('users/applicant/peerReviewProjects/p');
  const report = (await s.list('leader', 'g')).requests[0].report;
  assert.equal(report.reviewCount, 2);
  assert.equal(report.taskCompletionScore, 4);
});
