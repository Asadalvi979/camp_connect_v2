# CampConnect

Flutter Android and web account-flow development, using Firebase emulators with
project ID `demo-campconnect`. The current implementation includes login,
registration, password-reset requests, numeric OTP verification, account status,
alumni review on mobile and web, editable profiles, a live dashboard, public community creation/join/leave flows, community discussions with posts, comments, reactions and reports, and mentorship requests. The uploaded CampConnect PDF designs are
the visual reference.

## Local development

Use Flutter 3.47.4, Node 22 and Java 21. In this cloud workspace the Flutter SDK
is at `/workspace/.camp-connect-sdk/flutter-3.47.4`. Set `PUB_CACHE` and
`XDG_CONFIG_HOME` to writable directories if the machine restricts home writes.

From the repository root:

```sh
flutter pub get
npm --prefix functions ci
npx firebase-tools@15.37.0 emulators:start --project demo-campconnect --only auth,firestore,functions
```

Keep the emulators running and start Flutter in another terminal:

```sh
flutter run -d chrome
```

Use debug mode for this emulator-only build. FlutterFire restores emulator sessions before Auth initialization in debug mode; production release configuration remains pending. The app connects only to local emulators. For the Android emulator use
`flutter run --dart-define=EMULATOR_HOST=10.0.2.2`.
Real Firebase configuration and live service deployment are a later step.
The functions print numeric OTPs to the local emulator log. Password-reset links
are provided by the Auth emulator. No email is sent in this development mode.
The numeric OTP registration function refuses to run outside the emulator until
email delivery is implemented.

Student email domain is `student.riphahsahiwal.edu.pk`. Registration offers session
and course dropdowns and asks the user for only the four-digit CMS number. The
app assembles an ID such as `F24-BSSE-0044` and shows a preview before submission.
The session list covers spring/fall 2022 through the next calendar year; course
options are BSSE, BSCS, BSAI, BSIT, BBA, Pharm-D (`PHARMD`) and DPT. These
options can be adjusted when the official campus program list is supplied.
Semester 1–4 assigns Junior Student;
5–8 assigns Senior Student. Alumni stay Pending Admin Review after OTP verification.
OTP development defaults are five-minute expiry, five attempts and a one-minute
resend interval. These defaults need confirmation before production.

Accounts and CMS reservations are server-owned. Users can read their own account;
all client writes are denied. `reviewAlumni` requires an Auth `admin` custom claim
provisioned through a trusted administrative process and records an audit event.
Account status in Firestore is currently authoritative. Member category/status
custom claims and their synchronization are pending production identity work.

## Verification

With the emulators running:

```sh
node functions/test/accounts.cjs
flutter analyze
flutter test
flutter build web --debug
```

The backend test creates local test accounts and checks CMS uniqueness, resend
limits, OTP handling, activation, alumni approval, private account access,
post and comment creation, reaction, reporting and admin moderation.
The Flutter tests cover mobile/desktop layout and CMS validation. Web renderer
assets and Inter font are bundled locally.

## Administrator access on mobile and web

The user's 28 November 2026 decision enables administration on both platforms,
superseding the web-only requirement in SRS v1.2. The mobile admin layout adapts
the provided desktop admin design with bottom navigation. Backend custom-claim
checks apply identically on both platforms.

With the emulators running, provision a local administrator from the project root.
In PowerShell, set these environment variables using your chosen local test credentials:

```powershell
$env:FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:9099"
$env:CAMP_ADMIN_EMAIL="your-local-admin@example.com"
$env:CAMP_ADMIN_PASSWORD="your-chosen-test-password"
node functions/scripts/create-emulator-admin.cjs
```

Sign in with that account on mobile or web to access Overview, Verification,
Communities and Audit activity. Public registration cannot grant admin access.
Approving, rejecting and requesting information record audit events. Rejected
applicants can resubmit only after an administrator requests information again.
Profile editing preserves verified semester, category and graduation details.
Communities are created by admins, with atomic name uniqueness and idempotent
creation IDs. Active members can join and leave communities. Joined members can
publish, edit and delete their own posts and comments. Active users can read
published discussions and report posts. Admins can review reports and remove
reported posts on mobile and web. Post and comment creation uses operation IDs
to prevent duplicate writes after retries. All discussion writes run through
Cloud Functions, and Firestore rules prevent direct client writes.

## Remaining work

Messaging, resources, projects, notifications,
SQLite drafts, avatar uploads and expanded admin user management remain
for subsequent increments. Terms/privacy copy and live email delivery require
approved content/provider configuration. Live Functions and Storage require Blaze.
Native Android build/device testing remains pending because this cloud machine
has no Android SDK/emulator or KVM device. Mobile layouts are checked at 390 px in
Chromium. The emulator functions ran on the host's Node 24; Node 22 remains the
configured deployment runtime.

## Mentorship

Open **Explore** to browse active senior students and approved alumni. Mentor
profiles show department, skills, bio and availability. Directory search filters
loaded results; use Load more mentors to include more profiles. Students and
seniors can send a message with their request, see Sent requests, and cancel a
Pending request. Mentors can toggle availability and accept/reject Received
requests. Requests are private to their two participants; client writes are denied.

Defaults: five Pending requests per requester and a seven-day cooldown after
rejection. Configure `MENTORSHIP_PENDING_LIMIT` and `MENTORSHIP_COOLDOWN_DAYS`
on the backend before deployment if different limits are approved. Accepted
requests record conversation authorization for the future messaging module;
chat and notifications are not implemented yet. A cancelled/rejected request
that is resubmitted replaces the current pair's record.

The approved development plan includes senior mentors as well as alumni, extending
SRS v1.2's alumni-only formal mentorship eligibility. Backend emulator tests cover
eligibility, duplicates, cancellation, acceptance/rejection, cooldown, pending
limits, availability, participant read privacy and direct-write denial.
