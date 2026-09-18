const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

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
      submissionSnapshot, stateSnapshot, aggregateSnapshot] = await Promise.all([
      transaction.get(group),
      transaction.get(group.collection("members").doc(reviewerUID)),
      transaction.get(group.collection("members").doc(data.revieweeUID)),
      transaction.get(group.collection("members")),
      transaction.get(submission),
      transaction.get(state),
      transaction.get(privateSummary),
    ]);

    if (!groupSnapshot.exists) fail("not-found", "Group not found.");
    if (!reviewerSnapshot.exists || !revieweeSnapshot.exists) {
      fail("permission-denied", "Group membership required.");
    }
    const deadline = groupSnapshot.data().deadline;
    if (!(deadline instanceof Timestamp) || deadline.toMillis() > Date.now()) {
      fail("failed-precondition", "Peer review opens after the deadline.");
    }
    if (submissionSnapshot.exists) {
      fail("already-exists", "This review was already submitted.");
    }

    const oldReviewedUIDs = Array.isArray(stateSnapshot.data()?.reviewedUIDs)
      ? stateSnapshot.data().reviewedUIDs.filter((uid) => typeof uid === "string")
      : [];
    const reviewedUIDs = [...new Set([...oldReviewedUIDs, data.revieweeUID])].sort();
    const requiredReviewCount = Math.max(membersSnapshot.size - 1, 0);
    const wasCompleted = stateSnapshot.data()?.completed === true;
    const isCompleted = reviewedUIDs.length >= requiredReviewCount;

    const old = aggregateSnapshot.data() || {};
    const aggregate = {
      totalReviewCount: integer(old.totalReviewCount) + 1,
      completedReviewerCount: integer(old.completedReviewerCount) + (!wasCompleted && isCompleted ? 1 : 0),
      taskCompletionScoreTotal: integer(old.taskCompletionScoreTotal) + data.taskCompletionScore,
      discussionScoreTotal: integer(old.discussionScoreTotal) + data.discussionScore,
      collaborationScoreTotal: integer(old.collaborationScoreTotal) + data.collaborationScore,
      ideaScoreTotal: integer(old.ideaScoreTotal) + data.ideaScore,
      reliabilityScoreTotal: integer(old.reliabilityScoreTotal) + data.reliabilityScore,
      updatedAt: FieldValue.serverTimestamp(),
    };
    const resultsAvailable = aggregate.completedReviewerCount >= membersSnapshot.size;
    let commentsByReviewee = null;

    if (resultsAvailable) {
      const submissionsSnapshot = await transaction.get(
        group.collection("peerReviewSubmissions"),
      );
      commentsByReviewee = new Map(
        membersSnapshot.docs.map((member) => [member.id, []]),
      );

      const appendComment = (revieweeUID, comment) => {
        const normalizedComment = typeof comment === "string" ? comment.trim() : "";
        if (!normalizedComment || !commentsByReviewee.has(revieweeUID)) return;
        commentsByReviewee.get(revieweeUID).push(normalizedComment);
      };

      submissionsSnapshot.docs.forEach((document) => {
        const submissionData = document.data();
        appendComment(submissionData.revieweeUID, submissionData.comment);
      });
      appendComment(data.revieweeUID, data.comment);
      commentsByReviewee.forEach((comments) => comments.sort((left, right) => left.localeCompare(right, "zh-Hant")));
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
    transaction.set(publicSummary, {
      totalReviewCount: aggregate.totalReviewCount,
      completedReviewerCount: aggregate.completedReviewerCount,
      taskCompletionScoreTotal: resultsAvailable ? aggregate.taskCompletionScoreTotal : 0,
      discussionScoreTotal: resultsAvailable ? aggregate.discussionScoreTotal : 0,
      collaborationScoreTotal: resultsAvailable ? aggregate.collaborationScoreTotal : 0,
      ideaScoreTotal: resultsAvailable ? aggregate.ideaScoreTotal : 0,
      reliabilityScoreTotal: resultsAvailable ? aggregate.reliabilityScoreTotal : 0,
      resultsAvailable,
      updatedAt: FieldValue.serverTimestamp(),
    });
    commentsByReviewee?.forEach((comments, revieweeUID) => {
      transaction.set(privateComments.doc(revieweeUID), {
        comments,
        publishedAt: FieldValue.serverTimestamp(),
      });
    });
  });

  return { submitted: true };
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
