const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { randomBytes, randomUUID } = require("node:crypto");
const { getAuth } = require("firebase-admin/auth");
const { memberDisplayName } = require("./member-display-name");

initializeApp();

const db = getFirestore();
const region = "asia-east1";

async function accountName(uid) {
  const user = await getAuth().getUser(uid);
  return memberDisplayName(user);
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

function requirePlainObject(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw callableError("invalid-argument", "Invalid request.", "invalid-request");
  }
  return data;
}

function requireExactKeys(data, expectedKeys) {
  const keys = Object.keys(requirePlainObject(data)).sort();
  if (keys.join(",") !== [...expectedKeys].sort().join(",")) {
    throw callableError("invalid-argument", "Unexpected request fields.", "invalid-request");
  }
}

function normalizedUUID(value, reason, preserveCase = false) {
  const rawValue = typeof value === "string" ? value.trim() : "";
  const normalized = rawValue.toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(normalized)) {
    throw callableError("invalid-argument", "Invalid identifier.", reason);
  }
  return preserveCase ? rawValue : normalized;
}

function normalizedCreateTaskData(data) {
  requireExactKeys(data, [
    "assigneeUserID", "deadlineMillis", "detail", "groupID", "subtasks", "taskID", "title",
  ]);

  const groupID = normalizedUUID(data.groupID, "invalid-group-id", true);
  const taskID = normalizedUUID(data.taskID, "invalid-task-id");
  const title = typeof data.title === "string" ? data.title.trim() : "";
  const detail = typeof data.detail === "string" ? data.detail.trim() : "";
  const assigneeUserID = typeof data.assigneeUserID === "string" ? data.assigneeUserID.trim() : "";
  if (!title || title.length > 100) {
    throw callableError("invalid-argument", "Invalid task title.", "invalid-task-title");
  }
  if (detail.length > 1000) {
    throw callableError("invalid-argument", "Invalid task detail.", "invalid-task-detail");
  }
  if (!assigneeUserID || assigneeUserID.length > 128 || assigneeUserID.includes("/")) {
    throw callableError("invalid-argument", "Invalid assignee.", "invalid-assignee");
  }
  if (!Array.isArray(data.subtasks) || data.subtasks.length < 1 || data.subtasks.length > 10) {
    throw callableError("invalid-argument", "Invalid subtasks.", "invalid-subtasks");
  }

  const subtaskIDs = new Set();
  const baseWeight = Math.floor(100 / data.subtasks.length);
  const remainder = 100 % data.subtasks.length;
  const subtasks = data.subtasks.map((rawSubtask, index) => {
    requireExactKeys(rawSubtask, ["id", "title"]);
    const id = normalizedUUID(rawSubtask.id, "invalid-subtask-id");
    const subtaskTitle = typeof rawSubtask.title === "string" ? rawSubtask.title.trim() : "";
    if (!subtaskTitle || subtaskTitle.length > 200 || subtaskIDs.has(id)) {
      throw callableError("invalid-argument", "Invalid subtask.", "invalid-subtasks");
    }
    subtaskIDs.add(id);
    return {
      id,
      title: subtaskTitle,
      isComplete: false,
      weight: baseWeight + (index < remainder ? 1 : 0),
    };
  });

  const deadlineMillis = data.deadlineMillis;
  if (typeof deadlineMillis !== "number" || !Number.isFinite(deadlineMillis) || deadlineMillis <= Date.now()) {
    throw callableError("invalid-argument", "Invalid task deadline.", "invalid-task-deadline");
  }

  return { groupID, taskID, title, detail, assigneeUserID, subtasks, deadlineMillis };
}

