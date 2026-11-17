# ADR 0039: Ads, consent and the Remove ads purchase behind `AdService`

**In short, for Michael:** every ad, the privacy form and the Remove ads purchase go through one
service, `AdService`. The game never waits for an ad: with no network, no consent or no ad to show,
it simply goes on. In tests, in the editor, in the web preview and in the dev APK the service fakes
the ads, so nothing real is ever requested there. Banners show only in the menus and at the foot of
the open pause menu (upright only). After a match, at most one full-screen ad, never in a new
player's first two matches and at most one per 4 minutes of play. You can watch an ad by choice for
double XP or for +500 credits in the next match. Remove ads removes banners and full-screen ads;
the by-choice offers stay.

Status: **accepted, 2026-11-15** (Michael: 1-7, 10, 11 A; "Ja, planen er godkendt"; accepted in
docs row P400b of `docs/plans/2026-11-15-phase-6.md`, together with ADR 0040). Proposed 2026-11-15
(architect, row P400, branch `claude/p400-phase6-plan`, base `main` at a2204d2). Fix 1 the same
day: the lead's docs lens and the Phase 5 session's acceptance of the interfaces (the plan's
"Interfaces with Phase 5", with `fake_auto_close`). **Answered by Michael on 2026-11-15** (in chat,
through the Phase 6 lead): all A, so the plan's questions 1-7, 10 and 11 are decided as written
below.

