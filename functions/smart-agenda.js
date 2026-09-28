const {randomUUID} = require('node:crypto');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {membershipVersion, membershipSignature, materialsForMember, invalidateAgenda, timedStages} = require('./smart-agenda-core');
const region = 'asia-east1';
const types = {
  png:'image/png', jpg:'image/jpeg', jpeg:'image/jpeg', pdf:'application/pdf',
  docx:'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  pptx:'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  xlsx:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  zip:'application/zip', mov:'video/quicktime', mp4:'video/mp4',
};
const keysByAction = {
  createMeeting:['topic','meetingAtMillis','duration','expectedRevision'],
  deleteMeeting:['expectedRevision'],
  meeting:['topic','meetingAtMillis','duration','expectedRevision'],
  material:['note','attachment','expectedRevision'], retry:[],
  link:['linkID','title','url','expectedRevision'],
  start:['inputRevision'], end:['inputRevision'],
  claimPlan:['inputRevision','token'], completePlan:['inputRevision','token','phases'],
  failPlan:['inputRevision','token'],
};
function requireRequest(request) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated','Please sign in.');
  const d = request.data;
  const recordKey = d?.action === 'material' && Object.hasOwn(d, 'materialID') ? ['materialID'] : [];
  const agendaKey = d && Object.hasOwn(d, 'agendaID') ? ['agendaID'] : [];
  if (!d || typeof d !== 'object' || !/^[a-f0-9-]{36}$/.test(d.groupID)
      || (agendaKey.length && (typeof d.agendaID !== 'string' || (d.agendaID !== 'current' && !/^[a-f0-9-]{36}$/.test(d.agendaID))))
      || !Object.hasOwn(keysByAction, d.action)
      || Object.keys(d).sort().join('|') !== ['groupID','action',...keysByAction[d.action],...recordKey,...agendaKey].sort().join('|')) {
    throw new HttpsError('invalid-argument','Invalid agenda request.');
  }
  return d;
}
async function checkAttachment(value, groupID, uid) {
  if (value == null) return null;
  if (typeof value !== 'object' || Object.keys(value).sort().join('|') !== 'byteSize|contentType|fileName|storagePath'
      || typeof value.fileName !== 'string' || !value.fileName.trim() || value.fileName.length > 255
      || !Number.isInteger(value.byteSize) || value.byteSize < 1 || value.byteSize > 20*1024*1024) {
    throw new HttpsError('invalid-argument','Invalid attachment.');
  }
  const prefix = `groups/${groupID}/agendaMaterials/${uid}/`;
  if (typeof value.storagePath !== 'string' || !value.storagePath.startsWith(prefix)
      || !/^[a-f0-9-]{36}\/file\.(png|jpe?g|pdf|docx|pptx|xlsx|zip|mov|mp4)$/.test(value.storagePath.slice(prefix.length))) {
    throw new HttpsError('invalid-argument','Invalid attachment path.');
  }
  const ext = value.storagePath.split('.').at(-1);
  if (value.contentType !== types[ext]) throw new HttpsError('invalid-argument','File type does not match.');
  let metadata;
  try { [metadata] = await getStorage().bucket().file(value.storagePath).getMetadata(); }
  catch (error) {
    if (Number(error.code) === 404) throw new HttpsError('failed-precondition','Attachment is no longer available. Choose the file again.');
    throw error;
  }
  if (Number(metadata.size) !== value.byteSize || metadata.contentType !== value.contentType
      || metadata.metadata?.uploaderID !== uid) throw new HttpsError('failed-precondition','Upload is incomplete.');
  return value;
}

