# Implementation decisions

## 28 November 2026 — administrator platform coverage

The project owner explicitly requested administration on both mobile and web.
This supersedes the web-only administration constraint in SRS v1.2, including
CD-09 and FR-108. The original SRS is retained as historical documentation.

The administration shell now offers alumni review, community creation and audit
activity on both layouts. Mobile uses bottom navigation adapted from the supplied
web administration design. Authentication custom claims and trusted backend
functions enforce the same permissions on every client. Public registration
cannot create an administrator.

Current member work includes editable profile fields, a live dashboard and
community browsing/join/leave. Verified semester, category and graduation details
remain protected against member self-assignment.

## Mentorship eligibility — 28 November 2026

The user approved the proposed module with both senior students and approved
alumni as mentors. This expands SRS v1.2 formal mentorship beyond alumni. Active
junior/senior students may request guidance. Explore provides the mentor directory
and Sent/Received request lists. Messaging and notifications remain separate phases.
Pending limit 5 and rejection cooldown 7 days are configurable development defaults.
