const {randomUUID} = require('node:crypto');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {defineSecret} = require('firebase-functions/params');
const {generatePlan, model} = require('./smart-agenda-ai');
const openAIKey = defineSecret('OPENAI_API_KEY');
const {membershipVersion, membershipSignature, materialsForMember, invalidateAgenda} = require('./smart-agenda-core');
const region = 'asia-east1';
const types = {
  png:'image/png', jpg:'image/jpeg', jpeg:'image/jpeg', pdf:'application/pdf',
  docx:'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  pptx:'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  xlsx:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  zip:'application/zip', mov:'video/quicktime', mp4:'video/mp4',
};
const keysByAction = {
  meeting:['topic','meetingAtMillis','duration','expectedRevision'],
  material:['note','attachment','expectedRevision'], retry:[],
  link:['linkID','title','url','expectedRevision'],
  start:['inputRevision'], end:['inputRevision'],
};
function requireRequest(request) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated','Please sign in.');
  const d = request.data;
  const recordKey = d?.action === 'material' && Object.hasOwn(d, 'materialID') ? ['materialID'] : [];
  if (!d || typeof d !== 'object' || !/^[a-f0-9-]{36}$/.test(d.groupID)
      || !Object.hasOwn(keysByAction, d.action)
      || Object.keys(d).sort().join('|') !== ['groupID','action',...keysByAction[d.action],...recordKey].sort().join('|')) {
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
  const group = db.collection('groups').doc(d.groupID), ref = group.collection('smartAgenda').doc('current');
  // Authorize before inspecting an object; repeat inside the transaction for concurrent exits.
  if (!(await group.collection('members').doc(uid).get()).exists) throw new HttpsError('permission-denied','Membership required.');
  const attachment = d.action === 'material' ? await checkAttachment(d.attachment, d.groupID, uid) : null;
  return db.runTransaction(async tx => {
    const [parent, snapshot, membership] = await Promise.all([tx.get(group),tx.get(ref),tx.get(group.collection('members'))]);
    const members = membership.docs.map(m => ({...m.data(), id:m.id})), caller = members.find(m => m.id === uid);
    if (!parent.exists || parent.data().deleting || !caller) throw new HttpsError('permission-denied','Membership required.');
    const current = snapshot.data() || {materials:{}, meetingRevision:null};
    const changedMembers = current.membershipSignature !== membershipSignature(members);
    let agenda = changedMembers ? invalidateAgenda(current, members) : current;
    const write = value => tx.set(ref, {...value, updatedAt:FieldValue.serverTimestamp()});
    if (d.action === 'meeting') {
      if (caller.role !== 'leader') throw new HttpsError('permission-denied','Only the leader can edit the meeting.');
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
    if (d.action === 'retry') {
      if (!allPrepared || agenda.stages?.length) throw new HttpsError('failed-precondition','Everyone must prepare first.');
      if (agenda.generation?.expiresAt.toMillis() > Date.now()
          || (agenda.lastGenerationAt?.toMillis() || 0) > Date.now()-60000) {
        throw new HttpsError('resource-exhausted','Please wait a minute before trying again.');
      }
      write({...agenda,planState:'waiting',planError:null,generation:null,generationRequest:randomUUID()});
      return {queued:true};
    }
    if (changedMembers || d.inputRevision !== agenda.inputRevision || !allPrepared || !agenda.stages?.length) {
      throw new HttpsError('failed-precondition','The meeting plan is not ready.');
    }
    if (d.action === 'start' && !agenda.meetingStartedAt) write({...agenda, meetingStartedAt:FieldValue.serverTimestamp()});
    if (d.action === 'end') {
      if (caller.role !== 'leader') throw new HttpsError('permission-denied','Only the leader can end the meeting.');
      write({...agenda, meetingStartedAt:null});
    }
    return {saved:true};
  });
});

