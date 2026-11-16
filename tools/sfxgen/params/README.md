# Sound parameter files

One `SfxParams` `.tres` per generated sound (P504 to P506 add them). `bash scripts/gen-sfx.sh`
renders each to `assets/audio/sfx/<family>/<id>.wav`; its CREDITS row reads "this repository
(tools/sfxgen)".

The WAVs are byte-identical for the same parameters on one platform and Godot version only (the
synthesis uses the C library's `sin` and `pow`); `gen-sfx.sh --check` is a local tool, not a CI
gate. Names (`id`, `family`) are `[a-z0-9_]+`, the sample rate 22050 or 44100.
