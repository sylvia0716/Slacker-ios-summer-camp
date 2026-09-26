const {randomUUID} = require('node:crypto');

function membershipVersion(member) {
  const date = member.joinedAt;
  return date ? `${date.seconds ?? date._seconds}.${date.nanoseconds ?? date._nanoseconds}` : 'legacy';
}
function membershipSignature(members) {
  return members.map(m => `${m.id}:${membershipVersion(m)}`).sort().join('|');
}
function activeMaterials(materials, members) {
  const participants = new Map(members.map(member => [member.id, member]));
  return Object.fromEntries(Object.entries(materials || {}).filter(([id, value]) => {
    // Earlier records used the owner's UID as their key. Keep those records intact.
    const member = participants.get(value.ownerUID || id);
    return member && value.membershipVersion === membershipVersion(member)
      && (value.note?.trim() || value.attachment);
  }));
}
function materialsForMember(materials, uid) {
  return Object.entries(materials || {}).filter(([id, value]) => (value.ownerUID || id) === uid)
    .sort(([a, x], [b, y]) => (x.createdAtMillis || 0) - (y.createdAtMillis || 0) || a.localeCompare(b))
    .map(([, value]) => value);
}
function invalidateAgenda(agenda, members) {
  const materials = activeMaterials(agenda.materials, members);
  return {...agenda, materials, memberUIDs: members.map(m => m.id).sort(),
    preparedUIDs: [...new Set(Object.entries(materials).map(([id, value]) => value.ownerUID || id))].sort(),
    membershipSignature: membershipSignature(members),
    inputRevision: randomUUID(), stages: [], planState: 'waiting', generation: null, planError: null, planSource: null,
    meetingStartedAt: null};
}
// The model supplies priorities in minutes; allocate integer slots without gaps or lost minutes.
function timedStages(phases, duration) {
  if (!Number.isInteger(duration) || duration < 5 || duration > 180 || !Array.isArray(phases)
      || phases.length < 3 || phases.length > 4) throw Error('Invalid meeting plan');
  for (const phase of phases) {
    if (!phase || typeof phase.title !== 'string' || !phase.title.trim() || phase.title.length > 160
        || typeof phase.goal !== 'string' || !phase.goal.trim() || phase.goal.length > 300
        || !Number.isInteger(phase.minutes) || phase.minutes < 1 || phase.minutes > 180) {
      throw Error('Each stage needs a discussion, concrete goal and positive duration');
    }
    if (phase.titleZhHant != null || phase.goalZhHant != null) {
      if (typeof phase.titleZhHant !== 'string' || !phase.titleZhHant.trim() || phase.titleZhHant.length > 160
          || typeof phase.goalZhHant !== 'string' || !phase.goalZhHant.trim() || phase.goalZhHant.length > 300) {
        throw Error('Invalid plan translation');
      }
    }
  }
  const total = phases.reduce((sum, p) => sum + p.minutes, 0);
  const slots = phases.map(p => 1 + (duration - phases.length) * p.minutes / total);
  const minutes = slots.map(Math.floor);
  const order = slots.map((value, i) => ({i, remainder: value - minutes[i]}))
    .sort((a,b) => b.remainder - a.remainder || a.i - b.i);
  const remaining = duration - minutes.reduce((a,b) => a+b, 0);
  for (let i=0; i<remaining; i++) minutes[order[i].i]++;
  // Preserve a valid exact allocation rather than unnecessarily reweighting it.
  if (total === duration) phases.forEach((p,i) => { minutes[i] = p.minutes; });
  let start = 0;
  return phases.map((phase,i) => {
    const end = start + minutes[i];
    const stage = {start, end, title: phase.title.trim(), goal: phase.goal.trim()};
    if (phase.titleZhHant != null) {
      stage.titleZhHant = phase.titleZhHant.trim();
      stage.goalZhHant = phase.goalZhHant.trim();
    }
    start = end;
    return stage;
  });
}
module.exports = {membershipVersion, membershipSignature, activeMaterials, materialsForMember, invalidateAgenda, timedStages};
