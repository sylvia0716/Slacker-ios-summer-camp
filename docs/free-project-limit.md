# Free active-project limit

Free accounts may participate in at most **two unfinished projects**, counting projects they create and projects they join together. Memberships in projects that are settled, past their deadline, deleting, or no longer exist do not consume capacity. Leaving a project releases its slot. Missing/invalid deadlines count conservatively as unfinished.

Pending applications do not reserve a slot. A new application requires available capacity; approval checks capacity again. If an applicant has filled their slots since applying, approval fails without changing the pending application. The leader can still reject it. Retrying an existing application or approved membership remains safe. Existing memberships are not removed if an account is already over the limit.

## Enforcement

`functions/project-quota.js` counts authoritative Firestore memberships inside the same transaction that creates a project or admits a member. A server-only `projectQuotaLocks/{uid}` document serializes admissions for the same account, including concurrent calls from different devices. Clients cannot edit this document under the existing rules. No client-controlled premium flag is trusted.

The iOS app shows localized errors through its existing dialogs, with separate wording for the applicant and the reviewing leader. Local demo data is not subject to the cloud quota.

## Deployment

Deploy the three functions together after review:

```sh
firebase deploy --only functions:createGroup,functions:joinGroupByInviteCode,functions:reviewGroupJoinRequest
```

Ship the corresponding iOS build for readable quota messages. Old builds still receive a server rejection but may show their generic error. This change does not require new Firestore rules or indexes beyond the existing member lookup configuration. Local changes do not take effect on production until deployed.

## RevenueCat test purchase

The Debug app uses the RevenueCat Test Store public SDK key, associates the RevenueCat App User ID with the signed-in Firebase UID, displays the `monthly` package from the current offering, and supports purchase, restore, customer-info refresh, and the `oops_bomb_pro` entitlement. The account page has the Pro entry; quota dialogs can open it. Yearly and lifetime products remain in the dashboard but are not offered in this app flow.

Cloud Functions verify `oops_bomb_pro` against RevenueCat's subscriber API for the authenticated Firebase UID before creating a group, starting an application, or approving an applicant. Client-reported entitlement state is never trusted. If RevenueCat cannot be reached, users below the free limit can continue, while operations over the limit return a verification error. The backend needs `REVENUECAT_PUBLIC_API_KEY` set in its environment. For a local Functions emulator, put `REVENUECAT_PUBLIC_API_KEY=<your Test Store public SDK key>` in the ignored `functions/.env.local`. Do not deploy a Test Store key as a production entitlement source.

To demonstrate the entire flow without touching the shared Firebase project, run `npx --yes firebase-tools emulators:start --project group-bomb --only auth,firestore,functions,storage`, then add `-use-firebase-emulators` to the Debug app's Xcode launch arguments. Firebase's Firestore emulator requires Java. Create two unfinished projects with a test account, open Oops Bomb Pro from Settings or a quota dialog, and choose a **successful** Test Store monthly purchase. The same account should then be able to create a third project. Check the RevenueCat dashboard's sandbox customer record for an active `oops_bomb_pro` entitlement. Remove the launch argument to return to the normal shared Firebase configuration; emulator accounts and projects do not transfer there.

The Test Store key is Debug-only; Release does not initialize purchases or show a purchase button. Before shipping a real paid version, configure Apple App Store Connect subscriptions, connect them to the same RevenueCat entitlement and offering, use the Apple public SDK key in Release, set the matching backend key in the deployed Functions environment, and test purchase, cancellation, expiry, restore, and account switching with sandbox accounts. The RevenueCat dashboard still needs a designed paywall if the hosted RevenueCatUI paywall is desired. Customer Center is optional for this simple monthly flow; restore purchases is available now. None of the code here deploys backend functions or publishes a paid App Store product.

## Verification

```sh
node --test functions/*.test.js functions/*.test.cjs
firebase emulators:exec --project demo-group-bomb --only auth,firestore,functions 'node --test --test-concurrency=1 firebase-rules-tests/project-quota.test.mjs'
```

The emulator tests exercise real callable functions, mixed created/joined memberships, quota rejection, released capacity, concurrent creation/approval, parallel creation, and denial of direct client access to quota locks. They use only the demo Firebase project.
