const {HttpsError} = require('firebase-functions/v2/https');
const {randomUUID} = require('node:crypto');

const FREE_ACTIVE_PROJECT_LIMIT = 2;

// Call after the caller's other transaction reads and before any writes.
// Every membership-creating path must acquire this same per-user lock, so
// concurrent creates/approvals cannot both consume the last available slot.
async function enforceProjectQuota(db, tx, userID, proStatus = 'inactive') {
  const lock = db.collection('projectQuotaLocks').doc(userID);
  await tx.get(lock);
  const memberships = await tx.get(db.collectionGroup('members').where('userID', '==', userID));
  const ids = [...new Set(memberships.docs.filter(doc => {
    const parts = doc.ref.path.split('/');
    return parts.length === 4 && parts[0] === 'groups' && parts[2] === 'members' && parts[3] === userID;
  }).map(doc => doc.ref.path.split('/')[1]))];
  const groups = await Promise.all(ids.map(id => tx.get(db.collection('groups').doc(id))));
  const now = Date.now();
  const count = groups.filter(snapshot => {
    const group = snapshot.data();
    if (!group || group.deleting === true || group.settledAt != null) return false;
    // Corrupt/missing deadlines must not grant extra slots.
    const deadline = group.deadline?.toMillis?.();
    return !Number.isFinite(deadline) || deadline > now;
  }).length;
  if (count >= FREE_ACTIVE_PROJECT_LIMIT && proStatus === 'unknown') {
    throw new HttpsError('unavailable', 'Subscription status could not be verified.', {
      reason: 'subscription-verification-unavailable',
    });
  }
  if (count >= FREE_ACTIVE_PROJECT_LIMIT && proStatus !== 'active') {
    throw new HttpsError('resource-exhausted', 'Active project limit reached.', {
      reason: 'active-project-limit', limit: FREE_ACTIVE_PROJECT_LIMIT,
    });
  }
  tx.set(lock, {revision: randomUUID()});
}

module.exports = {enforceProjectQuota, FREE_ACTIVE_PROJECT_LIMIT};
