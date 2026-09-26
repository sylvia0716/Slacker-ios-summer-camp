# Smart Agenda QA — 2026-09-26

## Current review scope

- Integrated project-page agenda summary and detail navigation, own-material editing, shared meeting links, bilingual labels, preparation counts, and member progress ordering.
- The entrance animation has progressive sparks and pressure motion. Replay, early skip, immediate replay after skipping, and return to the login screen were verified through serve-sim. Timing uses a monotonic clock; stale completion work and zero-size drawing are guarded.
- Simulator Debug build and 62 server tests passed before integrating the latest main branch. Subsequent merge validation is recorded in the pull request.
- Live OpenAI generation remains unverified because API credits are exhausted; no new paid provider request was made during this review.
- Sections below retain the findings and limitations from earlier development stages.

## Language follow-up

- Smart Agenda uses the existing `AppLanguageSettings` / `L10n` path for all interface copy, sheets, errors, preparation counts, date formatting and minute units. The card continues to use `BombTheme.paper`, matching member progress.
- The explicitly tagged, app-created test fixture has Chinese and English sample translations. Real member names, notes, meeting topics and filenames are preserved as authored.
- New OpenAI plans contain matching English and Traditional Chinese titles/goals for the same 3–4 intervals. The viewer chooses the language locally; switching does not rewrite shared meeting data or trigger another AI call. Missing or oversized translations are rejected.
- `generateSmartAgendaPlan` was updated and verified ACTIVE at `2026-09-25T19:40:37Z`. API-credit exhaustion remains; bilingual provider responses are covered with adapter tests, not a claimed live AI success.
- Six Swift localization tests and thirteen agenda server/adapter tests passed; simulator build passed. An existing resource loader now resolves the actual localization-directory casing (SwiftPM emits `zh-hant`, not `zh-Hant`).
- serve-sim verification: Chinese topic/date/preparation/stages/buttons, Chinese material-editor labels, then Settings → General → English and the same four stages in English. Restored the user's original **Follow System** preference afterward.

## Historical Firebase / cloud AI integration checkpoint

**Result: Firebase deployed and app build verified; live OpenAI generation blocked by exhausted API credits. Final simulator interaction checks are pending because the Mac locked.**

- Work remains uncommitted on `feature/attachments-widget`. No Git push was made.
- The user's deployment approval supersedes the earlier preview-only scope below. Smart Agenda is now embedded in the existing project detail page. The existing entrance animation, authentication, settings and localization edits were preserved (five-file SHA-256 comparison passed).
- A newly approved OpenAI key was securely saved to ignored `.env.local` and Firebase Secret Manager. Only the cloud generation function receives the secret; the app does not contain it. No key value was printed or committed.
- Production project `group-bomb`, region `asia-east1`: `updateSmartAgenda`, `generateSmartAgendaPlan`, `syncAgendaMembership` and `cleanupAgendaAttachments` are ACTIVE. Deployed Firestore and Storage rule contents exactly match the local rule files.
- Real server generation uses OpenAI Responses with structured output, 3–4 stages, a goal per stage, and contiguous integer-minute intervals totaling the chosen duration. Transactional leases and revision checks discard duplicate or outdated results. Members cannot publish arbitrary generated plans.
- The direct provider check returned HTTP 429 `credit_balance_exhausted` / `insufficient_quota`. Live generation is **not verified**. No repeated provider calls were made after this finding. Adding API credits is required for the final cloud-AI test.

### Test data available in the app

- Group: `Firebase 雙帳號測試小隊` (`ca563c84-ec75-4e41-9248-eed9bcf7e36f`). Existing members, roles, deadline and tasks were preserved.
- Meeting: `[Test] Finalize Our Demo`, September 30 at 15:00 Asia/Taipei, 20 minutes, 8/8 members prepared with sample notes.
- Four explicit **sample** stages: 0–4 review materials; 4–9 decide feature order; 9–15 align narration and visuals; 15–20 finalize assignments. The UI labels this `Sample meeting plan`, never AI-generated output.
- Added 16 tasks prefixed `[議程測試]`, two per member, each with three subtasks. Existing 13 tasks remain, for 29 total.
- Native iOS build succeeded (`/private/tmp/agenda-cloud-build.log`), installed on the existing iPhone 17 Pro simulator and opened through serve-sim at `http://127.0.0.1:3231/`.
- After re-entering the project, the actual app displayed the shared meeting, 8/8 preparation count, real member avatars and the newly assigned tasks. Full plan scrolling, opening the material editor and starting the meeting have **not yet been manually verified in this production-connected build**; the Mac locked before these interactions.

### Validation evidence

- 32 pure-function / API-adapter / existing membership and task-progress tests passed: `/private/tmp/agenda-cloud-tests.log`.
- 5 server workflow tests passed, covering duplicate events, edits during generation, membership changes, quota failures, retry throttling and unauthorized client publication: `/private/tmp/agenda-workflow-tests.log`.
- 6 Firebase emulator integration tests passed, covering leader/own-material permissions, note-only and attachment-only preparation, cross-account PDF bytes and shared meeting state: `/private/tmp/agenda-cloud-emulator-tests.log`.
- These emulator checks are not claims of a successful production OpenAI response or final production UI interaction test.
- `git diff --check` passed. An unrelated existing `firebase-rules-tests/firestore.rules.test.mjs` syntax error remains outside this change; the whole repository's test suite is not claimed to pass.

---