Status note (2026-11-15, P400b docs; acceptance): Michael approved the plan on 2026-11-15 ("Ja,
planen er godkendt") with every question answered A; P400 merged as #472. The dated notes listed
under "Amends" are placed: ADR 0025 §11, §12, §15 and §17, and the hud-v2 plan's withdrawal of
P127. The `admob-policy` and CLAUDE.md texts are now plan row **P400c**, still pending Michael's
yes to the text (he said "wait" on 2026-11-15); where "P400b" below names those texts, read P400c.
Until that yes the internal build keeps Google's test App ID. §9 gains a note on the App ID's
route (P410, Michael 2026-11-15). No decision text changed.

Status note (2026-11-17, P400d docs; P405/P405b/P435 findings): P405 (#516), P405b (#517) and
P435 (#518) merged. Dated notes with what the merged code confirms, and where it no longer matches
this text, are added under §1, §2, §3, §5, §6, §9 and §10. §1's widget method `price_text` is
corrected to its name in the code, `remove_ads_price_text` (a name, not a decision). No
decision text changed.

Amends (dated notes in P400b, after acceptance; no accepted text is rewritten):
- `docs/plans/2026-11-01-hud-v2.md` row **P127** is absorbed by this plan: the band is row P430,
  the pause menu's foot P435, the menu banners are Phase 5's menus placing the band (§5), the
  "+500 starting credits" offer is P433. P127 itself is withdrawn.
- ADR 0025 §11's note of 2026-11-05 ("sideways ... and on short screens the menu scrolls: there it
  shows no banner until P127's row decides"): decided in §6 below.
- ADR 0025 §17's "no ad node in the battle scene": narrowed to "no ad node in the battle scene but
  the pause menu's `AdBannerBand`, which holds no banner while the menu is closed" (§6), and the
  scene-tree scan (`hud_walk.gd`) exempts the autoload node `/root/AdService` alone, which holds no
  banner child (P401).
- ADR 0025 §12's banner "only when Phase 6's `AdService` exists": it exists from P401 on; the start
  page keeps its 48 dp of air (§5).
- The `admob-policy` skill's pause-menu cell ("none until P127 decides") gets the plan's draft
  text, pending Michael's yes to the text (P400b).
- Michael chose 10 A (the real App ID in the internal-testing build), so CLAUDE.md's Monetization
  line "real IDs are injected only by the release workflow" and `admob-policy`'s "IDs and test
  mode" bullet change to the plan's draft texts, pending Michael's yes to the text (P400b). Until
  then the internal build uses Google's test App ID as well.

## Context
- `game/ads/` is empty; `game/meta/` holds only `HudPrefs.gd`. No ad, consent or billing code
  exists, and no plugin is vendored (`addons/` holds gdUnit4 only).
- A separate Phase 5 session builds the menus, `Progression` (rank, XP), `SaveService`, the boot
  flow, `MenuFlow` and `MatchSetup` (rows P501-P532 of `docs/plans/2026-11-15-phase-5.md`). On
  2026-11-15 the two sessions agreed a contract: Phase 5 calls one facade, `AdService`, places Phase
  6's banner band and hosts Phase 6's widgets in slots. This ADR builds on it; the plan's
  "Interfaces with Phase 5" holds it item by item, with the typed signatures.
- The repository holds no fact about the Poing Studios plugin (version, API names, how the AdMob
  App ID reaches the manifest, banner positions). `mobile-development/references/iap-and-ads.md`
  documents the first-party `GodotGooglePlayBilling` plugin (`BillingClient`, its signals and
  rules: acknowledge within 3 days, never grant `PENDING`). Each fact below that comes from
  neither is marked **to confirm** with the row that confirms it.
- The sim already takes per-player match setup outside Commands: `income_percent` (P173) is a
  setup array, set before tick 0, recorded in the `Replay` and covered by `defs_hash`.

## Decision

### 1. One facade, internal classes behind it
- **`AdService`** is an autoload (`res://game/ads/AdService.gd`, no `class_name`, the name
  CLAUDE.md gives). It is the only thing Phase 5 calls. Signals, methods, their types and the
  property `fake_auto_close` are exactly the contract's (plan, "Interfaces with Phase 5", item 1),
  including `take_start_credits_bonus() -> int`. P401 lands them first as a fake-mode stub, and its
  contract test pins them.
- **Internal** (Phase 6 only; Phase 5 never names them): `AdsSettingsDef` and
  `data/ads_settings.tres`; `AdCaps` (pure rules); `AdLedger` (counters and the pending start
  bonus); `AdBackend` with `FakeAdBackend` and `AdMobBackend`; `ConsentGate` with `FakeUmp` and
  `UmpPluginBackend`; `Purchases` with `FakeBilling` and `PlayBillingBackend`; `AdIds`.
- **Only `AdMobBackend` and `UmpPluginBackend` name Poing classes; only `PlayBillingBackend`
  names `BillingClient`.** A scan test enforces it, and that nothing in `game/sim`, `game/ai` or
  `game/core` names `AdService` or `game/ads`.
- Phase 6's widgets (the banner band, the rewarded offers, the Remove ads rows) may call internal
  methods (`rewarded_ready`, `show_rewarded`, `show_banner`, `hide_banner`,
  `remove_ads_price_text`). Phase 5 calls none of them: its menus place the band, which shows its
  banner on `enter_tree` and hides it on `exit_tree`.

Note (2026-11-17, P400d docs; P405/P405b findings): neither backend names a Poing GDScript class.
`AdMobBackend` and `UmpPluginBackend` reach the plugin's native singletons (`PoingGodotAdMob...`,
by name) through an injectable lookup (`Engine.get_singleton` by default, fake objects in tests),
so they import unchanged in every build without the plugin. The plugin's native Android part is not
vendored: the facts in the notes under §2, §3 and §5 come from the vendored v5.1.0 GDScript
wrappers and mocks (`addons/admob`), and the device-only ones are marked.

### 2. Modes; gameplay never waits for an ad
- **AdMob mode** only when all hold: the OS is Android, not the editor, the plugin's singleton
  exists, and the build is the Play preset (feature tag `play`, ADR 0040 §1). Otherwise **fake
  mode**: editor, tests, web preview, desktop, and the dev and perf APKs (they ship no plugin).
- **Fake mode** is scriptable for tests (ready or not, filled or not, reward or cancel, error,
  never answers, never closes). It draws a placeholder banner of the real size, labelled "Test
  ad", and a full-screen "Test ad" with a Close button, so the flows can be tried on the phone
  preview.
- **`fake_auto_close`** (default true when `DisplayServer.get_name() == "headless"`, else false;
  tests may set it). P401's stub returns from every call at once, and so does fake mode with no
  fill. From P403, with `fake_auto_close` false, the placeholder full-screen ad is awaited until
  its Close, and the fake consent and purchase flows wait for their buttons; with it true they
  close at once, a fake rewarded ad grants or not per a fake setting, and
  `maybe_show_interstitial` and the offer flows return at once (gdUnit4).
- **Nothing waits for an ad that has not shown.** The timeouts cover only the wait before
  something shows: `consent_timeout_ms` the consent info update and the form's load,
  `fullscreen_timeout_ms` a full-screen ad until `ad_opened`. When one passes, the call returns
  false (consent: ads stay unrequested) and nothing shows later for that call. **Once the form or
  an ad has shown, the call waits for its dismissal or close**, with no timeout: the game never
  goes on under an ad. With no network, no consent or no fill the calls return false and show
  nothing. No spinner, ever: an offer whose ad is not loaded is hidden.
- SDK callbacks are handled on the main thread (deferred). Whether the plugin already emits there
  is **to confirm in P405**.

Note (2026-11-17, P400d docs; P405 findings, Poing godot-admob v5.1.0):
- Uids are per singleton (the interstitial and the rewarded singleton both count from 1), so
  `AdMobBackend` keys its state by (kind, uid) and ignores a callback whose uid is not the kind's
  current one.
- Every plugin signal is connected with `CONNECT_DEFERRED`, so the backends' signals fire on the
  main thread (the wrappers defer too). The thread question above is closed.
- The reward arrives only through `on_rewarded_ad_user_earned_reward`. Signals are relayed in
  arrival order, so a reward that arrives after the close is dropped, never granted.
- A shown ad cannot be cancelled: `cancel_show` does nothing; AdService pairs a late open
  (`FullscreenRun`).

### 3. Consent (UMP) before any request
- `ensure_consent() -> bool` updates the consent info, shows Google's form when UMP says it is
  required, waits for its dismissal, and returns UMP's "can request ads" (also emitted as
  `consent_finished`). `MobileAds` is initialised, and any ad is loaded, only when it is true.
  Every load asks the gate again.
- `is_privacy_options_required()` is UMP's answer; `show_privacy_options()` shows UMP's form and
  returns when it closes.
- UMP's form is expected to need the real AdMob App ID with a configured GDPR message (Google's
  sample App ID may not show it), which is why the internal build carries the real App ID
  (Michael's answer 10 A): **to confirm in P404/P405**.
- Debug builds set UMP's debug geography to EEA for registered test devices; the device hash
  comes from a local git-ignored file, never from the repository (**to confirm** the plugin's
  call in P404/P405).
- The game is not child-directed: Play's target audience is 13 and over (not the Families
  programme), and the maximum ad content rating in the AdMob console is T (answer 11 A).

