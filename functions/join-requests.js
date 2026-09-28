const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {createHash, randomUUID} = require('node:crypto');
const {memberDisplayName} = require('./member-display-name');
const region = 'asia-east1';
const scoreKeys = ['taskCompletionScore', 'discussionScore', 'collaborationScore', 'ideaScore', 'reliabilityScore'];
function fail(code, message) { throw new HttpsError(code, message); }
function uid(request) {
  if (!request.auth?.uid) fail('unauthenticated', '請先登入。');
  return request.auth.uid;
}
function identifier(value) {
  if (typeof value !== 'string' || !value || value.length > 128 || value.includes('/')) fail('invalid-argument', '申請資料不正確。');
  return value;
}
function closed(group) {
  return !group || group.deleting === true || group.settledAt != null || !(group.deadline instanceof Timestamp) || group.deadline.toMillis() <= Date.now();
}
function invalidInvite(invite, groupID) {
  return !invite || invite.groupID !== groupID || invite.isActive !== true ||
    (invite.expiresAt != null && (!(invite.expiresAt instanceof Timestamp) || invite.expiresAt.toMillis() <= Date.now()));
}
async function reportSnapshot(db, userID) {
  const records = await db.collection('users').doc(userID).collection('peerReviewProjects').get();
  const projects = records.docs.map(d => d.data()).filter(d => d.reviewCount > 0 && scoreKeys.every(k => Number.isFinite(d[k]) && d[k] >= 1 && d[k] <= 5));
  const reviewCount = projects.reduce((n, p) => n + p.reviewCount, 0);
  return {projectCount: projects.length, reviewCount,
    ...Object.fromEntries(scoreKeys.map(k => [k, reviewCount ? projects.reduce((n, p) => n + p[k] * p.reviewCount, 0) / reviewCount : null]))};
}

exports.requestGroupJoin = onCall({region}, async request => {
  const userID = uid(request);
  const code = typeof request.data?.inviteCode === 'string' ? request.data.inviteCode.trim().toUpperCase() : '';
  if (!/^[A-Z0-9]{6}$/.test(code)) fail('invalid-argument', '請輸入六位邀請碼。');
  const db = getFirestore();
  const displayName = memberDisplayName(await getAuth().getUser(userID));
  const report = await reportSnapshot(db, userID);
  return db.runTransaction(async tx => {
    const inviteRef = db.collection('groupInviteCodes').doc(code);
    const invite = (await tx.get(inviteRef)).data();
    if (!invite || invalidInvite(invite, invite.groupID)) fail('failed-precondition', '邀請碼不存在或已失效。');
    const groupID = identifier(invite.groupID);
    const groupRef = db.collection('groups').doc(groupID);
    const id = createHash('sha256').update(JSON.stringify([groupID, userID])).digest('hex');
    const ref = db.collection('groupJoinRequests').doc(id);
    const [groupSnap, member, previous] = await Promise.all([tx.get(groupRef), tx.get(groupRef.collection('members').doc(userID)), tx.get(ref)]);
    if (member.exists) return {status: 'approved', alreadyMember: true};
    if (closed(groupSnap.data())) fail('failed-precondition', '群組已結束，無法申請加入。');
    const old = previous.data();
    if (old?.status === 'pending') {
      const previousInvite = old.inviteCode === code ? invite : (await tx.get(db.collection('groupInviteCodes').doc(old.inviteCode))).data();
      if (!invalidInvite(previousInvite, groupID)) return {status: 'pending'};
    }
    if (old?.status === 'rejected' && request.data?.resubmit !== true) return {status: 'rejected'};
    tx.set(ref, {groupID, groupName: groupSnap.data().name, applicantUID: userID, displayName,
      inviteCode: code, status: 'pending', version: randomUUID(), report,
      requestedAt: FieldValue.serverTimestamp()});
    return {status: 'pending'};
  });
});

