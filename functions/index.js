const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { randomBytes, randomUUID } = require("node:crypto");
const { getAuth } = require("firebase-admin/auth");
const { getStorage } = require("firebase-admin/storage");
const { memberDisplayName } = require("./member-display-name");
const { pokeNotification } = require("./poke-notification");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

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

function normalizedUpdateTaskData(data) {
  requireExactKeys(data, ["deadlineMillis", "detail", "groupID", "subtasks", "taskID", "title"]);
  const groupID = normalizedUUID(data.groupID, "invalid-group-id", true);
  const taskID = normalizedUUID(data.taskID, "invalid-task-id", true);
  const title = typeof data.title === "string" ? data.title.trim() : "";
  const detail = typeof data.detail === "string" ? data.detail.trim() : "";
  if (!title || title.length > 100) {
    throw callableError("invalid-argument", "Invalid task title.", "invalid-task-title");
  }
  if (detail.length > 1000) {
    throw callableError("invalid-argument", "Invalid task detail.", "invalid-task-detail");
  }
  if (!Array.isArray(data.subtasks) || data.subtasks.length < 1 || data.subtasks.length > 10) {
    throw callableError("invalid-argument", "Invalid subtasks.", "invalid-subtasks");
  }

  const subtaskIDs = new Set();
  const requestedSubtasks = data.subtasks.map(rawSubtask => {
    requireExactKeys(rawSubtask, ["id", "title"]);
    const id = normalizedUUID(rawSubtask.id, "invalid-subtask-id");
    const subtaskTitle = typeof rawSubtask.title === "string" ? rawSubtask.title.trim() : "";
    if (!subtaskTitle || subtaskTitle.length > 200 || subtaskIDs.has(id)) {
      throw callableError("invalid-argument", "Invalid subtask.", "invalid-subtasks");
    }
    subtaskIDs.add(id);
    return {id, title: subtaskTitle};
  });

  const deadlineMillis = data.deadlineMillis;
  if (typeof deadlineMillis !== "number" || !Number.isFinite(deadlineMillis) || deadlineMillis <= Date.now()) {
    throw callableError("invalid-argument", "Invalid task deadline.", "invalid-task-deadline");
  }
  return {groupID, taskID, title, detail, requestedSubtasks, deadlineMillis};
}

function normalizedDeleteTaskData(data) {
  requireExactKeys(data, ["groupID", "taskID"]);
  return {
    groupID: normalizedUUID(data.groupID, "invalid-group-id", true),
    taskID: normalizedUUID(data.taskID, "invalid-task-id", true),
  };
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

function normalizedPokeData(data) {
  requireExactKeys(data, ["groupID", "recipientUID", "style"]);
  const groupID = normalizedUUID(data.groupID, "invalid-group-id", true);
  const recipientUID = typeof data.recipientUID === "string" ? data.recipientUID.trim() : "";
  const style = typeof data.style === "string" ? data.style : "";
  if (!recipientUID || recipientUID.length > 128 || !["輕敲", "迷因轟炸", "警報催命"].includes(style)) {
    throw callableError("invalid-argument", "Invalid poke.", "invalid-recipient");
  }
  return { groupID, recipientUID, style };
}

function normalizedDeviceData(data) {
  const keys = ["deviceID", "token"];
  if (data?.languageCode !== undefined) keys.push("languageCode");
  if (data?.pokesEnabled !== undefined) keys.push("pokesEnabled");
  requireExactKeys(data, keys);
  if (data.pokesEnabled !== undefined && typeof data.pokesEnabled !== "boolean") {
    throw callableError("invalid-argument", "Invalid notification preference.", "invalid-device");
  }
  if (data.languageCode !== undefined && !["en", "zh-Hant"].includes(data.languageCode)) {
    throw callableError("invalid-argument", "Invalid language.", "invalid-device");
  }
  const deviceID = typeof data.deviceID === "string" ? data.deviceID : "";
  const token = typeof data.token === "string" ? data.token : "";
  if (!deviceID || deviceID.length > 128 || !token || token.length > 4096) {
    throw callableError("invalid-argument", "Invalid device.", "invalid-device");
  }
  return { deviceID, token, languageCode: data.languageCode || "zh-Hant", pokesEnabled: data.pokesEnabled };
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
    settledAtMillis: millis(data.settledAt),
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
    const applicationRef = groupRef.collection("joinRequests").doc(userID);
    const [groupSnapshot, memberSnapshot, applicationSnapshot] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(memberRef),
      transaction.get(applicationRef),
    ]);

    if (!groupSnapshot.exists || groupSnapshot.data().deleting === true) {
      throw callableError("not-found", "Group not found.", "group-not-found");
    }

    if (!memberSnapshot.exists) {
      const groupDeadline = millis(groupSnapshot.data().deadline);
      if (groupSnapshot.data().settledAt != null || groupDeadline === null || groupDeadline <= Date.now()) {
        throw callableError("failed-precondition", "This group is already closed.", "group-closed");
      }
      if (applicationSnapshot.data()?.status !== "pending") {
        const application = {
          requestID: randomUUID(), groupID, groupName: groupSnapshot.data().name,
          applicantID: userID, applicantName: displayName, status: "pending",
          requestedAt: FieldValue.serverTimestamp(),
        };
        transaction.set(applicationRef, application);
        transaction.set(db.collection("users").doc(userID).collection("groupJoinRequests").doc(groupID), application);
      }
    }

    return {
      alreadyMember: memberSnapshot.exists,
      status: memberSnapshot.exists ? "approved" : "pending",
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
    if (groupSnapshot.data().settledAt != null) {
      throw callableError("failed-precondition", "Group is already settled.", "group-settled");
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
    const [groupSnapshot, callerSnapshot, taskSnapshot] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(callerRef),
      transaction.get(taskRef),
    ]);
    if (!groupSnapshot.exists) {
      throw callableError("not-found", "Group not found.", "group-not-found");
    }
    if (groupSnapshot.data().settledAt != null) {
      throw callableError("failed-precondition", "Group is already settled.", "group-settled");
    }
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

