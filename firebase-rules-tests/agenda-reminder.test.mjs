import {test, before, beforeEach, after} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {initializeTestEnvironment, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, onSnapshot, collection, setDoc, serverTimestamp} from 'firebase/firestore';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('This test requires the local Firestore emulator.');
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {leadTime, publishReminder} = require('./smart-agenda-reminder-core');
const projectId = 'demo-group-bomb', now = Date.now(), groupID = 'agenda-reminder-test';
let env, app, db, group, agenda;
const publish = () => publishReminder(db, agenda, now, () => FieldValue.serverTimestamp());
before(async () => {
  env = await initializeTestEnvironment({projectId});
  app = initializeApp({projectId}, 'agenda-reminder-integration');
  db = getFirestore(app); group = db.collection('groups').doc(groupID);
  agenda = group.collection('smartAgenda').doc('current');
});
beforeEach(async () => {
  await env.clearFirestore();
  await group.set({name:'Reminder integration test'});
  await group.collection('members').doc('leader').set({userID:'leader',role:'leader',displayName:'Mia'});
  await group.collection('members').doc('member').set({userID:'member',role:'member',displayName:'Alex'});
  await agenda.set({topic:'Demo',duration:20,meetingAt:Timestamp.fromMillis(now + leadTime),materials:{
    leader:{note:'A note is sufficient',membershipVersion:'legacy'},
  }});
});
after(async () => { await env.cleanup(); await deleteApp(app); });

test('at 30 minutes the cloud summary reaches both accounts with live updates', async () => {
  const member = env.authenticatedContext('member').firestore();
  const received = new Promise((resolve,reject) => {
    const timeout = setTimeout(() => { stop(); reject(Error('Reminder was not synced')); },10000);
    const stop = onSnapshot(collection(member,`groups/${groupID}/messages`), snapshot => {
      if (!snapshot.empty) { clearTimeout(timeout); stop(); resolve(snapshot.docs[0]); }
    }, reject);
  });
  assert.equal(await publish(),true);
  const synced = await received;
  const leaderCopy = await getDoc(doc(env.authenticatedContext('leader').firestore(), synced.ref.path));
  assert.deepEqual(leaderCopy.data(),synced.data());
  assert.deepEqual(synced.data().agendaSummary.preparedNames,['Mia']);
  assert.deepEqual(synced.data().agendaSummary.missingNames,['Alex']);
  assert.equal(synced.data().kind,'agendaReminder');
  await assertFails(getDoc(doc(env.authenticatedContext('outsider').firestore(),synced.ref.path)));
});
test('concurrent runs, retries and material edits still produce only one chat message', async () => {
  const results = await Promise.all(Array.from({length:5},publish));
  assert.equal(results.filter(Boolean).length,1);
  await agenda.update({'materials.member':{note:'Now prepared',membershipVersion:'legacy'},topic:'Revised topic'});
  assert.equal(await publish(),false);
  assert.equal((await group.collection('messages').get()).size,1);
});
test('rescheduled and started meetings are checked again before sending', async () => {
  await agenda.update({meetingAt:Timestamp.fromMillis(now+leadTime+1)});
  assert.equal(await publish(),false);
  await agenda.update({meetingAt:Timestamp.fromMillis(now)});
  assert.equal(await publish(),false);
  await agenda.update({meetingAt:Timestamp.fromMillis(now+leadTime),meetingStartedAt:Timestamp.fromMillis(now)});
  assert.equal(await publish(),false);
  await agenda.update({meetingStartedAt:null});
  assert.equal(await publish(),true);
  await agenda.update({meetingAt:Timestamp.fromMillis(now+leadTime-1000)});
  assert.equal(await publish(),true);
  assert.equal((await group.collection('messages').get()).size,2);
});
test('departed members and stale preparation from a prior membership are excluded', async () => {
  await group.collection('members').doc('leader').delete();
  await group.collection('members').doc('member').update({joinedAt:Timestamp.fromMillis(200000)});
  await agenda.update({'materials.member':{note:'Old preparation',membershipVersion:'100.0'}});
  await publish();
  const summary = (await group.collection('messages').get()).docs[0].data().agendaSummary;
  assert.deepEqual(summary.preparedNames,[]);
  assert.deepEqual(summary.missingNames,['Alex']);
});
test('deleted or empty groups never receive reminders', async () => {
  await group.update({deleting:true});
  assert.equal(await publish(),false);
  await group.update({deleting:false});
  await group.collection('members').doc('leader').delete();
  await group.collection('members').doc('member').delete();
  assert.equal(await publish(),false);
  assert.equal((await group.collection('messages').get()).size,0);
});
test('clients cannot impersonate a server-authored agenda summary', async () => {
  await publish();
  const original = (await group.collection('messages').get()).docs[0].data();
  await assertFails(setDoc(doc(env.authenticatedContext('member').firestore(),`groups/${groupID}/messages/forged`),
    {...original,id:'forged',senderID:'member',createdAt:serverTimestamp()}));
});

test('each meeting gets its own reminder; a deleted agenda never sends one', async () => {
  const second = group.collection('smartAgenda').doc('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  await second.set({...((await agenda.get()).data()), topic:'Second meeting'});
  assert.equal(await publish(),true);
  assert.equal(await publishReminder(db,second,now,()=>FieldValue.serverTimestamp()),true);
  assert.equal(await publishReminder(db,second,now,()=>FieldValue.serverTimestamp()),false);
  assert.equal((await group.collection('messages').get()).size,2);
  await second.set({deleted:true});
  assert.equal(await publishReminder(db,second,now,()=>FieldValue.serverTimestamp()),false);
});
