const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {leadTime, publishReminder} = require('./smart-agenda-reminder-core');

exports.publishAgendaReminders = onSchedule({region:'asia-east1', schedule:'every 1 minutes',
  timeZone:'UTC', timeoutSeconds:120, maxInstances:1, retryCount:3}, async () => {
  const db = getFirestore(), now = Date.now();
  const query = db.collectionGroup('smartAgenda')
    .where('meetingAt', '>', Timestamp.fromMillis(now))
    .where('meetingAt', '<=', Timestamp.fromMillis(now + leadTime))
    .orderBy('meetingAt').limit(100);
  let cursor;
  do {
    const page = await (cursor ? query.startAfter(cursor) : query).get();
    if (page.empty) break;
    for (const document of page.docs) {
      await publishReminder(db, document.ref, Date.now(), () => FieldValue.serverTimestamp());
    }
    cursor = page.size === 100 ? page.docs.at(-1) : null;
  } while (cursor);
});
