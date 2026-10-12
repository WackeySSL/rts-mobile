# LLVM libc++ licence

`LICENSE.TXT` is the licence file of LLVM's libc++, unchanged. Apache License v2.0 with LLVM
Exceptions; the file also carries the legacy University of Illinois/NCSA and MIT licences of
libc++'s older code.

- Source: https://github.com/llvm/llvm-project/blob/llvmorg-21.1.0/libcxx/LICENSE.TXT
  (fetched from `https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-21.1.0/libcxx/LICENSE.TXT`)
- Tag: `llvmorg-21.1.0`
- SHA-256: `539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b`

## Why this tag

Every Android build ships Godot's `libc++_shared.so`, and Godot's `COPYRIGHT.txt` does not name it.
Godot 4.7.2-stable pins NDK 29.0.14206865 (`platform/android/detect.py`, `get_ndk_version()`) and
its `SCsub` copies `libc++_shared.so` out of that NDK's sysroot. NDK r29 ships Android clang
r563880c, an LLVM 21 development build. The copy in the `android-dev-latest` APK (Godot 4.7.2
template, read on 2026-10-12) agrees:

- Its `.comment` section names Android clang 21.0.0 (r563880c) and LLD 21.0.0 (r563880c, the same
  llvm-project commit). It also names Android clang 19.0.0 (r530567c) and its `.note.android.ident`
  says r28; those most likely come from NDK r28 sysroot objects linked into the library.
- Its exported symbols match the LLVM 21 line of upstream's libc++ ABI list for
  `x86_64-linux-android21` (`libcxx/lib/abi/`), not LLVM 19. It exports
  `std::__ndk1::__from_chars_floating_point` (`double` and `float`), which the list has from
  `llvmorg-20.1.0` on and not at `llvmorg-19.1.0`. It does not export `declare_reachable` (in the
  list at `llvmorg-19.1.0`, gone at `llvmorg-20.1.0`) and it does not export the pmr
  `__null_memory_resource_imp` and `__new_delete_memory_resource_imp` symbols (in the list at
  `llvmorg-19.1.0` and `llvmorg-20.1.0`, gone at `llvmorg-21.1.0`).

So `llvmorg-21.1.0`, the first release of the LLVM 21 line, is the nearest upstream tag. Android
builds libc++ from its own fork, so no upstream tag is byte-identical to it. The licence text does
not depend on the choice: `libcxx/LICENSE.TXT` has the same SHA-256 at `llvmorg-19.1.0`,
`llvmorg-19.1.7`, `llvmorg-20.1.0` and `llvmorg-21.1.0` (compared when this folder was added).

## Use

`scripts/export-android.sh` and `scripts/export-web.sh` append `LICENSE.TXT` to the
`THIRD_PARTY_LICENSES.txt` they write, with the same text in both (ADR 0005 section 5).
`scripts/ci/test-export-notices.sh` checks both, and the tag and SHA-256 above.

To bump the tag, fetch the file again, update the tag and SHA-256 here, the tag in both export
scripts, and run that test.
