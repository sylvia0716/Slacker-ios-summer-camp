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
  await db.runTransaction(async tx => {
    const snapshot = await tx.get(group);
    const members = await tx.get(group.collection('members'));
    const caller = members.docs.find(member => member.id === uid);
    // Idempotent after a successful exit, including a lost network response.
    if (!snapshot.exists || !caller) return;
    const remaining = members.docs.filter(member => member.id !== uid);
    tx.delete(caller.ref);
    tx.delete(group.collection('presence').doc(uid));
    if (remaining.length === 0) {
      tx.update(group, {deleting: true});
    } else {
      // Keep leader-only operations usable after the original leader leaves.
      if (!remaining.some(member => member.data().role === 'leader')) {
        tx.update(remaining[0].ref, {role: 'leader'});
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
