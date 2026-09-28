import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {before, after, test} from 'node:test';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, connectAuthEmulator, signInAnonymously} from 'firebase/auth';
import {getFunctions, connectFunctionsEmulator, httpsCallable} from 'firebase/functions';
import {doc, getDoc, setDoc, updateDoc, Timestamp} from 'firebase/firestore';
const projectId = 'demo-group-bomb';
let env;
const apps = [];
before(async () => {
  env = await initializeTestEnvironment({projectId, firestore: {host: '127.0.0.1', port: 8080,
    rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8')}});
});
after(async () => {await Promise.all(apps.map(deleteApp)); await env.cleanup();});
async function client() {
  const app = initializeApp({apiKey: 'demo-key', projectId}, `approval-${apps.length}`); apps.push(app);
  const auth = getAuth(app); connectAuthEmulator(auth, 'http://127.0.0.1:9099', {disableWarnings: true});
  const uid = (await signInAnonymously(auth)).user.uid;
  const functions = getFunctions(app, 'asia-east1'); connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  return {uid, firestore: env.authenticatedContext(uid).firestore(), call: (name, data = {}) => httpsCallable(functions, name)(data)};
}
test('two accounts: pending access denied, leader rejection, resubmission and atomic approval', async () => {
  const [leader, applicant, outsider] = await Promise.all([client(), client(), client()]);
  const {data: {group}} = await leader.call('createGroup', {name: 'Approval integration', displayName: 'Leader', deadlineMillis: Date.now() + 3600000});
  const {groupID, inviteCode} = group;
  await assert.rejects(applicant.call('joinGroupByInviteCode', {inviteCode}), e => e.code === 'functions/failed-precondition');
  const results = await Promise.all([applicant.call('requestGroupJoin', {inviteCode}), applicant.call('requestGroupJoin', {inviteCode})]);
  assert(results.every(r => r.data.status === 'pending'));
  await assertFails(getDoc(doc(applicant.firestore, `groups/${groupID}`)));
  await assertFails(setDoc(doc(applicant.firestore, `groups/${groupID}/members/${applicant.uid}`), {userID: applicant.uid, role: 'member'}));
  let rows = (await applicant.call('listGroupJoinRequests')).data.requests;
  assert.equal(rows.length, 1);
  assert.equal(rows[0].status, 'pending');
  assert(!('report' in rows[0]));
  const entry = rows[0];
  await assertFails(getDoc(doc(leader.firestore, `groupJoinRequests/${entry.id}`)));
  await assertFails(setDoc(doc(applicant.firestore, `groupJoinRequests/${entry.id}`), {status: 'approved'}));
  await assert.rejects(outsider.call('listGroupJoinRequests', {groupID}), e => e.code === 'functions/permission-denied');
  const decision = {requestID: entry.id, version: entry.version, approve: true};
  await assert.rejects(applicant.call('decideGroupJoinRequest', decision), e => e.code === 'functions/permission-denied');
  await assert.rejects(outsider.call('decideGroupJoinRequest', decision), e => e.code === 'functions/permission-denied');
  await leader.call('decideGroupJoinRequest', {...decision, approve: false});
  assert.equal((await applicant.call('listGroupJoinRequests')).data.requests[0].status, 'rejected');
  await assertFails(getDoc(doc(applicant.firestore, `groups/${groupID}`)));
  assert.equal((await applicant.call('requestGroupJoin', {inviteCode})).data.status, 'rejected');
  await applicant.call('requestGroupJoin', {inviteCode, resubmit: true});
  await assert.rejects(leader.call('decideGroupJoinRequest', decision), e => e.code === 'functions/failed-precondition');
  const next = (await leader.call('listGroupJoinRequests', {groupID})).data.requests[0];
  assert.equal(next.report.reviewCount, 0);
  const approvals = await Promise.all([true, true].map(approve => leader.call('decideGroupJoinRequest', {requestID: next.id, version: next.version, approve})));
  assert(approvals.every(r => r.data.status === 'approved'));
  await assertSucceeds(getDoc(doc(applicant.firestore, `groups/${groupID}`)));
  assert.equal((await applicant.call('listGroupJoinRequests')).data.requests[0].status, 'approved');
  assert((await applicant.call('listMyGroups')).data.groups.some(g => g.groupID === groupID));
  await assert.rejects(applicant.call('listGroupJoinRequests', {groupID}), e => e.code === 'functions/permission-denied');
});
test('pending application reports closed after deadline and never admits applicant', async () => {
  const [leader, applicant] = await Promise.all([client(), client()]);
  const {data: {group}} = await leader.call('createGroup', {name: 'Closing', displayName: 'Leader', deadlineMillis: Date.now() + 3600000});
  await applicant.call('requestGroupJoin', {inviteCode: group.inviteCode});
  await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), `groups/${group.groupID}`), {deadline: Timestamp.fromMillis(1)}));
  const entry = (await applicant.call('listGroupJoinRequests')).data.requests[0];
  assert.equal(entry.status, 'closed');
  assert.equal((await leader.call('decideGroupJoinRequest', {requestID: entry.id, version: entry.version, approve: true})).data.status, 'closed');
  await assertFails(getDoc(doc(applicant.firestore, `groups/${group.groupID}`)));
});
