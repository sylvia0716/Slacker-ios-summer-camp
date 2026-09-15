const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { randomBytes, randomUUID } = require("node:crypto");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

initializeApp();

const db = getFirestore();
const region = "asia-east1";

async function accountName(uid) {
  const user = await getAuth().getUser(uid);
  return (user.displayName?.trim() || user.email?.split('@')[0] || `成員 ${uid.slice(0, 8)}`).slice(0, 60);
}

function callableError(code, message, reason) {
  return new HttpsError(code, message, { reason });
}

function requireAuthenticatedUser(request) {
  const userID = request.auth?.uid;
  if (!userID) {
    throw callableError("unauthenticated", "Authentication required.", "not-authenticated");
  }
  return userID;
}

function normalizedInviteCode(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw callableError("invalid-argument", "Invalid request.", "invalid-request");
  }

  const keys = Object.keys(data);
  if (keys.length !== 1 || keys[0] !== "inviteCode" || typeof data.inviteCode !== "string") {
    throw callableError("invalid-argument", "Only inviteCode is accepted.", "invalid-request");
  }

  const inviteCode = data.inviteCode.trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(inviteCode)) {
    throw callableError("invalid-argument", "Invalid invite code.", "invite-code-not-found");
  }
  return inviteCode;
}

function normalizedCreateGroupData(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw callableError("invalid-argument", "Invalid request.", "invalid-request");
  }

  const keys = Object.keys(data).sort();
  if (keys.join(",") !== "deadlineMillis,displayName,name") {
    throw callableError("invalid-argument", "Only group creation fields are accepted.", "invalid-request");
  }

  const name = typeof data.name === "string" ? data.name.trim() : "";
  if (!name || name.length > 60) {
    throw callableError("invalid-argument", "Invalid group name.", "invalid-group-name");
  }

  const deadlineMillis = data.deadlineMillis;
  if (typeof deadlineMillis !== "number"
      || !Number.isFinite(deadlineMillis)
      || deadlineMillis <= Date.now()) {
    throw callableError("invalid-argument", "Invalid group deadline.", "invalid-group-deadline");
  }

  const requestedDisplayName = typeof data.displayName === "string"
    ? data.displayName.trim()
    : "";
  if (requestedDisplayName.length > 60) {
    throw callableError("invalid-argument", "Invalid display name.", "invalid-display-name");
  }

  return {
    name,
    deadlineMillis,
    displayName: requestedDisplayName || "組員",
  };
}

function normalizedCreateTaskData(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw callableError("invalid-argument", "Invalid request.", "invalid-task");
  }

  const keys = Object.keys(data).sort();
  if (keys.join(",") !== "assigneeUID,deadlineMillis,detail,groupID,title") {
    throw callableError("invalid-argument", "Only task creation fields are accepted.", "invalid-task");
  }

  const groupID = typeof data.groupID === "string" ? data.groupID.toLowerCase() : "";
  const title = typeof data.title === "string" ? data.title.trim() : "";
  const detail = typeof data.detail === "string" ? data.detail.trim() : "";
  const assigneeUID = typeof data.assigneeUID === "string" ? data.assigneeUID : "";
  const deadlineMillis = data.deadlineMillis;
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
  if (!uuid.test(groupID) || !title || title.length > 100 || detail.length > 1000
      || !assigneeUID || assigneeUID.length > 128 || typeof deadlineMillis !== "number"
      || !Number.isFinite(deadlineMillis) || deadlineMillis <= Date.now()) {
    throw callableError("invalid-argument", "Invalid task.", "invalid-task");
  }
  return { groupID, title, detail, assigneeUID, deadlineMillis };
}

function normalizedPokeData(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)
      || Object.keys(data).sort().join(",") !== "groupID,recipientUID,style") {
    throw callableError("invalid-argument", "Invalid poke.", "invalid-recipient");
  }
  const groupID = typeof data.groupID === "string" ? data.groupID.toLowerCase() : "";
  const recipientUID = typeof data.recipientUID === "string" ? data.recipientUID : "";
  const style = typeof data.style === "string" ? data.style : "";
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
  if (!uuid.test(groupID) || !recipientUID || recipientUID.length > 128
      || !["輕敲", "迷因轟炸", "警報催命"].includes(style)) {
    throw callableError("invalid-argument", "Invalid poke.", "invalid-recipient");
  }
  return { groupID, recipientUID, style };
}

function normalizedDeviceData(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)
      || Object.keys(data).sort().join(",") !== "deviceID,token") {
    throw callableError("invalid-argument", "Invalid device.", "invalid-device");
  }
  const deviceID = typeof data.deviceID === "string" ? data.deviceID : "";
  const token = typeof data.token === "string" ? data.token : "";
  if (!deviceID || deviceID.length > 128 || !token || token.length > 4096) {
    throw callableError("invalid-argument", "Invalid device.", "invalid-device");
  }
  return { deviceID, token };
}

function makeInviteCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from(randomBytes(6), byte => alphabet[byte % alphabet.length]).join("");
}

function millis(from) {
  if (from instanceof Timestamp) return from.toMillis();
  if (typeof from?.toMillis === "function") return from.toMillis();
  if (from instanceof Date) return from.getTime();
  if (typeof from === "number" && Number.isFinite(from)) return from;
  return null;
}

function groupPayload(groupID, data, inviteCode = "") {
  return {
    groupID,
    name: typeof data.name === "string" && data.name.trim() ? data.name.trim() : "未命名群組",
    deadlineMillis: millis(data.deadline),
    inviteCode: inviteCode || (typeof data.inviteCode === "string" ? data.inviteCode : ""),
  };
}

exports.createGroup = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  const { name, deadlineMillis, displayName } = normalizedCreateGroupData(request.data);
  const groupID = randomUUID().toLowerCase();
  const inviteCode = makeInviteCode();
  const deadline = Timestamp.fromMillis(deadlineMillis);
  const groupRef = db.collection("groups").doc(groupID);
  const memberRef = groupRef.collection("members").doc(userID);
  const inviteRef = db.collection("groupInviteCodes").doc(inviteCode);

  await db.runTransaction(async (transaction) => {
    const inviteSnapshot = await transaction.get(inviteRef);
    if (inviteSnapshot.exists) {
      throw callableError("aborted", "Invite code collision.", "invite-code-collision");
    }

    transaction.create(groupRef, {
      name,
      deadline,
      inviteCode,
      createdAt: FieldValue.serverTimestamp(),
      createdByUserID: userID,
    });
    transaction.create(memberRef, {
      userID,
      displayName,
      role: "leader",
      joinedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(inviteRef, {
      groupID,
      isActive: true,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return {
    group: groupPayload(groupID, { name, deadline, inviteCode }, inviteCode),
  };
});

exports.createTask = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  const { groupID, title, detail, assigneeUID, deadlineMillis } = normalizedCreateTaskData(request.data);
  const groupRef = db.collection("groups").doc(groupID);
  const taskID = randomUUID().toLowerCase();
  const taskRef = groupRef.collection("tasks").doc(taskID);

  await db.runTransaction(async transaction => {
    const [group, publisher, assignee] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(groupRef.collection("members").doc(userID)),
      transaction.get(groupRef.collection("members").doc(assigneeUID)),
    ]);
    if (!group.exists) {
      throw callableError("not-found", "Group not found.", "group-not-found");
    }
    if (publisher.data()?.userID !== userID) {
      throw callableError("permission-denied", "Membership required.", "not-group-member");
    }
    if (assignee.data()?.userID !== assigneeUID) {
      throw callableError("failed-precondition", "Assignee is not a group member.", "assignee-not-member");
    }
    const groupDeadlineMillis = millis(group.data().deadline);
    if (groupDeadlineMillis === null || deadlineMillis > groupDeadlineMillis) {
      throw callableError("failed-precondition", "Task deadline is invalid.", "invalid-task");
    }
    transaction.create(taskRef, {
      title,
      detail,
      groupID,
      weight: 1,
      ownerMemberID: assigneeUID,
      createdByMemberID: userID,
      subtasks: [{ id: randomUUID().toLowerCase(), title, isComplete: false, weight: 100 }],
      deadline: Timestamp.fromMillis(deadlineMillis),
      createdAt: FieldValue.serverTimestamp(),
      status: "pending",
      confirmedMemberUIDs: [],
    });
  });

  return { taskID };
});

exports.registerPokeDevice = onCall({ region }, async request => {
  const userID = requireAuthenticatedUser(request);
  const { deviceID, token } = normalizedDeviceData(request.data);
  await db.collection("users").doc(userID).collection("devices").doc(deviceID).set({
    token,
    platform: "ios",
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { registered: true };
});

exports.sendPoke = onCall({ region }, async request => {
  const senderID = requireAuthenticatedUser(request);
  const { groupID, recipientUID, style } = normalizedPokeData(request.data);
  if (senderID === recipientUID) {
    throw callableError("invalid-argument", "Cannot poke yourself.", "invalid-recipient");
  }
  const groupRef = db.collection("groups").doc(groupID);
  const result = await db.runTransaction(async transaction => {
    const [group, sender, recipient, countSnapshot] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(groupRef.collection("members").doc(senderID)),
      transaction.get(groupRef.collection("members").doc(recipientUID)),
      transaction.get(groupRef.collection("pokeCounts").doc(recipientUID)),
    ]);
    if (!group.exists) throw callableError("not-found", "Group not found.", "not-group-member");
    if (sender.data()?.userID !== senderID || recipient.data()?.userID !== recipientUID) {
      throw callableError("permission-denied", "Membership required.", "not-group-member");
    }
    const count = (countSnapshot.data()?.count || 0) + 1;
    const eventRef = groupRef.collection("pokes").doc(randomUUID().toLowerCase());
    transaction.set(groupRef.collection("pokeCounts").doc(recipientUID), { count, updatedAt: FieldValue.serverTimestamp() });
    transaction.create(eventRef, {
      senderID,
      recipientID: recipientUID,
      style,
      pokeCount: count,
      groupName: group.data().name || "你的群組",
      createdAt: FieldValue.serverTimestamp(),
    });
    return { count };
  });
  return result;
});