exports.settleGroup = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  requireExactKeys(request.data, ["groupID"]);
  const groupID = normalizedUUID(request.data.groupID, "invalid-group-id", true);
  const groupRef = db.collection("groups").doc(groupID);
  const callerRef = groupRef.collection("members").doc(userID);
  const tasksQuery = groupRef.collection("tasks");

  const settledAt = await db.runTransaction(async (transaction) => {
    const [groupSnapshot, callerSnapshot, tasksSnapshot] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(callerRef),
      transaction.get(tasksQuery),
    ]);
    if (!groupSnapshot.exists) {
      throw callableError("not-found", "Group not found.", "group-not-found");
    }
    if (!callerSnapshot.exists || callerSnapshot.data()?.userID !== userID
        || callerSnapshot.data()?.role !== "leader") {
      throw callableError("permission-denied", "Only the group leader may settle.", "not-group-leader");
    }
    const existing = groupSnapshot.data().settledAt;
    if (existing instanceof Timestamp) return existing;
    if (tasksSnapshot.empty) {
      throw callableError("failed-precondition", "At least one task is required.", "no-tasks");
    }
    const allTasksComplete = tasksSnapshot.docs.every((document) => {
      const subtasks = document.data().subtasks;
      return Array.isArray(subtasks) && subtasks.length > 0
        && subtasks.every((subtask) => subtask?.isComplete === true);
    });
    if (!allTasksComplete) {
      throw callableError("failed-precondition", "Every task must be complete.", "tasks-incomplete");
    }
    const timestamp = Timestamp.now();
    transaction.update(groupRef, { settledAt: timestamp, settledByUserID: userID });
    return timestamp;
  });

  return { settledAtMillis: settledAt.toMillis() };
});