exports.updateSmartAgenda = onCall({region}, async request => {
  const d = requireRequest(request), uid = request.auth.uid, db = getFirestore();
  const group = db.collection('groups').doc(d.groupID), ref = group.collection('smartAgenda').doc(d.agendaID ?? 'current');
  // Authorize before inspecting an object; repeat inside the transaction for concurrent exits.
  if (!(await group.collection('members').doc(uid).get()).exists) throw new HttpsError('permission-denied','Membership required.');
  const attachment = d.action === 'material' ? await checkAttachment(d.attachment, d.groupID, uid) : null;
  return db.runTransaction(async tx => {
    const [parent, snapshot, membership] = await Promise.all([tx.get(group),tx.get(ref),tx.get(group.collection('members'))]);
    const members = membership.docs.map(m => ({...m.data(), id:m.id})), caller = members.find(m => m.id === uid);
    if (!parent.exists || parent.data().deleting || !caller) throw new HttpsError('permission-denied','Membership required.');
    const current = snapshot.data() || {materials:{}, meetingRevision:null};
    if (['createMeeting','deleteMeeting','meeting'].includes(d.action) && caller.role !== 'leader') {
      throw new HttpsError('permission-denied','Only the leader can manage meetings.');
    }
    if (current.deleted) {
      if (d.action === 'deleteMeeting') return {saved:true};
      throw new HttpsError('not-found','This agenda was deleted.');
    }
    if (d.action === 'deleteMeeting') {
      if (!snapshot.exists) return {saved:true};
      if (d.expectedRevision !== current.meetingRevision) throw new HttpsError('aborted','Meeting changed. Reopen the editor.');
      // Keep only a tombstone so delayed create/save retries cannot resurrect a deleted meeting.
      tx.set(ref, {deleted:true, updatedAt:FieldValue.serverTimestamp()});
      return {saved:true};
    }
    if (!snapshot.exists && d.action !== 'createMeeting' && !(d.action === 'meeting' && !d.agendaID)) {
      throw new HttpsError('not-found','This agenda was deleted.');
    }
    const changedMembers = current.membershipSignature !== membershipSignature(members);
    let agenda = changedMembers ? invalidateAgenda(current, members) : current;
    const write = value => tx.set(ref, {...value, updatedAt:FieldValue.serverTimestamp()});
    if (d.action === 'meeting' || d.action === 'createMeeting') {
      if (typeof d.topic !== 'string' || !d.topic.trim() || d.topic.length > 120
          || !Number.isFinite(d.meetingAtMillis) || d.meetingAtMillis < 0
          || !Number.isInteger(d.duration) || d.duration < 5 || d.duration > 180) {
        throw new HttpsError('invalid-argument','Enter a topic, meeting date and 5–180 minute duration.');
      }
      if (current.topic === d.topic.trim() && current.duration === d.duration
          && Math.abs(current.meetingAt.toMillis() - d.meetingAtMillis) < 1) {
        if (changedMembers) write(agenda);
        return {saved:true};
      }
      if (d.action === 'createMeeting' && snapshot.exists) throw new HttpsError('already-exists','This agenda already exists.');
      if (agenda.meetingStartedAt) throw new HttpsError('failed-precondition','End the meeting before editing its settings.');
      if (d.expectedRevision !== current.meetingRevision) throw new HttpsError('aborted','Meeting changed. Reopen the editor.');
      write(invalidateAgenda({...agenda, topic:d.topic.trim(), meetingAt:Timestamp.fromMillis(d.meetingAtMillis),
        duration:d.duration, meetingRevision:randomUUID()}, members));
      return {saved:true};
    }
    if (!agenda.topic) throw new HttpsError('failed-precondition','The leader must set a meeting first.');
    if (d.action === 'link') {
      if (typeof d.linkID !== 'string' || !/^[a-f0-9-]{36}$/.test(d.linkID)
          || typeof d.title !== 'string' || d.title.length > 120
          || typeof d.url !== 'string' || d.url.length > 2048) {
        throw new HttpsError('invalid-argument','Enter a link title up to 120 characters and a valid HTTP or HTTPS URL.');
      }
      const title = d.title.trim(), url = d.url.trim(), links = {...agenda.links};
      if (url) {
        let parsed;
        try { parsed = new URL(url); } catch {}
        if (!parsed || !['https:','http:'].includes(parsed.protocol) || !parsed.hostname
            || parsed.username || parsed.password || /\s/.test(url)) {
          throw new HttpsError('invalid-argument','Enter a valid HTTP or HTTPS URL.');
        }
      }
      const own = links[d.linkID];
      if (own && own.ownerUID !== uid && caller.role !== 'leader') {
        throw new HttpsError('permission-denied','You can only edit your own meeting links.');
      }
      const unchanged = own && own.title === title && own.url === url;
      const alreadyRemoved = !own && typeof d.expectedRevision === 'string' && d.expectedRevision.length > 0 && !url && !title;
      if (d.expectedRevision !== (own?.revision || null) && !unchanged && !alreadyRemoved) {
        throw new HttpsError('aborted','Meeting link changed. Reopen the editor.');
      }
      if (unchanged || alreadyRemoved) {
        if (changedMembers) write(agenda);
        return {saved:true};
      }
      if (!own && !url) throw new HttpsError('invalid-argument','Enter a valid HTTP or HTTPS URL.');
      if (!own && Object.keys(links).length >= 20) throw new HttpsError('resource-exhausted','A meeting can have up to 20 links.');
      if (url) links[d.linkID] = {title,url,ownerUID:own?.ownerUID ?? uid,
        createdAtMillis:own?.createdAtMillis ?? Date.now(),revision:randomUUID()};
      else delete links[d.linkID];
      // Shared room/resources are separate from preparation and must not reset or regenerate a plan.
      write({...agenda,links});
      return {saved:true};
    }
    if (d.action === 'material') {
      if (typeof d.note !== 'string' || d.note.length > 1000) throw new HttpsError('invalid-argument','Note must be 1000 characters or less.');
      const materialID = d.materialID ?? uid; // Retain support for the previously installed app.
      if (typeof materialID !== 'string' || (!/^[a-f0-9-]{36}$/.test(materialID) && materialID !== uid)) {
        throw new HttpsError('invalid-argument','Invalid material.');
      }
      const own = agenda.materials[materialID];
      if (own && (own.ownerUID || materialID) !== uid) throw new HttpsError('permission-denied','You can only edit your own material.');
      const unchanged = own && own.note === d.note.trim()
        && (attachment ? own.attachment && Object.keys(attachment).every(key => own.attachment[key] === attachment[key]) : !own.attachment);
      const alreadyRemoved = !own && typeof d.expectedRevision === 'string' && d.expectedRevision.length > 0
        && !d.note.trim() && !attachment;
      // Retrying the same committed result is safe; a stale request with different content is not.
      if (d.expectedRevision !== (own?.revision || null) && !unchanged && !alreadyRemoved) {
        throw new HttpsError('aborted','Your material changed. Reopen the editor.');
      }
      if (unchanged || alreadyRemoved) {
        if (changedMembers) write(agenda);
        return {saved:true};
      }
      if (!own && !d.note.trim() && !attachment) throw new HttpsError('invalid-argument','Add a note or attachment.');
      const materials = {...agenda.materials};
      if (d.note.trim() || attachment) materials[materialID] = {note:d.note.trim(), attachment, ownerUID:uid,
        createdAtMillis:own?.createdAtMillis ?? (own ? 0 : Date.now()),
        revision:randomUUID(), membershipVersion:membershipVersion(caller)};
      else delete materials[materialID];
      write(invalidateAgenda({...agenda, materials}, members));
      return {saved:true};
    }
    const allPrepared = members.length > 0 && agenda.preparedUIDs?.length === members.length;
    if (['claimPlan','completePlan','failPlan'].includes(d.action)) {
      if (typeof d.token !== 'string' || !/^[a-f0-9-]{36}$/.test(d.token)) {
        throw new HttpsError('invalid-argument','Invalid generation token.');
      }
      if (changedMembers || d.inputRevision !== agenda.inputRevision || !allPrepared) {
        throw new HttpsError('failed-precondition','Preparation changed. Reopen the agenda.');
      }
      const lease = agenda.generation;
      const ownsLease = lease?.ownerUID === uid && lease.token === d.token;
      if (d.action === 'claimPlan') {
        if (agenda.stages?.length) return {status:'ready'};
        // Legacy cloud leases have no ownerUID and must not block the on-device replacement.
        if (lease?.ownerUID && lease.expiresAt.toMillis() > Date.now() && !ownsLease) return {status:'busy'};
        if (!ownsLease || lease.expiresAt.toMillis() <= Date.now()) {
          write({...agenda,planState:'generating',planError:null,lastGenerationAt:FieldValue.serverTimestamp(),
            generation:{token:d.token,ownerUID:uid,inputRevision:agenda.inputRevision,
              expiresAt:Timestamp.fromMillis(Date.now()+300000)}});
        }
        return {status:'claimed',input:{topic:agenda.topic,duration:agenda.duration,
          members:members.map((m,index)=>({member:index+1,materials:materialsForMember(agenda.materials,m.id)
            .map(material=>({note:material.note,fileName:material.attachment?.fileName || ''}))}))}};
      }
      // Retrying a committed upload after a lost response must not replace the result.
      if (d.action === 'completePlan' && agenda.completedGeneration?.token === d.token
          && agenda.completedGeneration.ownerUID === uid && agenda.stages?.length) return {saved:true};
      if (!ownsLease || lease.expiresAt.toMillis() <= Date.now()) {
        throw new HttpsError('failed-precondition','Generation expired. Please try again.');
      }
      if (d.action === 'failPlan') {
        write({...agenda,planState:'failed',planError:'unavailable',generation:null});
        return {saved:true};
      }
      let stages;
      try {
        stages = timedStages(d.phases, agenda.duration);
        if (stages.some(stage=>!stage.titleZhHant || !stage.goalZhHant)) throw Error('Missing translation');
      } catch {
        throw new HttpsError('invalid-argument','Provide 3–4 stages with goals and both languages.');
      }
      write({...agenda,stages,planState:'ready',planError:null,generation:null,
        planSource:'appleIntelligence',planModel:'SystemLanguageModel.default',
        completedGeneration:{token:d.token,ownerUID:uid}});
      return {saved:true};
    }
    if (d.action === 'retry') {
      if (!allPrepared || agenda.stages?.length) throw new HttpsError('failed-precondition','Everyone must prepare first.');
      if (agenda.generation?.expiresAt.toMillis() > Date.now()
          || (agenda.lastGenerationAt?.toMillis() || 0) > Date.now()-60000) {
        throw new HttpsError('resource-exhausted','Please wait a minute before trying again.');
      }
      write({...agenda,planState:'waiting',planError:null,generation:null,generationRequest:randomUUID()});
      return {queued:true};
    }
    if (d.action === 'end') {
      if (caller.role !== 'leader') throw new HttpsError('permission-denied','Only the leader can end the meeting.');
      if (!agenda.meetingStartedAt) {
        if (changedMembers) write(agenda);
        return {saved:true};
      }
      if (d.inputRevision !== agenda.inputRevision) throw new HttpsError('failed-precondition','The meeting plan is not ready.');
      if (agenda.preparationChangedDuringMeeting) write(invalidateAgenda({...agenda, meetingStartedAt:null}, members));
      else write({...agenda, meetingStartedAt:null});
      return {saved:true};
    }
    if (d.action === 'start' && caller.role !== 'leader') throw new HttpsError('permission-denied','Only the leader can start the meeting.');
    if (changedMembers || d.inputRevision !== agenda.inputRevision || !allPrepared || !agenda.stages?.length) {
      throw new HttpsError('failed-precondition','The meeting plan is not ready.');
    }
    if (d.action === 'start' && !agenda.meetingStartedAt) write({...agenda, meetingStartedAt:FieldValue.serverTimestamp()});
    return {saved:true};
  });
});

