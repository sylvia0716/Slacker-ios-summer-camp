# Internal developer tools

Firebase project: `group-bomb`.

The existing 12 Email accounts approved on 2026-09-28 are the internal developer cohort. The 30 anonymous accounts and newly registered accounts are not automatically included. App code does not contain their emails or UIDs.

- Trusted administration sets the Firebase Authentication custom claim `groupBombDeveloper: true` on each approved UID, preserving other custom claims.
- `AuthSessionStore` reads the claim from the Firebase SDK token result. Only an explicitly true boolean on a signed-in, non-anonymous Email account enables access.
- Claims are refreshed on authentication/token changes and on foreground entry. Account changes clear access immediately; stale responses cannot grant access to a different account. A failed lookup denies access.
- Settings exposes the existing developer tools in both Debug and Release only for authorized accounts. Losing access exits demo mode. `AppStore` also guards demo mode entry and demo review resets.
- The flag grants no Firebase Console, Apple Developer, group leader, Firestore, or Storage privileges. Existing backend authorization remains unchanged. Demo fixtures remain local.
- This is a runtime feature permission, not a TestFlight invitation or distribution restriction. The updated App must be built and distributed before existing TestFlight installations can use it.

To revoke access, a trusted administrator removes only `groupBombDeveloper` (or sets it to false), preserving other claims. The app observes the change after token refresh/relogin; previously issued tokens are not instantly rewritten. Never expose a client endpoint that lets users set their own claims.

Validation: `DeveloperAccessTests` covers explicit boolean validation, missing claims, anonymous/signed-out users, account changes, stale responses, and failed/revoked access. Build Release as well as Debug when changing these tools.
