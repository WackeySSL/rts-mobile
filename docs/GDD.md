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
- Team colours: eight three-tone colours. By default each player takes its side's colour, which
  is also its HUD's accent: Derrick League orange, Lumen Accord cyan; in a mirror match player 2
  takes the other one (ADR 0025, Michael's answer 7 of 2026-11-02).
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
Structures are ordered in the build drawer, built in the queue and placed when they are ready
(ADR 0017, ADR 0019). ADR 0026's place-first path (a site that rises on the spot, 75 % refund on
cancel) is in the sim but not used (Michael, 2026-11-05).

| Role | Derrick League | Lumen Accord | Size | Cost | Power | Requires | Purpose |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Headquarters | Rigworks | Grid Hub | 3x3 | - | +20 | - | Builds structures |
| Power | Turbine Hall | Wind Park | 2x2 | 300 (Wind Park 250) | +100 (Wind Park +80) | Headquarters | Power |
| Refinery | Oil Works | Fuel Works | 3x3 | 1 400 | -30 | Power | Oil and gas drop-off, includes 1 tanker |
| Barracks | Bunkhouse | Crew Hall | 2x2 | 400 | -20 | Power | Infantry |
| Vehicle factory | Heavy Yard | Motor Hall | 3x3 | 1 800 | -40 | Refinery | Vehicles |
| Radar | Signal Mast | Relay Post | 2x2 | 800 | -30 | Refinery | Unlocks artillery and the superweapon |
| Defence | Redoubt | Rail Battery | 1x1 | 600 | -20 | Barracks | Redoubt against infantry, Rail Battery against vehicles |
| Superweapon | Deep Bore | Dusk Array | 3x3 | 2 500 | -60 | Radar | See "Superweapons" |

## Units (MVP)
Starting points for balance runs; the real numbers live in `data/*.tres`.

| Role | Derrick League | Lumen Accord | Cost | HP | Speed (tiles/s) | Range (tiles) | Strong against | Weak against |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Rifle squad | Rig Hands | Linemen | 100 | 100 | 1.0 | 4 | Infantry | Vehicles |
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

## Damage and destruction
How a building or vehicle looks as it is shot (Michael's sheets of 2026-11-03 and his answers of
2026-11-04; ADR 0028 and ADR 0029). It is a look only: the stages change no rule, and the hp, the
health bar and the fight are the same with or without them. The thresholds and every time below live
in `data/life_settings.tres`.

Buildings show the damage in their shape, not only in their colour:
| Stage | Hp left | Shape | Surface | Fire and smoke |
| --- | --- | --- | --- | --- |
| Whole | above 2/3 | whole | clean | none |
| Damaged | 2/3 down to 1/3 | small breaks: a corner, a mast, a wing | blown panes as dark holes, soot over the breaks; the team colour starts to burn off | one fire with a weak glow, thin grey smoke; a cracked gas tank burns as a jet |
| Critical | under 1/3 | a part has collapsed and the inside shows: floors, rebar, beams, dark rooms | soot over the breaks; little team colour left | fire lit from inside, thick black smoke |

- **Materials break their own way:** concrete along its joints with rebar sticking out, steel bends
  and twists (never shatters), glass goes first as dark holes with the frames left, tanks and spheres
  crack, burn as a jet and then tear open, masts and towers snap at one point and fall one way.
- **Smoke and fire are effects, not drawn into the building**, so they move, and which of a
  building's points burn differs between two of the same building.
