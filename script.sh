#!/bin/bash
# Run the real script's balance step on a fresh copy of the base image, three
# boots in a row. The script hard-codes / and /home, so the test points those
# words at the test filesystem and changes nothing else.
# usage: script.sh LABEL SCRIPT
set -euo pipefail
label=$1 script=$2
W=/mnt/bench
cp --sparse=always $W/base.img $W/run.img
dev=$(losetup --direct-io=on -f --show $W/run.img)
mount -o compress-force=zstd,noatime "$dev" $W/fs
name=$(basename "$dev")
sed -e "s#btrfs device stats /home#btrfs device stats $W/fs#" \
    -e "s#btrfs device stats /#btrfs device stats $W/fs#" \
    -e "s#balance start -dusage=50 -musage=50 /home#balance start -dusage=50 -musage=50 $W/fs#" \
    -e "s#balance start -dusage=50 -musage=50 /\$#balance start -dusage=50 -musage=50 $W/fs#" \
    -e "s#^    balance /home\$#    balance $W/fs#" -e "s#^    balance /\$#    balance $W/fs#" \
    -e 's#\[ "\$FolderHome" != "\$FolderRoot" \]#false#' "$script" > /tmp/under-test
grep -n "$W/fs" /tmp/under-test >&2
unalloc() { btrfs filesystem usage -b $W/fs | awk '/Device unallocated/ {print $3}'; }
written() { awk '{print $7}' /sys/block/$name/stat; }
for pass in 1 2 3; do
    sync; echo 3 > /proc/sys/vm/drop_caches
    u0=$(unalloc); w0=$(written); t0=$(date +%s.%N)
    bash /tmp/under-test >/dev/null 2>&1
    sync
    t1=$(date +%s.%N); w1=$(written); u1=$(unalloc)
    printf '%s,%s,%.2f,%d,%d\n' "$label" "$pass" "$(bc <<<"$t1 - $t0")" \
        $(( (w1 - w0) * 512 / 1048576 )) $(( (u1 - u0) / 1048576 ))
done
umount $W/fs; losetup -d "$dev"; rm -f $W/run.img