Note (2026-11-17, P400d docs; P405/P405b findings):
- The plugin's consent status enum is UNKNOWN 0, NOT_REQUIRED 1, REQUIRED 2, OBTAINED 3, not the
  order of `ConsentBackend.Status`; `UmpPluginBackend` maps it. The plugin has no "can request
  ads" call, so it is derived: true for NOT_REQUIRED or OBTAINED.
- The request configuration sets max ad content rating T, not child-directed and not under the
  age of consent; UMP's info update gets the same under-age answer (false). Its test device list
  is empty.
- Offline: with no network the info update fails or times out (`consent_timeout_ms`) and no ad is
  requested for that session. There is no fallback to a stored consent (UMP's own pattern would
  use it). Revisit only with a device finding.
- The debug geography cannot be exercised on a device as written here and in P422: it needs a
  debug build (`ConsentFlow` drops it otherwise), `AdService.debug_geography_eea` set (only tests
  set it) and `res://consent_test_device.cfg`, which is debug-only and which no preset exports.
  No AdMob-mode build is a debug build: the only one is the `Android internal` AAB, exported with
  `--export-release`. P414 must register Michael's phone as an AdMob test device (plan M8) before
  real units ship.

### 4. Caps and placements (`data/ads_settings.tres`)
| Field | Value (answer 2 A for the caps) | Rule |
| --- | --- | --- |
| `interstitial_free_matches` | 2 | none in a player's first 2 completed matches |
| `interstitial_min_play_s` | 240 | at least 4 minutes of play since the last one |
| `interstitial_per_match` | 1 | at most one per completed match |
| `fullscreen_timeout_ms`, `consent_timeout_ms` | 8000, 10000 | the longest wait before an ad or the form shows (§2) |
| `reward_xp_multiplier` | 2 | Double XP |
| `reward_start_credits`, `start_credits_bonus_max` | 500, 500 | one pending bonus, no stacking |
| `rewarded_offers_per_screen` | 1 | one offer per screen |
| `banner_gap_dp` | 16 | the least air between a banner and any control |
| `start_banner_gap_dp` | 48 | the start page's air round its banner (ADR 0025 §12) |
| `banner_reload_min_ms` | 30000 | a turn reloads at most this often |
| `remove_ads_product_id` | `remove_ads` | the Play product |

