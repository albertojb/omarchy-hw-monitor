#!/bin/sh
# One-shot system stats sample for the desktop widget. Prints one JSON object.
# Storage covers "/" plus anything mounted under /run/media, /media or /mnt,
# which is where udisks2 puts USB sticks and external drives.
#
# The output feeds a long-lived QML process, so the producer is bounded here:
# the lsblk/jq stage runs under a deadline, the device list is capped at
# MAX_DEVICES rows, every device-derived string is reduced to printable ASCII
# and length-limited before serialization, and the storage JSON is capped in
# bytes as a last resort. The consumer re-validates the schema on its side.
MAX_DEVICES=8
MAX_NAME=24
MAX_PATH=255
MAX_STORAGE_BYTES=8192
DEADLINE=3

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

storage=$(timeout -k 1 "$DEADLINE" lsblk -J -b -o NAME,LABEL,MOUNTPOINTS,FSSIZE,FSUSED 2>/dev/null \
  | timeout -k 1 "$DEADLINE" jq -c \
      --argjson max "$MAX_DEVICES" --argjson maxName "$MAX_NAME" --argjson maxPath "$MAX_PATH" '
  def clean($n): tostring | gsub("[^ -~]"; "") | .[0:$n] | if . == "" then "DISK" else . end;
  def clamp: if . < 0 then 0 elif . > 100 then 100 else . end;
  [ .. | objects
    | select(((.mountpoints? // []) | length) > 0 and (.fssize | type) == "number" and .fssize > 0)
    | . as $d | $d.mountpoints[]
    | select(type == "string" and length <= $maxPath
             and (. == "/" or test("^/(run/media|media|mnt)/")))
    | { name: (if . == "/" then "STORAGE" else (($d.label // $d.name) | clean($maxName)) end | ascii_upcase),
        path: .,
        pct: ((($d.fsused // 0) * 100 / $d.fssize | floor) | clamp),
        text: ((($d.fsused // 0) / 1000000000 | floor | tostring) + " / "
               + ($d.fssize / 1000000000 | floor | tostring) + " GB") } ]
  | sort_by(.path != "/") | .[:$max]' 2>/dev/null \
  | head -c "$MAX_STORAGE_BYTES")

printf '{"cpu":%d,"mem":%d,"memText":"%s / %s GiB","storage":%s}\n' \
  "$cpu" "$mempct" "$memused" "$memtotal" "${storage:-[]}"
