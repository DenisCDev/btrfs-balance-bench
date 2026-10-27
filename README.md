# btrfs-balance-bench

**English** · [Português](README.pt-BR.md)

Measures what BigLinux's `big-btrfs-balance` script does across consecutive boots, and compares the original script with the change proposed in [biglinux/auto-rules-io#4](https://github.com/biglinux/auto-rules-io/pull/4).

The original script runs `btrfs balance start -dusage=50 -musage=50` after every boot. Once the first balance has packed the data, the last chunk stays partly filled, matches the same filter on the next boot and is rewritten again, so later boots write data without freeing any space. The patched script only starts a balance when the unused space of a type is at least one chunk, the minimum needed to free anything.

## How it works

Everything runs on a GitHub Actions Ubuntu 24.04 runner, on a btrfs loopback image mounted with `compress-force=zstd,noatime` and `--direct-io=on`.

- `fill.py` builds the file layout: large and small files written interleaved, then all small files and part of the large ones deleted.
- `script.sh LABEL SCRIPT` runs the real script on a fresh copy of the image for three boots in a row. The script hard-codes `/` and `/home`, so only those paths are pointed at the test filesystem. Each boot logs `btrfs filesystem df`, the chunk sizes, the balance command it started and a CSV row: seconds, MiB written, MiB returned to unallocated space.
- `bench.sh LABEL "FILTERS" REP` runs a single `btrfs balance start` with the given filters and prints the same CSV row, to compare filters in isolation.
- `contend.sh` measures a balance while other I/O is running.

Scripts under test:

| file | what it is |
|---|---|
| `big-btrfs-balance.orig` | the upstream script |
| `big-btrfs-balance.patched-v1` | first version of the patch, with a fixed 1 GiB data threshold |
| `big-btrfs-balance.patched` | current version: reads the metadata chunk size and caps both thresholds at 10% of the filesystem size, as the kernel does below 10 GiB |

Workflows: `bench.yml` (12 GiB image) and `small.yml` (5 GiB image, where data chunks are 512 MiB). Raw CSV and logs are uploaded as run artifacts.

## Results

12 GiB image, three boots, three repetitions each:

| boot | original: written / returned to unallocated | patched: written / returned |
|---|---|---|
| 1 | 1437-1438 MiB / 4048 MiB | 1430 MiB / 4096 MiB |
| 2 | 494-495 MiB / 0 | 0 / 0 |
| 3 | 495 MiB / 0 | 0 / 0 |

5 GiB image:

| boot | original: written / returned | patched: written / returned |
|---|---|---|
| 1 | 148 MiB / 472 MiB | 139 MiB / 520 MiB |
| 2 | 8 MiB / 0 (2 chunks relocated) | 0 / 0 |
| 3 | 9 MiB / 0 (2 chunks relocated) | 0 / 0 |

## Limits

This was not run on a BigLinux install, and the test filesystems hold only a few chunks. The first balance after many deletions costs the same with both scripts; only the repeated rewrite on later boots goes away.
