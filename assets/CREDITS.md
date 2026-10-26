# Asset credits

SVG drawn as code in this repository is MIT like the rest of the code and needs no entry.
Every other asset (sound, music, fonts, CC0 packs) must be listed here before it is merged.

| File or folder | Author | Source URL | Licence | Notes |
| --- | --- | --- | --- | --- |
| Godot Engine logo (what still shows it: the engine's default boot splash, the start-up screen of the game and `index.png`, the loading image of the web build; and the Android export template's unused default monochrome launcher layer, `res/mipmap*/icon_monochrome.webp`, which no launcher shows because the presets name no monochrome icon) | Andrea Calabró | https://godotengine.org | CC BY 4.0 | Engine default, not a project asset. The launcher icon of the Android APKs and the favicon of the web build are the game's own icon (next row). Attribution is in `THIRD_PARTY_LICENSES.txt` (Godot's COPYRIGHT.txt) next to every web build and every debug APK (both carry the same Godot `LICENSE.txt` and `COPYRIGHT.txt`). Replace the boot splash with the game's own before release (ROADMAP Phase 7); delete this row when neither it nor the monochrome layer is Godot's |
| `assets/art/svg/icon/` (the app icon: `app_icon.svg`, `icon_foreground.svg`, `icon_background.svg`) | AppCode ApS (art-director) | This repository | MIT | Own work, no outside asset. The SVG of the approved design was emitted by art-director's small projection script, which is kept outside the repository; the committed SVG is the source. Drawn from Michael's brief; the AI-made mood reference he supplied is not copied or traced. Used as the project icon (`application/config/icon`), as the main and adaptive launcher icons of both Android presets and as the favicon of the web build (`html/export_icon`) |
