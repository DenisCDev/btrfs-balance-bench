#!/bin/bash
# One balance run on a fresh copy of the base image; prints one CSV row.
# usage: bench.sh LABEL "BALANCE FILTERS" REP
set -euo pipefail
label=$1 filters=$2 rep=$3
W=/mnt/bench
cp --sparse=always $W/base.img $W/run.img
dev=$(losetup --direct-io=on -f --show $W/run.img)
mount -o compress-force=zstd,noatime "$dev" $W/fs
name=$(basename "$dev")
unalloc() { btrfs filesystem usage -b $W/fs | awk '/Device unallocated/ {print $3}'; }
written() { awk '{print $7}' /sys/block/$name/stat; }
for pass in 1 2; do
    sync; echo 3 > /proc/sys/vm/drop_caches
    u0=$(unalloc); w0=$(written); t0=$(date +%s.%N)
    # shellcheck disable=SC2086
    out=$(nice -n 19 ionice -c 3 btrfs balance start $filters $W/fs 2>&1 | tail -n1)
    sync
    t1=$(date +%s.%N); w1=$(written); u1=$(unalloc)
    chunks=$(sed -n 's/.*relocate \([0-9]*\) out of \([0-9]*\).*/\1\/\2/p' <<<"$out")
    printf '%s,%s,%s,%.2f,%d,%d,%s\n' "$label" "$rep" "$pass" \
        "$(bc <<<"$t1 - $t0")" $(( (w1 - w0) * 512 / 1048576 )) \
        $(( (u1 - u0) / 1048576 )) "${chunks:-0/0}"
done
umount $W/fs; losetup -d "$dev"; rm -f $W/run.img