exports.listGroupJoinRequests = onCall({region}, async request => {
  const userID = uid(request);
  const db = getFirestore();
  const groupID = request.data?.groupID;
  let query = db.collection('groupJoinRequests');
  if (groupID != null) {
    identifier(groupID);
    const leader = await db.collection('groups').doc(groupID).collection('members').doc(userID).get();
    if (leader.data()?.role !== 'leader') fail('permission-denied', '只有組長可以查看入群申請。');
    query = query.where('groupID', '==', groupID);
  } else query = query.where('applicantUID', '==', userID);
  const snapshot = await query.get();
  const requests = await Promise.all(snapshot.docs.map(async document => {
    const data = document.data().status !== 'pending' ? document.data() : await db.runTransaction(async tx => {
      const ref = db.collection('groupJoinRequests').doc(document.id);
      const current = (await tx.get(ref)).data();
      if (current.status !== 'pending') return current;
      const groupRef = db.collection('groups').doc(current.groupID);
      const [group, invite, member] = await Promise.all([tx.get(groupRef), tx.get(db.collection('groupInviteCodes').doc(current.inviteCode)), tx.get(groupRef.collection('members').doc(current.applicantUID))]);
      const status = member.exists ? 'approved' : closed(group.data()) || invalidInvite(invite.data(), current.groupID) ? 'closed' : 'pending';
      if (status !== 'pending') tx.update(ref, {status, decidedAt: FieldValue.serverTimestamp()});
      return {...current, status};
    });
    const status = data.status;
    return {id: document.id, groupID: data.groupID, groupName: data.groupName, displayName: data.displayName,
      status, version: data.version, requestedAt: data.requestedAt?.toMillis() || 0,
      ...(groupID != null ? {report: data.report} : {})};
  }));
  // Recheck after loading private reports in case leadership changed mid-request.
  if (groupID != null) {
    const leader = await db.collection('groups').doc(groupID).collection('members').doc(userID).get();
    if (leader.data()?.role !== 'leader') fail('permission-denied', '組長已變更。');
  }
  return {requests: requests.sort((a, b) => b.requestedAt - a.requestedAt)};
});

exports.decideGroupJoinRequest = onCall({region}, async request => {
  const userID = uid(request);
  const id = identifier(request.data?.requestID);
  const version = identifier(request.data?.version);
  const approve = request.data?.approve;
  if (typeof approve !== 'boolean') fail('invalid-argument', '請選擇核准或拒絕。');
  const db = getFirestore();
  return db.runTransaction(async tx => {
    const ref = db.collection('groupJoinRequests').doc(id);
    const data = (await tx.get(ref)).data();
    if (!data) fail('not-found', '申請不存在。');
    const group = db.collection('groups').doc(data.groupID);
    const memberRef = group.collection('members').doc(data.applicantUID);
    const [groupSnap, leader, member, invite] = await Promise.all([tx.get(group), tx.get(group.collection('members').doc(userID)), tx.get(memberRef), tx.get(db.collection('groupInviteCodes').doc(data.inviteCode))]);
    if (leader.data()?.role !== 'leader' || userID === data.applicantUID) fail('permission-denied', '只有目前的組長可以審核。');
    if (data.version !== version) fail('failed-precondition', '申請已更新，請重新整理。');
    if (data.status !== 'pending') return {status: data.status};
    const status = member.exists ? 'approved' : closed(groupSnap.data()) || invalidInvite(invite.data(), data.groupID) ? 'closed' : approve ? 'approved' : 'rejected';
    if (status === 'approved' && !member.exists) {
      tx.create(memberRef, {userID: data.applicantUID, role: 'member', displayName: data.displayName,
        joinedAt: FieldValue.serverTimestamp(), leaderElectionID: groupSnap.data().leaderElectionID || null, leaderVoteUID: null});
      tx.update(group, {membershipUpdatedAt: FieldValue.serverTimestamp()});
    }
    tx.update(ref, {status, decidedBy: userID, decidedAt: FieldValue.serverTimestamp()});
    return {status};
  });
});
