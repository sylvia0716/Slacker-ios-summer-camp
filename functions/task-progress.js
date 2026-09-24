const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const region = 'asia-east1';

function latestReady(docs) {
  return docs.filter(d => d.data().status === 'ready').sort((a, b) =>
    (b.data().createdAt?.toMillis?.() || 0) - (a.data().createdAt?.toMillis?.() || 0)
      || a.id.localeCompare(b.id))[0];
}

async function reconcile(groupID, taskID, actor = null) {
  const db = getFirestore(), group = db.collection('groups').doc(groupID), ref = group.collection('tasks').doc(taskID);
  return db.runTransaction(async tx => {
    const [groupSnapshot, task, members, attachments] = await Promise.all([
      tx.get(group), tx.get(ref), tx.get(group.collection('members')), tx.get(ref.collection('attachments')),
    ]);
    if (!task.exists) { if (actor) throw new HttpsError('not-found', 'Task missing'); return; }
    if (actor && groupSnapshot.data()?.settledAt != null) {
      throw new HttpsError('failed-precondition', 'Group is already settled');
    }
    const data = task.data();
    if (data.departureID) {
      if (actor) throw new HttpsError('failed-precondition', 'Former member task is archived');
      return;
    }
    const uids = members.docs.filter(d => d.data().userID === d.id).map(d => d.id);
    const reviewers = uids.filter(uid => uid !== data.ownerMemberID);
    if (actor && !uids.includes(actor.uid)) throw new HttpsError('permission-denied', 'Membership required');
    const latest = latestReady(attachments.docs);
    let subtasks = data.subtasks || [];
    let confirmed = data.confirmedAttachmentID === (latest?.id || null)
      ? (data.confirmedMemberUIDs || []).filter(uid => reviewers.includes(uid)) : [];
    if (actor?.action === 'setSubtask') {
      if (data.ownerMemberID !== actor.uid) throw new HttpsError('permission-denied', 'Owner required');
      if (!subtasks.some(s => s.id === actor.subtaskID)) throw new HttpsError('not-found', 'Subtask missing');
      const changed = subtasks.some(s => s.id === actor.subtaskID && s.isComplete !== actor.isComplete);
      subtasks = subtasks.map(s => s.id === actor.subtaskID ? {...s, isComplete: actor.isComplete} : s);
      if (changed) confirmed = [];
    }
    const allDone = subtasks.every(s => s.isComplete === true);
    if (actor?.action === 'confirm') {
      if (actor.uid === data.ownerMemberID) throw new HttpsError('permission-denied', 'Owner does not review own task');
      if (!latest || latest.id !== actor.attachmentID) throw new HttpsError('failed-precondition', 'Result changed; reload');
      if (!allDone) throw new HttpsError('failed-precondition', 'Subtasks incomplete');
      confirmed = [...new Set([...confirmed, actor.uid])];
    }
    confirmed.sort();
    const completed = !!latest && allDone && uids.length > 0 && reviewers.every(uid => confirmed.includes(uid));
    const status = completed ? 'completed' : latest ? 'submitted'
      : subtasks.some(s => s.isComplete) ? 'inProgress' : 'pending';
    const next = {status, confirmedAttachmentID: latest?.id || null, confirmedMemberUIDs: latest ? confirmed : []};
    if (actor?.action === 'setSubtask') next.subtasks = subtasks;
    if (Object.entries(next).some(([key, value]) => JSON.stringify(data[key]) !== JSON.stringify(value))) {
      tx.update(ref, {...next, updatedAt: FieldValue.serverTimestamp()});
    }
    return {status};
  });
}

exports.updateTaskProgress = onCall({region}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required');
  const d = request.data;
  const uuid = /^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$/;
  const keys = d?.action === 'confirm' ? ['groupID','taskID','action','attachmentID'] : ['groupID','taskID','action','subtaskID','isComplete'];
  if (!d || typeof d !== 'object' || Object.keys(d).length !== keys.length || Object.keys(d).some(k => !keys.includes(k))
      || !uuid.test(d.groupID) || !uuid.test(d.taskID)
      || (d.action !== 'confirm' && d.action !== 'setSubtask')
      || (d.action === 'confirm' && (typeof d.attachmentID !== 'string' || !uuid.test(d.attachmentID)))
      || (d.action === 'setSubtask' && (typeof d.isComplete !== 'boolean' || typeof d.subtaskID !== 'string' || !uuid.test(d.subtaskID)))) {
    throw new HttpsError('invalid-argument', 'Invalid task operation');
  }
  return reconcile(d.groupID, d.taskID, {...d, uid: request.auth.uid});
});

// Re-read current state inside transactions: retries/out-of-order events cannot restore old approvals.
exports.syncAttachmentProgress = onDocumentWritten({region, document: 'groups/{groupID}/tasks/{taskID}/attachments/{attachmentID}'},
  event => reconcile(event.params.groupID, event.params.taskID));
exports.syncTaskProgress = onDocumentWritten({region, document: 'groups/{groupID}/tasks/{taskID}'},
  event => reconcile(event.params.groupID, event.params.taskID));
exports.syncMemberProgress = onDocumentWritten({region, document: 'groups/{groupID}/members/{userID}'}, async event => {
  const before = event.data?.before, after = event.data?.after;
  if (before?.exists && after?.exists && before.data().userID === after.data().userID) return;
  const tasks = await getFirestore().collection('groups').doc(event.params.groupID).collection('tasks').get();
  for (const task of tasks.docs) await reconcile(event.params.groupID, task.id);
});