exports.updateTask = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  const data = normalizedUpdateTaskData(request.data);
  const groupRef = db.collection("groups").doc(data.groupID);
  const callerRef = groupRef.collection("members").doc(userID);
  const taskRef = groupRef.collection("tasks").doc(data.taskID);

  await db.runTransaction(async transaction => {
    const [groupSnapshot, callerSnapshot, taskSnapshot] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(callerRef),
      transaction.get(taskRef),
    ]);
    if (!groupSnapshot.exists) {
      throw callableError("not-found", "Group not found.", "group-not-found");
    }
    if (!callerSnapshot.exists || callerSnapshot.data()?.userID !== userID) {
      throw callableError("permission-denied", "Group membership required.", "permission-denied");
    }
    if (!taskSnapshot.exists) {
      throw callableError("not-found", "Task not found.", "task-not-found");
    }
    const task = taskSnapshot.data();
    if (task.ownerMemberID !== userID) {
      throw callableError("permission-denied", "Only the assignee may edit this task.", "not-task-owner");
    }
    const groupDeadline = millis(groupSnapshot.data().deadline);
    if (groupDeadline === null || data.deadlineMillis > groupDeadline) {
      throw callableError("failed-precondition", "Task deadline exceeds group deadline.", "task-deadline-after-group");
    }
    if (!Array.isArray(task.subtasks)) {
      throw callableError("failed-precondition", "Task subtasks are invalid.", "invalid-task-data");
    }

    const existingByID = new Map(task.subtasks.map(subtask => [String(subtask.id).toLowerCase(), subtask]));
    const baseWeight = Math.floor(100 / data.requestedSubtasks.length);
    const remainder = 100 % data.requestedSubtasks.length;
    const subtasks = data.requestedSubtasks.map((subtask, index) => ({
      id: subtask.id,
      title: subtask.title,
      isComplete: existingByID.get(subtask.id)?.isComplete === true,
      weight: baseWeight + (index < remainder ? 1 : 0),
    }));
    const subtasksChanged = JSON.stringify(task.subtasks.map(({id, title}) => ({id, title})))
      !== JSON.stringify(data.requestedSubtasks);
    const status = subtasks.every(subtask => subtask.isComplete) ? "completed"
      : subtasks.some(subtask => subtask.isComplete) ? "inProgress" : "pending";

    transaction.update(taskRef, {
      title: data.title,
      detail: data.detail,
      subtasks,
      deadline: Timestamp.fromMillis(data.deadlineMillis),
      status,
      ...(subtasksChanged ? {confirmedMemberUIDs: []} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return {taskID: data.taskID};
});

exports.deleteTask = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  const data = normalizedDeleteTaskData(request.data);
  const groupRef = db.collection("groups").doc(data.groupID);
  const callerRef = groupRef.collection("members").doc(userID);
  const taskRef = groupRef.collection("tasks").doc(data.taskID);
  const [callerSnapshot, taskSnapshot] = await Promise.all([callerRef.get(), taskRef.get()]);
  if (!callerSnapshot.exists || callerSnapshot.data()?.userID !== userID) {
    throw callableError("permission-denied", "Group membership required.", "permission-denied");
  }
  if (!taskSnapshot.exists) {
    throw callableError("not-found", "Task not found.", "task-not-found");
  }
  if (taskSnapshot.data()?.ownerMemberID !== userID) {
    throw callableError("permission-denied", "Only the assignee may delete this task.", "not-task-owner");
  }

  await getStorage().bucket().deleteFiles({
    prefix: `groups/${data.groupID}/tasks/${data.taskID}/`,
  });
  await db.recursiveDelete(taskRef);
  return {taskID: data.taskID};
});

exports.registerPokeDevice = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  const { deviceID, token, languageCode, pokesEnabled } = normalizedDeviceData(request.data);
  await db.collection("users").doc(userID).collection("devices").doc(deviceID).set({
    token,
    languageCode,
    ...(pokesEnabled === undefined ? {} : { pokesEnabled }),
    platform: "ios",
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { registered: true };
});

// Remove only the authenticated account's registration on this device.
exports.unregisterPokeDevice = onCall({ region }, async (request) => {
  const userID = requireAuthenticatedUser(request);
  requireExactKeys(request.data, ["deviceID"]);
  const deviceID = request.data.deviceID;
  if (typeof deviceID !== "string" || !deviceID || deviceID.length > 128 || deviceID.includes("/")) {
    throw callableError("invalid-argument", "Invalid device.", "invalid-device");
  }
  await db.collection("users").doc(userID).collection("devices").doc(deviceID).delete();
  return { unregistered: true };
});

