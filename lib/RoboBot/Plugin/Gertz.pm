package RoboBot::Plugin::Gertz;

use strict;
use warnings;

sub commands { qw( * ) }

sub handle_message {
    my ($class, $bot, $sender, $channel, $command, $original, $timestamp, $message) = @_;

    if ($message =~ m{\b(gertz)\b}oi) {
      return 'GERTZ ALERTZ!';
    }
    return (-1);
}

1;