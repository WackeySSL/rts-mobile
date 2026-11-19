# ADR 0041: Audio: one AudioService, four buses, battle sounds read from the sim's events

**In short, for Michael:** one service plays every sound and the music. It has four volume
channels (master, music, effects, interface); your Sound and Music settings set two of them. The
battle sounds come from the same per-tick event list the explosions and muzzle flashes already
use, so the simulation never knows that sound exists, and you only hear what you can see: a shot in
the fog is silent. A fixed number of voices is reused, so a big battle costs the same as a small
one. The game goes quiet when it goes to the background or an ad opens, and the music fades from
one piece to the next. Every sound file is CC0, CC-BY or made by a script in this repository, each
with a line in `assets/CREDITS.md`.

Status: **accepted, 2026-11-15 (Michael: "Ja til anbefaling", yes to every recommendation of
the plan's questions).** Written by the architect on branch
`claude/p500-phase5-plan` (base `main` at a2204d2f) with the plan
`docs/plans/2026-11-15-phase-5.md` (rows P501-P509, P535). Questions 1, 8 and 9 of the plan are
this ADR's.

Amends by dated notes (written in P500b; the accepted texts stay): ADR 0025 §11 (the pause
menu's Sound and Music chips come from P531), ADR 0027 §8 (no change of `reduced`; sounds are not
"life" effects).

## Michael's answers (2026-11-15)
- **Question 1, music mood:** menu calm synth pads with a slow pulse (about 90 BPM); battle driving
  percussion and a bass figure (110-120 BPM), no lead melody; victory and defeat as two short
  stings (6-10 s), rising and falling (§5).
- **Question 8, haptics:** one on/off Vibration switch; strengths per event stay in
  `data/input_settings.tres` (§8).
- **Question 9, CC-BY credits:** yes, a Credits part in the Licences screen lists every CC-BY file,
  and the CC0 ones as a courtesy (§7, ADR 0043 §7).

## Context
- `assets/audio/` is empty. GDD: "short radio chirps and mechanical sounds instead of voice acting,
  CC0 or generated". Michael (2026-11-15): only CC0 or CC-BY with a CREDITS entry, or audio made in
  this repo (for example synthesised by a script in `tools/`); for launch CC0/CC-BY effects and
  2-3 music pieces (menu, battle, victory/defeat); a composed theme later; no asset-store packs and
  no AI audio from outside tools.
- The sim already reports what happens, per tick, in `MatchSnapshot.events` (records of
  `World.EVENT_STRIDE` 8 ints, ADR 0007 §10): `SPAWNED` 1, `DIED` 2, `SHOT` 3 (`[3, shooter id,
  x, y, target id, weapon, target x, target y]`), `IMPACT` 4, `STRIKE` 5 (ADR 0027 §7: `[5,
  building id, x, y, kind, owner, landing tick, 0]`, kind 3 = the sweep), `UNLOADED` 6,
  `MINE_BLAST` 7, `REPAIRED` 8. The view reads them inside `runner.ticked` (`EffectsLayer`,
  `HitFx`, `PuffFx`, `StrikeFx`, `RigLife`, `AttackCues`, `RevealBadge`), and `EffectsLayer` hides
  an effect born on a tile the local player does not see.
- `AttackCues` (Hud) raises "under attack" and emits `cue_changed`. Human Commands go through the
  `CommandQueue` autoload (`submit`). Five call sites buzz through `HudPrefs.vibrates`.
- Phase 4b's rows still open on `main.tscn`, the view layers and `CommandBar` (P281, P293, the
  polish V4 rows); audio must not need them.
- The 150-unit budget (CLAUDE.md rule 6) and the web preview (Compatibility, browsers start audio
  only after a user gesture).

