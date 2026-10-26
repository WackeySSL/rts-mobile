# Game design document: rts-mobile (MVP)

Store title: "Treadline: Offline RTS" (ADR 0006; trademark search in Phase 7). Codename: rts-mobile.

## Pitch
A classic base-building RTS rebuilt for the phone: build a base, harvest oil and gas, and
out-produce and out-manoeuvre one computer opponent in an 8-10 minute match. Free, playable offline,
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
- Two original factions, both playable, each with its own buildings, units and superweapon
  (ADR 0023): the **Derrick League**, an oil and gas bloc (concrete, riveted steel, olive vehicles,
  gas spheres, flare stacks, pumpjacks; heavy, robust, slow), and the **Lumen Accord**, a
  green-energy alliance (white ceramic, glass, wind turbines, solar panels, blue-grey vehicles;
  fast, precise, fragile). Invented energy blocs with original lore: no geography, no flags, stars
  or real insignia, no link to existing franchises. Mirror matches are allowed.
- Team colours: eight three-tone colours; player 1 orange and player 2 cyan by default.
- Start: one Headquarters, 2 000 credits and 2 rifle squads of the player's faction.
- Victory: the enemy has neither a Headquarters nor a production building left.
- Target: median match length 8-10 minutes, checked by the balance harness.

## Economy
- Oil and gas fields regrow slowly (1 unit per field cell per 10 seconds, capped); a field shows
  full, half or dry. Oil and gas pay the same.
- A tanker carries 500 credits per trip; every refinery comes with one free tanker.
- Buildings produce or consume power. Low power: production at 50% speed, defences offline.
- No pumps, captured derricks or pipelines in the MVP.

## Buildings (MVP)
Each faction builds its own eight; every footprint is square.

| Role | Derrick League | Lumen Accord | Size | Cost | Power | Requires | Purpose |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Headquarters | Rigworks | Grid Hub | 3x3 | - | +20 | - | Builds structures |
| Power | Turbine Hall | Wind Park | 2x2 | 300 (Wind Park 250) | +100 (Wind Park +80) | Headquarters | Power |
| Refinery | Cracking Plant | Synthesis Works | 3x3 | 1 400 | -30 | Power | Oil and gas drop-off, includes 1 tanker |
| Barracks | Bunkhouse | Crew Hall | 2x2 | 400 | -20 | Power | Infantry |
| Vehicle factory | Heavy Yard | Motor Works | 3x3 | 1 800 | -40 | Refinery | Vehicles |
| Radar | Signal Mast | Relay Tower | 2x2 | 800 | -30 | Refinery | Unlocks artillery and the superweapon |
| Defence | Redoubt | Rail Battery | 1x1 | 600 | -20 | Barracks | Redoubt against infantry, Rail Battery against vehicles |
| Superweapon | Deep Bore | Blackout Array | 3x3 | 2 500 | -60 | Radar | See "Superweapons" |

## Units (MVP)
Starting points for balance runs; the real numbers live in `data/*.tres`.

| Role | Derrick League | Lumen Accord | Cost | HP | Speed (tiles/s) | Range (tiles) | Strong against | Weak against |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Rifle squad | Roustabouts | Linemen | 100 | 100 | 1.0 | 4 | Infantry | Vehicles |
| Rocket squad | Wildcatters | Breakers | 300 | 90 | 0.9 | 5 | Vehicles, buildings | Infantry |
| Scout tank | Flarejack | Swift | 600 | 300 | 1.8 | 4.5 | Infantry | Rocket squads, tanks |
| Tank | Bullhead | Torque | 1 000 | 650 | 1.1 | 5 | Vehicles | Massed rocket squads |
| Artillery | Mortar Rig | Arcline | 900 | 200 | 1.0 | 9 (minimum 3) | Buildings, groups | Anything close |
| Tanker | Tanker | Fuel Runner | 1 200 | 800 | 1.1 | - | - | Everything |

The numbers are the Derrick League's: heavy, robust, slow. The Lumen Accord is fast, precise and
fragile: Linemen 1.1 tiles/s and 80 HP, Breakers range 5.5, Swift 2.2 tiles/s and 220 HP, Torque
1.4 tiles/s and 520 HP, Arcline range 10 and 160 HP, Fuel Runner 1.4 tiles/s carrying 450. Squads
show three figures. Artillery needs a radar.

Armour classes: infantry, light, heavy, building. Weapons deal a percentage of damage per class;
the table lives in `data/`.

## Superweapons (MVP)
One per faction, built after the radar. It charges for 5 minutes from placement; then the player
taps its button and a spot and confirms:
- **Deep Bore** (Derrick League): after a 3-second warning every player sees, the ground splits
  and everything within 3 tiles, own units and buildings included, takes heavy damage.
- **Blackout Array** (Lumen Accord): enemy buildings within 4 tiles go dark for 30 seconds: no
  power, defences silent, production paused. Units are not affected.

No freeze weapons. The Phase 3 dummy opponent never builds or fires one; Phase 4's AI does.

## Maps (MVP)
Three 2-player maps of 56x56 to 64x64 tiles. Each base has 2 safe oil or gas fields; the middle has
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
Rules in the `svg-art-style` skill: an isometric 2:1 view (ADR 0023) in a flat-shaded, muted vector
look with one light from the north-west. Units, turrets and most buildings are simple 3D models that
the in-repo generator (`tools/artgen/`) draws as SVG in every direction; team colour shows as bands
in the player's colour.
Audio: short radio chirps and mechanical sounds instead of voice acting, CC0 or generated.

## Not in version 1
Online multiplayer, campaign, air and naval units, map editor.

## Targets to validate after launch
Day-1 retention, median session length and the share of players who accept a rewarded offer,
measured with AdMob reports and Play Console vitals.
