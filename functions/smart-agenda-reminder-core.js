const {createHash} = require('node:crypto');
const {activeMaterials, materialsForMember} = require('./smart-agenda-core');

const leadTime = 30 * 60 * 1000;
function meetingMillis(agenda) { return agenda?.meetingAt?.toMillis?.(); }
function isReminderDue(agenda, now) {
  const at = meetingMillis(agenda);
  return typeof agenda?.topic === 'string' && agenda.topic.trim().length > 0
    && Number.isFinite(at) && at > now && at - now <= leadTime && !agenda.meetingStartedAt;
}
function reminderID(path, at) {
  // Material/topic edits and scheduler retries must not send another reminder for the same start time.
  return `agenda-${createHash('sha256').update(`${path}/${at}`).digest('hex').slice(0, 32)}`;
}
function buildReminder(agenda, members) {
  const materials = activeMaterials(agenda.materials, members);
  const preparedNames = [], missingNames = [];
  for (const member of [...members].sort((a,b) => a.id.localeCompare(b.id))) {
    const name = member.displayName?.trim() || member.email?.trim() || '成員';
    (materialsForMember(materials, member.id).length ? preparedNames : missingNames).push(name);
  }
  const stages = (agenda.stages || []).slice(0, 4).filter(stage => typeof stage.title === 'string' && stage.title.trim());
  return {
    topic: agenda.topic, meetingAtMillis: meetingMillis(agenda), duration: agenda.duration,
    preparedNames, missingNames,
    discussionTitles: stages.map(stage => stage.title),
    discussionTitlesZhHant: stages.map(stage => stage.titleZhHant || stage.title),
  };
}
function shortNames(names) {
  return names.slice(0, 4).join('、') + (names.length > 4 ? `等 ${names.length} 人` : '');
}
function fallbackText(summary) {
  const date = new Intl.DateTimeFormat('zh-TW', {timeZone:'Asia/Taipei', month:'numeric', day:'numeric', hour:'2-digit', minute:'2-digit', hour12:false})
    .format(new Date(summary.meetingAtMillis));
  const count = summary.preparedNames.length, total = count + summary.missingNames.length;
  const parts = [`會前提醒：「${summary.topic}」將於 ${date} 開始，預計 ${summary.duration} 分鐘。`];
  if (count) parts.push(`會前資料已提交 ${count}/${total} 人（${shortNames(summary.preparedNames)}）。`);
  if (summary.missingNames.length) parts.push(`尚未提交筆記或附件：${shortNames(summary.missingNames)}。`);
  else parts.push('全員已完成會前準備。');
  if (summary.discussionTitlesZhHant.length) parts.push(`討論重點：${summary.discussionTitlesZhHant.join('、')}。`);
  return parts.join(' ');
}

async function publishReminder(db, ref, now, serverTimestamp) {
  const group = ref.parent.parent;
  if (ref.id !== 'current' || group?.parent.id !== 'groups') return false;
  return db.runTransaction(async tx => {
    const [snapshot, parent, membership] = await Promise.all([
      tx.get(ref), tx.get(group), tx.get(group.collection('members')),
    ]);
    const agenda = snapshot.data();
    // Re-read the live date and membership: a reschedule or exit can race the scheduled query.
    if (!snapshot.exists || !parent.exists || parent.data().deleting || membership.empty || !isReminderDue(agenda, now)) return false;
    const id = reminderID(ref.path, meetingMillis(agenda)), message = group.collection('messages').doc(id);
    if ((await tx.get(message)).exists) return false;
    const summary = buildReminder(agenda, membership.docs.map(member => ({...member.data(), id:member.id})));
    tx.create(message, {id, senderID:'smart-agenda', senderName:'自動化議程', kind:'agendaReminder',
      text:fallbackText(summary), agendaSummary:summary, createdAt:serverTimestamp()});
    return true;
  });
}
module.exports = {leadTime, isReminderDue, reminderID, buildReminder, fallbackText, publishReminder};