## Decision
### 1. Where audio lives
- `game/view/audio/` (presentation; no new top-level folder, so CLAUDE.md's layout stands).
  `audio_service.gd` is the autoload **`AudioService`** (no `class_name`,
  `tests/project/test_autoloads.gd`). Helpers with `class_name`: `AudioSettings` (Resource),
  `AudioCueDef` (Resource), `AudioCueTable` (Resource), `VoicePool`, `MusicDeck`, `BattleSounds`
  (Node), `UiSounds`.
- `game/sim`, `native/` and `game/ai` never reference audio (rule 1; the AI acts only through
  Commands).

### 2. Buses
`res://default_bus_layout.tres` (the project's default layout path): **Master** (one hard limiter,
so twenty explosions do not clip), and **Music**, **Sfx**, **Ui** sent to Master. No other bus
effect (no reverb, no sidechain compressor: CPU on weak phones). The player's Sound setting sets Sfx
and Ui together, Music sets Music; each is an int step 0-10 in the save (ADR 0042), turned into dB
in `AudioService` (view code may use floats). Step 0 mutes the bus.

### 3. Voices and pooling
- `VoicePool` makes its players once, at the autoload's `_ready`: `world_voices` (16)
  `AudioStreamPlayer2D` for battle sounds, `ui_voices` (4) `AudioStreamPlayer` for the interface,
  and `MusicDeck`'s two. No player is created or freed during play.
- A cue has `max_voices` and a `priority`. A new sound takes a free voice, or steals the oldest of
  lower priority, or is dropped. A battle cannot start more than `voices_per_tick` (6) new world
  voices per tick; the rest are dropped by priority.
- World voices sit at the event's world position; the listener is the current `Camera2D`. Distance
  attenuation and `max_distance` come from `AudioSettings`. (Unverified on 4.7.2 with the camera's
  zoom: P501 checks how zoom changes the heard distance and, if it does, scales `max_distance` by
  the zoom level.) Off-screen events farther than `hear_margin_px` from the view are not played at
  all.

### 4. Battle sounds: the event feed
`BattleSounds` is a Node in the main scene (P535 adds it to `scenes/main.tscn` and
`scenes/dev/perf_arena.tscn` after the Phase 4b gate; until then it is built by its tests). It
connects to `runner.ticked`, reads `runner.snapshot.events` once per tick and never writes the sim.

| Source | Sound | Rule |
| --- | --- | --- |
| `SHOT` | the weapon's fire cue (by `WeaponDef` id, built into an index table at match start) | seen only |
| `IMPACT` | hit by weapon family and target armour | seen only |
| `DIED` | flag 0 (killed): death by move class (foot, vehicle, flyer) or the building's collapse; flag 1 (cancelled site): nothing; flag 2 (boarded, `Carry.BOARDED`, ADR 0036/0037): the boarding clunk or nothing, **never a death cue**; flag 3 (sold): the sale's pack-up sound | seen only |
| `STRIKE` | the launch at acceptance, the landing at its landing tick; kind 3 = the sweep's hum | own and seen; an enemy strike's warning is a UI cue |
| `SPAWNED` | own unit ready (own rows only) | own |
| `UNLOADED`, `REPAIRED` | door clunk, weld crackle (throttled per building) | seen only |
| `MINE_BLAST` | the blast | seen only |
| `AttackCues.cue_changed` | the "under attack" radio chirp | own (UI bus) |
| `HudState` ready chip | "construction ready" chirp | own (UI bus) |
| `CommandQueue.submitted` | the order acknowledgement chirp | own Commands only (UI bus) |

- **Fairness:** "seen" is exactly `EffectsLayer`'s fog rule (the tile of the point in that tick's
  fog), called read-only. No sound tells the player what the fog hides: no enemy production, no
  unseen shots, no unknown mine (ADR 0037 §8). A test proves it on scripted snapshots.
- **Determinism:** the variant and the pitch of a cue are chosen without a random generator, from
  `(event's id * 31 + tick) % variants` and a table of pitch steps in milli. The sim is never
  read for audio outside the published snapshot.
- **Cost:** one pass over the events with reused arrays; cue lookups are int-indexed tables built at
  match start; same-cue events inside `cooldown_ms` coalesce into one voice (louder by
  `stack_db`). No allocation per tick (the existing allocation guard pattern). Budget: under 0.3 ms
  of main work per frame on the phone (estimate; the perf arena card shows it after P535).
