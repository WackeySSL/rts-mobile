# Game design document: rts-mobile (MVP)

Store title: "Treadline: Offline RTS" (ADR 0006; trademark search in Phase 7). Codename: rts-mobile.

## Pitch
A classic base-building RTS rebuilt for the phone: build a base, harvest ore, and out-produce
and out-manoeuvre one computer opponent in an 8-10 minute match. Free, playable offline,
funded by optional rewarded ads and capped post-match interstitials.

## Audience and platforms
- Adults 20+ who played PC strategy games, and newcomers who want short, readable strategy.
- Android first, iOS later. Landscape and portrait: the phone's sensor picks the orientation, also during a match
  (Michael, 2026-10-19; ADR 0015).
- English at launch; all strings in translation files from day one so Danish and German can follow.

## Pillars
1. Readable at a glance on a 6-inch screen.
2. Controls that feel natural with two thumbs.
3. Short matches with a clear arc: expand, build up, push.
4. Fair: the AI plays by the same rules and has no map vision it has not scouted.

## Match setup (MVP)
- 1 vs 1 against the AI on Easy, Normal or Hard.
- Both sides use the same faction in the MVP (mirror). A second, asymmetric faction comes after launch.
- Working faction names: Blue "Northern Coalition" and Red "Iron Directorate". Original lore with
  no link to existing franchises.
- Start: one Headquarters, 2 000 credits and 2 rifle squads.
- Victory: the enemy has neither a Headquarters nor a production building left.
- Target: median match length 8-10 minutes, checked by the balance harness.

## Economy
- Ore fields regrow slowly (1 unit per field cell per 10 seconds, capped).
- A harvester carries 500 credits per trip; every refinery comes with one free harvester.
- Buildings produce or consume power. Low power: production at 50% speed, defences offline.

## Buildings (MVP)
| Building | Size | Cost | Power | Requires | Purpose |
| --- | --- | --- | --- | --- | --- |
| Headquarters | 3x3 | - | +20 | - | Builds structures |
| Power plant | 2x2 | 300 | +100 | Headquarters | Power |
| Refinery | 3x3 | 1 400 | -30 | Power plant | Ore drop-off, includes 1 harvester |
| Barracks | 2x2 | 400 | -20 | Power plant | Infantry |
| Vehicle factory | 3x3 | 1 800 | -40 | Refinery | Vehicles |
| Defence turret | 1x1 | 600 | -20 | Barracks | Anti-vehicle defence |

## Units (MVP)
Starting points for balance runs; the real numbers live in `data/*.tres`.

| Unit | Cost | HP | Speed (tiles/s) | Range (tiles) | Strong against | Weak against |
| --- | --- | --- | --- | --- | --- | --- |
| Rifle squad | 100 | 100 | 1.0 | 4 | Infantry | Vehicles |
| Rocket squad | 300 | 90 | 0.9 | 5 | Vehicles, buildings | Infantry |
| Light tank | 600 | 300 | 1.8 | 4.5 | Infantry | Rocket squads, heavy tanks |
| Heavy tank | 1 000 | 650 | 1.1 | 5 | Vehicles | Massed rocket squads |
| Artillery | 900 | 200 | 1.0 | 9 (minimum 3) | Buildings, groups | Anything close |
| Harvester | 1 200 | 800 | 1.1 | - | - | Everything |

Armour classes: infantry, light, heavy, building. Weapons deal a percentage of damage per class;
the table lives in `data/`.

## Maps (MVP)
Three 2-player maps of 56x56 to 64x64 tiles. Each base has 2 safe ore fields; the middle has
2 contested fields and chokepoints. Fog of war: unexplored is black, explored but not visible
shows the last known buildings.

## AI difficulty
- Easy: slow reactions, weak build order, small attack waves.
- Normal: standard build order, scouting, mixed armies.
- Hard: better economy and unit control plus a 20% income bonus. No extra vision.

## Meta progression
Commander rank from XP (win, loss, difficulty bonus). Unlocks: maps, Hard difficulty, team
colours, cosmetic Headquarters skins. Everything can be unlocked without watching ads.
Rewarded ads offer double XP after a match and +500 starting credits for the next match.

## Monetization
Rules in the `admob-policy` skill: never ads in battle, rewarded by choice, capped interstitial
after a match, banners only in menus, plus a Remove ads purchase.

## Art and audio
Rules in the `svg-art-style` skill: flat top-down military-map look drawn as SVG code.
Audio: short radio chirps and mechanical sounds instead of voice acting, CC0 or generated.

## Not in version 1
Online multiplayer, campaign, air and naval units, second faction, map editor.

## Targets to validate after launch
Day-1 retention, median session length and the share of players who accept a rewarded offer,
measured with AdMob reports and Play Console vitals.
