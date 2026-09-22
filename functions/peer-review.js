const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentDeleted } = require("firebase-functions/v2/firestore");
const {
  participantUIDs: normalizedParticipantUIDs,
  peerReviewProgress,
  personalReviewSummaries,
  reviewedUIDs: normalizedReviewedUIDs,
} = require("./peer-review-calculation");

const region = "asia-east1";

function fail(code, message) {
  throw new HttpsError(code, message);
}

function normalizedRequest(data) {
  const expected = [
    "collaborationScore", "comment", "discussionScore", "groupID",
    "ideaScore", "reliabilityScore", "revieweeUID", "taskCompletionScore",
  ];
  if (!data || typeof data !== "object" || Array.isArray(data)
      || Object.keys(data).sort().join(",") !== expected.sort().join(",")) {
    fail("invalid-argument", "Invalid peer review request.");
  }
  if (typeof data.groupID !== "string"
      || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(data.groupID)) {
    fail("invalid-argument", "Invalid group identifier.");
  }
  if (typeof data.revieweeUID !== "string" || !data.revieweeUID
      || data.revieweeUID.length > 128 || data.revieweeUID.includes("/")) {
    fail("invalid-argument", "Invalid reviewee.");
  }
  const scoreKeys = [
    "taskCompletionScore", "discussionScore", "collaborationScore",
    "ideaScore", "reliabilityScore",
  ];
  if (!scoreKeys.every((key) => Number.isInteger(data[key]) && data[key] >= 1 && data[key] <= 5)) {
    fail("invalid-argument", "Every score must be between 1 and 5.");
  }
  if (typeof data.comment !== "string" || data.comment.length > 200) {
    fail("invalid-argument", "Invalid comment.");
  }
  return data;
}

function integer(value) {
  return Number.isInteger(value) && value >= 0 ? value : 0;
}

function commentsByRevieweeForParticipants(participants, submissionDocuments, pendingSubmission = null) {
  const result = new Map(participants.map((uid) => [uid, []]));
  const append = (revieweeUID, comment) => {
    const normalizedComment = typeof comment === "string" ? comment.trim() : "";
    if (!normalizedComment || !result.has(revieweeUID)) return;
    result.get(revieweeUID).push(normalizedComment);
  };

  submissionDocuments.forEach((document) => {
    const submission = document.data();
    append(submission.revieweeUID, submission.comment);
  });
  if (pendingSubmission) append(pendingSubmission.revieweeUID, pendingSubmission.comment);
  result.forEach((comments) => comments.sort((left, right) => left.localeCompare(right, "zh-Hant")));
  return result;
}

