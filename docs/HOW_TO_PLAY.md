# How to play (onboarding source)

Living list of everything a player can do. Each player-facing feature adds or updates its entry
in the PR that ships it (CLAUDE.md, Workflow). Phase 5 builds the interactive tutorial and the
in-game "How to play" screen from this list (ROADMAP Phase 5), so a feature without an entry here
is a feature players will not learn.

**Teach** marks what a new player will not find alone: the tutorial must show it, not only the
help screen. Timings and sizes live in `data/`, so entries name the setting instead of a number.

## Camera
| Action | Result | Teach |
|---|---|---|
| Drag one finger | Pans the map | |
| Pinch | Zooms about the fingers; on release it settles on the nearest of three zoom levels (`zoom_levels` in `data/input_settings.tres`) | |
| Look at the map | The map is drawn at an angle, as a diamond: every tile is a diamond and the map's corners point up, down, left and right. Drag, pinch and taps work as before, and a tap on the ground sends the units to the point under your finger | |
| Drag the map to its edge | The camera stops at the map's edge: the middle of the screen never leaves the map. The edge can reach the middle of the screen, so what lies under the build menu, the army bar or the panels at the top can be scrolled into view; beyond the edge the screen is dark grey. Turning the phone keeps the middle of the screen where it was | |

## Turn the phone
| Action | Result | Teach |
|---|---|---|
| Turn the phone, on a menu or during a match | The game plays in portrait and in landscape and follows the phone's sensor. A match goes on while you turn: nothing restarts and no order is given, the map keeps its centre and the size of what is on it, and the controls keep their size and move to the layout of the other orientation | |
| Turn the phone while a finger is on the screen (a drag, a box or a pinch) | That gesture is cancelled, never turned into a tap or an order: no unit is selected or sent. Lift the finger and start the gesture again | |
| Auto-rotate is off in the phone's settings | The game stays in the orientation the phone is in. The game cannot force a turn and has no lock of its own | |

## Units
| Action | Result | Teach |
|---|---|---|
| Look at your units | Each unit is drawn from the picture set of its side (the Derrick League or the Lumen Accord) in its player's team colour (the first player amber, the second cyan) with a shadow on the ground under it; units of two players on one side still differ by colour. The selection panel shows the unit's item card | |
| Watch a unit drive or fight | The picture turns in steps to face where the unit drives (infantry in coarser steps); a tank's turret turns on its own to face its target while the hull keeps its heading; infantry turn as a whole toward their target. A unit lower on the screen is drawn in front of one above it | |

## Buildings
| Action | Result | Teach |
|---|---|---|
| Look at a building | Each building is drawn from the picture set of its side in its player's team colour, standing on its footprint with a soft shadow on the ground. It is drawn like a unit: a unit lower on the screen, in front of it, is drawn over it, and one higher up, behind it, is hidden by it. A defence's gun head turns on its own to face its target and stays turned while it has none | |
| Look at the enemy's buildings | An enemy building is drawn only while you see the ground it stands on now; one cell of its footprint is enough, and then the whole building shows. Out of sight it is not drawn as it is, but see the next row | |
| Look at the fog | An enemy building you have seen stays on the map as a dimmed picture, in its side's colours, where you last saw it, even if it has been destroyed since out of your sight. Seeing any one tile of the building is enough, its edge or corner as well as its middle. The picture stays until you see any tile of that spot again: if the building is there, it shows as it is; if not, the picture goes. A building destroyed while you see any tile of it leaves no picture. The picture is hidden while you see any tile of the building, and comes back when you look away. The dimmed picture has no health bar and cannot be tapped (a tap there is a tap on the ground), and your units are drawn in front of it | |
| A building is hit, or selected | A bar shows above it, as wide as its footprint (small, medium or large), filled by the hp it has left, for a few seconds after each hit and for as long as the building is selected. Your bars are plain, an enemy's has a notch in the top edge. An enemy building the fog hides shows none | |
| A building is destroyed | It disappears from the map and the units behind it are no longer hidden. One you saw fall, and any of your own, leaves a crater on the ground where it stood, as wide as its footprint, for the rest of the match | |

