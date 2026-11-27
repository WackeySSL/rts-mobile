#!/usr/bin/env python3
"""Deterministic split of the gdUnit4 suite files into N shards (CI follow-up #87).

Usage: python3 -I scripts/ci/shard-tests.py --shard I/N [--root DIR] [--weights FILE]
       python3 -I scripts/ci/shard-tests.py --check N     [--root DIR] [--weights FILE]
       python3 -I scripts/ci/shard-tests.py --list        [--root DIR]

--shard prints the repo-relative paths of shard I (1-based) of N, one per line, in byte order.
--check  recomputes all N shards and fails (exit 1) unless they are disjoint, their union is exactly
         the list that --list prints, and no unit that has to stay whole was split.
--list   prints every .gd file below tests/ that run-tests.sh would hand to gdUnit4: hidden
         entries and directories with a .gdignore are skipped, as in run-tests.sh.

There is no hand-maintained list of suites. Every file below tests/ is found by walking the tree, so a
new suite lands in some shard by itself. The rule:
  1. A file weighs its estimated seconds: the number of `func test_` lines times a per-case rate
     (0.25 s by default), at least 2 s. scripts/ci/test-shard-weights.txt only changes the balance
     (a file's total seconds, or a directory's per-case rate); it never decides what runs.
  2. Files that must run in one gdUnit4 call form one unit: tests/sim/native/** (scripts/ci/
     check-native-tests.sh reads one results.xml that has to hold every native suite).
  3. Units go heaviest first (ties by path) to the shard with the least load so far (ties to the
     lowest index): the longest-processing-time rule.
Exit: 0 ok, 1 --check failed, 2 usage.
"""
import os
import sys

DEFAULT_RATE = 0.25
MIN_FILE_SECONDS = 2.0
TESTS = "tests"
# Path prefixes whose files form one unit.
WHOLE = ("tests/sim/native/",)


def die(code, msg):
    print("shard-tests: " + msg, file=sys.stderr)
    sys.exit(code)


def list_files(root):
    """The .gd files below tests/, repo-relative with '/', in byte order of the path."""
    found = []
    base = os.path.join(root, TESTS)
    if not os.path.isdir(base):
        die(2, "no %s directory below %s" % (TESTS, root))
    for dirpath, dirnames, filenames in os.walk(base):
        if os.path.exists(os.path.join(dirpath, ".gdignore")):
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            if name.endswith(".gd") and not name.startswith("."):
                rel = os.path.relpath(os.path.join(dirpath, name), root).replace(os.sep, "/")
                found.append(rel)
    return sorted(found, key=lambda p: p.encode())


def read_weights(path):
    hints = []
    if path and os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            for n, line in enumerate(fh, 1):
                line = line.split("#", 1)[0].strip()
                if not line:
                    continue
                parts = line.split()
                try:
                    if len(parts) != 2:
                        raise ValueError
                    hints.append((parts[0], float(parts[1])))
                except ValueError:
                    die(2, "%s:%d: expected '<path> <seconds>'" % (path, n))
    return hints


def weight(root, rel, hints):
    exact = [v for p, v in hints if p == rel]
    if exact:
        return exact[0]
    rate = DEFAULT_RATE
    best = -1
    for p, v in hints:
        if p.endswith("/") and rel.startswith(p) and len(p) > best:
            best, rate = len(p), v
    cases = 0
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
            cases = sum(1 for line in fh if line.startswith("func test_"))
    except OSError:
        pass
    return max(MIN_FILE_SECONDS, cases * rate)


def shards(root, n, hints):
    files = list_files(root)
    units = {}
    for rel in files:
        key = next((w for w in WHOLE if rel.startswith(w)), rel)
        units.setdefault(key, []).append(rel)
    sized = [(sum(weight(root, f, hints) for f in fs), key, fs) for key, fs in units.items()]
    sized.sort(key=lambda t: (-t[0], t[1].encode()))
    load = [0.0] * n
    out = [[] for _ in range(n)]
    for w, _key, fs in sized:
        i = min(range(n), key=lambda k: (load[k], k))
        load[i] += w
        out[i].extend(fs)
    return [sorted(s, key=lambda p: p.encode()) for s in out], load


def parse_n(text):
    if not text.isdigit() or int(text) < 1:
        die(2, "N must be a positive integer, got '%s'" % text)
    return int(text)


def main(argv):
    root = os.getcwd()
    weights = None
    mode = arg = None
    it = iter(argv)
    for a in it:
        if a in ("--shard", "--check", "--root", "--weights"):
            v = next(it, None)
            if v is None:
                die(2, "%s needs a value" % a)
            if a == "--root":
                root = v
            elif a == "--weights":
                weights = v
            else:
                mode, arg = a, v
        elif a == "--list":
            mode = a
        else:
            die(2, "unknown argument '%s'" % a)
    if mode is None:
        die(2, "usage: shard-tests.py --shard I/N | --check N | --list [--root DIR] [--weights FILE]")
    if weights is None:
        weights = os.path.join(root, "scripts/ci/test-shard-weights.txt")
    if mode == "--list":
        print("\n".join(list_files(root)))
        return 0
    if mode == "--shard":
        i_text, sep, n_text = arg.partition("/")
        if not sep:
            die(2, "--shard needs I/N, got '%s'" % arg)
        i, n = parse_n(i_text), parse_n(n_text)
        if i > n:
            die(2, "shard index %d is above the shard count %d" % (i, n))
        out, _ = shards(root, n, read_weights(weights))
        if out[i - 1]:
            print("\n".join(out[i - 1]))
        return 0
    n = parse_n(arg)
    out, load = shards(root, n, read_weights(weights))
    full = list_files(root)
    flat = [f for s in out for f in s]
    problems = []
    if len(flat) != len(set(flat)):
        problems.append("a file is in two shards: %s" % sorted({f for f in flat if flat.count(f) > 1}))
    if set(flat) != set(full):
        problems.append("union differs from the suite list: missing %s, extra %s"
                        % (sorted(set(full) - set(flat)), sorted(set(flat) - set(full))))
    for w in WHOLE:
        homes = {k for k, s in enumerate(out) if any(f.startswith(w) for f in s)}
        if len(homes) > 1:
            problems.append("%s* is split over shards %s" % (w, sorted(h + 1 for h in homes)))
    if not full:
        problems.append("no suite files found")
    if problems:
        for p in problems:
            print("shard-tests: FAIL " + p, file=sys.stderr)
        return 1
    print("shard-tests: ok, %d files in %d shards (estimated s: %s)"
          % (len(full), n, ", ".join("%d: %d files %.0f" % (k + 1, len(out[k]), load[k]) for k in range(n))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