// Retain the deployed trigger during the provider transition. It is deliberately inert:
// devices now generate plans and completePlan validates/shares them; no cloud AI call or secret.
exports.generateSmartAgendaPlan = onDocumentWritten({region,document:'groups/{groupID}/smartAgenda/current'}, async () => {});

// Joining/leaving changes the denominator and invalidates an old plan. Profile/role edits do not.
exports.syncAgendaMembership = onDocumentWritten({region, document:'groups/{groupID}/members/{uid}', retry:true}, async event => {
  if (event.data.before.exists && event.data.after.exists
      && membershipVersion(event.data.before.data()) === membershipVersion(event.data.after.data())) return;
  const db = getFirestore(), group = db.collection('groups').doc(event.params.groupID);
  await db.runTransaction(async tx => {
    const [agendas, members] = await Promise.all([tx.get(group.collection('smartAgenda')),tx.get(group.collection('members'))]);
    const participants = members.docs.map(m => ({...m.data(),id:m.id}));
    for (const agenda of agendas.docs) {
      if (agenda.data().deleted || agenda.data().membershipSignature === membershipSignature(participants)) continue;
      tx.set(agenda.ref, {...invalidateAgenda(agenda.data(), participants),updatedAt:FieldValue.serverTimestamp()});
    }
  });
});

async function cleanupAttachments(event) {
  const old = Object.values(event.data.before.data()?.materials || {}).map(m => m.attachment?.storagePath).filter(Boolean);
  if (!old.length) return;
  const agendas = await event.data.after.ref.parent.get();
  const retained = new Set(agendas.docs.flatMap(doc => Object.values(doc.data().materials || {}).map(m => m.attachment?.storagePath)));
  for (const path of old) {
    if (!retained.has(path) && path.startsWith(`groups/${event.params.groupID}/agendaMaterials/`)) {
      await getStorage().bucket().file(path).delete({ignoreNotFound:true});
    }
  }
}
exports.cleanupAgendaAttachments = onDocumentWritten({region, document:'groups/{groupID}/smartAgenda/current', retry:true}, cleanupAttachments);
exports.cleanupAdditionalAgendaAttachments = onDocumentWritten({region, document:'groups/{groupID}/smartAgenda/{agendaID}', retry:false}, async event => {
  if (event.params.agendaID !== 'current') await cleanupAttachments(event);
});
