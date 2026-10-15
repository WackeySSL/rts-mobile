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

## Selection
| Action | Result | Teach |
|---|---|---|
| Tap an own unit | Selects that unit only; selected units show a ring | |
| Double-tap an own unit | Selects every own unit of that type on screen | yes |
| Long-press, then drag | Draws a box while the finger moves; on release it selects the own units inside (`long_press_ms` in `data/input_settings.tres`) | yes |
| Long-press and drag a box with no own unit inside | Clears the selection (the only way to deselect) | yes |
| Any selection | The panel at the bottom centre shows each selected unit type with its icon, its display name (a very long name is cut short with an ellipsis) and its count, and a total for mixed types; it hides when nothing is selected. Tapping it does nothing | |

## Orders
| Action | Result | Teach |
|---|---|---|
| With units selected, tap the ground | Attack-move: the units go there and fight what they meet; chevrons mark the point | yes |
| With units selected, tap an enemy | Attack: the units drive at that enemy; a diamond marks it | yes |

## Army bar (bottom left)
| Action | Result | Teach |
|---|---|---|
| Tap "All army" | Selects every own unit that can move, anywhere on the map | |
| Tap a group (1-3) | Selects the units stored in that group | |
| Hold a group (1-3) | Stores the current selection in that group; the phone buzzes and the count shows (`group_assign_ms` in `data/input_settings.tres`) | yes |

## Not yet in the game
Base building, harvesting, power, production, win and lose conditions, menus and rewards get
their entries when their phase ships them (ROADMAP Phases 3-6).

| Action | Result | Teach |
|---|---|---|
| Moving without fighting (retreat) | Every ground tap is an attack-move | |