function publicSummaryData(aggregate, progress) {
  return {
    participantCount: progress.participantCount,
    totalReviewCount: aggregate.totalReviewCount,
    completedReviewerCount: progress.completedReviewerCount,
    taskCompletionScoreTotal: progress.resultsAvailable ? aggregate.taskCompletionScoreTotal : 0,
    discussionScoreTotal: progress.resultsAvailable ? aggregate.discussionScoreTotal : 0,
    collaborationScoreTotal: progress.resultsAvailable ? aggregate.collaborationScoreTotal : 0,
    ideaScoreTotal: progress.resultsAvailable ? aggregate.ideaScoreTotal : 0,
    reliabilityScoreTotal: progress.resultsAvailable ? aggregate.reliabilityScoreTotal : 0,
    resultsAvailable: progress.resultsAvailable,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function personalProjectData(groupID, groupData, summary) {
  return {
    groupID,
    groupName: typeof groupData?.name === "string" ? groupData.name : "已完成專案",
    completedAt: groupData?.settledAt instanceof Timestamp
      ? groupData.settledAt
      : groupData?.deadline instanceof Timestamp
        ? groupData.deadline
      : FieldValue.serverTimestamp(),
    ...summary,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function writePersonalProjects(transaction, db, group, groupData, participants, submissions) {
  personalReviewSummaries(participants, submissions).forEach((summary, uid) => {
    transaction.set(
      db.collection("users").doc(uid).collection("peerReviewProjects").doc(group.id),
      personalProjectData(group.id, groupData, summary),
    );
  });
}

exports.submitPeerReview = onCall({ region }, async (request) => {
  const reviewerUID = request.auth?.uid;
  if (!reviewerUID) fail("unauthenticated", "Sign in required.");
  const data = normalizedRequest(request.data);
  if (reviewerUID === data.revieweeUID) {
    fail("invalid-argument", "You cannot review yourself.");
  }

  const db = getFirestore();
  const group = db.collection("groups").doc(data.groupID);
  const submission = group.collection("peerReviewSubmissions")
    .doc(`${reviewerUID}_${data.revieweeUID}`);
  const state = group.collection("peerReviewStates").doc(reviewerUID);
  const privateSummary = group.collection("peerReviewAggregates").doc("summary");
  const publicSummary = group.collection("peerReviewPublic").doc("summary");
  const privateComments = group.collection("peerReviewComments");

  await db.runTransaction(async (transaction) => {
    const [groupSnapshot, reviewerSnapshot, revieweeSnapshot, membersSnapshot,
      submissionSnapshot, stateSnapshot, statesSnapshot, aggregateSnapshot] = await Promise.all([
      transaction.get(group),
      transaction.get(group.collection("members").doc(reviewerUID)),
      transaction.get(group.collection("members").doc(data.revieweeUID)),
      transaction.get(group.collection("members")),
      transaction.get(submission),
      transaction.get(state),
      transaction.get(group.collection("peerReviewStates")),
      transaction.get(privateSummary),
    ]);

    if (!groupSnapshot.exists) fail("not-found", "Group not found.");
    if (!reviewerSnapshot.exists || !revieweeSnapshot.exists) {
      fail("permission-denied", "Group membership required.");
    }
    const groupData = groupSnapshot.data();
    const deadline = groupData.deadline;
    if (!(groupData.settledAt instanceof Timestamp)
        && (!(deadline instanceof Timestamp) || deadline.toMillis() > Date.now())) {
      fail("failed-precondition", "Peer review opens after the deadline.");
    }
    if (submissionSnapshot.exists) {
      fail("already-exists", "This review was already submitted.");
    }

    const old = aggregateSnapshot.data() || {};
    const participants = normalizedParticipantUIDs(old.participantUIDs).length > 0
      ? normalizedParticipantUIDs(old.participantUIDs)
      : normalizedParticipantUIDs(membersSnapshot.docs.map((member) => member.id));
    if (!participants.includes(reviewerUID) || !participants.includes(data.revieweeUID)) {
      fail("failed-precondition", "Peer review roster is already locked.");
    }
    const reviewedUIDs = normalizedParticipantUIDs([
      ...normalizedReviewedUIDs(stateSnapshot.data()),
      data.revieweeUID,
    ]);
    const statesByUID = new Map(statesSnapshot.docs.map((document) => [document.id, document.data()]));
    statesByUID.set(reviewerUID, { reviewedUIDs });
    const progress = peerReviewProgress(participants, statesByUID);
    const isCompleted = progress.completedUIDs.includes(reviewerUID);

    const aggregate = {
      participantUIDs: progress.participantUIDs,
      participantCount: progress.participantCount,
      totalReviewCount: integer(old.totalReviewCount) + 1,
      completedReviewerCount: progress.completedReviewerCount,
      taskCompletionScoreTotal: integer(old.taskCompletionScoreTotal) + data.taskCompletionScore,
      discussionScoreTotal: integer(old.discussionScoreTotal) + data.discussionScore,
      collaborationScoreTotal: integer(old.collaborationScoreTotal) + data.collaborationScore,
      ideaScoreTotal: integer(old.ideaScoreTotal) + data.ideaScore,
      reliabilityScoreTotal: integer(old.reliabilityScoreTotal) + data.reliabilityScore,
      updatedAt: FieldValue.serverTimestamp(),
    };
    let commentsByReviewee = null;
    let completedSubmissions = null;

    if (progress.resultsAvailable) {
      const submissionsSnapshot = await transaction.get(
        group.collection("peerReviewSubmissions"),
      );
      commentsByReviewee = commentsByRevieweeForParticipants(
        progress.participantUIDs,
        submissionsSnapshot.docs,
        { revieweeUID: data.revieweeUID, comment: data.comment },
      );
      completedSubmissions = [
        ...submissionsSnapshot.docs.map((document) => document.data()),
        { ...data, reviewerUID },
      ];
    }

    transaction.create(submission, {
      reviewerUID,
      revieweeUID: data.revieweeUID,
      taskCompletionScore: data.taskCompletionScore,
      discussionScore: data.discussionScore,
      collaborationScore: data.collaborationScore,
      ideaScore: data.ideaScore,
      reliabilityScore: data.reliabilityScore,
      comment: data.comment,
      submittedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(state, {
      reviewedUIDs,
      completed: isCompleted,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(privateSummary, aggregate);
    transaction.set(publicSummary, publicSummaryData(aggregate, progress));
    commentsByReviewee?.forEach((comments, revieweeUID) => {
      transaction.set(privateComments.doc(revieweeUID), {
        comments,
        publishedAt: FieldValue.serverTimestamp(),
      });
    });
    if (completedSubmissions) {
      writePersonalProjects(
        transaction, db, group, groupSnapshot.data(), progress.participantUIDs, completedSubmissions,
      );
    }
  });

  return { submitted: true };
});

// A member can leave after reviews have started. Recalculate against the locked roster so
// the departed member never remains an impossible reviewer or review target.
exports.reconcilePeerReviewMemberExit = onDocumentDeleted(
  { region, document: "groups/{groupID}/members/{userID}", retry: true },
  async (event) => {
    const db = getFirestore();
    const group = db.collection("groups").doc(event.params.groupID);
    const privateSummary = group.collection("peerReviewAggregates").doc("summary");
    const publicSummary = group.collection("peerReviewPublic").doc("summary");
    const privateComments = group.collection("peerReviewComments");

    await db.runTransaction(async (transaction) => {
      const [groupSnapshot, aggregateSnapshot, membersSnapshot, statesSnapshot, submissionsSnapshot] = await Promise.all([
        transaction.get(group),
        transaction.get(privateSummary),
        transaction.get(group.collection("members")),
        transaction.get(group.collection("peerReviewStates")),
        transaction.get(group.collection("peerReviewSubmissions")),
      ]);
      if (!aggregateSnapshot.exists) return;

      const old = aggregateSnapshot.data() || {};
      const liveUIDs = new Set(membersSnapshot.docs.map((member) => member.id));
      const participants = normalizedParticipantUIDs(old.participantUIDs)
        .filter((uid) => liveUIDs.has(uid));
      if (participants.length === normalizedParticipantUIDs(old.participantUIDs).length) return;

      const statesByUID = new Map(statesSnapshot.docs.map((document) => [document.id, document.data()]));
      const progress = peerReviewProgress(participants, statesByUID);
      const aggregate = {
        ...old,
        participantUIDs: progress.participantUIDs,
        participantCount: progress.participantCount,
        completedReviewerCount: progress.completedReviewerCount,
        updatedAt: FieldValue.serverTimestamp(),
      };

      progress.participantUIDs.forEach((uid) => {
        const oldState = statesByUID.get(uid) || {};
        transaction.set(group.collection("peerReviewStates").doc(uid), {
          reviewedUIDs: normalizedReviewedUIDs(oldState),
          completed: progress.completedUIDs.includes(uid),
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
      transaction.set(privateSummary, aggregate);
      transaction.set(publicSummary, publicSummaryData(aggregate, progress));

      if (progress.resultsAvailable) {
        const comments = commentsByRevieweeForParticipants(
          progress.participantUIDs,
          submissionsSnapshot.docs,
        );
        comments.forEach((values, uid) => {
          transaction.set(privateComments.doc(uid), {
            comments: values,
            publishedAt: FieldValue.serverTimestamp(),
          });
        });
        writePersonalProjects(
          transaction,
          db,
          group,
          groupSnapshot.data(),
          progress.participantUIDs,
          submissionsSnapshot.docs.map((document) => document.data()),
        );
      }
    });
  },
);

// Backfill completed projects that the signed-in user can still access. Future reports are
// published automatically when the final review arrives and remain available after leaving.
exports.syncMyPeerReviewHistory = onCall({ region }, async (request) => {
  const userID = request.auth?.uid;
  if (!userID) fail("unauthenticated", "Sign in required.");
  if (request.data && (typeof request.data !== "object"
      || Array.isArray(request.data) || Object.keys(request.data).length > 0)) {
    fail("invalid-argument", "No arguments are accepted.");
  }

  const db = getFirestore();
  const memberships = await db.collectionGroup("members").where("userID", "==", userID).get();
  const groupRefs = memberships.docs
    .filter((document) => document.id === userID && document.ref.parent.parent?.parent.path === "groups")
    .map((document) => document.ref.parent.parent);
  let syncedProjectCount = 0;

  for (const group of groupRefs) {
    const [groupSnapshot, publicSummarySnapshot] = await Promise.all([
      group.get(),
      group.collection("peerReviewPublic").doc("summary").get(),
    ]);
    if (!groupSnapshot.exists || publicSummarySnapshot.data()?.resultsAvailable !== true) continue;
    const submissionsSnapshot = await group.collection("peerReviewSubmissions")
      .where("revieweeUID", "==", userID).get();
    const personal = personalReviewSummaries(
      [userID], submissionsSnapshot.docs.map((document) => document.data()),
    ).get(userID);
    if (!personal || personal.reviewCount === 0) continue;
    await db.collection("users").doc(userID).collection("peerReviewProjects").doc(group.id)
      .set(personalProjectData(group.id, groupSnapshot.data(), personal));
    syncedProjectCount += 1;
  }
  return { syncedProjectCount };
});

exports.getPeerReviewComments = onCall({ region }, async (request) => {
  const userID = request.auth?.uid;
  if (!userID) fail("unauthenticated", "Sign in required.");
  if (!request.data || typeof request.data !== "object" || Array.isArray(request.data)
      || Object.keys(request.data).length !== 1
      || typeof request.data.groupID !== "string"
      || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(request.data.groupID)) {
    fail("invalid-argument", "Invalid group identifier.");
  }

  const group = getFirestore().collection("groups").doc(request.data.groupID);
  const [memberSnapshot, publicSummarySnapshot] = await Promise.all([
    group.collection("members").doc(userID).get(),
    group.collection("peerReviewPublic").doc("summary").get(),
  ]);
  if (!memberSnapshot.exists) fail("permission-denied", "Group membership required.");
  if (publicSummarySnapshot.data()?.resultsAvailable !== true) {
    fail("failed-precondition", "Peer review results are not available yet.");
  }

  const submissionsSnapshot = await group.collection("peerReviewSubmissions")
    .where("revieweeUID", "==", userID)
    .get();
  const comments = submissionsSnapshot.docs
    .map((document) => document.data().comment)
    .filter((comment) => typeof comment === "string" && comment.trim())
    .map((comment) => comment.trim())
    .sort((left, right) => left.localeCompare(right, "zh-Hant"));
  return { comments };
});