## Historical visual-preview review (before Firebase approval)

final result: passed

## Scope

Local DEBUG-only preview on `feature/attachments-widget`, entered with `-preview-smart-agenda`. This revision addresses the user's rejection of the previous text and styling. The supplied reference is authoritative for this preview.

The live project page, authentication, settings, attachments and Firebase services remain unchanged. Earlier uncommitted entrance-animation work is preserved. No commit or push was made. Plans and submissions remain in-memory examples, not live AI or Firebase data.

## Evidence

- Source: `/Users/yen/Desktop/UI/2026-09-24_4.26.18.webp` (650 × 1258, including a photographed phone bezel). The originally supplied Desktop file had moved into the UI directory.
- Final capture: `/Users/yen/.codex/visualizations/2026/09/15/01a0a3ee-4011-7c02-922b-4b4011bed4f2/smart-agenda-preview-v2.png` (1206 × 2622).
- Capture origin: Screenshot button in the serve-sim in-app browser at `http://127.0.0.1:3231/`.
- Native viewport: iPhone 17 Pro, 402 × 874 points at 3× density. Visible browser pane approximately 319 × 747. Native screenshots are independent of the scaled browser stream.
- Source and final native capture were compared together in one tool output, at the initial scroll position: Mia as leader, 4/4 prepared, Sep 30 at 3 PM, 20 minutes and three stages.
- Source card approximately x75–573, y492–1102; final native card approximately x48–1158, y977–2302. Normalized by card width, native card height is about 594 source pixels versus 610 in the reference, roughly a 3% difference. Photographed bezel/perspective and status-bar height are excluded.
- Focused card review also used `/Users/yen/Desktop/serve-sim-screenshot-2026-09-25T16-08-33-123.png` while scrolled. This was not used as evidence of the initial full-page layout.
- Final full-page review confirms the complete Start meeting button and My progress heading appear above the bottom navigation.

## Comparison and corrections

1. **Reopened — P2 text and color fidelity.** The previous report accepted existing app styling. The user rejected the overly rounded/heavy headings, yellowish card and pale text. That earlier pass is superseded.
2. **Resolved — text hierarchy and palette.** Preview styles now use Arial regular/bold card copy, non-rounded heavy section headings, a light cream card, cool gray notes/goals and dark primary copy. Topic, member and button weights were reduced. Sample wording follows the reference.
3. **Resolved — countdown character.** The preview uses segmented numerals with separate smaller day/hour/minute units. Production countdown code is untouched.
4. **Resolved — P2 lower heading occlusion.** The first revised render clipped My progress. Reducing outer section spacing and countdown vertical padding made Start meeting and My progress fully visible above navigation.
5. **Passed final comparison.** Topic/Edit alignment, prepared count, avatar/name/material columns, paperclip rows, thin separators and three goal-bearing stages follow the reference. No truncated sample text or overlapping Agenda controls remains.

## Fidelity details

- **Copy:** Finalize Our Demo; Wed, Sep 30 · 3:00 PM · 20 min; four names, notes and filenames; Add my material; AI suggested plan; Start meeting. No Ready badges, preparation checkmarks, colored type icons or preparation progress bar.
- **Typography:** ArialMT/Arial-BoldMT for card copy; system heavy without rounded design for section headings. The source photograph does not identify its font files; these are visually matched choices, not a claim of identical font assets.
- **Palette:** Preview-only yellow `(1, 0.81, 0)`, ink `(0.075, 0.075, 0.07)`, paper `(0.974, 0.958, 0.909)` and secondary `(0.34, 0.37, 0.42)`. Live BombTheme is unchanged. Source photographic shading is not recreated as a gradient.
- **Structure:** One cream card with a single dark outline, aligned three-column preparation rows, outlined add button, left time/right discussion-and-goal columns, black full-width meeting button.
- **Assets:** Initial avatars and SF Symbols. DSEG7 Classic Regular from the [official DSEG v0.46 release](https://github.com/keshikan/DSEG/releases/tag/v0.46), SIL OFL 1.1. Font and license are in `group/Resources/SmartAgendaPreview/`; runtime registration is scoped to the DEBUG preview.

## Verification

- Latest simulator Debug build passed: `/tmp/smart-agenda-style-build.log`. Existing unrelated DeadlineNotificationService warning remains.
- Installed/launched the latest build and inspected only through the serve-sim in-app browser.
- `git diff --check` passed. Hash checks confirm AppRootView, BombLaunchView, GroupBombApp and both existing localization files were unchanged during this style revision.
- Earlier checks against the same functional model passed: 10/15/20/30/45/60-minute plans contain 3–4 contiguous stages ending exactly at the chosen duration; leader-only editing; own-member update isolation; blank/note-only/file-only readiness; clearing material invalidates the plan. This revision changes countdown/name display data, not these behaviors.
- Earlier in-app interactions passed: Note/Attachment Sheet; retaining a note after removing an attachment keeps 4/4; generating state; Save dismisses the Sheet. Editing to 45 minutes displays 0–9, 9–22, 22–35, 35–45 and dismisses the Sheet.
- Final preview restored to the reference's 20-minute, three-stage example and left open for review.

## Preview limitations

- Real AI generation, shared persistence, attachment upload/download and backend authorization are not implemented in this visual preview.
- Peripheral project/navigation controls provide preview context, not replacements for the existing app screens.
- Start meeting and preparation replay are available but were not exhaustively UI-tested in this styling pass.