- **UI clicks:** `UiSounds` connects to `SceneTree.node_added` and hooks every `BaseButton`'s
  `pressed` (opt-out: meta `no_click`), so no HUD or menu file needs an edit.
  `command_queue_service.gd` gains one signal, `submitted(command)`, emitted in `submit` (P503):
  it means "a player just gave an order". It also gains `submit_logged(command)`, the same queueing
  without the signal, which only the Restorer uses (ADR 0042 §6), so a restore never chirps its
  thousands of logged orders.

### 5. Music, ducking and the background
- `MusicDeck`: two `AudioStreamPlayer`s on Music; `play_music(id)` crossfades over `crossfade_ms`
  (1,500); a sting (`victory`, `defeat`) plays once over a faded-out battle loop. Tracks: `menu`
  (loop), `battle` (loop), `victory` and `defeat` stings (question 1). Battle music starts with the
  first published tick, menu music with the menu.
- **Duck:** Music goes down by `duck_db` (6) for `duck_ms` when a strike lands and while a sting
  plays, by a tween on the Music bus volume.
  *Note (2026-11-15, P501b):* the duck lowers the two music players, not the Music bus, because
  the bus volume belongs to the player's Music step. A sting plays at full level with the loop
  faded out beneath it, and the duck is not applied to the sting.
- **Mute reasons:** a set of reasons; the Master bus is muted while it is not empty, with a
  `fade_ms` (150) fade in and out:
  - `background`: `NOTIFICATION_APPLICATION_PAUSED` and `NOTIFICATION_APPLICATION_FOCUS_OUT` add
    it (the music's stream is also paused, so it resumes where it was); `RESUMED` and `FOCUS_IN`
    clear it;
  - `ad`: `AdService.ad_opened` adds it, `ad_closed` clears it (agreed with Phase 6, 2026-11-15);
  - `restoring`: the Restorer adds it for the whole restore and clears it when the restored match
    enters the tree (ADR 0042 §6), a second guard beside `submit_logged`.
  Each is idempotent; the order of the notifications does not matter. Explicit muting is needed
  because a browser tab keeps playing in the background, and the Android behaviour of the audio
  driver on pause is not relied on (unverified).
- **Web:** the browser starts audio only after the first touch; the menu music may start a moment
  late on the preview. Accepted.

### 6. Data
- `data/audio_settings.tres` (`AudioSettings`): default steps per bus, voice counts,
  `voices_per_tick`, `hear_margin_px`, `max_distance`, `cooldown_ms` default, `stack_db`,
  `crossfade_ms`, `duck_db`, `duck_ms`, `fade_ms`.
- `data/audio_cues.tres` (`AudioCueTable`): each `AudioCueDef` has an id, its streams (variants),
  `volume_db`, pitch steps, `cooldown_ms`, `priority`, `max_voices`, bus; and the maps from weapon
  ids, move classes, building types and UI events to cue ids. A weapon or type without a mapping
  falls back to its family's cue; a data test fails on a roster weapon with neither.
- View data: never loaded by `game/sim`, not in `defs_hash`. P509 keeps these paths from starting
  `balance.yml`.

### 7. Files, formats and licences
- `assets/audio/sfx/<family>/*.wav` (mono, 22,050 or 44,100 Hz, short) and
  `assets/audio/music/*.ogg` (Ogg Vorbis, loops flagged in the import). The WAV import compression
  (QOA or IMA ADPCM) is chosen in P504 by export size and an audible check, not measured for time
  in a session. Budget: all audio in the APK at most 12 MB.
- **Allowed:** CC0 1.0; CC-BY 3.0 or 4.0; audio made in this repository by `tools/sfxgen/` (a
  GDScript synthesiser whose parameter files are committed; its output is own work under the MIT
  licence). **Not allowed:** CC-BY-SA, any NC or ND licence, "royalty-free" or custom store
  licences, asset-store packs, sounds from games or films, AI audio from outside tools.
  Note (2026-11-15): ADR 0046 replaces "under the MIT licence": sfxgen output under
  `assets/audio/` is Copyright (c) 2026 AppCode ApS, all rights reserved, and its CREDITS rows say
  "All rights reserved (AppCode ApS)"; `tools/sfxgen/` itself stays MIT.
- **Candidate sources by licence type** (each file checked on its own page, never assumed from a
  site or a pack name): CC0 packs on Kenney and on OpenGameArt (licence filter CC0); Freesound with
  the "Creative Commons 0" filter; CC-BY on Freesound ("Attribution" filter) and OpenGameArt
  (CC-BY 3.0/4.0); CC-BY music libraries that state CC-BY 4.0 per track.
- **Each file's CREDITS row:** the file, the author, the URL of that file's own page, the licence
  and version as the page states it, the date checked, and what was changed (cut, normalised,
  mixed). A pack's own licence file is kept beside its files. Art-director rejects a file whose page
  hints at sampled third-party material or whose uploader is not its author.
  Note (Michael, 2026-11-18, P504): a file uploaded by someone other than its author is allowed
  when its page names the author and states the author's own licence declaration; its CREDITS row
  records both the author and the uploader. Anonymous re-uploads stay rejected. Combat sounds use
  real recordings (CC0 or CC-BY), not sfxgen synthesis; sfxgen stays for radio chirps and UI
  (P505). No Freesound API key for now: P504 ships the OpenGameArt set (a ship cannon for the tank
  gun, a layered cannon for artillery), which may be upgraded later.
  Note (2026-11-18, P504c): the tank gun, the artillery and the rocket now come from Freesound
  recordings, downloaded by hand from the website (still no API key). The tank gun and the
  artillery use Yle's 1958 field recording of a 76 mm field gun (CC BY 4.0, uploaded by Yle's own
  archive account): its two nearest shots for the tank gun, two farther shots for the artillery.
  The rocket is a hobby rocket launch recorded by its uploader (CC0). Every other combat cue keeps
  its OpenGameArt file.
