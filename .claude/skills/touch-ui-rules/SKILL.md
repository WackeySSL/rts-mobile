---
name: touch-ui-rules
description: Touch controls, camera, HUD and layout rules for rts-mobile on phones in landscape - gesture map, thresholds, hit areas in dp, sidebar layout, safe areas, text sizes and feedback. Use whenever building or reviewing input handling, camera, selection, HUD, the build sidebar, menus or any on-screen control.
paths:
  - "game/input/**"
  - "game/ui/**"
  - "game/view/camera*"
  - "scenes/ui/**"
---

# Touch UI rules

Target: a 6-inch phone in landscape, held with two thumbs. It must also work on tablets and in
the desktop web preview, where the mouse emulates touch.

## Gesture map
| Gesture | Result |
| --- | --- |
| Tap own unit | Select it, replacing the selection |
| Tap own building | Select it; a production building opens its build tab |
| Tap ground with units selected | Attack-move there |
| Tap enemy with units selected | Attack it |
| Tap enemy with nothing selected | Show its info card |
| Double-tap own unit | Select all own units of that type on screen |
| Long-press 300 ms on ground, then drag | Selection box, selects on release |
| One-finger drag beyond 12 dp | Pan the camera |
| Two-finger pinch | Zoom between 3 levels, smoothly |
| Two-finger drag | Pan, always |
| Tap minimap | Move the camera there |
| Long-press minimap with units selected | Move the units there |

Thresholds live in `data/input_settings.tres`, never in code.

## Sizes in dp, not pixels
- Convert with `game/ui/UiScale.gd` (`dp(value)`), which uses `DisplayServer.screen_get_dpi()`
  and the current canvas scale. Never hardcode pixel sizes for touch targets.
- Every tappable thing has a hit area of at least 48 dp, even when its sprite is smaller
  (infantry in particular).
- When hit areas overlap the touch point, pick the target whose centre is closest; with units
  selected, enemies win over own units.

## Building placement
- The ghost follows the finger 64 dp above the touch point, so the finger never hides it.
- Valid tiles are tinted green, invalid red. Confirm with a check-mark button, cancel with an X.
  Never place a building on touch release alone.

## Layout in landscape
- Right sidebar: 20% of the width and at least 200 dp. Minimap at the top, then credits and the
  power bar, then tabs (Buildings, Infantry, Vehicles) with build icons of at least 64 dp that
  show cost and progress.
- Bottom-left: "All army" and groups 1-3 (tap selects, long-press assigns).
- Top-left: pause and menu.
- No ads on this screen, ever.
- Keep every control inside `DisplayServer.get_display_safe_area()`.

## Text and feedback
- At least 14 sp body text and 18 sp HUD numbers. Never use colour alone for meaning; team
  colours also differ by marker shape.
- Every command gets instant feedback: selection ring, move marker, short sound, optional light
  haptic (`Input.vibrate_handheld(15)`, can be turned off in settings).
- Under attack: edge-of-screen indicator and a minimap ping.

## Project settings
- `display/window/handheld/orientation = sensor_landscape`
- `input_devices/pointing/emulate_touch_from_mouse = true`, `emulate_mouse_from_touch = false`
- Stretch mode `canvas_items`, aspect `expand`, base size 1280x720.

## Verify on three sizes
1280x720, 2400x1080 (20:9) and 2048x1536 (4:3). Attach screenshots of each to PRs that change
the layout.
