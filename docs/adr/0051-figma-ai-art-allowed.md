# ADR 0051: Art made with Figma's AI features may ship in the game

**In short, for Michael:** from 2026-11-24 art made with Figma's own AI features may go into the
game wherever it gives the best result. Each such file is marked as AI-made in
`assets/CREDITS.md`, and AppCode ApS does not claim "all rights reserved" over it, because its
copyright is uncertain. The rule against looking like Command & Conquer, Red Alert or any other
game stays, so every AI-made picture is checked before it goes in.

Status: **accepted, 2026-11-24.** Michael answered "C" to the lead's three options the same day
(A: AI as reference only; B: AI only for menus, loading screens and portraits; C: AI wherever it
fits), with the reason "vi bruger alligevel andre ting i spillet som vi ikke har ophavsret på" and
"vi skal lave det bedste vi kan". The lead had set out the costs before he chose: the uncertain
copyright of AI-made images in the EU, the risk of output close to an existing game, and that one
picture from one angle does not give a unit's 8 to 16 directions. Written by the lead, row P622.

Status note (2026-11-24, P621b docs; ADR 0050 accepted 2026-11-24): after P637's same-scene
comparison, Michael chose generator SVG for every building on the map ("ja, kør med generator-SVG
og Figma AI til menuer"). So §2's "large building pictures" item does not apply on the map.
Figma AI makes stand-alone art: menu and loading backdrops, portraits and store art (ADR 0050
§2), and serves as reference. No accepted text changed.

Amends:
- CLAUDE.md, Legal: "Never Figma's or a plugin's AI image or model tools" (Michael, 2026-11-09)
  and "no AI images from outside tools". Figma's own AI features are now allowed; a plugin's AI
  tools and every AI tool outside Figma stay banned.
- ADR 0046 §2 (own assets are reserved): AI-made files are outside its "all rights reserved"
  scope. A dated note there points here.

## Context
The Treadline restyle (ADR 0049, row P600) takes its look from Michael's Figma file, whose
vehicle, building, terrain and backdrop pictures were made with an image generator. Until today
the project's rules allowed only art drawn by us (by hand, by `tools/artgen/` or as vectors in
Figma) and CC0 or CC-BY assets. The game already ships things AppCode ApS does not own: CC0 and
CC-BY assets, the OFL fonts, the Godot engine and its parts. Michael wants the best-looking game
the team can make and accepts the trade-off below.

## Decision
1. **Allowed tools.** Figma's own AI features, for example "Make image" and the Figma MCP's image
   and vector-illustration generators, may make art that ships. A Figma plugin's AI tools, art
   from community files or shared libraries, and AI tools outside Figma stay banned.
2. **Where it fits.** Anywhere it gives the best result, with the art-director's judgement:
   - single-view art: menu and loading backdrops, portraits for production and unit details,
     store art, large building pictures (ADR 0050 keeps PNG for the large buildings);
   - references and starting points for our own models (`tools/artgen/`) and vector drawings.
   Units keep coming from `tools/artgen/`, because they need 8 to 16 directions, moving turrets and
   shadows in one projection and one light (ADR 0023); one generated picture does not give those.
   A generated building must match the game's dimetric 2:1 view, its north-west light and its
   footprint, or be redrawn.
3. **The look rule still holds (CLAUDE.md Legal).** No prompt names another game, studio,
   faction, unit, character or brand, or asks for another game's style. Every AI-made picture is
   screened before it is committed: the art-director rejects any output that resembles Command &
   Conquer, Red Alert or any other existing game (silhouettes, insignia, unit designs, glowing
   crystal ore, interface look), and records the screen in the CREDITS entry.
4. **Marking.** Each AI-made file gets its own row in `assets/CREDITS.md`:
   - source: the Figma file's link and the frame;
   - licence column: "AI-made with Figma AI, no copyright claimed by AppCode ApS";
   - notes: the feature used, the date, the prompt (short), what was edited by hand afterwards,
     and "screened: no resemblance to an existing game".
   A file that we then redraw substantially by hand or rebuild as our own model is our own work
   again and is listed as such, naming the AI picture only as a reference.
5. **Ownership.** AppCode ApS makes no copyright claim on AI-made files, and `assets/LICENSE.md`
   excludes them from "all rights reserved". Copies of them in another game cannot be stopped by
   a copyright complaint. The game's name, logo and own-made art stay protected as before.

## Consequences
- The art pipeline (ADR 0050) may use Figma AI for the large buildings, backdrops and portraits,
  and as references for unit models.
- `assets/LICENSE.md` gets a line excluding the files that CREDITS marks as AI-made (row P623,
  with a test that every AI-made row has the required fields and that no AI-made path sits in the
  reserved scope without the exclusion).
- The store listing may need to mention AI-made content if a store's policy asks for it at
  release time (Phase 7 release checklist).
- The risk Michael accepted: part of the game's look can be copied by others without recourse,
  and an AI picture can come out close to an existing game; the screen in item 3 lowers but does
  not remove that risk.