exports.sendPoke = onCall({ region }, async (request) => {
  const senderID = requireAuthenticatedUser(request);
  const { groupID, recipientUID, style } = normalizedPokeData(request.data);
  if (senderID === recipientUID) {
    throw callableError("invalid-argument", "Cannot poke yourself.", "invalid-recipient");
  }
  const groupRef = db.collection("groups").doc(groupID);
  return db.runTransaction(async (transaction) => {
    const [group, sender, recipient, countSnapshot] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(groupRef.collection("members").doc(senderID)),
      transaction.get(groupRef.collection("members").doc(recipientUID)),
      transaction.get(groupRef.collection("pokeCounts").doc(recipientUID)),
    ]);
    if (!group.exists || group.data()?.deleting === true) {
      throw callableError("not-found", "Group not found.", "group-not-found");
    }
    if (sender.data()?.userID !== senderID || recipient.data()?.userID !== recipientUID) {
      throw callableError("permission-denied", "Membership required.", "not-group-member");
    }
    const count = (countSnapshot.data()?.count || 0) + 1;
    transaction.set(groupRef.collection("pokeCounts").doc(recipientUID), {
      count,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(groupRef.collection("pokes").doc(randomUUID().toLowerCase()), {
      senderID,
      recipientID: recipientUID,
      style,
      pokeCount: count,
      groupName: group.data().name || "你的群組",
      createdAt: FieldValue.serverTimestamp(),
    });
    return { count };
  });
});

exports.deliverPokePush = onDocumentCreated({ region, document: "groups/{groupID}/pokes/{pokeID}" }, async (event) => {
  const poke = event.data?.data();
  if (!poke?.recipientID || !poke?.groupName || !poke?.style || !Number.isInteger(poke?.pokeCount)) return;
  const devices = await db.collection("users").doc(poke.recipientID).collection("devices").get();
  const recipients = devices.docs.filter((device) => {
    const token = device.data().token;
    return typeof token === "string" && token.length > 0 && device.data().pokesEnabled !== false;
  });
  for (let offset = 0; offset < recipients.length; offset += 500) {
    const batch = recipients.slice(offset, offset + 500);
    const response = await getMessaging().sendEach(batch.map((device) => ({
      token: device.data().token,
      notification: pokeNotification(poke, device.data().languageCode),
      data: { recipientUID: poke.recipientID, groupName: poke.groupName, pokeCount: String(poke.pokeCount), style: poke.style },
      apns: { payload: { aps: { sound: "default" } } },
    })));
    await Promise.all(response.responses.map((result, index) => {
      if (result.success || !["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(result.error?.code)) return null;
      return batch[index].ref.delete();
    }));
  }
});

Object.assign(exports, require('./group-membership'));
Object.assign(exports, require('./group-admission'));
Object.assign(exports, require('./peer-review'));
Object.assign(exports, require('./smart-agenda'));
Object.assign(exports, require('./smart-agenda-reminders'));


// Confirm only the current cloud attachment; progress remains driven by subtasks.
exports.confirmTaskAttachment = onCall({ region }, async request => {
  const uid = requireAuthenticatedUser(request);
  const { groupID, taskID, attachmentID } = request.data || {};
  const uuid = /^[a-f0-9-]{36}$/i;
  if (![groupID, taskID, attachmentID].every(v => typeof v === 'string' && uuid.test(v))) {
    throw new HttpsError('invalid-argument', 'Invalid attachment identifiers');
  }
  const group = db.collection('groups').doc(groupID);
  const task = group.collection('tasks').doc(taskID);
  await db.runTransaction(async tx => {
    const [groupSnapshot, member, snapshot, attachments] = await Promise.all([
      tx.get(group), tx.get(group.collection('members').doc(uid)), tx.get(task),
      tx.get(task.collection('attachments').where('status', '==', 'ready'))
    ]);
    if (groupSnapshot.data()?.settledAt != null) {
      throw new HttpsError('failed-precondition', 'Group is already settled');
    }
    if (!member.exists) throw new HttpsError('permission-denied', 'Membership required');
    if (!snapshot.exists) throw new HttpsError('not-found', 'Task missing');
    const latest = attachments.docs.sort((a,b) => (b.data().createdAt?.toMillis() || 0) - (a.data().createdAt?.toMillis() || 0) || a.id.localeCompare(b.id))[0];
    if (latest?.id !== attachmentID) throw new HttpsError('failed-precondition', 'Attachment changed');
    const data = snapshot.data();
    if (data.departureID) throw new HttpsError('failed-precondition', 'Former member task is archived');
    if (data.ownerMemberID === uid) throw new HttpsError('permission-denied', 'Owner does not review own task');
    const confirmed = data.confirmedAttachmentID === attachmentID ? (data.confirmedMemberUIDs || []) : [];
    tx.update(task, { confirmedAttachmentID: attachmentID, confirmedMemberUIDs: [...new Set([...confirmed, uid])] });
  });
  return { confirmed: true };
});
