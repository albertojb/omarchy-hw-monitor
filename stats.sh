#!/bin/sh
# One-shot system stats sample for the desktop widget. Prints JSON.
# Storage covers "/" plus anything mounted under /run/media, /media or /mnt,
# which is where udisks2 puts USB sticks and external drives.
read -r _ a b c d e f g h _ < /proc/stat
t1=$((a+b+c+d+e+f+g+h)); i1=$((d+e))
sleep 0.3
read -r _ a b c d e f g h _ < /proc/stat
t2=$((a+b+c+d+e+f+g+h)); i2=$((d+e))
dt=$((t2-t1)); cpu=0
[ "$dt" -gt 0 ] && cpu=$(( (100 * (dt - (i2-i1))) / dt ))

mem=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2}
  END{printf "%d %.1f %.1f", (t-a)*100/t, (t-a)/1048576, t/1048576}' /proc/meminfo)
set -- $mem; mempct=$1; memused=$2; memtotal=$3

storage=$(lsblk -J -b -o NAME,LABEL,MOUNTPOINTS,FSSIZE,FSUSED | jq -c '
  [ .. | objects | select(((.mountpoints? // []) | length) > 0 and .fssize != null)
    | . as $d | $d.mountpoints[]
    | select(. == "/" or test("^/(run/media|media|mnt)/"))
    | { name: (if . == "/" then "STORAGE" else ($d.label // $d.name) end | ascii_upcase),
        path: .,
        pct: (($d.fsused // 0) * 100 / $d.fssize | floor),
        text: ((($d.fsused // 0)/1000000000 | floor | tostring) + " / "
               + ($d.fssize/1000000000 | floor | tostring) + " GB") } ]
  | sort_by(.path != "/")')

printf '{"cpu":%d,"mem":%d,"memText":"%s / %s GiB","storage":%s}\n' \
  "$cpu" "$mempct" "$memused" "$memtotal" "${storage:-[]}"