exports.deliverPokePush = onDocumentCreated({ region, document: "groups/{groupID}/pokes/{pokeID}" }, async event => {
  const poke = event.data?.data();
  if (!poke?.recipientID || !poke?.groupName || !poke?.style || !Number.isInteger(poke?.pokeCount)) return;
  const devices = await db.collection("users").doc(poke.recipientID).collection("devices").get();
  const tokens = devices.docs.map(device => device.data().token).filter(token => typeof token === "string" && token.length > 0);
  if (tokens.length === 0) return;
  const body = poke.pokeCount < 5
    ? `你被${poke.groupName}的隊員戳了${poke.pokeCount} 下！`
    : poke.pokeCount < 10 ? "你的組員一直在戳你‼️快回來啦🫨" : "檢舉雷包，人人有責😤";
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: "有人在找你", body },
    data: { groupName: poke.groupName, pokeCount: String(poke.pokeCount), style: poke.style },
    apns: { payload: { aps: { sound: "default" } } },
  });
  await Promise.all(response.responses.map((result, index) => {
    if (result.success || !["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(result.error?.code)) return null;
    return devices.docs[index].ref.delete();
  }));
});

exports.joinGroupByInviteCode = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  const inviteCode = normalizedInviteCode(request.data);
  const displayName = await accountName(userID);
  const inviteRef = db.collection("groupInviteCodes").doc(inviteCode);

  const result = await db.runTransaction(async (transaction) => {
    const inviteSnapshot = await transaction.get(inviteRef);
    if (!inviteSnapshot.exists) {
      throw callableError("not-found", "Invite code not found.", "invite-code-not-found");
    }

    const invite = inviteSnapshot.data();
    if (invite.isActive !== true) {
      throw callableError("failed-precondition", "Invite code is inactive.", "invite-code-inactive");
    }

    if (invite.expiresAt != null && !(invite.expiresAt instanceof Timestamp)) {
      throw callableError("failed-precondition", "Invite expiration is invalid.", "invalid-invite-data");
    }
    const expiration = millis(invite.expiresAt);
    if (expiration !== null && expiration <= Date.now()) {
      throw callableError("failed-precondition", "Invite code has expired.", "invite-code-expired");
    }

    const groupID = typeof invite.groupID === "string" ? invite.groupID : "";
    if (!groupID || groupID.includes("/")) {
      throw callableError("failed-precondition", "Invite code is invalid.", "invalid-invite-data");
    }

    const groupRef = db.collection("groups").doc(groupID);
    const memberRef = groupRef.collection("members").doc(userID);
    const [groupSnapshot, memberSnapshot] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(memberRef),
    ]);

    if (!groupSnapshot.exists) {
      throw callableError("not-found", "Group not found.", "group-not-found");
    }

    if (!memberSnapshot.exists) {
      transaction.create(memberRef, {
        userID,
        role: "member",
        joinedAt: FieldValue.serverTimestamp(),
        displayName,
      });
    }

    return {
      alreadyMember: memberSnapshot.exists,
      group: groupPayload(groupID, groupSnapshot.data(), inviteCode),
    };
  });

  return result;
});

exports.listMyGroups = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  if (request.data && Object.keys(request.data).length > 0) {
    throw callableError("invalid-argument", "No arguments are accepted.", "invalid-request");
  }

  const memberships = await db.collectionGroup("members")
    .where("userID", "==", userID)
    .get();
  const groupRefs = [];
  const seen = new Set();

  for (const membership of memberships.docs) {
    const groupRef = membership.ref.parent.parent;
    // A matching field alone is not membership: require groups/{groupID}/members/{uid}.
    if (membership.id === userID
        && groupRef?.parent.path === "groups"
        && !seen.has(groupRef.path)) {
      seen.add(groupRef.path);
      groupRefs.push(groupRef);
    }
  }

  if (groupRefs.length === 0) return { groups: [] };
  // Repair the caller's legacy membership name using trusted Auth data, never a client UID.
  const displayName = await accountName(userID);
  for (const groupRef of groupRefs) {
    await db.runTransaction(async tx => {
      const ref = groupRef.collection('members').doc(userID);
      const member = await tx.get(ref);
      if (member.exists && member.data().userID === userID && !member.data().displayName?.trim()) {
        tx.update(ref, {displayName});
      }
    });
  }
  const groupSnapshots = await db.getAll(...groupRefs);
  return {
    groups: groupSnapshots
      .filter((snapshot) => snapshot.exists)
      .map((snapshot) => groupPayload(snapshot.id, snapshot.data())),
  };
});

Object.assign(exports, require('./task-progress'));