- **CC-BY attribution in the game:** the Licences screen lists every CC-BY file's credit line
  (question 9; ADR 0043 §7). P508's scan checks that every file has a row and an allowed licence;
  it cannot check that the row is true.

### 8. Haptics
Not audio: the one Vibration switch stays `HudPrefs` (`[hud] haptics`, now inside the save file,
ADR 0042 §3), shown in Settings (question 8: one on/off switch; strengths per event stay in
`data/input_settings.tres`).

### 9. Proof (headless)
The dummy audio driver headless: `AudioService` mute reasons in any order; volume steps to buses;
`VoicePool` caps, steals and `voices_per_tick`; `BattleSounds` on scripted snapshots (seen and
unseen events, coalescing, the fallbacks, a DIED record with flag 2 (boarded) that plays no death cue,
no allocation); `submit_logged` emits no `submitted`; `MusicDeck` crossfade and stings with a
fake clock; `UiSounds` hooks a button added after it; the asset scan (P508).

## Consequences
- Audio needs no Phase 4b file until P535's two scene lines and P503's one signal in `game/core`.
- Hearing only what is seen keeps ADR 0010's fairness and the GDD's pillar 4; a player hears no
  more than the explosions show.
- A fixed pool and a per-tick cap bound the cost at 150 units; distant and coalesced sounds are lost
  by design.
- Every new weapon or unit type needs a cue mapping or uses its family's; the data test reports it.
- The CC-BY credits must ship in the Licences screen; a CC0-only set would need none, but is not
  required.

## Alternatives considered
1. **The sim emits sound events.** Rejected: rule 1; the event list already says everything needed.
2. **A Node per sound, created per event.** Rejected: allocation per tick and unbounded voices.
3. **`AudioStreamPolyphonic` per cue.** Possible, fewer nodes; rejected for now because steal by
   priority across cues and per-voice position need the pool anyway.
4. **Sidechain compressor for ducking.** Rejected: CPU per frame on the Music bus; a tween is free.
5. **Hearing the whole map.** Rejected: leaks hidden information.
6. **Random variation with `randf()`.** Rejected: view tests would not repeat; a hash pick is enough.
