def check_inputs(a, w, mode):
    if mode not in (0, 1):
        raise ValueError("mode must be 0 (int8) or 1 (W4A8)")
    if len(a) != 2 or len(a[0]) != len(a[1]):
        raise ValueError("a needs two rows of the same length")
    if len(w) != len(a[0]):
        raise ValueError("w needs one row for each input position")

    for row in a:
        for num in row:
            if type(num) != int or num < -128 or num > 127:
                raise ValueError("activations must be integers from -128 to 127")

    low, high = -128, 127
    if mode == 1:
        low, high = -8, 7
    for row in w:
        if len(row) != 2:
            raise ValueError("each weight row needs two numbers")
        for num in row:
            if type(num) != int or num < low or num > high:
                raise ValueError("weight is outside the signed range for this mode")


def matmul(a, w, mode=0):
    check_inputs(a, w, mode)
    ans = [[0, 0], [0, 0]]
    for row in range(2):
        for col in range(2):
            for k in range(len(w)):
                ans[row][col] += a[row][k] * w[k][col]
    return ans


def acc24(values):
    acc = 0
    overflow = False
    for p in values:
        if type(p) != int:
            raise ValueError("step values must be integers")
        total = acc + p
        if total < -8388608 or total > 8388607:
            overflow = True
        acc = (total + 8388608) % 16777216 - 8388608
    return acc, overflow


def pack_step(a, w, k, mode=0):
    check_inputs(a, w, mode)
    steps = len(w)
    if mode == 1:
        steps = (len(w) + 1) // 2
    if type(k) != int or k < 0 or k >= steps:
        raise ValueError("step index is outside this product")

    if mode == 0:
        return [a[0][k] & 255, a[1][k] & 255,
                w[k][0] & 255, w[k][1] & 255]

    first = 2 * k
    second = first + 1
    next_a0, next_a1 = 0, 0
    next_w0, next_w1 = 0, 0
    if second < len(w):
        next_a0 = a[0][second]
        next_a1 = a[1][second]
        next_w0 = w[second][0]
        next_w1 = w[second][1]

    packed0 = ((next_w0 & 15) << 4) | (w[first][0] & 15)
    packed1 = ((next_w1 & 15) << 4) | (w[first][1] & 15)
    return [a[0][first] & 255, next_a0 & 255,
            a[1][first] & 255, next_a1 & 255, packed0, packed1]


def run_array(a, w, mode=0):
    check_inputs(a, w, mode)
    ans = [[0, 0], [0, 0]]
    overflow = False
    stride = 1
    if mode == 1:
        stride = 2

    for row in range(2):
        for col in range(2):
            stuff = []
            for k in range(0, len(w), stride):
                p = a[row][k] * w[k][col]
                if mode == 1 and k + 1 < len(w):
                    p += a[row][k + 1] * w[k + 1][col]
                stuff.append(p)
            ans[row][col], bad = acc24(stuff)
            overflow = overflow or bad
    return ans, overflow


def chunked(a, w, mode=0, limit=None):
    check_inputs(a, w, mode)
    safe_limit = 511
    if mode == 1:
        safe_limit = 8190
    if limit is None:
        limit = safe_limit
    if type(limit) != int or limit < 1 or limit > safe_limit:
        raise ValueError("chunk limit must be between 1 and the mode's safe limit")

    ans = [[0, 0], [0, 0]]
    for start in range(0, len(w), limit):
        stop = start + limit
        small_a = [a[0][start:stop], a[1][start:stop]]
        small_w = w[start:stop]
        part, overflow = run_array(small_a, small_w, mode)
        if overflow:
            raise OverflowError("a supposedly safe chunk overflowed")
        for row in range(2):
            for col in range(2):
                ans[row][col] += part[row][col]
    return ans


def result_bytes(sums):
    if len(sums) != 2 or len(sums[0]) != 2 or len(sums[1]) != 2:
        raise ValueError("sums must be a 2x2 matrix")
    data = []
    for row in sums:
        for num in row:
            if type(num) != int or num < -8388608 or num > 8388607:
                raise ValueError("pass wrapped INT24 results, not wide host sums")
            bits = num & 0xffffff
            data.extend([bits & 255, (bits >> 8) & 255, (bits >> 16) & 255])
    return data + [0, 0, 0, 0]


if __name__ == "__main__":
    a = [[1, 2, 3], [-1, 0, 2]]
    w = [[4, -2], [1, 3], [-3, 2]]
    print("Exact answer:", matmul(a, w))
    print("Chip answer and OVF:", run_array(a, w))
    print("First W4A8 step:", pack_step(a, w, 0, mode=1))
    print("Last W4A8 step (padded):", pack_step(a, w, 1, mode=1))
    print("Result addresses 0..15:", result_bytes(run_array(a, w)[0]))
