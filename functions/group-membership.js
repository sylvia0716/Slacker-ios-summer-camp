const { randomUUID } = require('node:crypto');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const region = 'asia-east1';

// Membership changes and joins both read the group document, serializing the last exit with joins.
exports.leaveGroup = onCall({region}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required');
  const data = request.data;
  if (!data || typeof data !== 'object' || Object.keys(data).join(',') !== 'groupID'
      || typeof data.groupID !== 'string'
      || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(data.groupID)) {
    throw new HttpsError('invalid-argument', 'Only groupID is accepted');
  }
  const db = getFirestore(), group = db.collection('groups').doc(data.groupID);
  const uid = request.auth.uid;
  const departureID = randomUUID();
  await db.runTransaction(async tx => {
    const snapshot = await tx.get(group);
    const members = await tx.get(group.collection('members'));
    const caller = members.docs.find(member => member.id === uid);
    // Idempotent after a successful exit, including a lost network response.
    if (!snapshot.exists || !caller) return;
    const remaining = members.docs.filter(member => member.id !== uid);
    const tasks = await tx.get(group.collection('tasks').where('ownerMemberID', '==', uid));
    for (const task of tasks.docs) {
      const data = task.data(), subtasks = data.subtasks || [];
      const total = subtasks.reduce((sum, item) => sum + item.weight, 0);
      const done = subtasks.filter(item => item.isComplete).reduce((sum, item) => sum + item.weight, 0);
      tx.update(task.ref, {
        ownerMemberID: null, departedMemberName: caller.data().displayName || uid,
        departureID, includedInProgress: true, departureReviewed: false,
        departedProgress: total > 0 ? Math.floor(done * 100 / total) : data.status === 'completed' ? 100 : 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.delete(caller.ref);
    tx.delete(group.collection('presence').doc(uid));
    if (remaining.length === 0) {
      tx.update(group, {deleting: true});
    } else {
      if (!remaining.some(member => member.data().role === 'leader')) {
        const newElection = caller.data().role === 'leader' || !snapshot.data().leaderElectionID;
        const electionID = newElection ? randomUUID() : snapshot.data().leaderElectionID;
        const eligible = new Set(remaining.map(member => member.id));
        const votes = remaining.map(member => !newElection && eligible.has(member.data().leaderVoteUID)
          ? member.data().leaderVoteUID : null);
        const winner = remaining.length === 1 ? remaining[0].id
          : remaining.find(member => votes.filter(uid => uid === member.id).length > remaining.length / 2)?.id;
        for (const [index, member] of remaining.entries()) {
          tx.update(member.ref, {role: member.id === winner ? 'leader' : 'member',
            leaderElectionID: winner ? null : electionID, leaderVoteUID: winner ? null : votes[index]});
        }
        tx.update(group, {leaderElectionID: winner ? null : electionID});
      }
      tx.update(group, {membershipUpdatedAt: FieldValue.serverTimestamp()});
    }
  });
  return {left: true};
});

// Retry failed cleanup. Keep the parent until every child and file has been removed.
exports.cleanupEmptyGroup = onDocumentUpdated({region, document: 'groups/{groupID}', retry: true}, async event => {
  if (event.data?.after.data().deleting !== true) return;
  const db = getFirestore(), group = db.collection('groups').doc(event.params.groupID);
  const snapshot = await group.get();
  if (!snapshot.exists || snapshot.data().deleting !== true) return;
  const members = await group.collection('members').limit(1).get();
  if (!members.empty) throw new Error('Refusing to delete a group with members');
  await getStorage().bucket().deleteFiles({prefix: `groups/${group.id}/`});
  const invites = await db.collection('groupInviteCodes').where('groupID', '==', group.id).get();
  for (const invite of invites.docs) await invite.ref.delete();
  for (const collection of await group.listCollections()) await db.recursiveDelete(collection);
  await group.delete();
});

// One leader decision covers the tasks from this specific departure, never a later rejoin.
exports.setDepartedTasksInclusion = onCall({region}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required');
  const d = request.data;
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
  if (!d || Object.keys(d).length !== 3 || !uuid.test(d.groupID) || !uuid.test(d.departureID)
      || typeof d.included !== 'boolean') throw new HttpsError('invalid-argument', 'Invalid decision');
  const group = getFirestore().collection('groups').doc(d.groupID);
  await getFirestore().runTransaction(async tx => {
    const member = await tx.get(group.collection('members').doc(request.auth.uid));
    if (!member.exists || member.data().role !== 'leader') throw new HttpsError('permission-denied', 'Leader required');
    const tasks = await tx.get(group.collection('tasks').where('departureID', '==', d.departureID));
    if (tasks.empty) throw new HttpsError('not-found', 'Departure missing');
    for (const task of tasks.docs) tx.update(task.ref, {
      includedInProgress: d.included, departureReviewed: true, updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {updated: true};
});

exports.chooseGroupLeader = onCall({region}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required');
  const d = request.data;
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
  if (!d || !uuid.test(d.groupID) || typeof d.candidateUID !== 'string'
      || !d.candidateUID || !['transfer', 'vote'].includes(d.action)
      || Object.keys(d).some(key => !['groupID','candidateUID','action','electionID'].includes(key))
      || (d.action === 'vote' && !uuid.test(d.electionID))) {
    throw new HttpsError('invalid-argument', 'Invalid leader selection');
  }
  const group = getFirestore().collection('groups').doc(d.groupID);
  return getFirestore().runTransaction(async tx => {
    const snapshot = await tx.get(group);
    const members = await tx.get(group.collection('members'));
    const caller = members.docs.find(m => m.id === request.auth.uid);
    if (!snapshot.exists || snapshot.data().deleting || !caller) throw new HttpsError('permission-denied', 'Membership required');
    if (!members.docs.some(m => m.id === d.candidateUID)) throw new HttpsError('failed-precondition', 'Candidate has left');
    let winner;
    if (d.action === 'transfer') {
      if (caller.data().role !== 'leader') throw new HttpsError('permission-denied', 'Leader required');
      winner = d.candidateUID;
    } else {
      if (members.docs.some(m => m.data().role === 'leader') || snapshot.data().leaderElectionID !== d.electionID) {
        throw new HttpsError('failed-precondition', 'Election ended or changed');
      }
      const votes = members.docs.map(m => m.id === caller.id ? d.candidateUID : m.data().leaderVoteUID);
      winner = members.docs.find(m => votes.filter(uid => uid === m.id).length > members.docs.length / 2)?.id;
      if (!winner) tx.update(caller.ref, {leaderVoteUID: d.candidateUID});
    }
    if (winner) {
      for (const member of members.docs) tx.update(member.ref, {
        role: member.id === winner ? 'leader' : 'member', leaderElectionID: null, leaderVoteUID: null,
      });
    }
    tx.update(group, {leaderElectionID: winner ? null : d.electionID, membershipUpdatedAt: FieldValue.serverTimestamp()});
    return {elected: !!winner};
  });
});