function normalizedUpdateSubtaskData(data) {
  requireExactKeys(data, ["groupID", "isComplete", "subtaskID", "taskID"]);
  if (typeof data.isComplete !== "boolean") {
    throw callableError("invalid-argument", "Invalid completion state.", "invalid-completion-state");
  }
  return {
    groupID: normalizedUUID(data.groupID, "invalid-group-id", true),
    taskID: normalizedUUID(data.taskID, "invalid-task-id", true),
    subtaskID: normalizedUUID(data.subtaskID, "invalid-subtask-id"),
    isComplete: data.isComplete,
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
      if (member.exists && member.data().userID === userID && member.data().displayName !== displayName) {
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

exports.createTask = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  const data = normalizedCreateTaskData(request.data);
  const groupRef = db.collection("groups").doc(data.groupID);
  const callerRef = groupRef.collection("members").doc(userID);
  const assigneeRef = groupRef.collection("members").doc(data.assigneeUserID);
  const taskRef = groupRef.collection("tasks").doc(data.taskID);
  const deadline = Timestamp.fromMillis(data.deadlineMillis);

  await db.runTransaction(async (transaction) => {
    const [groupSnapshot, callerSnapshot, assigneeSnapshot, taskSnapshot] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(callerRef),
      transaction.get(assigneeRef),
      transaction.get(taskRef),
    ]);
    if (!groupSnapshot.exists) {
      throw callableError("not-found", "Group not found.", "group-not-found");
    }
    if (!callerSnapshot.exists || callerSnapshot.data()?.userID !== userID) {
      throw callableError("permission-denied", "Group membership required.", "permission-denied");
    }
    if (!assigneeSnapshot.exists || assigneeSnapshot.data()?.userID !== data.assigneeUserID) {
      throw callableError("failed-precondition", "Assignee is not a group member.", "assignee-not-in-group");
    }
    const groupDeadline = millis(groupSnapshot.data().deadline);
    if (groupDeadline === null || data.deadlineMillis > groupDeadline) {
      throw callableError("failed-precondition", "Task deadline exceeds group deadline.", "task-deadline-after-group");
    }
    if (taskSnapshot.exists) {
      throw callableError("already-exists", "Task already exists.", "task-already-exists");
    }

    transaction.create(taskRef, {
      title: data.title,
      groupID: data.groupID,
      detail: data.detail,
      weight: 1,
      ownerMemberID: data.assigneeUserID,
      createdByMemberID: userID,
      subtasks: data.subtasks,
      deadline,
      createdAt: FieldValue.serverTimestamp(),
      status: "inProgress",
    });
  });

  return { taskID: data.taskID };
});

exports.updateSubtask = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  const data = normalizedUpdateSubtaskData(request.data);
  const groupRef = db.collection("groups").doc(data.groupID);
  const callerRef = groupRef.collection("members").doc(userID);
  const taskRef = groupRef.collection("tasks").doc(data.taskID);

  const status = await db.runTransaction(async (transaction) => {
    const [callerSnapshot, taskSnapshot] = await Promise.all([
      transaction.get(callerRef),
      transaction.get(taskRef),
    ]);
    if (!callerSnapshot.exists || callerSnapshot.data()?.userID !== userID) {
      throw callableError("permission-denied", "Group membership required.", "permission-denied");
    }
    if (!taskSnapshot.exists) {
      throw callableError("not-found", "Task not found.", "task-not-found");
    }
    const task = taskSnapshot.data();
    if (task.ownerMemberID !== userID) {
      throw callableError("permission-denied", "Only the assignee may update progress.", "not-task-owner");
    }
    if (!Array.isArray(task.subtasks)) {
      throw callableError("failed-precondition", "Task subtasks are invalid.", "invalid-task-data");
    }
    let found = false;
    const subtasks = task.subtasks.map((subtask) => {
      if (typeof subtask?.id !== "string" || subtask.id.toLowerCase() !== data.subtaskID) return subtask;
      found = true;
      return { ...subtask, isComplete: data.isComplete };
    });
    if (!found) {
      throw callableError("not-found", "Subtask not found.", "subtask-not-found");
    }
    const nextStatus = subtasks.length > 0 && subtasks.every((subtask) => subtask?.isComplete === true)
      ? "completed"
      : "inProgress";
    transaction.update(taskRef, { subtasks, status: nextStatus });
    return nextStatus;
  });

  return { taskID: data.taskID, subtaskID: data.subtaskID, isComplete: data.isComplete, status };
});

Object.assign(exports, require('./group-membership'));