// Only the server can create a plan. Duplicate events share a lease; stale responses are discarded.
exports.generateSmartAgendaPlan = onDocumentWritten({region,document:'groups/{groupID}/smartAgenda/current',
  secrets:[openAIKey],timeoutSeconds:120,maxInstances:3,retry:false}, async event => {
  const after = event.data.after.data();
  if (!after || after.planState !== 'waiting' || !after.topic || after.stages?.length
      || !after.memberUIDs?.length || after.preparedUIDs?.length !== after.memberUIDs.length) return;
  const db=getFirestore(), ref=event.data.after.ref, group=ref.parent.parent;
  const claim = await db.runTransaction(async tx=>{
    const [snap,parent,membership]=await Promise.all([tx.get(ref),tx.get(group),tx.get(group.collection('members'))]);
    if (!snap.exists || !parent.exists || parent.data().deleting) return null;
    const agenda=snap.data(), members=membership.docs.map(m=>({...m.data(),id:m.id}));
    if (agenda.membershipSignature !== membershipSignature(members)) {
      tx.set(ref,{...invalidateAgenda(agenda,members),updatedAt:FieldValue.serverTimestamp()}); return null;
    }
    if (agenda.planState !== 'waiting' || agenda.stages?.length || !members.length
        || agenda.preparedUIDs?.length !== members.length) return null;
    const token=randomUUID();
    tx.update(ref,{planState:'generating',planError:null,lastGenerationAt:FieldValue.serverTimestamp(),
      generation:{token,inputRevision:agenda.inputRevision,expiresAt:Timestamp.fromMillis(Date.now()+180000)}});
    return {token,revision:agenda.inputRevision,signature:agenda.membershipSignature,input:{topic:agenda.topic,duration:agenda.duration,
      members:members.map((m,index)=>({member:index+1,materials:materialsForMember(agenda.materials,m.id)
        .map(material=>({note:material.note,fileName:material.attachment?.fileName || ''}))}))}};
  });
  if (!claim) return;
  let stages, errorCode;
  try { stages=await generatePlan(claim.input,openAIKey.value()); }
  catch(error) {
    errorCode=['quota','configuration','unavailable','invalid-plan'].includes(error.code) ? error.code : 'unavailable';
    console.warn('Agenda generation failed',{groupID:event.params.groupID,code:errorCode});
  }
  await db.runTransaction(async tx=>{
    const [snap,parent,membership]=await Promise.all([tx.get(ref),tx.get(group),tx.get(group.collection('members'))]);
    if (!snap.exists || !parent.exists || parent.data().deleting) return;
    const current=snap.data(),members=membership.docs.map(m=>({...m.data(),id:m.id}));
    if (current.generation?.token !== claim.token || current.inputRevision !== claim.revision) return;
    if (membershipSignature(members) !== claim.signature) {
      tx.set(ref,{...invalidateAgenda(current,members),updatedAt:FieldValue.serverTimestamp()}); return;
    }
    tx.update(ref,{stages:stages || [],planState:stages ? 'ready' : 'failed',planError:errorCode || null,
      generation:null,planSource:stages ? 'openai' : null,planModel:stages ? model : null,updatedAt:FieldValue.serverTimestamp()});
  });
});

// Joining/leaving changes the denominator and invalidates an old plan. Profile/role edits do not.
exports.syncAgendaMembership = onDocumentWritten({region, document:'groups/{groupID}/members/{uid}', retry:true}, async event => {
  if (event.data.before.exists && event.data.after.exists
      && membershipVersion(event.data.before.data()) === membershipVersion(event.data.after.data())) return;
  const db = getFirestore(), group = db.collection('groups').doc(event.params.groupID);
  const ref = group.collection('smartAgenda').doc('current');
  await db.runTransaction(async tx => {
    const [agenda, members] = await Promise.all([tx.get(ref),tx.get(group.collection('members'))]);
    if (!agenda.exists) return;
    const participants = members.docs.map(m => ({...m.data(),id:m.id}));
    if (agenda.data().membershipSignature === membershipSignature(participants)) return;
    tx.set(ref, {...invalidateAgenda(agenda.data(), participants),updatedAt:FieldValue.serverTimestamp()});
  });
});

exports.cleanupAgendaAttachments = onDocumentWritten({region, document:'groups/{groupID}/smartAgenda/current', retry:true}, async event => {
  const old = Object.values(event.data.before.data()?.materials || {}).map(m => m.attachment?.storagePath).filter(Boolean);
  const latest = await event.data.after.ref.get();
  const retained = new Set(Object.values(latest.data()?.materials || {}).map(m => m.attachment?.storagePath));
  for (const path of old) {
    if (!retained.has(path) && path.startsWith(`groups/${event.params.groupID}/agendaMaterials/`)) {
      await getStorage().bucket().file(path).delete({ignoreNotFound:true});
    }
  }
});
