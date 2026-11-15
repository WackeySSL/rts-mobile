# Play Console and ad setup checklist (M1-M11)

Steps only Michael can do, in order. Source: `docs/plans/2026-11-15-phase-6.md`. Never put secret values in
the repo or in chat; set them with `gh secret set`.

Decisions (Michael, 2026-11-15): target audience 13 and over (not Families); maximum ad content rating T;
Remove ads costs 29 kr; Play App Signing (Google holds the app key, Michael keeps the upload key and a backup).

- [x] **M1** Play developer account for AppCode ApS. Done (organisation account, Michael 2026-11-15). Check that the
  EU trader declaration is filled in.
- [ ] **M2** Create the app "Treadline: Offline RTS" (English, Game, Free, contains ads). Declarations: privacy policy
  URL (M10), ads, advertising ID use, target audience 13+, content rating questionnaire, Data safety
  (`data-safety.md`).
- [ ] **M3** Make the upload key (`keytool`, command in the plan) and set secrets in GitHub environment
  `play-internal` (deployment branch `main` only): `ANDROID_UPLOAD_KEYSTORE_BASE64`,
  `ANDROID_UPLOAD_KEYSTORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS` (value `upload`). Keep the keystore and a backup
  outside the repo.
- [ ] **M4** Play App Signing: accept Google's app signing key at the first release.
- [ ] **M5** First upload by hand: the AAB from the first `main` run, in Internal testing (locks `dk.appcode.rts`).
- [ ] **M6** Google Cloud project with the Google Play Android Developer API, a service account and JSON key ->
  secret `PLAY_SERVICE_ACCOUNT_JSON` (`play-internal`); invite the service account in Play Console with release
  rights to testing tracks.
- [ ] **M7** Internal testers list with Michael's Google account; opt in on the phone.
- [ ] **M8** AdMob: account (AppCode ApS, payments), the Android app (not listed yet); App ID -> secret
  `ADMOB_APP_ID_ANDROID` (`play-internal`); unit IDs -> `ADMOB_BANNER_ID_ANDROID`, `ADMOB_INTERSTITIAL_ID_ANDROID`,
  `ADMOB_REWARDED_ID_ANDROID` (environment `play-release`, may be set now); the phone as test device; Privacy &
  messaging: GDPR message (EEA, UK, Switzerland); maximum ad content rating T.
- [ ] **M9** Managed product `remove_ads` at 29 kr, after a build with `BILLING` is uploaded; license testing with
  Michael's account.
- [ ] **M10** Host `privacy-policy.md` on appcode.dk (Michael picks the URL, for example
  `https://appcode.dk/treadline/privacy`); put the URL in Play.
- [ ] **M11** Serve `https://appcode.dk/app-ads.txt` with the AdMob line (`app-ads.txt.md`); Play developer website
  `https://appcode.dk`; later link the app in AdMob once listed.
