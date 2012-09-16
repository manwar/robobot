package RoboBot::Plugin::Sub;

use strict;
use warnings;

sub commands { qw( sub ) }
sub usage { "/<pattern>/<replacement>/ [source]" }

sub handle_message {
    my ($class, $bot, $sender, $channel, $command, $original, $timestamp, $message) = @_;

    return unless $message =~ m{^/(.*)(?<!\x{5c})/(.*)/\s+(.*)}o;

    my $search = $1;
    my $replace = $2;
    my $source = $3;

    $source =~ s{$search}{$replace};

    return $source;
}

1;