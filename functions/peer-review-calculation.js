function participantUIDs(values) {
  if (!Array.isArray(values)) return [];
  return [...new Set(values.filter((value) => typeof value === "string" && value))].sort();
}

function reviewedUIDs(state) {
  return participantUIDs(state?.reviewedUIDs);
}

function reviewerCompleted(reviewerUID, participants, state) {
  const reviewed = new Set(reviewedUIDs(state));
  return participants.every((participantUID) => (
    participantUID === reviewerUID || reviewed.has(participantUID)
  ));
}

function peerReviewProgress(rawParticipantUIDs, statesByUID = new Map()) {
  const participants = participantUIDs(rawParticipantUIDs);
  const completedUIDs = participants.filter((reviewerUID) => (
    reviewerCompleted(reviewerUID, participants, statesByUID.get(reviewerUID))
  ));
  return {
    participantUIDs: participants,
    participantCount: participants.length,
    completedUIDs,
    completedReviewerCount: completedUIDs.length,
    resultsAvailable: participants.length > 0 && completedUIDs.length === participants.length,
  };
}

function personalReviewSummaries(rawParticipantUIDs, submissions) {
  const participants = new Set(participantUIDs(rawParticipantUIDs));
  const summaries = new Map();
  const scoreKeys = [
    "taskCompletionScore", "discussionScore", "collaborationScore",
    "ideaScore", "reliabilityScore",
  ];

  const validSubmissionsByReviewee = new Map();
  for (const submission of submissions) {
    const revieweeUID = submission?.revieweeUID;
    if (!participants.has(revieweeUID)) continue;
    if (!scoreKeys.every((key) => Number.isInteger(submission[key])
      && submission[key] >= 1 && submission[key] <= 5)) continue;

    const values = validSubmissionsByReviewee.get(revieweeUID) || [];
    values.push(submission);
    validSubmissionsByReviewee.set(revieweeUID, values);
  }

  function median(values) {
    const sorted = [...values].sort((left, right) => left - right);
    const middle = Math.floor(sorted.length / 2);
    return sorted.length % 2 === 0
      ? (sorted[middle - 1] + sorted[middle]) / 2
      : sorted[middle];
  }

  validSubmissionsByReviewee.forEach((validSubmissions, revieweeUID) => {
    const medians = Object.fromEntries(scoreKeys.map((key) => [
      key,
      median(validSubmissions.map((submission) => submission[key])),
    ]));
    const acceptedSubmissions = validSubmissions.length < 3
      ? validSubmissions
      : validSubmissions.filter((submission) => {
        const extremeDifferenceCount = scoreKeys.filter((key) => (
          Math.abs(submission[key] - medians[key]) >= 2
        )).length;
        return extremeDifferenceCount < 3;
      });
    const trustedSubmissions = acceptedSubmissions.length > 0
      ? acceptedSubmissions
      : validSubmissions;

    const summary = {
      reviewCount: validSubmissions.length,
      acceptedReviewCount: trustedSubmissions.length,
      excludedReviewCount: validSubmissions.length - trustedSubmissions.length,
      taskCompletionScoreTotal: 0,
      discussionScoreTotal: 0,
      collaborationScoreTotal: 0,
      ideaScoreTotal: 0,
      reliabilityScoreTotal: 0,
    };
    validSubmissions.forEach((submission) => {
      scoreKeys.forEach((key) => { summary[`${key}Total`] += submission[key]; });
    });
    scoreKeys.forEach((key) => {
      summary[key] = median(trustedSubmissions.map((submission) => submission[key]));
    });
    summaries.set(revieweeUID, summary);
  });
  return summaries;
}

module.exports = { participantUIDs, peerReviewProgress, personalReviewSummaries, reviewedUIDs };