## Selection
| Action | Result | Teach |
|---|---|---|
| Tap an own unit | Selects that unit only. Tap anywhere on its picture, the middle of it included, not only on the ground under its feet: a unit is hit round the middle of its picture, and where two are close the one whose middle is nearer your finger is picked. A unit is easy to hit: at least 48 dp across (`hit_radius_dp` in `data/input_settings.tres`), however small it is drawn. Selected units show a white oval ring lying on the ground under them, as big as the unit's circle on the ground and never smaller than 36 dp across | |
| Tap your own building | Selects that building only, and a unit standing at the same spot is picked instead of it. Tap anywhere on the building's picture, the part that stands up over the ground included, not only on the ground it covers; where two buildings overlap, the one drawn in front is selected. A building is easy to hit: at least 48 dp across (`hit_radius_dp` in `data/input_settings.tres`), however small it is drawn. It gets a frame of four corner brackets and its health bar, the panel names it, and a Headquarters, barracks or vehicle factory opens the tab it builds | |
| Tap an enemy building you can see, with nothing selected | Selects it for its information only: an amber frame and its notched health bar show, and the panel names it. It takes no orders, and an enemy building the fog hides cannot be tapped | |
| Tap the ground with a building selected | Lets go of the building. Nothing is ordered and nothing moves | |
| Double-tap an own unit | Selects every own unit of that type on screen. A building never joins a double-tap, a box or "All army" | yes |
| Long-press, then drag | Draws a box while the finger moves; on release it selects the own units inside (`long_press_ms` in `data/input_settings.tres`) | yes |
| Long-press and drag a box with no own unit inside | Clears the selection. With units selected it is the only way to deselect them; a selected building also lets go on a tap on the ground | yes |
| Any selection | The panel at the bottom centre; at the top in portrait, in one line right of the Dev button. It shows each selected unit type or building with its icon, its display name (a very long name is cut short with an ellipsis) and its count, and a total for mixed types; it hides when nothing is selected. Tapping it does nothing. In portrait the line never grows past the screen: when the types do not fit it drops the names, then the total, and then shows the first types with a "+N" for the types it leaves out | |
| A selected unit or building is destroyed | It leaves the selection, and the count in the panel drops (a building's frame goes with it) | |

## Orders
| Action | Result | Teach |
|---|---|---|
| With units selected, tap the ground | Move: the units drive there without fighting, also out of a fight; on arrival they fire at enemies within weapon range without moving; chevrons lying flat on the ground close in on the point | yes |
| With units selected, tap an enemy | Attack: the units drive to weapon range of that enemy, stop there and fire at it until it is destroyed, then attack-move on to where it stood; a flat diamond on the ground marks it. An enemy building is attacked the same way once the middle of it is in your sight: a tap anywhere on its picture counts, also where one of your own buildings is drawn in front of it. One you see only at its edge, or the fog hides, is a tap on the ground | yes |

## Combat
| Action | Result | Teach |
|---|---|---|
| Enemies come within weapon range of your standing units | The units fire at them on their own, without an order, until they are destroyed or out of range; units on a move order do not fire until they have arrived; a destroyed unit disappears from the map | |
| Units that finish an attack meet more enemies | They stop to fight: they drive to weapon range of the enemy they picked, fire until it is destroyed, pick the next one, and go on to where the enemy you tapped stood when no enemy is left within their reach | yes |
| A unit is selected, or has just been damaged | A health bar shows above its picture, filled by the hp it has left (a unit that lives always shows a little fill). Selected units keep their bar; a damaged unit shows it for a few seconds; an enemy hidden by the fog shows none. Your bars are plain, enemy bars have a notch in the top edge, so you can tell them apart without colour | |

## Terrain
| Action | Result | Teach |
|---|---|---|
| Look at the ground | Every tile is a diamond of grass, sand, scrub, rock, water or dark oil-stained earth, drawn in two slightly different arrangements so that a stretch of one kind does not look stamped; outside the map's edge the screen is dark grey | |
| Send units across rock, water or scrub | Rock and water block all units, and scrub (the patterned ground) blocks vehicles but not infantry, which walks across it; a unit that cannot cross drives around to the point you tapped | yes |

## Economy
| Action | Result | Teach |
|---|---|---|
| Look at an oil field | A field is a patch of dark, oil-stained ground with a wellhead standing in it. A full field is one black pool; as oil is taken the pool shrinks to a small one with bare earth round it (half) and then to a cracked stain (dry), and the field fills up again slowly, a step at a time | yes |

## Fog
| Action | Result | Teach |
|---|---|---|
| Look at the map | Black ground has never been seen. Dimmed ground was seen before, but enemy units there are not shown, and an enemy building there shows only as the dimmed picture of what you last saw, when you saw any tile of it (see Buildings). Ground that one of your units sees now is clear, and the enemies on it show, with their shots and blasts. Driving out lights new ground and leaves a dimmed trail behind; your own units always show | yes |
| With units selected, tap near an enemy the fog hides | It counts as a tap on the ground: the units move to the point you tapped, with chevrons, and the hidden enemy is not attacked. Once one of your units sees it, the same tap attacks it | |
| Fight in the fog | Your units only attack enemies your side can see, whichever of your units sees them. An enemy that slips out of sight is no longer attacked: units you sent against it attack-move on to where it was last seen, and the others look for a new target | |

## Army bar (bottom left)
| Action | Result | Teach |
|---|---|---|
| Tap "All army" | Selects every own unit that can move, anywhere on the map | |
| Tap a group (1-3) | Selects the units stored in that group | |
| Hold a group (1-3) | Stores the current selection in that group; the phone buzzes and the count shows (`group_assign_ms` in `data/input_settings.tres`) | yes |
| A grouped unit is destroyed | It leaves the group; the group's badge shows the new count, and an empty group shows only its number | |

## Build menu
| Action | Result | Teach |
|---|---|---|
| Look at the screen with the phone sideways | The build menu floats over the map at the bottom right: three tabs as icons above one row of cards. Your credits and the power bar sit in a pill at the top left, next to the Dev button, and a panel at the top right is kept for the minimap (the minimap itself comes later) | |
| Look at the screen with the phone upright | The build menu is the band at the bottom, and your credits and the power bar are its first line; the pill and the panel at the top right are not shown. Turning the phone moves the credits line between the two and changes nothing else | |
| Look at the credits and the power bar | They show your credits and a power bar. The bar fills with the power your buildings use against the power they make and shows both numbers where it is wide enough; when you use more than you make, the bar is full and amber and its bolt becomes a warning triangle | |
| Tap a tab | It opens: Structures, Infantry or Vehicles, as an icon; the open tab is the lighter one with a thick bar under it | |
| Tap an item in the open tab | One of it is queued and paid for at once; the icon fills while it is built, and a number on it counts how many of it are queued. Each card shows the item's name under its cost (a long name is cut short with an ellipsis; the upright band's tiles show no name). A padlock on a dimmed icon means a building you need is missing (for the Derrick League: a Turbine Hall for a Bunkhouse, a Bunkhouse for infantry, a Signal Mast for the Mortar Rig). Stripes mean it cannot be queued now: you cannot pay it (its cost turns amber) or its queue is full (`queue_slots` in `data/rules.tres`). A finished building shows "Ready" where its price was (tap it to place it, see the next rows). A tap on a padlocked or striped item shakes it and does nothing. The row scrolls sideways with a drag, and a drag never queues anything | yes |
| Hold an item (`long_press_ms` in `data/input_settings.tres`) | The last one of it you queued is cancelled and its cost is paid back in full; the phone buzzes. An item with none queued does nothing, however long you hold | yes |
| Tap your Headquarters, barracks or vehicle factory (the Derrick League's Rigworks, Bunkhouse or Heavy Yard) | The building is selected (see Selection) and the build menu opens the tab it builds: Structures, Infantry or Vehicles. Tap it again after you opened another tab and the menu comes back to its tab | |
| Open any tab | It lists only the buildings and units of your own side, and those that both sides share; the other side's items are never shown | |
| Tap a finished building ("Ready" on its card) | Placement begins: a ghost of the building appears in the middle of the view, its footprint marked as diamonds on the ground with the building faded over them, and a check mark and an X take the place of the cards. A green wash and a solid frame mean it fits. A red wash with stripes and a small sign mean it does not, and the sign says why: it leaves the map, the ground is rock, water or built on, a unit stands there, you have not explored the ground, it is too far from your buildings (`build_reach_tiles` in `data/rules.tres`) or you have as many buildings as you may (`building_cap`). Tap the check mark to build it where the ghost stands (it waits dimmed while the ghost does not fit, see the next rows), or the X to keep it for later: the finished building stays "Ready" on its card. Lifting a finger never builds anything | yes |
| Tap the check mark | The building order is sent once and the check mark goes dim, so a second tap sends nothing. The ghost stays where it stands, held, until the game answers, a fraction of a second later: the building appears and placement ends, and the cards come back. The X still works meanwhile, but the order is already on its way | |
| The ghost turns red with the word "Blocked" after the check mark | The game refused the order, for instance because a unit moved onto the ground after the ghost was last checked. The ghost is red with stripes and a sign and the word "Blocked" stands under it; the check mark stays dim and the finished building stays "Ready". Move the ghost (drag it, or tap the ground) and tap the check mark again, or tap the X | |
| While the ghost shows, drag from the ghost or from just beside it (`ghost_grab_dp` in `data/input_settings.tres`) | The ghost follows your finger and sits above it (`ghost_lift_dp`), so the finger never hides it, and it snaps to tiles. A drag that starts anywhere else pans the map as usual. Tap the ground and the ghost jumps to that tile; pinch and two-finger drag work as ever. Holding a finger down draws no selection box, and a tap or a drag on the map selects and orders nothing until you build or cancel | yes |
| Hold the dragged ghost near the edge of the screen | The map scrolls that way and the ghost stays under your finger as the ground moves. The band is `edge_band_dp` wide and the speed is `edge_pan_dp_per_s`, both in `data/input_settings.tres`: the same on every phone and at every zoom, and it keeps inside the notch and the rounded corners. The ghost rides above your finger, so the band at the top starts where the ghost is, not the finger. It stops at the map's edge, when your finger leaves the band, lifts or a second finger joins | |
| Turn the phone while the ghost shows | The ghost keeps its tile and the map keeps its centre; the check mark and the X move with the build menu into the other layout. A drag of the ghost in progress, and a scroll at the edge, are cancelled (lift the finger and drag again), and the turn itself builds and sends nothing. A turn while the building order is on its way changes nothing: the answer comes as before | |

## Superweapon
| Action | Result | Teach |
|---|---|---|
| Own a Deep Bore or a Blackout Array | A round button shows the building's picture inside a ring: sideways it is on the top line, left of the minimap's panel; upright it is at the right edge, above the army bar. The ring fills clockwise while the strike charges (`charge_ticks` of the building in `data/units/`) and the time left shows on the button; when the ring is full and green, the button says "Ready". With no such building there is no button | yes |
| Tap the button while it charges | The button gives a small nudge and nothing else happens | |
| Tap the ready button | You aim: the button stays pressed and says "Tap map", and a check mark and an X appear beside it. Drag and pinch still move the map; nothing is selected, ordered or boxed while you aim | yes |
| While aiming, tap the map | A ring on the ground shows where the strike will hit and how far it reaches (`strike_radius` of the building); tap again to move it. Tap the check mark → the strike is fired once and aiming ends. The check mark waits dimmed until you have tapped the map | yes |
| While aiming, tap the X or the pressed button, or turn the phone | Aiming ends and nothing is fired | |
| A Deep Bore is fired, by anyone | Every player sees a red ring on the ground at the target and a blinking warning triangle for the warning time (`strike_delay`), with a white ring closing in on the target. Move out of the ring while it closes | yes |
| A Deep Bore's ring has closed | A fireball bursts at the target and the ground splits: everything inside the ring, yours too, takes damage, and a crater as wide as the ring stays there for the rest of the match. You see the burst and the crater when you can see the target's own tile, just before it hits or as it hits; a rupture whose target tile is dark leaves no mark | yes |
| A Blackout Array is fired | At once every building that is not the firing player's and whose middle is within reach of the spot it was fired at (`strike_radius` of the Blackout Array, counted from that spot) is switched off for `strike_ticks`: it does not shoot, its power counts for nothing and its queue stands still. No warning shows before it, and no ring stays on the ground after it | |
| A building is switched off | An amber lightning bolt struck through by a brighter amber slash, on a dark badge with an amber rim, stands over the building for as long as it is off, yours and any enemy building you can see; it is gone when the building comes back on | yes |

## Not yet in the game
Base building, harvesting, power, production, win and lose conditions, menus and rewards get
their entries when their phase ships them (ROADMAP Phases 3-6).

| Action | Result | Teach |
|---|---|---|
| An "under attack" warning at the screen edge | Not shown yet: nothing points at a unit that is hit off screen | |
| Gas fields | Not shown yet: every field is oil. Once a map names its gas fields, one shows a pale crust with a glowing vent instead of a black pool, with the same full, half and dry steps | |
| Play the Derrick League (oil and gas) or the Lumen Accord (green energy) | Not shown yet: no match lets you choose a side, and the preview's match gives both players Derrick League units. Every building and unit already belongs to one side, and your build menu shows only your side's. Once a match has both sides, each side plays its own buildings and units | |
