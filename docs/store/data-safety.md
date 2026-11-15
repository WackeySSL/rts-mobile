# Play Data safety answers (draft)

Entered by Michael in Play Console (M2). Every row is **to confirm against Google's disclosure** before submitting.

Disclosures to check (URLs to confirm, they move):
- AdMob: https://developers.google.com/admob/android/privacy/play-data-disclosure
- UMP (the "Consent choice" row checks against it): https://developers.google.com/admob/ump/android/play-data-disclosure
- Play Billing and SDK data declarations, Play's Data safety form guide: https://support.google.com/googleplay/android-developer/answer/10787469

"Required or optional" is to confirm per row (AdMob says the advertising ID is optional).

| Item | Collected | Shared | Required or optional | Purpose | Status |
| --- | --- | --- | --- | --- | --- |
| Device or other IDs (advertising ID) | Yes, by AdMob | Yes, with Google | Optional (to confirm) | Advertising | to confirm against AdMob disclosure |
| Approximate location (from IP) | Yes, by AdMob | Yes, with Google | to confirm | Advertising | to confirm against AdMob disclosure |
| App interactions (ad interactions) | Yes, by AdMob | Yes, with Google | to confirm | Advertising, analytics | to confirm against AdMob disclosure |
| Diagnostics (crash, performance) | Yes, by AdMob | Yes, with Google | to confirm | Fraud prevention, security, and compliance | to confirm against AdMob disclosure |
| Purchase history | Handled by Google Play Billing; the app caches only the `remove_ads` entitlement on the device (ADR 0039 §10), and Billing's answer depends on that | to confirm | to confirm | App functionality | to confirm against Billing disclosure |
| Consent choice | Stored by UMP | to confirm | to confirm | Compliance | to confirm against UMP disclosure |
| Personal info, contacts, files, photos, audio | No | No | n/a | n/a | we collect none |

Other answers:
- Data of our own: none (no account, no server, no analytics of ours).
- Data encrypted in transit: yes for AdMob (its disclosure: TLS); UMP and Billing to confirm.
- Deletion request route: no account, so nothing of ours to delete; progress is local and removed on uninstall.
  Google-held data: Google's tools. Questions to `<contact email>` (the privacy policy lists the same).
- Privacy policy URL: the appcode.dk page from `privacy-policy.md` (M10).