- **A hit** gives a short white flash where it lands and a few small chips.
- **Destroyed (0 hp):** a flash and a burst, the building sinks into itself behind a dust cloud, and
  when the dust settles a scorch crater is left (the refinery's is the largest). Smoke rises from the
  crater for 8 seconds and embers glow for 15. There is no ruin, and the camera does not shake.
- **Vehicles:** a soot scar under half their hp; under a quarter a charred patch, a loose skirt plate
  or fender, and a small fire with smoke that trails behind them.
- **Fog:** a stage, a collapse and its crater show only where the player sees them; a building seen
  and then hidden keeps the stage it had when last seen.

## Superweapons (MVP)
One per faction, built after the radar. It charges for 5 minutes from completion; then the player
taps its button and a spot and confirms:
- **Deep Bore** (Derrick League): after a 3-second warning every player sees, the ground splits
  and everything within 3 tiles, own units and buildings included, takes heavy damage.
- **Dusk Array** (Lumen Accord): enemy buildings within 4 tiles go dark for 30 seconds: no
  power, defences silent, production paused. Units are not affected.

No freeze weapons. The Phase 3 dummy opponent never builds or fires one; Phase 4's AI does.

## Maps (MVP)
Three 2-player maps of 56x56 to 64x64 tiles. Each base has 2 safe oil or gas fields; the middle has
2 contested fields and chokepoints. Fog of war: unexplored is black, explored but not visible
shows the last known buildings.

## AI difficulty
- Easy: slow reactions, weak build order, small attack waves.
- Normal: standard build order, scouting, mixed armies.
- Hard: better economy and unit control. No extra vision. No income bonus at first: a 20% income
  bonus comes only if Hard proves not hard enough against Normal (ADR 0030, Michael's answer of
  2026-11-06).

## Meta progression
Commander rank from XP (win, loss, difficulty bonus). Unlocks: maps, Hard difficulty, cosmetic
Headquarters skins; all eight team colours are open from the start. Everything can be unlocked
without watching ads.
Rewarded ads offer double XP after a match and +500 starting credits for the next match.

## Monetization
Rules in the `admob-policy` skill: no ads in battle but one banner at the foot of the open pause
menu (Michael, 2026-11-05), rewarded by choice, capped interstitial after a match, banners only in
menus, plus a Remove ads purchase.

## Art and audio
Rules in the `svg-art-style` skill: an isometric 2:1 view (ADR 0023) in a flat-shaded, muted vector
look with one light from the north-west. Units, turrets and most buildings are simple 3D models that
the in-repo generator (`tools/artgen/`) draws as SVG in every direction; team colour shows as bands
in the player's colour.
Audio: short radio chirps and mechanical sounds instead of voice acting, CC0 or generated.

## Planned: air, anti-air, engineering centre, space centre (designed 2026-11-09, built after the Phase 4 gate)
Michael asked for this on 2026-11-09: an airfield and aircraft, air defence, more buildings, an
engineering centre that develops better bombers, and a space centre whose satellite makes the fog
disappear. The same day he added an aircraft that carries infantry, infantry that fly with drones,
and the repair of aircraft. The design is ADR 0036 (proposed) and the plan is
`docs/plans/2026-11-09-air-and-tech.md`.

**Michael's decision is pending:** version 1 or an update. The recommendation is update 1.1 (air,
anti-air, satellite, research) after launch, then 1.2 (transport, drone squads) with the ground
design's infantry carrier. Until he decides, the "Not in version 1" line below stands. If he
chooses version 1, that line loses "air".

Everything below is a starting value for the balance runs. The real numbers will live in `data/`.

**How it plays**
- **Aircraft hover and fly straight** over rock, water and buildings. There is no runway, landing
  or fuel.
- **Who hits aircraft:** anti-air buildings, rocket squads and fighters. The low-flying drone
  squads are also hit by rifle squads and the Redoubt. Everything else (tanks, artillery, the Rail
  Battery, bombers) hits only the ground.
- **The airfield.** Each one serves 4 aircraft on its pads, which is the cap on aircraft. A bomber
  carries 2 bombs, flies home by itself when it is empty, reloads on its pad, and waits there. An
  aircraft on its pad is repaired for credits. Tap your airfield with aircraft selected to send
  them home.
- **The transport** carries squads:
  - Select squads and tap your transport, or select the transport and tap a squad; the transport
    flies to them and they climb in.
  - "Unload" and a tap on the ground drop them there.
  - If the transport is shot down, the squads aboard are lost.
- **Drone squads** are infantry carried by drones at low height. They are built at the barracks
  once you have an airfield, and they cross cliffs and water.
- **The engineering centre** researches bomber upgrades, each once per match, in the Research tab:
  heavier bombs and a tougher hull (question 5 of ADR 0036).
- **The space centre** charges for 3 minutes. Then its button lifts the fog over the whole map for
  45 seconds; ground you had never seen stays explored afterwards. The enemy sees a warning for as
  long as it lasts. Destroying the space centre, or a Dusk Array blackout on it, ends the sweep at
  once. The computer on Normal and Hard uses it by the same rules (questions 3 and 4).

**Buildings (planned; 12 per faction instead of 8)**