- **Play time** is the sim time of completed matches: `note_match_completed(play_seconds)` gets
  the finished match's sim ticks / the tick rate (an int) from `MenuFlow`. Pause, menus and
  loading do not count. A completed match is one that ended (win, loss, surrender); an exit
  mid-match is not.
- **An interstitial shows** only for placement `&"post_match"`, without Remove ads, with consent,
  after more than `interstitial_free_matches` completed matches, after `interstitial_min_play_s`
  of play since the last one, not twice for one completed match, and only if one is loaded. A
  shown one resets the play counter and records the match number.
- **Rewarded:** the offer names the exact reward, shows only when the ad is loaded, grants only in
  the SDK's reward callback, and the grant is saved before the close is handled (§7).
- **Banners:** main menu, map select, settings (Phase 5's menus place the band, §5) and the pause
  menu's foot (§6).
  `banner_height_dp()` is the adaptive anchored height whenever a banner may show (consent allows
  it, no Remove ads, a band is in the tree); otherwise 0. It changes, with `banner_changed`, on
  consent, entitlement, show, hide and a turn (the adaptive height follows the width), not on
  fill, so a late fill does not move the layout.

### 5. The banner band
- One scene, `AdBannerBand` (P430), serves every placement: Phase 5's menus and the pause foot
  place it in their bottom band and call nothing. It reserves `banner_height_dp()` plus the gap,
  shows its banner on `enter_tree`, hides it on `exit_tree` and lays out again on
  `banner_changed`.
- A banner sits in that bottom band of the safe rect, the full width, with at least
  `banner_gap_dp` (16) to any control above it, never beside, between or over controls; the start
  page uses `start_banner_gap_dp` (48, ADR 0025 §12). The band shows a small "Advertisement"
  caption above the banner in the theme's text colour, with no frame (answer 4 A).
- After a turn the banner is destroyed and loaded again at the new width (ADR 0015 §5's open
  point), at most once per `banner_reload_min_ms`; until then the band is empty.
- Whether Poing's banner takes a custom position or only screen top/bottom is **to confirm in
  P405**. If only the bottom, the band is at the screen's bottom and the safe-area inset lies
  under the banner, so menus reserve the inset plus the band.

Note (2026-11-17, P400d docs; P405 findings):
- `AdMobBackend` creates an anchored adaptive banner at the plugin's `AdPosition.BOTTOM` with no
  custom position (the plugin takes one; it is not used). Its height is 0 until the native load
  succeeds (`banner_height_changed`), and again after a failed load.
- After a turn the banner is destroyed and created again at the new width at once; the height is
  0 until the new one loads. `banner_reload_min_ms` gates only the reload of a failed banner (which
  keeps its view) and, in AdService, rewarded retries, so "at most once per
  `banner_reload_min_ms`" above does not match the code for a turn.
- Remove ads and lost consent destroy the view (`destroy_banner`), not hide it. A full-screen ad
  whose load fails is destroyed natively, so no-fill retries do not leak.
- To confirm on the device (P410b's build or P422): whether a created view is visible before its
  first `show`, the size unit (dp assumed: the adaptive size call takes a width), whether BOTTOM is
  the screen's or the safe area's bottom, and whether the native side reuses a destroyed ad's uid
  (a late callback of the old ad would then match the new one).

### 6. The pause menu's foot (P127 decided)
- Upright, where the foot is free (below the Vibration chip, with 16 dp to it), the foot holds the
  band while the menu is open.
- **Sideways, and whenever the menu scrolls: no banner** (Michael's answer 5 A). Sideways
  the button column reaches the safe bottom, so a banner would sit beside controls.
- The banner is shown when the menu opens and **destroyed** when it closes. No banner object
  exists in battle while the menu is closed: a hidden banner still refreshes and costs network
  and CPU during play.

Note (2026-11-17, P400d docs; P435 findings): `PauseMenu` builds the band hidden (it then holds no
show) and, two frames later when the layout has settled, shows it only if
`AdBannerBand.preview_reserved_px()` fits under the content; otherwise it frees it. The preview
comes from `AdService.banner_height_preview_dp()`, which makes no request. Upright only; while a
confirm dialog is open the band is freed (placed again when the dialog closes); a resize or a turn
checks again. On close the band node is freed, but AdService then only hides the native banner
(`hide_banner`); it destroys it only on Remove ads or lost consent. So a hidden native view can
exist in battle, which "No banner object exists in battle" above does not allow: a follow-up for
the lead (destroy on the last release, or a device finding that a hidden view does not refresh).

### 7. Rewards enter meta and the match only through Phase 5's paths
- **Where** (Michael's answer 1 A): Double XP on the result screen; "+500 credits next match" on
  map select only; no offer on the main menu or settings. One offer per screen.
- **Double XP:** in the reward callback the widget calls `Progression.apply_bonus(award_id,
  reward_xp_multiplier)`, which applies once per award and persists before it returns.
- **+500 starting credits:** in the reward callback `AdLedger` records one pending bonus (capped
  by `start_credits_bonus_max`) in the `ads` save section; the widget writes no `MatchSetup`, so a
  granted bonus survives an app kill before the match. At match start, Phase 5's setup path calls
  `AdService.take_start_credits_bonus()` (the bonus once, then 0) and writes it into
  `MatchSetup.bonus_starting_credits`. The sim applies it at load as setup data recorded in
  the replay, as `income_percent` is (P173). It is **never a Command** and never written into a
  live World: a "grant credits" Command would let any Command source mint credits, and it would be
  a cheat path for multiplayer. Computer players, the smoke and the harness never get it.

### 8. Remove ads
- One non-consumable product (`remove_ads_product_id`) at **29 kr** (Michael's answer 3 A; set in
  Play Console, and the game shows Play's localised price text, never a literal). Purchase: query
  the product, launch, and on `PURCHASED` (never `PENDING`) acknowledge, record the entitlement,
  save, emit `entitlement_changed`. Banners are destroyed and interstitials stop; rewarded offers
  stay.
- `restore_purchases()` (the "Restore purchases" row) queries Play. Play's answer is the truth when
  it answers; offline, the cached entitlement stands; a successful query without the purchase clears
  the cache (a refund).
- The plugin is the first-party `GodotGooglePlayBilling` (API as in the reference above). Its
  release for Godot 4.7 and the Play Billing Library version it wraps against Play's minimum then
  are **to confirm in P411**.

### 9. Ad IDs
- `AdIds` holds Google's published test IDs as constants (to confirm against
  https://developers.google.com/admob/android/test-ads in P405). Real **ad unit** IDs come only
  from a git-ignored `res://ad_ids.cfg` that a workflow writes into the export (ADR 0040 §7); it
  holds unit IDs only. Without it, every build uses test units.
- The **App ID** is not read at run time: the SDK reads it from the manifest, so it must reach the
  manifest at build time (the plugin's export option or a manifest step: **to confirm in
  P410/P410b**; ADR 0040 §5).
- A guard test fails on any `ca-app-pub-` or `pub-` ID with 16 digits in a tracked file other
  than Google's test publisher `3940256099942544` or the placeholder `0000000000000000`.

Note (2026-11-15, P400b docs; P410, Michael 2026-11-15): the App ID's build-time path is the Poing
plugin's project setting `admob/general/android/app_id` (v5.1.0, pinned with two documented local
patches; ADR 0040's status note of 2026-11-15). Its default is Google's test App ID, so every build
without an override carries the test App ID. The plugin is enabled only for P410b's `--aab` run.
P414 sets the real one from `ADMOB_APP_ID_ANDROID` for the `Android internal` export only, never
in a tracked file (the guard above), and only after Michael's yes to the P400c text.

Note (2026-11-17, P400d docs; P405 findings, for P414): `res://ad_ids.cfg` is one `[units]`
section with the keys `banner`, `interstitial` and `rewarded`, unit IDs only; a key that does not
match `ca-app-pub-<16 digits>/<10 digits>` falls back to its test unit. It is git-ignored and read
only by a release build (a debug build always uses the test units). Today no build packs it: it is
not an imported resource and no preset's `include_filter` names it. P414 must add it to the
`Android internal` preset's `include_filter`, with a check that the bundle holds it, and widen
`scripts/ci/check-aab.sh`, which today fails on any publisher ID but Google's test one in the
manifest or the assets. `res://consent_test_device.cfg` (`[consent]` `test_device_hash`) is also
git-ignored, debug-only and not exported (§3's note).

### 10. Save and audio
- Phase 6 keeps its state in Phase 5's `SaveService` section `ads`: `completed_matches`,
  `play_s_since_interstitial`, `last_interstitial_match`, `remove_ads` (the cache),
  `pending_start_credits`. UMP keeps its own storage. Until `SaveService` lands the ledger lives
  in memory (fake mode only).
- `ad_opened` and `ad_closed` wrap every full-screen ad; Phase 5's `AudioService` mutes on them.

Note (2026-11-17, P400d docs): stale in one point. "Until `SaveService` lands the ledger lives in
memory (fake mode only)" no longer holds: since P407 (#504) the ledger is the `ads` section of
`SaveService`, with the five keys above, read in AdService's `_ready` (the autoload follows
`SaveService`); the entitlement, a shown interstitial and a start-credits grant flush at once.
Consent is not saved. The audio line matches the code.

### 11. Proof (headless)
The facade's typed signatures and `fake_auto_close`; the caps table row by row; the reward only in
the callback and saved before close; an offer hidden while not loaded; no load before consent (a spy
backend); every awaitable returning at its timeout under a backend that never answers before
showing, and staying pending under one that shows and never closes; `PENDING` never granted,
acknowledge called, restore and refund; the band at the six sizes of ADR 0015 §6 with the gap,
collapse to 0 and the turn reload; the pause foot upright only and no banner object while closed;
the scans of §1 and §9; the start bonus's replay giving equal hashes (Phase 5's row, this ADR's
acceptance). Not headless: the real SDKs, the UMP form, billing and the Play upload, checked on
Michael's phone (plan P422).

### 12. AdMob alone
No mediation and no other ad network in Phase 6: AdMob alone first, measured with AdMob's
reports, then decided (`admob-policy`, "Store setup"; Michael's answer 7 A).

## Consequences
- Phase 5 codes against a stub from P401 on, so neither session waits for the other's internals.
- The debug and perf APKs never load the AdMob SDK: their numbers do not include its cost. The
  Play build does (plan, Risks).
- `data/ads_settings.tres` sits under `data/**`, which starts `balance.yml`; P412 adds a negation
  for that file.
- Mediation stays out until AdMob alone has been measured (§12).

## Alternatives considered
- **UI calling the plugin directly:** rejected; no fake mode, no caps in one place, untestable.
- **Starting credits by a Command at tick 0:** rejected (§7).
- **A separate `user://ads.cfg`:** rejected by the Phase 5 contract (one versioned save file).
- **A banner sideways under the pause card, or at the end of a scrolling menu:** options 5 B and
  5 C, not chosen (beside controls, or moving under the finger).
- **+500 also on the main menu, or Double XP alone:** options 1 B and 1 C, not chosen.
