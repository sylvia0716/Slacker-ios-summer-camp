const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { randomBytes, randomUUID } = require("node:crypto");
const { getAuth } = require("firebase-admin/auth");

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

    if (!groupSnapshot.exists || groupSnapshot.data().deleting === true) {
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

Object.assign(exports, require('./group-membership'));
