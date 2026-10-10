---
name: admob-policy
description: Ad placement, consent and ad-ID rules for rts-mobile (AdMob through the Poing Studios plugin) - where each ad format may appear, frequency caps, the rewarded flow, UMP consent, the Remove ads purchase and release-only ad IDs. Use whenever touching ads, consent, purchases, rewards, progression or menus, even for small UI changes on menu screens.
paths:
  - "game/ads/**"
  - "game/meta/**"
  - "game/ui/menus/**"
---

# AdMob policy for rts-mobile

The game is free and funded by ads. Ads must never cost the player a battle or cost us the
AdMob account.

## Placement matrix
| Screen | Banner | Interstitial | Rewarded |
| --- | --- | --- | --- |
| Battle, including pause | Never | Never | Never |
| Match result | Never | After the player taps Continue, capped | Offer "Double XP" |
| Main menu, map select, settings | Adaptive banner at the bottom, at least 16 dp from any button | Never | Offer "+500 starting credits next match" |
| App start and loading | Never | Never | Never |

AdMob's own guidance rejects banners on gameplay screens where players tap continuously
(https://support.google.com/admob/answer/6275345). This game goes further: no ads in battle.

## Frequency caps (in `data/ads_settings.tres`)
- Interstitial: at most one per 4 minutes of play, none in a new player's first 2 matches,
  and at most one per completed match.
- Rewarded: whenever the player chooses, but at most one offer per screen.

## Rewarded flow
1. Show the offer with the exact reward.
2. Preload the ad. If it is not ready, hide the offer; never block the player with a spinner.
3. Grant the reward only in the SDK's reward callback.
4. Save the grant before resuming the game.

## Consent (EEA and UK)
- Show Google's UMP consent form at first launch; request ads only after consent info is updated.
- Settings shows "Privacy options" when UMP says it is required.
- The game is not child-directed. Set the maximum ad content rating in AdMob to match the
  game's age rating.

## IDs and test mode
- Debug builds, the editor, tests and the web preview use `AdService` fake mode or Google's
  official test ad units (see https://developers.google.com/admob/android/test-ads and the iOS
  equivalent). Never real IDs.
- Release builds get real IDs injected by the release workflow from `ADMOB_*` secrets.
  Real IDs are never committed.
- Never tap live ads on your own devices; register test devices.

## Remove ads purchase
- One non-consumable product that removes banners and interstitials. Rewarded offers stay,
  because the player chooses them.
- Settings has "Restore purchases" (required on iOS).

## Store setup
- `app-ads.txt` on the developer website listed in the stores must include this app's
  publisher ID.
- Start with AdMob alone and measure before adding mediation.
