# Play Data safety answers (draft)

Entered by Michael in Play Console (M2). Every row is **to confirm against Google's disclosure** before submitting.

Disclosures to check (all URLs to confirm, they move):
- AdMob: https://support.google.com/admob/answer/10171310
- UMP and consent: https://developers.google.com/admob/android/privacy
- Play Billing and SDK data declarations: https://support.google.com/googleplay/android-developer/answer/10787469

| Item | Collected | Shared | Purpose | Status |
| --- | --- | --- | --- | --- |
| Device or other IDs (advertising ID) | Yes, by AdMob | Yes, with Google | Advertising | to confirm against AdMob disclosure |
| Approximate location (from IP) | Yes, by AdMob | Yes, with Google | Advertising | to confirm against AdMob disclosure |
| App interactions (ad interactions) | Yes, by AdMob | Yes, with Google | Advertising, analytics | to confirm against AdMob disclosure |
| Diagnostics (crash, performance) | Yes, by AdMob | Yes, with Google | Analytics, fraud prevention | to confirm against AdMob disclosure |
| Purchase history | Handled by Google Play Billing | to confirm | App functionality | to confirm against Billing disclosure |
| Consent choice | Stored by UMP | to confirm | Compliance | to confirm against UMP disclosure |
| Personal info, contacts, files, photos, audio | No | No | n/a | we collect none |

Other answers:
- Data of our own: none (no account, no server, no analytics of ours).
- Data encrypted in transit: yes (to confirm for each SDK against its disclosure).
- Deletion request route: no account, so nothing of ours to delete; progress is local and removed on uninstall.
  Google-held data: Google's tools. Questions to `<contact email>` (the privacy policy lists the same).
- Privacy policy URL: the appcode.dk page from `privacy-policy.md` (M10).
