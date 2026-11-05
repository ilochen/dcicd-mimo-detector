"""Produce per-clock RTL stimuli and an independent integer K-best scoreboard.

Rows are reset, valid, channel/data flag, 96-bit bus, expected input accepted,
and expected packed output. The RTL bench checks matching o_valid six clocks later.
"""
from itertools import product
from pathlib import Path
import argparse
import random

SYMBOLS = (3, 1, -1, -3)
GRAY = {1: 0, 3: 1, -1: 2, -3: 3}
BUDGETS = (4, 16, 8, 8, 2, 1)
rng = random.Random(0xD01CD)


def pack(fields):
    value = 0
    for field in fields:
        assert -32768 <= field <= 32767
        value = (value << 16) | (field & 0xFFFF)
    return value


def word(symbols):
    value = 0
    for i in range(3):
        value = (value << 4) | (GRAY[symbols[i]] << 2) | GRAY[symbols[i + 3]]
    return value


def detect(matrix, z):
    # Explicitly enumerate and sort candidates, independent of hardware selectors.
    beam = [(0, ())]
    for depth, budget in enumerate(BUDGETS):
        row = 5 - depth
        candidates = []
        for parent_rank, (prior, suffix) in enumerate(beam):
            for child_rank, symbol in enumerate(SYMBOLS):
                path = (symbol,) + suffix
                prediction = sum(r*x for r, x in zip(matrix[row][row:], path))
                cost = prior + abs(4*z[row] - prediction)
                candidates.append((cost, parent_rank, child_rank, path))
        candidates.sort()
        beam = [(c, p) for c, _, _, p in candidates[:budget]]
    return word(beam[0][1])


def matrix_beats(matrix):
    entries = [matrix[r][c] for r in range(6) for c in range(r, 6)] + [0]*3
    return [pack(entries[i:i+6]) for i in range(0, 24, 6)]


class Stream:
    def __init__(self):
        self.lines = []
        self.observations = 0

    def drive(self, reset=0, valid=0, data=1, bus=0, expected=None):
        self.lines.append(f'{reset} {valid} {data} {bus:024x} {int(expected is not None)} {(expected or 0):03x}')
        self.observations += expected is not None

    def bubble(self):
        self.drive(data=rng.randrange(2), bus=rng.getrandbits(96))

    def channel(self, matrix):
        for beat in matrix_beats(matrix):
            self.bubble()
            self.drive(valid=1, data=0, bus=beat)

    def observe(self, matrix, z):
        self.drive(valid=1, bus=pack(z), expected=detect(matrix,z))


def exercise(matlab_vectors=None):
    stream = Stream()
    identity = [[4096*int(i==j) for j in range(6)] for i in range(6)]
    stream.drive(reset=1)
    stream.drive(valid=1, bus=pack([100]*6))  # No channel yet.
    stream.channel(identity)
    # All 4,096 possible transmitted vectors. Known truth is independent of search.
    for symbols in product(SYMBOLS, repeat=6):
        stream.drive(valid=1, bus=pack([1024*x for x in symbols]), expected=word(symbols))

    # Reload while detections are in flight. Old matrix remains active until commit.
    matrix = [[rng.randint(-32768,32767) if c >= r else 0 for c in range(6)] for r in range(6)]
    for i, beat in enumerate(matrix_beats(matrix)):
        stream.drive(valid=1,data=0,bus=beat)
        stream.observe(identity if i < 3 else matrix, [rng.randint(-32768,32767) for _ in range(6)])

    for case in range(32):
        if case==0:
            matrix=[[0]*6 for _ in range(6)]  # All candidates tie.
        elif case==1:
            matrix=[[(-32768 if c%2 else 32767) if c>=r else 0 for c in range(6)] for r in range(6)]
        else:
            matrix=[[rng.randint(-32768,32767) if c>=r else 0 for c in range(6)] for r in range(6)]
        stream.channel(matrix)
        for n in range(12):
            if n%4==1:
                stream.bubble()
            if n==0:
                z=[32767,-32768]*3
            else:
                z=[rng.randint(-32768,32767) for _ in range(6)]
            stream.observe(matrix,z)

    # Reset must discard pending results, a partially loaded matrix, and valid state.
    stream.drive(valid=1,data=0,bus=matrix_beats(identity)[0])
    stream.drive(reset=1)
    stream.drive(valid=1,bus=pack([0]*6))
    stream.channel(identity)
    stream.observe(identity,[3072,-1024,1024,-3072,3072,-1024])

    if matlab_vectors:
        for _ in range(6):
            stream.bubble()
        stream.drive(reset=1)
        for row in Path(matlab_vectors).read_text().splitlines():
            if not row.strip():
                continue
            flag,bus,expected=row.split()
            flag=int(flag)
            assert flag in (0,1) and len(bus)==24 and len(expected)==3
            stream.drive(valid=1,data=flag,bus=int(bus,16),expected=int(expected,16) if flag else None)
    for _ in range(8):
        stream.bubble()
    return stream


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('out',type=Path)
    parser.add_argument('--matlab')
    args=parser.parse_args()
    stream=exercise(args.matlab)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text('\n'.join(stream.lines)+'\n')
    print(f'{len(stream.lines)} stimulus cycles, {stream.observations} accepted observations before reset flushing')
