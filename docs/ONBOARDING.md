# Setup and permission guide

Implemented in development 0.6.1. Setup is a convenience flow, not an OS-permission bypass. Completing or skipping the guide never implies every permission was granted.

## First run and returning users

- New Mac installs with no remembered phone automatically present a setup sheet once. Settings → Setup & permissions reopens it. Existing paired users are not forced through it on update.
- New Android installs with no trusted Mac show a Welcome prompt, offering Start setup or Later. Setup progresses through Welcome, Pair your Mac, Choose permissions and Ready. Returning users open it from Settings or Pair a Mac.
- Pairing still uses an expiring code and explicit phone-side trust confirmation. Existing credentials survive the update; no re-pairing is required.

## One-time access

The Mac's Set up recommended access requests undetermined notification, microphone and Bluetooth access in sequence. Existing grants are reused; denied grants require System Settings because macOS will not repeatedly show a fresh authorization prompt. The guide also shows the connected companion's actual reported permission states. It never starts a call, camera or screen session.

Android's Set up recommended access batches ungranted camera/notification runtime permissions, then walks through missing notification sharing, optional Accessibility phone control, shared storage and battery settings. Each special-access step explains its purpose and opens Android's own settings; return after reviewing it, or Skip. Already allowed steps are skipped. Individual Review actions remain available, including folder/media selection as alternatives to broad storage. A camera permission request does not open the camera. Revocation/denial is reflected when returning to the app.

The foreground clipboard toggle remains separate and optional. No Android microphone, contacts, call-log, SMS or Bluetooth runtime permission was added for the Mac HFP backend. Camera/microphone can be granted only once by the OS if the user chooses that mode; one-time grants and OS revocation still apply. Android screen capture always needs consent for each new session. Optional background camera policy remains per trusted Mac and is not enabled by setup. Battery settings, force stop/reboot and foreground-service rules still apply.

## Mac notifications

Notifications now includes a delivery status card, Review access and a local Test Mac banner button. If denied, enable Seamless in macOS System Settings → Notifications and select an alert/banner style. Phone app filters and Android notification-sharing access must also be configured. MacNotificationDelivery installs a foreground delegate so allowed notifications may show while Seamless is active, uses default sound, and reports scheduling errors. Focus, banner settings and quiet/provisional authorization remain macOS-controlled. The local test distinguishes Mac presentation from phone relay; it sends no message to another person.

## Device details on Android

The Overview shows a connection card, one compact Mac card per authenticated Mac, quick sharing actions and only pending sharing/transfer requests. Settings contains optional setup and connection policies. The Mac card uses an original Compose-drawn laptop illustration and reports device family/model, processor, RAM, startup-volume capacity/usage and macOS version. It intentionally omits serial numbers, private volume names and files. Hardware and volume metadata are collected off the Mac UI thread, tied to the authenticated client and refreshed at most once per minute while status updates arrive. Values are snapshots, not live disk measurements.

## Verification limits

Builds/regressions and completed device checks are recorded in VALIDATION.md. First-run behavior must also be checked on a genuinely new install; do not clear a paired user's credentials merely to simulate it. Use only devices explicitly authorized for testing.

Platform references: [Android runtime permissions](https://developer.android.com/training/permissions/requesting), [Android special access](https://developer.android.com/training/permissions/requesting-special), [Apple notification authorization](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).

0.6.10 pairing refinement: Mac creates the QR, Android scans it using optional camera access, and Android still displays the trust approval. Manual full-code generation is a visible/selectable fallback with progress, expiry and errors. QR scanning does not require camera access on the Mac.
