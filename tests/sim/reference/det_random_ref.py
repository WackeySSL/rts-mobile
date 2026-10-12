#!/usr/bin/env python3
"""Reference literals for tests/sim/test_det_random.gd (ADR 0007 section 7). Not run by verify.

Plain transcription with Python's unbounded ints (a product is masked after the fact), so it
shares nothing with the 16-bit halves of DetRandom.mul32. The generator itself was checked
against Vigna's public-domain xoshiro128starstar.c: state [1, 2, 3, 4] gives 11520 0 5927040
70819200 2031721883 1637235492. Run: python3 -I tests/sim/reference/det_random_ref.py
"""

M32 = 0xFFFFFFFF
MUL_PAIRS = ((M32, M32), (M32, 2), (0xDEADBEEF, 0x7FEB352D))
ROTL_PAIRS = ((0x12345678, 8), (0xDEADBEEF, 31))


def mul32(a, b):
    return (a * b) & M32


def rotl(x, k):
    return ((x << k) & M32) | (x >> (32 - k))


def mix32(x):  # lowbias32
    x ^= x >> 16
    x = mul32(x, 0x7FEB352D)
    x ^= x >> 15
    x = mul32(x, 0x846CA68B)
    return x ^ (x >> 16)


def create(seed, stream):
    seed &= 0x7FFFFFFF
    stream &= 0xFFFF
    s = [mix32((seed + stream * 0x632BE5AB + i * 0x9E3779B9) & M32) for i in range(4)]
    return s if any(s) else [1, 0, 0, 0]


def draw(s):
    result = mul32(rotl(mul32(s[1], 5), 7), 9)
    t = (s[1] << 9) & M32
    s[2] ^= s[0]
    s[3] ^= s[1]
    s[1] ^= s[2]
    s[0] ^= s[3]
    s[2] ^= t
    s[3] = rotl(s[3], 11)
    return result


def next_int(s, n):  # n in 1..2^31, unbiased by rejection
    limit = (1 << 32) - (1 << 32) % n
    value = draw(s)
    while value >= limit:
        value = draw(s)
    return value % n


def shuffle(s, values):  # Fisher-Yates from the end
    for i in range(len(values) - 1, 0, -1):
        j = next_int(s, i + 1)
        values[i], values[j] = values[j], values[i]
    return values


if __name__ == "__main__":
    s = [1, 2, 3, 4]
    print("state [1, 2, 3, 4]:", *[draw(s) for _ in range(6)])
    for seed, stream in ((0, 1), (42, 1), (7, 101)):
        s = create(seed, stream)
        print(f"create({seed}, {stream}) draws:", *[draw(s) for _ in range(5)])
    print("mul32:", *[(a, b, mul32(a, b)) for a, b in MUL_PAIRS])
    print("rotl:", *[(x, k, rotl(x, k)) for x, k in ROTL_PAIRS])
    s = create(42, 1)
    print("create(42, 1) next_int(1000) x5:", *[next_int(s, 1000) for _ in range(5)])
    s = create(42, 1)
    print("create(42, 1) range_int(-5, 5) x5:", *[-5 + next_int(s, 11) for _ in range(5)])
    print("create(42, 1) shuffle(0..9):", *shuffle(create(42, 1), list(range(10))))
    s = create(42, 1)
    print("create(42, 1) pick_random x5:", *[[10, 20, 30, 40, 50][next_int(s, 5)] for _ in range(5)])
