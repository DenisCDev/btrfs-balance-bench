"""Build a btrfs layout that a desktop used for games and code ends up with.

Large "game" files and small "build/cache" files are written interleaved, as
when a game downloads while a project builds, so their extents share chunks.
Then every build/cache file and a third of the game files are deleted
(a `cargo clean`/shader-cache purge and an uninstall), leaving chunks partly
used. Deterministic: same seed, same layout.
"""
import os, random, sys

root = sys.argv[1]
rng = random.Random(42)
MiB = 1 << 20
os.makedirs(f"{root}/games", exist_ok=True)
os.makedirs(f"{root}/build", exist_ok=True)

games = [rng.randint(64, 384) * MiB for _ in range(14)]   # ~3.1 GiB
builds = [rng.randint(1, 16) * MiB for _ in range(400)]  # ~3.3 GiB
BLOCK = 4 * MiB

def writer(kind, sizes):
    for i, size in enumerate(sizes):
        path = f"{root}/{kind}/{i:04d}"
        with open(path, "wb") as f:
            left = size
            while left:
                n = min(left, BLOCK)
                f.write(os.urandom(n))  # incompressible, as game assets are
                left -= n
                yield
            f.flush()
            os.fsync(f.fileno())

g, b = writer("games", games), writer("build", builds)
live = [g, b]
while live:
    for w in list(live):
        try:
            next(w)
        except StopIteration:
            live.remove(w)

for i in range(len(builds)):
    os.remove(f"{root}/build/{i:04d}")
for i in range(0, len(games), 3):
    os.remove(f"{root}/games/{i:04d}")
os.sync()
