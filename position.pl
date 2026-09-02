#!/usr/bin/perl
# Read or write the widget position state file.
#   position.pl read  FILE
#   position.pl write FILE X Y
#
# The state path is predictable, so the file is never trusted.
#
# read:  the pathname is opened exactly once with O_RDONLY|O_NOFOLLOW|O_NONBLOCK
#        and every later check uses that descriptor, so nothing can be swapped
#        in between a check and the read. fstat must report a regular file
#        owned by the current user. At most 65 bytes (the accepted maximum
#        plus one) are read, and the content is printed only when it is
#        exactly two non-negative integers. Anything else prints nothing.
# write: the content is validated, staged in a private 0600 temp file in the
#        target directory, and rename()d over the target. A planted symlink is
#        displaced rather than followed, and the file is never truncated in
#        place.
use strict;
use warnings;
use Fcntl qw(O_RDONLY O_NOFOLLOW O_NONBLOCK);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempfile);

use constant MAX_BYTES => 64;
my $VALID = qr/^([0-9]{1,6}) ([0-9]{1,6})$/;

my ($mode, $file, $x, $y) = @ARGV;
exit 1 unless defined $mode && defined $file && $file ne '';

if ($mode eq 'read') {
    sysopen(my $fh, $file, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or exit 0;
    my @st = stat($fh);
    exit 0 unless @st && -f _ && $st[4] == $<;
    my $buf = '';
    my $n = sysread($fh, $buf, MAX_BYTES + 1);
    close($fh);
    exit 0 unless defined $n && $n <= MAX_BYTES;
    $buf =~ s/\s+\z//;
    print "$1 $2\n" if $buf =~ $VALID;
    exit 0;
}

if ($mode eq 'write') {
    exit 1 unless defined $x && defined $y && "$x $y" =~ $VALID;
    my $dir = dirname($file);
    eval { make_path($dir) };
    exit 1 unless -d $dir;
    my ($fh, $tmp) = eval { tempfile('.albertojb-hwmonitor.XXXXXX', DIR => $dir) };
    exit 1 unless $fh;
    my $ok = print {$fh} "$x $y";
    $ok = close($fh) && $ok;
    $ok = rename($tmp, $file) if $ok;
    unlink $tmp unless $ok;
    exit($ok ? 0 : 1);
}

exit 1;