| Role | Size | Cost | Power | Requires | Purpose |
| --- | --- | --- | --- | --- | --- |
| Airfield | 3x3 | 1 500 | -40 | Radar | Builds aircraft (Flight tab); 4 pads: reload, repair |
| Anti-air | 1x1 | 700 | -20 | Barracks | Shoots high and low air only |
| Engineering centre | 2x2 | 1 200 | -40 | Airfield | Research tab: bomber upgrades |
| Space centre | 3x3 | 2 000 | -60 | Radar | Satellite sweep: whole map visible for a while |

**Units (planned; Derrick League numbers, then the Lumen Accord's take)**

| Role | Cost | HP | Speed (tiles/s) | Range (tiles) | Hits | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Fighter | 900 | 260 | 3.0 | 5 | air | No ammo limit. Lumen: 3.6 tiles/s, 200 HP |
| Bomber | 1 400 | 500 | 1.8 | 2.5 | ground | 2 bombs, then home to reload. Lumen: 2.2 tiles/s, 380 HP |
| Transport | 1 000 | 600 | 1.6 | - | - | 3 squads. Lumen: 800 credits, 380 HP, 2.4 tiles/s, 2 squads |
| Drone squad | 350 | 140 | 1.4 | 4 | ground | Flies low. Lumen: 300 credits, 90 HP, 2.0 tiles/s |

**Name candidates (Michael picks; A is the first of each pair).** All are original, the short ones
fit a build card on one line, and each is checked against other games and real military names (ADR
0036 §16).

| Item | Derrick League | Lumen Accord |
| --- | --- | --- |
| Airfield | Flight Yard / Hangar Row | Glide Deck / Sky Dock |
| Fighter | Torchjet / Pipewing | Glint / Skylance |
| Bomber | Drillhead / Gusher | Sunfall / Halcyon |
| Transport | Skyhauler / Liftbarge | Ferrywing / Seedpod |
| Drone squad | Hoist Crew / Liftjacks | Kite Crew / Updrafts |
| Anti-air | Burst Stack / Sky Stack | Sky Needle / Sun Needle |
| Engineering centre | Draft Shop / Test Bench | Lens Works / Kiln Lab |
| Space centre | Skyrig / Launch Rig | Zenith / Lift Spire |
| Satellite | Survey Eye / Plumb Star | Sunward / Noonlight |
| Upgrade: bombs | Heavy Charges | Focused Charges |
| Upgrade: hull | Plated Hull | Ceramic Hull |

**Looks, in each faction's own style**
- **Derrick League:** riveted olive steel, gas bottles and flare-stack exhausts.
  - The fighter is a stubby delta with one big intake.
  - The bomber is a fat twin-boom lifting body with a drill-bit nose.
  - The transport is a boxy armoured hull on four ducted fans.
  - The drone squad is soldiers hanging under heavy six-rotor drones.
  - The anti-air gun is a stack of four short barrels on a concrete drum.
  - The space centre is a launch tower built like a drilling derrick.
- **Lumen Accord:** white ceramic, glass and blue-grey.
  - The fighter is a slim forward-swept wing with a glass canopy.
  - The bomber is a wide solar-topped flying wing.
  - The transport is a glider-like wing on two tilting fans.
  - The drone squad is soldiers on light kite-wing drones.
  - The anti-air is a glass needle on a turning ring.
  - The space centre is a white spire with a solar collar.
- **Looks we never use:** no tandem twin-rotor transport, no jet-pack infantry and no dish uplink.
  Those belong to other games.

**More buildings: what else a complete mobile RTS could have, and what we recommend**
- **Repair building:** the separate ground design covers it, and it meets this design at a shared
  "repair" order. Aircraft are repaired at their airfield.
- **A forward outpost that extends where you may build:** worth it later, once the balance runs
  show whether far oil fields matter.
- **Not recommended:**
  - walls and gates: they are fiddly to place on a phone and costly for path finding;
  - storage or silos: credits have no cap, so they would add nothing;
  - jammers and a second defence tier: more to learn with little new play.

So this expansion adds no buildings beyond the four above. The repair building comes with the
ground design.

## Not in version 1
Online multiplayer, campaign, air and naval units, map editor.

## Targets to validate after launch
Day-1 retention, median session length and the share of players who accept a rewarded offer,
measured with AdMob reports and Play Console vitals.
