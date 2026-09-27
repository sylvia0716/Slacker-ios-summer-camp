const {test} = require('node:test');
const assert = require('node:assert/strict');
const {leadTime, isReminderDue, reminderID, buildReminder, fallbackText} = require('./smart-agenda-reminder-core');
const now = 1790751600000;
const meeting = delta => ({topic:'Demo',duration:20,meetingAt:{toMillis:()=>now+delta}});

test('reminders start at 30 minutes, never before or after the meeting starts', () => {
  assert.equal(isReminderDue(meeting(leadTime + 1), now), false);
  assert.equal(isReminderDue(meeting(leadTime), now), true);
  assert.equal(isReminderDue(meeting(1), now), true);
  assert.equal(isReminderDue(meeting(0), now), false);
  assert.equal(isReminderDue(meeting(-1), now), false);
  assert.equal(isReminderDue({...meeting(leadTime), meetingStartedAt:{}}, now), false);
  assert.equal(isReminderDue({topic:'Demo'}, now), false);
});
test('reminders distinguish prepared material from missing material without demanding both fields', () => {
  const members = ['a','b','c','rejoined'].map(id => ({id,displayName:id}));
  members[3].joinedAt = {seconds:200,nanoseconds:0};
  const agenda = {...meeting(leadTime),preparedUIDs:['a','b','c','rejoined','departed'],materials:{
    a:{note:'Note alone is enough',membershipVersion:'legacy'},
    file:{ownerUID:'b',note:'',attachment:{fileName:'Slides.pdf'},membershipVersion:'legacy'},
    c:{note:'  ',membershipVersion:'legacy'},
    rejoined:{note:'Old membership',membershipVersion:'100.0'},
    departed:{note:'No longer a member',membershipVersion:'legacy'},
  }};
  const summary = buildReminder(agenda, members);
  assert.deepEqual(summary.preparedNames,['a','b']);
  assert.deepEqual(summary.missingNames,['c','rejoined']);
  assert(!fallbackText(summary).includes('departed'));
  assert(!fallbackText(summary).includes('全員已完成'));
});
test('all-prepared summaries include short discussion topics, not full notes or attachments', () => {
  const summary = buildReminder({...meeting(leadTime),materials:{a:{note:'Private full detail',membershipVersion:'legacy'}},
    stages:[{title:'Review',titleZhHant:'檢視',goal:'Long detailed goal'}]},[{id:'a',displayName:'Mia'}]);
  const text = fallbackText(summary);
  assert(text.includes('全員已完成會前準備'));
  assert(text.includes('檢視'));
  assert(!text.includes('Private full detail'));
  assert(!text.includes('Long detailed goal'));
  assert(!text.includes('\n'));
});
test('a start time identifies one reminder across topic/material edits and changes on reschedule', () => {
  assert.equal(reminderID('groups/a/smartAgenda/current',now),reminderID('groups/a/smartAgenda/current',now));
  assert.notEqual(reminderID('groups/a/smartAgenda/current',now),reminderID('groups/a/smartAgenda/current',now+1));
  assert.notEqual(reminderID('groups/a/smartAgenda/current',now),reminderID('groups/b/smartAgenda/current',now));
});
