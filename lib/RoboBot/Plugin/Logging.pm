package RoboBot::Plugin::Logging;

use v5.20;

use namespace::autoclean;

use Moose;
use MooseX::SetOnce;

use Number::Format;
use Term::ExtendedColor qw( fg bold );

extends 'RoboBot::Plugin';

has '+name' => (
    default => 'Logging',
);

has '+description' => (
    default => 'Provides basic message logging and recall capabilities.',
);

has '+before_hook' => (
    default => 'log_incoming',
);

has '+after_hook' => (
    default => 'log_outgoing',
);

has '+commands' => (
    default => sub {{
        'last' => { method      => 'show_last',
                    description => 'Returns a previous message from the given nick(s). The <step> is how many messages backward to count, with "1" assumed and being the most recent message available. Nick is optional, and if ommitted the caller is assumed. By default, any messages which had S-Expressions in them are skipped.',
                    usage       => '[:include-expressions] [<step>] [<nick>]' },

        'seen' => { method      => 'last_seen',
                    description => 'Reports the last time the given nick was observed saying something in any channel.',
                    usage       => '<nick>' },

        'search' => { method      => 'log_search',
                      description => 'Searches scrollback in the current channel for anything that matches <pattern>, which may be a simple string or a regular expression. Returns the most recent matching entry.',
                      usage       => '<pattern>' },
    }},
);

sub log_search {
    my ($self, $message, $command, $pattern) = @_;

    unless (defined $pattern && $pattern =~ m{.+}) {
        $message->response->raise('Must provide a pattern to search.');
        return;
    }

    my $res = $self->bot->config->db->do(q{
        select n.name, l.message, to_char(l.posted_at, 'YYYY-MM-DD HH24:MI') as posted_at
        from logger_log l
            join channels c on (c.id = l.channel_id)
            join nicks n on (n.id = l.nick_id)
        where c.id = ?
            and l.message ~* ?
            and not l.has_expression
        order by l.posted_at desc
        limit 1
    }, $message->channel->id, $pattern);

    unless ($res && $res->next) {
        $message->response->raise('No matching messages were found.');
        return;
    }

    $message->response->push(sprintf('[%s] <%s> %s', $res->{'posted_at'}, $res->{'name'}, $res->{'message'}));
    return;
}

sub last_seen {
    my ($self, $message, $command, $nick) = @_;

    my $res = $self->bot->config->db->do(q{
        select id, name
        from nicks
        where lower(name) = lower(?)
    }, $nick);

    if ($res && $res->next) {
        $res = $self->bot->config->db->do(q{
            select to_char(l.posted_at, 'on FMDay, FMMonth FMDDth, YYYY at FMHH:MI PM') as last_seen,
                n.name, c.name as channel_name, nt.name as network_name, l.message
            from logger_log l
                join nicks n on (n.id = l.nick_id)
                join channels c on (c.id = l.channel_id)
                join networks nt on (nt.id = c.network_id)
            where l.nick_id = ?
            order by l.posted_at desc
            limit 1
        }, $res->{'id'});

        if ($res && $res->next) {
            $message->response->push(sprintf('%s was last observed %s speaking in %s on the %s network. Their last words were:',
                $res->{'name'}, $res->{'last_seen'}, $res->{'channel_name'}, $res->{'network_name'}));
            $message->response->push(sprintf('<%s> %s', $res->{'name'}, $res->{'message'}));
        } else {
            $message->response->raise(sprintf('The nick %s is known to me, but I cannot seem to find a message from them in my logs.', $nick));
        }
    } else {
        $message->response->raise(sprintf('I do not appear to have ever seen the nick: %s', $nick));
    }

    return;
}

sub show_last {
    my ($self, $message, $command, @args) = @_;

    my $include_expressions = 0;
    my $step = 1;
    my ($nick, $nick_id) = ($message->sender->name, $message->sender->id);

    my ($res);

    if (@args && @args > 0 && lc($args[0]) eq ':include-expressions') {
        shift(@args);
        $include_expressions = 1;
    }

    if (@args && @args > 0 && $args[0] =~ m{^\d+$}o) {
        $step = shift(@args);
    }

    if (@args && @args > 0) {
        $res = $self->bot->config->db->do(q{
            select id, name
            from nicks
            where lower(name) = lower(?)
        }, $args[0]);

        if ($res && $res->next) {
            ($nick_id, $nick) = ($res->{'id'}, $res->{'name'});
        } else {
            $message->response->raise(sprintf('Could not locate the nick: %s', $args[0]));
            return;
        }
    }

    # prevent offset from ever being less than 0
    $step = 1 unless $step > 1;

    $res = $self->bot->config->db->do(q{
        select n.name, l.message
        from logger_log l
            join nicks n on (n.id = l.nick_id)
        where n.id = ? and l.channel_id = ?
            and has_expression = ?
            and l.posted_at < ?
        order by l.posted_at desc
        limit 1 offset ?
    }, $nick_id, $message->channel->id, ($include_expressions ? 't' : 'f'), $message->timestamp->iso8601(), $step - 1);

    if ($res && $res->next) {
        return sprintf('<%s> %s', $res->{'name'}, $res->{'message'});
    } else {
        $message->response->raise('Could not locate a message in this channel for the nick: %s', $nick);
        return;
    }
}

sub log_incoming {
    my ($self, $message) = @_;

    if ($message->has_channel) {
        $self->bot->config->db->do(q{
            insert into logger_log ???
        }, {
            channel_id     => $message->channel->id,
            nick_id        => $message->sender->id,
            message        => $message->raw,
            has_expression => ($message->has_expression ? 't' : 'f'),
            posted_at      => $message->timestamp->iso8601(),
        });
    }

    $self->log_to_terminal($message);
}

sub log_outgoing {
    my ($self, $message) = @_;

    if ($message->response->has_channel && $message->response->has_content) {
        $self->bot->config->db->do(q{
            insert into logger_log ???
        }, [map {{
            channel_id => $message->response->channel->id,
            nick_id    => $message->network->nick->id,
            message    => $_,
        }} @{$message->response->content}] );
    }

    $self->log_to_terminal($message->response);
}

sub log_to_terminal {
    my ($self, $msg) = @_;

    binmode STDOUT, ":encoding(UTF-8)";

    if ($msg->isa('RoboBot::Message')) {
        my $where = $msg->has_channel ? '#' . $msg->channel->name : $msg->sender->name;

        printf("%s [%s] <%s> %s\n",
            fg('seagreen1', sprintf('%s %s', $msg->timestamp->ymd, $msg->timestamp->hms)),
            bold(fg('darkorange1', $where)),
            bold(fg('magenta8', $msg->sender->name)),
            $msg->raw
        );
    } elsif ($msg->isa('RoboBot::Response') && $msg->has_content) {
        my $response = $msg; # for readability
        my $where = $response->has_channel ? '#' . $response->channel->name : $response->nick->name;
        my $when = DateTime->now();

        foreach my $line (@{$response->content}) {
            printf("%s [%s] <%s> %s\n",
                fg('seagreen1', sprintf('%s %s', $when->ymd, $when->hms)),
                bold(fg('darkorange1', $where)),
                bold(fg('magenta8', $response->network->nick->name)),
                $line
            );
        }
    }
}

__PACKAGE__->meta->make_immutable;

1;
