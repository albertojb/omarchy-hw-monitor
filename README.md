# HW Monitor

A small desktop widget for [Omarchy](https://omarchy.org/) that shows the three
numbers you actually check: CPU, memory, and storage.

It sits on the desktop, below your windows, so it is there when you clear the
screen and out of the way when you do not. It follows your Omarchy theme, so it
looks like the rest of the desktop without any configuration.

![HW Monitor on the desktop](preview.png)

## What it does

- **CPU, memory and storage** as labelled bars, refreshed every 3 seconds.
- **Drag it anywhere.** Grab the dotted handle at the top right. Where you drop
  it is remembered across restarts.
- **Click a storage bar** to open that drive in Files.
- **USB sticks and external drives show up on their own.** Anything mounted
  under `/run/media`, `/media` or `/mnt` gets its own labelled row, and its own
  click target. Unplug it and the row goes away.

No configuration file, no daemon, no extra packages.

## Install

```bash
omarchy plugin add https://github.com/albertojb/omarchy-hw-monitor.git --enable
omarchy restart shell
```

To remove it:

```bash
omarchy plugin remove albertojb.hwmonitor
omarchy restart shell
```

The widget stores one thing outside its own directory: the position you dragged
it to, in `~/.local/state/omarchy/albertojb-hwmonitor-position`. Nothing else in
your configuration is read or written.

## Notes

The widget's layer surface covers the screen so that dragging stays stable, but
its input region is masked to the card itself - the rest of your desktop stays
clickable. It renders below windows, never on top of them.

Storage numbers come from `lsblk`, memory from `/proc/meminfo`, and CPU from two
samples of `/proc/stat` taken 300 ms apart.

If you edit `HwMonitor.qml`, run `omarchy restart shell` to see the change.

## Security notes

The widget runs as a long-lived shell process, so every input it takes from
outside its own files is treated as untrusted. This is what is enforced, and
where.

**Position file** (`position.pl`). The path is predictable, so the file is never
trusted. On read, the pathname is opened exactly once with
`O_RDONLY|O_NOFOLLOW|O_NONBLOCK`; the same descriptor is then `fstat`ed and
accepted only if it is a regular file owned by the current user. At most 65
bytes are read from that descriptor (the accepted maximum of 64 plus one), and
the content is used only if it is exactly two non-negative integers. A planted
symlink, FIFO, directory, or oversized file yields nothing and never blocks. On
write, the content is validated, staged in a private 0600 temp file in the same
directory, and `rename()`d over the target, so a planted symlink is displaced
rather than followed and the file is never truncated in place.

**Stats producer** (`stats.sh`). The `lsblk`/`jq` stage runs under a 3 second
deadline, so a stuck block device cannot hang the sampler. Before anything is
serialized, the device list is capped at 8 rows, device labels are reduced to
printable ASCII and cut to 24 characters, mount paths longer than 255 characters
are dropped, percentages are clamped to 0-100, and the storage JSON is capped at
8 KiB as a last resort.

**Stats consumer** (`HwMonitor.qml`). Every sample is re-validated against the
expected schema before it is applied: samples over 16 KiB are dropped, numbers
must be finite and are clamped to 0-100, strings must be within the same length
limits and free of control characters, mount paths must be `/` or sit under
`/run/media`, `/media` or `/mnt`, and the device list is again capped at 8. A
sample that fails any check is dropped whole rather than partially applied.
Labels and values are rendered with `textFormat: Text.PlainText`, so
device-supplied strings can never be interpreted as rich text.

**Opening a drive.** The click handler passes the validated mount path to
`nautilus` as a single argument through an argument array; no shell is involved.

## Requirements

- Omarchy 4.x with the Quickshell-based shell
- `jq`, `lsblk`, `timeout` (all standard on Omarchy)
- `perl` for the position file helper (present on every Omarchy install as a
  dependency of `git`; no modules outside the Perl core are used)
- `nautilus` for the click-to-open action

Tested on Omarchy 4.0.1.

## License

MIT
