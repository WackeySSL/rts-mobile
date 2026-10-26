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

## Turn the phone
| Action | Result | Teach |
|---|---|---|
| Turn the phone, on a menu or during a match | The game plays in portrait and in landscape and follows the phone's sensor. A match goes on while you turn: nothing restarts and no order is given, the map keeps its centre and the size of what is on it, and the controls keep their size and move to the layout of the other orientation | |
| Turn the phone while a finger is on the screen (a drag, a box or a pinch) | That gesture is cancelled, never turned into a tap or an order: no unit is selected or sent. Lift the finger and start the gesture again | |
| Auto-rotate is off in the phone's settings | The game stays in the orientation the phone is in. The game cannot force a turn and has no lock of its own | |

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
| With units selected, tap the ground | Move: the units drive there without fighting, also out of a fight; on arrival they fire at enemies within weapon range without moving; chevrons mark the point | yes |
| With units selected, tap an enemy | Attack: the units drive to weapon range of that enemy, stop there and fire at it until it is destroyed, then attack-move on to where it stood; a diamond marks it | yes |

## Combat
| Action | Result | Teach |
|---|---|---|
| Enemies come within weapon range of your standing units | The units fire at them on their own, without an order, until they are destroyed or out of range; units on a move order do not fire until they have arrived; a destroyed unit disappears from the map | |
| Units that finish an attack meet more enemies | They stop to fight: they drive to weapon range of the enemy they picked, fire until it is destroyed, pick the next one, and go on to where the enemy you tapped stood when no enemy is left within their reach | yes |
| A unit is selected, or has just been damaged | A health bar shows above it, filled by the hp it has left (a unit that lives always shows a little fill). Selected units keep their bar; a damaged unit shows it for a few seconds; an enemy hidden by the fog shows none. Your bars are plain, enemy bars have a notch in the top edge, so you can tell them apart without colour | |

## Terrain
| Action | Result | Teach |
|---|---|---|
| Send units across rock, water or scrub | Rock and water block all units, and scrub (the patterned ground) blocks vehicles but not infantry, which walks across it; a unit that cannot cross drives around to the point you tapped | yes |

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

## Build sidebar
| Action | Result | Teach |
|---|---|---|
| Look at the sidebar (on the right; at the bottom when the phone is upright) | It shows your credits, a power bar and three tabs: Structures, Infantry and Vehicles. The bar fills with the power your buildings use against the power they make and shows both numbers where it is wide enough; when you use more than you make, the bar is full and amber and its bolt becomes a warning triangle. Tap a tab to open it: the open tab is the lighter one with a thick bar under it. The tab names show beside the icons only where the sidebar is wide enough; a phone shows the icons alone | |
| Tap an item in the open tab | One of it is queued and paid for at once; the icon fills while it is built, and a number on it counts how many of it are queued. A padlock on a dimmed icon means a building you need is missing (a power plant for a barracks, a barracks for infantry). Stripes mean it cannot be queued now: you cannot pay it (its cost turns amber) or its queue of five is full. A finished building shows "Ready" (tapping it does nothing yet). A tap on a padlocked or striped item shakes it and does nothing. The row scrolls with a drag, down in the sidebar on the right and sideways in the band at the bottom, and a drag never queues anything | yes |
| Hold an item (`long_press_ms` in `data/input_settings.tres`) | The last one of it you queued is cancelled and its cost is paid back in full; the phone buzzes. An item with none queued does nothing, however long you hold | yes |
| Tap your Headquarters, barracks or vehicle factory | The sidebar opens the tab it builds: Structures, Infantry or Vehicles | |

## Not yet in the game
Base building, harvesting, power, production, win and lose conditions, menus and rewards get
their entries when their phase ships them (ROADMAP Phases 3-6).

| Action | Result | Teach |
|---|---|---|
| An "under attack" warning at the screen edge | Not shown yet: nothing points at a unit that is hit off screen | |
