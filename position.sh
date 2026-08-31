#!/bin/sh
# Read or write the widget position state file.
# Usage: position.sh read FILE
#        position.sh write FILE X Y
# The state path is predictable, so it is never trusted: reads accept only a
# small regular file (a planted symlink or FIFO is ignored instead of followed
# or blocked on), and writes go to a private temp file that atomically
# replaces the target, so a planted symlink is displaced rather than followed.
mode=$1
file=$2
case "$mode" in
  read)
    [ -f "$file" ] && [ ! -L "$file" ] || exit 0
    dd if="$file" bs=64 count=1 iflag=nonblock 2>/dev/null || true
    ;;
  write)
    dir=$(dirname -- "$file") || exit 1
    mkdir -p -- "$dir" || exit 1
    tmp=$(mktemp -- "$dir/.albertojb-hwmonitor.XXXXXX") || exit 1
    if printf '%s %s' "$3" "$4" > "$tmp" && [ ! -d "$file" ] && mv -f -- "$tmp" "$file"; then
      exit 0
    fi
    rm -f -- "$tmp"
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
