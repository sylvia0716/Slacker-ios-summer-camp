const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const region = 'asia-east1';
const {enforceProjectQuota} = require('./project-quota');
const {proStatusForUser} = require('./revenuecat-entitlement');

function input(request, keys) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in required');
  const data = request.data;
  if (!data || Array.isArray(data) || Object.keys(data).sort().join(',') !== [...keys].sort().join(',')
      || typeof data.groupID !== 'string' || !/^[a-f0-9-]{36}$/i.test(data.groupID)
      || typeof data.applicantID !== 'string' || !data.applicantID || data.applicantID.includes('/')
      || typeof data.requestID !== 'string' || !data.requestID) {
    throw new HttpsError('invalid-argument', 'Invalid application');
  }
  return data;
}

async function authorizedApplication(tx, group, uid, data) {
  const [groupSnapshot, leader, application] = await Promise.all([
    tx.get(group), tx.get(group.collection('members').doc(uid)),
    tx.get(group.collection('joinRequests').doc(data.applicantID)),
  ]);
  if (!groupSnapshot.exists || groupSnapshot.data().deleting
      || leader.data()?.userID !== uid || leader.data()?.role !== 'leader') {
    throw new HttpsError('permission-denied', 'Current group leader required');
  }
  if (!application.exists || application.data().requestID !== data.requestID) {
    throw new HttpsError('failed-precondition', 'Application changed; refresh and try again');
  }
  return {groupSnapshot, application};
}

exports.reviewGroupJoinRequest = onCall({region}, async request => {
  const data = input(request, ['groupID', 'applicantID', 'requestID', 'decision']);
  if (!['approved', 'rejected'].includes(data.decision)) {
    throw new HttpsError('invalid-argument', 'Invalid decision');
  }
  const db = getFirestore(), group = db.collection('groups').doc(data.groupID);
  const proStatus = data.decision === 'approved' ? await proStatusForUser(data.applicantID) : 'inactive';
  return db.runTransaction(async tx => {
    const {groupSnapshot, application} = await authorizedApplication(tx, group, request.auth.uid, data);
    if (application.data().status === data.decision) return {status: data.decision};
    if (application.data().status !== 'pending') {
      throw new HttpsError('failed-precondition', 'Application already reviewed');
    }
    const memberRef = group.collection('members').doc(data.applicantID);
    const member = await tx.get(memberRef);
    if (data.decision === 'approved') {
      const groupData = groupSnapshot.data();
      if (groupData.settledAt || !groupData.deadline?.toMillis || groupData.deadline.toMillis() <= Date.now()) {
        throw new HttpsError('failed-precondition', 'Group is closed', {reason: 'group-closed'});
      }
      if (!member.exists) {
        await enforceProjectQuota(db, tx, data.applicantID, proStatus);
        tx.create(memberRef, {
          userID: data.applicantID, displayName: application.data().applicantName, role: 'member',
          joinedAt: FieldValue.serverTimestamp(), leaderElectionID: groupData.leaderElectionID || null,
          leaderVoteUID: null,
        });
        tx.update(group, {membershipUpdatedAt: FieldValue.serverTimestamp()});
      }
    }
    const result = {...application.data(), status: data.decision, reviewedBy: request.auth.uid,
      reviewedAt: FieldValue.serverTimestamp()};
    tx.set(application.ref, result);
    tx.set(db.collection('users').doc(data.applicantID).collection('groupJoinRequests').doc(data.groupID), result);
    return {status: data.decision};
  });
});

// Return only published score summaries. Raw reviews, comments and reviewer identities stay private.
exports.getJoinApplicantProfile = onCall({region}, async request => {
  const data = input(request, ['groupID', 'applicantID', 'requestID']);
  const db = getFirestore(), group = db.collection('groups').doc(data.groupID);
  return db.runTransaction(async tx => {
    const {application} = await authorizedApplication(tx, group, request.auth.uid, data);
    if (application.data().status !== 'pending') {
      throw new HttpsError('failed-precondition', 'Application no longer pending');
    }
    const history = await tx.get(db.collection('users').doc(data.applicantID).collection('peerReviewProjects'));
    const projects = history.docs.filter(doc => doc.data().reviewCount > 0).map(doc => {
      const p = doc.data(), count = p.reviewCount;
      const result = {groupID: p.groupID || doc.id, groupName: p.groupName || '',
        completedAtMillis: p.completedAt?.toMillis() || 0, reviewCount: count,
        acceptedReviewCount: p.acceptedReviewCount ?? count, excludedReviewCount: p.excludedReviewCount ?? 0};
      for (const key of ['taskCompletion', 'discussion', 'collaboration', 'idea', 'reliability']) {
        result[`${key}Score`] = p[`${key}Score`] ?? (p[`${key}ScoreTotal`] || 0) / count;
      }
      return result;
    });
    return {projects};
  });
});
