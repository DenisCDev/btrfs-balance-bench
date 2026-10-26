#!/bin/bash
# Time to read a cold 256 MiB "game asset" alone, and while the boot balance
# runs under `nice -n 19 ionice -c 3`, with the loop device on SCHED.
# usage: contend.sh SCHED REP
set -euo pipefail
sched=$1 rep=$2
W=/mnt/bench
cp --sparse=always $W/base.img $W/run.img
dev=$(losetup --direct-io=on -f --show $W/run.img)
name=$(basename "$dev")
echo "$sched" > /sys/block/$name/queue/scheduler
mount -o compress-force=zstd,noatime "$dev" $W/fs
asset=$(ls $W/fs/games | sed -n 2p)
read_asset() {
    echo 3 > /proc/sys/vm/drop_caches
    local t0 t1; t0=$(date +%s.%N)
    dd if=$W/fs/games/$asset of=/dev/null bs=1M count=256 status=none
    t1=$(date +%s.%N); bc <<<"$t1 - $t0"
}
alone=$(read_asset)
nice -n 19 ionice -c 3 btrfs balance start -dusage=50 -musage=50 $W/fs >/dev/null 2>&1 &
bal=$!
sleep 3
during=$(read_asset)
wait $bal || true
printf '%s,%s,%.2f,%.2f\n' "$sched" "$rep" "$alone" "$during"
umount $W/fs; losetup -d "$dev"; rm -f $W/run.img
