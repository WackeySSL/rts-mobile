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
| Drag the map to its edge | The camera stops at the map's edge: the middle of the screen never leaves the map. The edge can reach the middle of the screen, so what lies under the sidebar or the army bar can be scrolled into view; beyond the edge there is only empty ground. Turning the phone keeps the middle of the screen where it was | |

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

## Selection
| Action | Result | Teach |
|---|---|---|
| Tap an own unit | Selects that unit only; selected units show a ring | |
| Double-tap an own unit | Selects every own unit of that type on screen | yes |
| Long-press, then drag | Draws a box while the finger moves; on release it selects the own units inside (`long_press_ms` in `data/input_settings.tres`) | yes |
| Long-press and drag a box with no own unit inside | Clears the selection (the only way to deselect) | yes |
| Any selection | The panel at the bottom centre; at the top in portrait, in one line right of the Dev button. It shows each selected unit type with its icon, its display name (a very long name is cut short with an ellipsis) and its count, and a total for mixed types; it hides when nothing is selected. Tapping it does nothing. In portrait the line never grows past the screen: when the types do not fit it drops the names, then the total, and then shows the first types with a "+N" for the types it leaves out | |
| A selected unit is destroyed | It leaves the selection, and the count in the panel drops | |

## Orders
| Action | Result | Teach |
|---|---|---|
| With units selected, tap the ground | Move: the units drive there without fighting, also out of a fight; on arrival they fire at enemies within weapon range without moving; chevrons lying flat on the ground close in on the point | yes |
| With units selected, tap an enemy | Attack: the units drive to weapon range of that enemy, stop there and fire at it until it is destroyed, then attack-move on to where it stood; a flat diamond on the ground marks it | yes |

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
| Look at the map | Black ground has never been seen. Dimmed ground was seen before, but enemies there are not shown. Ground that one of your units sees now is clear, and the enemies on it show, with their shots and blasts. Driving out lights new ground and leaves a dimmed trail behind; your own units always show | yes |
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
| Look at the screen with the phone sideways | The build menu floats over the map at the bottom right: three tabs as icons above one row of cards. Your credits and the power bar sit in a pill at the top left, next to the Dev button, and a panel at the top right is kept for the minimap (the minimap itself comes later). Nothing else moves: the army bar, the selection panel and the Dev button keep their places | |
| Look at the screen with the phone upright | The build menu is the band at the bottom, and your credits and the power bar are its first line; the pill and the panel at the top right are not shown. Turning the phone moves the credits line between the two and changes nothing else | |
| Look at the credits and the power bar | They show your credits and a power bar. The bar fills with the power your buildings use against the power they make and shows both numbers where it is wide enough; when you use more than you make, the bar is full and amber and its bolt becomes a warning triangle | |
| Tap a tab | It opens: Structures, Infantry or Vehicles, as an icon; the open tab is the lighter one with a thick bar under it | |
| Tap an item in the open tab | One of it is queued and paid for at once; the icon fills while it is built, and a number on it counts how many of it are queued. Each card shows the item's name under its cost (a long name is cut short with an ellipsis; the upright band's tiles show no name). A padlock on a dimmed icon means a building you need is missing (a power plant for a barracks, a barracks for infantry). Stripes mean it cannot be queued now: you cannot pay it (its cost turns amber) or its queue is full (`queue_slots` in `data/rules.tres`). A finished building shows "Ready" where its price was (tapping it does nothing yet). A tap on a padlocked or striped item shakes it and does nothing. The row scrolls sideways with a drag, and a drag never queues anything | yes |
| Hold an item (`long_press_ms` in `data/input_settings.tres`) | The last one of it you queued is cancelled and its cost is paid back in full; the phone buzzes. An item with none queued does nothing, however long you hold | yes |
| Tap your Headquarters, barracks or vehicle factory | The build menu opens the tab it builds: Structures, Infantry or Vehicles | |
| Open any tab | It lists only the buildings and units of your own side, and those that both sides share; the other side's items are never shown | |

## Not yet in the game
Base building, harvesting, power, production, win and lose conditions, menus and rewards get
their entries when their phase ships them (ROADMAP Phases 3-6).

| Action | Result | Teach |
|---|---|---|
| An "under attack" warning at the screen edge | Not shown yet: nothing points at a unit that is hit off screen | |
| Gas fields | Not shown yet: every field is oil. Once a map names its gas fields, one shows a pale crust with a glowing vent instead of a black pool, with the same full, half and dry steps | |
| Play the Derrick League (oil and gas) or the Lumen Accord (green energy) | Not shown yet: no match has sides, so no building or unit belongs to one side only. Once a match has them, each side has its own buildings and units and your build menu shows only yours (and what both sides share) | |
