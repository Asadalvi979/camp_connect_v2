# Community discussion review — 28 November 2026

Fixed findings:
- Post deletion failed because the backend required a title absent from the UI delete payload. Deletion now accepts that payload.
- Exact document reads exposed removed posts and comments. Rules now require Published status, and comment/reaction reads also require an active community.
- The compose dialog could overflow with a small viewport or mobile keyboard. Its content is now scrollable.

Verification: Flutter analyze and both widget tests passed. The Firebase emulator suite passed with added regressions for the UI delete payload and denied reads of removed posts/comments. The updated rules were explicitly loaded into the running emulator before verification.

Limits: native Android and live Firebase have not been tested. Comment lists currently show the latest 50 comments. Reaction totals and comment moderation are not implemented. Pixel matching against the full Figma design was not part of this code review.
