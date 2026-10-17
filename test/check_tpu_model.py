import random

from tpu_model import matmul, acc24, pack_step, run_array, chunked, result_bytes


a = [[1, 2, 3], [-1, 0, 2]]
w = [[4, -2], [1, 3], [-3, 2]]
assert matmul(a, w) == [[-3, 10], [-10, 6]]
assert run_array(a, w, 1) == ([[-3, 10], [-10, 6]], False)
assert pack_step(a, w, 0) == [1, 255, 4, 254]
assert pack_step(a, w, 0, 1) == [1, 2, 255, 0, 0x14, 0x3e]
assert pack_step(a, w, 1, 1) == [3, 0, 2, 0, 0x0d, 0x02]
assert result_bytes([[-1, 8388607], [-8388608, 0]]) == [
    255, 255, 255, 255, 255, 127, 0, 0, 128, 0, 0, 0, 0, 0, 0, 0]

assert acc24([8388607, 1]) == (-8388608, True)
assert acc24([-8388608, -1]) == (8388607, True)
assert acc24([8388607, 1, -1]) == (8388607, True)
assert run_array([[0], [-128]], [[-128, 0]]) == ([[0, 0], [16384, 0]], False)

for mode, weight, safe_k in [(0, -128, 511), (1, -8, 8190)]:
    for k, expected_ovf in [(safe_k, False), (safe_k + (1 if mode == 0 else 2), True)]:
        a = [[-128] * k, [-128] * k]
        w = [[weight, weight] for i in range(k)]
        sums, overflow = run_array(a, w, mode)
        assert overflow == expected_ovf
        exact = matmul(a, w, mode)
        expected = (exact[0][0] + 8388608) % 16777216 - 8388608
        assert sums == [[expected, expected], [expected, expected]]
        assert chunked(a, w, mode) == exact

row = [-128] * 8190 + [-128, -127, -127, 127]
a = [row, row[:]]
w = [[-8, -8] for i in range(len(row))]
assert run_array(a, w, 1) == ([[8388600, 8388600], [8388600, 8388600]], False)

a = [[-128] * 2000, [127] * 2000]
w = [[-128, 127] for i in range(2000)]
assert chunked(a, w) == matmul(a, w)

rng = random.Random(42)
for mode in (0, 1):
    for k in range(1, 65):
        a = [[rng.randint(-128, 127) for i in range(k)] for row in range(2)]
        low, high = (-128, 127) if mode == 0 else (-8, 7)
        w = [[rng.randint(low, high) for col in range(2)] for i in range(k)]
        decoded = [[0, 0], [0, 0]]
        steps = k if mode == 0 else (k + 1) // 2
        for step in range(steps):
            data = pack_step(a, w, step, mode)
            if mode == 0:
                signed = [num if num < 128 else num - 256 for num in data]
                for row in range(2):
                    for col in range(2):
                        decoded[row][col] += signed[row] * signed[2 + col]
            else:
                acts = [num if num < 128 else num - 256 for num in data[:4]]
                for row in range(2):
                    for col in range(2):
                        lo = data[4 + col] & 15
                        hi = data[4 + col] >> 4
                        if lo >= 8: lo -= 16
                        if hi >= 8: hi -= 16
                        decoded[row][col] += acts[2 * row] * lo + acts[2 * row + 1] * hi
        exact = matmul(a, w, mode)
        assert decoded == exact
        assert run_array(a, w, mode) == (exact, False)
        assert chunked(a, w, mode, limit=3) == exact

assert run_array([[], []], []) == ([[0, 0], [0, 0]], False)
assert chunked([[], []], []) == [[0, 0], [0, 0]]
for bad_call in [
    lambda: matmul([[128], [0]], [[1, 1]]),
    lambda: matmul([[1], [0]], [[8, 0]], 1),
    lambda: matmul([[1], [0]], [[1, 1]], 2),
    lambda: matmul([[1], [0]], [[1]]),
    lambda: matmul([[1.0], [0]], [[1, 1]]),
    lambda: pack_step([[1], [0]], [[1, 1]], -1),
    lambda: chunked([[1], [0]], [[1, 1]], limit=512),
    lambda: result_bytes([[8388608, 0], [0, 0]]),
]:
    try:
        bad_call()
    except ValueError:
        pass
    else:
        raise AssertionError("invalid input should have been rejected")

print("All model checks passed.")
