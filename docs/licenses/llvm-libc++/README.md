# LLVM libc++ licence

`LICENSE.TXT` is the licence file of LLVM's libc++, unchanged. Apache License v2.0 with LLVM
Exceptions; the file also carries the legacy University of Illinois/NCSA and MIT licences of
libc++'s older code.

- Source: https://github.com/llvm/llvm-project/blob/llvmorg-19.1.0/libcxx/LICENSE.TXT
  (fetched from `https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-19.1.0/libcxx/LICENSE.TXT`)
- Tag: `llvmorg-19.1.0`
- SHA-256: `539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b`

## Why this tag

Every Android build ships Godot's `libc++_shared.so`, and Godot's `COPYRIGHT.txt` does not name it.
Godot 4.7.2-stable pins NDK 29.0.14206865 (`platform/android/detect.py`) and its `SCsub` copies
`libc++_shared.so` out of that NDK's sysroot. The `.comment` section of the copy in the
`android-dev-latest` APK (Godot 4.7.2 template, read on 2026-10-12) names the compiler of its
libc++ objects: Android clang 19.0.0 (r530567c), the LLVM 19 line of NDK r28. Its linker is LLD
21.0.0 (r563880c, NDK r29). So `llvmorg-19.1.0`, the first release of the LLVM 19 line, is the
nearest upstream tag. Android builds libc++ from its own fork, so no upstream tag is byte-identical
to it. The licence text does not depend on the choice: `libcxx/LICENSE.TXT` has the same SHA-256 at
`llvmorg-19.1.0`, `llvmorg-19.1.7` and `llvmorg-21.1.0` (compared when this folder was added).

## Use

`scripts/export-android.sh` and `scripts/export-web.sh` append `LICENSE.TXT` to the
`THIRD_PARTY_LICENSES.txt` they write, with the same text in both (ADR 0005 section 5).
`scripts/ci/test-export-notices.sh` checks both, and the tag and SHA-256 above.

To bump the tag, fetch the file again, update the tag and SHA-256 here, the tag in both export
scripts, and run that test.
