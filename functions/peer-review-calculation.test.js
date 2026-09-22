const test = require("node:test");
const assert = require("node:assert/strict");
const { peerReviewProgress, personalReviewSummaries } = require("./peer-review-calculation");

test("a member joining after the review roster is locked does not increase the requirement", () => {
  const states = new Map([
    ["a", { reviewedUIDs: ["b"] }],
    ["b", { reviewedUIDs: ["a"] }],
    ["late-member", { reviewedUIDs: [] }],
  ]);

  const progress = peerReviewProgress(["a", "b"], states);

  assert.equal(progress.participantCount, 2);
  assert.equal(progress.completedReviewerCount, 2);
  assert.equal(progress.resultsAvailable, true);
});

test("removing a member recalculates every remaining reviewer's completion", () => {
  const states = new Map([
    ["a", { reviewedUIDs: ["b"] }],
    ["b", { reviewedUIDs: ["a"] }],
    ["c", { reviewedUIDs: [] }],
  ]);

  const beforeExit = peerReviewProgress(["a", "b", "c"], states);
  const afterExit = peerReviewProgress(["a", "b"], states);

  assert.equal(beforeExit.completedReviewerCount, 0);
  assert.equal(beforeExit.resultsAvailable, false);
  assert.equal(afterExit.completedReviewerCount, 2);
  assert.equal(afterExit.resultsAvailable, true);
});

test("duplicate and invalid participant identifiers do not corrupt the denominator", () => {
  const progress = peerReviewProgress(["b", "a", "a", "", null], new Map([
    ["a", { reviewedUIDs: ["b", "b"] }],
    ["b", { reviewedUIDs: ["a"] }],
  ]));

  assert.deepEqual(progress.participantUIDs, ["a", "b"]);
  assert.equal(progress.completedReviewerCount, 2);
});

test("personal summaries contain only scores received by each participant", () => {
  const summaries = personalReviewSummaries(["a", "b", "c"], [
    { revieweeUID: "a", taskCompletionScore: 5, discussionScore: 4, collaborationScore: 3, ideaScore: 2, reliabilityScore: 1 },
    { revieweeUID: "a", taskCompletionScore: 3, discussionScore: 3, collaborationScore: 3, ideaScore: 3, reliabilityScore: 3 },
    { revieweeUID: "b", taskCompletionScore: 1, discussionScore: 2, collaborationScore: 3, ideaScore: 4, reliabilityScore: 5 },
    { revieweeUID: "outsider", taskCompletionScore: 5, discussionScore: 5, collaborationScore: 5, ideaScore: 5, reliabilityScore: 5 },
  ]);

  assert.deepEqual(summaries.get("a"), {
    reviewCount: 2,
    acceptedReviewCount: 2,
    excludedReviewCount: 0,
    taskCompletionScoreTotal: 8,
    discussionScoreTotal: 7,
    collaborationScoreTotal: 6,
    ideaScoreTotal: 5,
    reliabilityScoreTotal: 4,
    taskCompletionScore: 4,
    discussionScore: 3.5,
    collaborationScore: 3,
    ideaScore: 2.5,
    reliabilityScore: 2,
  });
  assert.equal(summaries.get("b").reviewCount, 1);
  assert.equal(summaries.has("outsider"), false);
  assert.equal(Object.hasOwn(summaries.get("a"), "reviewerUID"), false);
});

test("a consistently extreme review is excluded from a personal project score", () => {
  const summaries = personalReviewSummaries(["a"], [
    { revieweeUID: "a", taskCompletionScore: 5, discussionScore: 5, collaborationScore: 5, ideaScore: 5, reliabilityScore: 5 },
    { revieweeUID: "a", taskCompletionScore: 4, discussionScore: 5, collaborationScore: 4, ideaScore: 5, reliabilityScore: 4 },
    { revieweeUID: "a", taskCompletionScore: 1, discussionScore: 1, collaborationScore: 1, ideaScore: 1, reliabilityScore: 1 },
  ]);

  assert.equal(summaries.get("a").reviewCount, 3);
  assert.equal(summaries.get("a").acceptedReviewCount, 2);
  assert.equal(summaries.get("a").excludedReviewCount, 1);
  assert.equal(summaries.get("a").taskCompletionScore, 4.5);
  assert.equal(summaries.get("a").discussionScore, 5);
});

test("fewer than three reviews are never treated as anomalous", () => {
  const summaries = personalReviewSummaries(["a"], [
    { revieweeUID: "a", taskCompletionScore: 1, discussionScore: 1, collaborationScore: 1, ideaScore: 1, reliabilityScore: 1 },
    { revieweeUID: "a", taskCompletionScore: 5, discussionScore: 5, collaborationScore: 5, ideaScore: 5, reliabilityScore: 5 },
  ]);

  assert.equal(summaries.get("a").acceptedReviewCount, 2);
  assert.equal(summaries.get("a").excludedReviewCount, 0);
  assert.equal(summaries.get("a").taskCompletionScore, 3);
});
