package RoboBot::Plugin::Skills;

use v5.20;

use namespace::autoclean;

use Moose;
use MooseX::SetOnce;

use Text::Wrap qw( wrap );

extends 'RoboBot::Plugin';

has '+name' => (
    default => 'Skills',
);

has '+description' => (
    default => 'Provides functions for managing skillsets and user proficiency levels.',
);

has '+commands' => (
    default => sub {{
        'iknow' => { method      => 'skill_know',
                     description => 'Assigns a proficiency level to yourself for the named skill. If no skill is named, shows a list of all skills you possess.',
                     usage       => '[<skill name> [<proficiency name or number>]]' },

        'theyknow' => { method      => 'skill_theyknow',
                        description => 'Displays all of the registered skills of the named person. You cannot modify another user\'s skills or proficiencies.',
                        usage       => '<nick>' },

        'idontknow' => { method      => 'skill_dontknow',
                         description => 'Removes you from the list of people with any proficiency in the named skill.',
                         usage       => '<skill name>' },

        'whoknows' => { method      => 'skill_whoknows',
                        description => 'Shows a list of all the people who claim any proficiency in the named skill.',
                        usage       => '<skill name>' },

        'skills' => { method      => 'skill_list',
                      description => 'Returns a list of all skills. You may optionally provide a regular expression so that only matching skills are returned.',
                      usage       => '[<pattern>]', },

        'skill-add' => { method      => 'skill_add',
                         description => 'Adds a new skill to the collection.',
                         usage       => '<skill name>', },

        'skill-levels' => { method      => 'skill_levels',
                            description => 'Displays and manages the enumeration of skill proficiencies.' },

        'describe-skill' => { method      => 'describe_skill',
                              description => 'Allows for the addition of descriptive text to a skill, to be shown whenever the skill is queried via (whoknows).',
                              usage       => '<skill name> "<description>"',
                              example     => 'SQL "Structured Query Language; the most common interface language used for interacting with relational databases."' },
    }},
);

sub describe_skill {
    my ($self, $message, $command, $skill, @args) = @_;

    unless (defined $skill && $skill =~ m{\w}) {
        $message->response->raise('You must provide a skill name.');
        return;
    }

    my $desc = join(' ', grep { defined $_ && $_ =~ m{\w+} } @args);

    unless (defined $desc && length($desc) > 0) {
        $message->response->raise('You must provide a description of the skill.');
        return;
    }

    my $res = $self->bot->config->db->do(q{
        update skills_skills
        set description = ?
        where lower(?) = lower(name)
        returning *
    }, $desc, $skill);

    unless ($res && $res->next) {
        $message->response->raise('Could not add a description to the skill "%s". Please make sure the skill exists and try again.', $skill);
        return;
    }

    $message->response->push(sprintf('Description for %s has been updated.', $skill));
    return;
}

sub skill_dontknow {
    my ($self, $message, $command, @skills) = @_;

    unless (@skills) {
        $message->response->push('Must supply skill name(s) to remove.');
        return;
    }

    foreach my $skill (@skills) {
        next unless defined $skill && $skill =~ m{\w+};

        my $res = $self->bot->config->db->do(q{
            delete from skills_nicks
            where nick_id = ?
                and skill_id = ( select skill_id
                                 from skills_skills
                                 where lower(?) = lower(name) )
        }, $message->sender->id, $skill);

        unless ($res && $res->count > 0) {
            $message->response->push(sprintf("You didn't know %s before.", $skill));
            next;
        }

        $message->response->push(sprintf("You have now forgotten %s.", $skill));
    }

    return;
}

sub skill_know {
    my ($self, $message, $command, $skill_name, $skill_level) = @_;

    unless (defined $skill_name && $skill_name =~ m{\w+}) {
        my @skills = $self->show_user_skills($message, $message->sender->id);

        if (@skills < 1) {
            $message->response->push('You have no registered skills.');
            return;
        } else {
            $message->response->push('You have the following skills registered:', @skills);
            return;
        }
    }

    my ($res, $level_id, $level_name);

    # We have a skill name (and unknown skills will be added automatically), but we need
    # to figure out what skill level they want to register at. Provided, but invalid,
    # skill levels are an error, unprovided levels default to the lowest by sort_order.
    if (defined $skill_level && $skill_level =~ m{.+}) {
        no warnings 'numeric';

        $res = $self->bot->config->db->do(q{
            select level_id, name
            from skills_levels
            where level_id = ? or lower(name) = lower(?)
            order by sort_order desc
            limit 1
        }, int($skill_level), $skill_level);

        if ($res && $res->next) {
            ($level_id, $level_name) = ($res->{'level_id'}, $res->{'name'});
        } else {
            $message->response->raise('The proficiency level "%s" does not appear to be valid. Check (skill-levels) for the known list.', $skill_level);
            return;
        }
    } else {
        $res = $self->bot->config->db->do(q{
            select level_id, name
            from skills_levels
            order by sort_order asc
            limit 1
        });

        unless ($res && $res->next) {
            $message->response->raise('Could not determine the default proficiency level.');
            return;
        }

        ($level_id, $level_name) = ($res->{'level_id'}, $res->{'name'});
    }

    $res = $self->bot->config->db->do(q{
        select skill_id, name
        from skills_skills
        where lower(name) = lower(?)
    }, $skill_name);

    my ($skill_id);

    if ($res && $res->next) {
        $skill_id = $res->{'skill_id'};
    } else {
        $res = $self->bot->config->db->do(q{
            insert into skills_skills ??? returning skill_id
        }, { name => $skill_name, created_by => $message->sender->id });

        unless ($res && $res->next) {
            $message->response->raise('Could not create the new skill. Please try again.');
            return;
        }

        $message->response->push(sprintf('The skill "%s" was newly added to the collection.', $skill_name));
        $skill_id = $res->{'skill_id'};
    }

    $res = $self->bot->config->db->do(q{
        select *
        from skills_nicks
        where skill_id = ? and nick_id = ?
    }, $skill_id, $message->sender->id);

    if ($res && $res->next) {
        $res = $self->bot->config->db->do(q{
            update skills_nicks
            set skill_level_id = ?
            where skill_id = ? and nick_id = ?
        }, $level_id, $skill_id, $message->sender->id);

        if ($res) {
            $message->response->push(sprintf('Your proficiency in "%s" has been changed to %s.', $skill_name, $level_name));
            return;
        } else {
            $message->response->raise('Could not update your proficiency in "%s". Please try again.', $skill_name);
            return;
        }
    } else {
        $res = $self->bot->config->db->do(q{
            insert into skills_nicks ???
        }, { skill_id => $skill_id, skill_level_id => $level_id, nick_id => $message->sender->id });

        if ($res) {
            $message->response->push(sprintf('Your proficiency in "%s" has been registered as %s.', $skill_name, $level_name));
            return;
        } else {
            $message->response->raise('Could not register your proficiency in "%s". Please try again.', $skill_name);
            return;
        }
    }

    return;
}

sub skill_theyknow {
    my ($self, $message, $command, $targetname) = @_;

    my $res = $self->bot->config->db->do(q{
        select id, name
        from nicks
        where lower(name) = lower(?)
    }, $targetname);

    unless ($res && $res->next) {
        $message->response->raise('%s is not known to me.', $targetname);
        return;
    }

    my ($nick_id, $nick_name) = ($res->{'id'}, $res->{'name'});

    my @skills = $self->show_user_skills($message, $nick_id);

    if (@skills < 1) {
        $message->response->push(sprintf('%s does not have any skills registered. Pester them to add a few!', $nick_name));
    } else {
        $message->response->push(sprintf('%s has registered the following skills:', $nick_name), @skills);
    }

    return;
}

sub show_user_skills {
    my ($self, $message, $nick_id) = @_;

    my $res = $self->bot->config->db->do(q{
        select l.name, array_agg(s.name) as skills
        from skills_nicks n
            join skills_levels l on (l.level_id = n.skill_level_id)
            join skills_skills s on (s.skill_id = n.skill_id)
        where n.nick_id = ?
        group by l.name, l.sort_order
        order by l.sort_order asc
    }, $nick_id);

    unless ($res) {
        $message->response->raise('Could not retrieve skill list. Please try again.');
        return;
    }

    my @l;

    while ($res->next) {
        push(@l, sprintf('*%s:* %s', $res->{'name'}, join(', ', sort { lc($a) cmp lc($b) } @{$res->{'skills'}})));
    }

    return @l;
}

sub skill_whoknows {
    my ($self, $message, $command, $skill_name) = @_;

    my $skill = $self->bot->config->db->do(q{
        select name, description
        from skills_skills
        where lower(name) = lower(?)
    }, $skill_name);

    unless ($skill && $skill->next) {
        $message->response->push(sprintf('Nobody has yet claimed to know about %s.', $skill_name));
        return;
    }

    $message->response->push(sprintf('*%s*', $skill->{'name'}));
    $message->response->push(sprintf('%s', $skill->{'description'})) if $skill->{'description'};

    my $res = $self->bot->config->db->do(q{
        select l.name, array_agg(n.name) as nicks
        from skills_nicks sn
            join skills_levels l on (l.level_id = sn.skill_level_id)
            join skills_skills s on (s.skill_id = sn.skill_id)
            join nicks n on (n.id = sn.nick_id)
        where lower(s.name) = lower(?)
        group by l.name, l.sort_order
        order by l.sort_order asc
    }, $skill_name);

    if ($res->count < 1) {
        $message->response->push(sprintf('Nobody has yet claimed to know about %s.', $skill));
        return;
    }

#    $message->response->push(sprintf('The following people have expressed some level of proficiency with "%s":', $skill_name));
    while ($res->next) {
        $message->response->push(sprintf('*%s:* %s', $res->{'name'}, join(', ', sort { $a cmp $b } @{$res->{'nicks'}})));
    }

    return;
}

sub skill_add {
    my ($self, $message, $command, @skills) = @_;

    my @existing;
    my @new;

    foreach my $skill (@skills) {
        my $res = $self->bot->config->db->do(q{
            select skill_id, name
            from skills_skills
            where lower(name) = lower(?)
        }, $skill);

        if ($res && $res->next) {
            push(@existing, $skill);
        } else {
            $res = $self->bot->config->db->do(q{
                insert into skills_skills ???
            }, { name => $skill, created_by => $message->sender->id });

            push(@new, $skill);
        }
    }

    if (@existing > 0) {
        $message->response->push(sprintf('The following skills were already known: %s', join(', ', sort { $a cmp $b } @existing)));
    }

    if (@new > 0) {
        $message->response->push(sprintf('The following skills were added to the collection: %s', join(', ', sort { $a cmp $b } @new)));
    }

    return;
}

sub skill_list {
    my ($self, $message, $command, $pattern) = @_;

    my ($res);

    if (defined $pattern && $pattern =~ m{\w+}) {
        $res = $self->bot->config->db->do(q{
            select s.name, count(n.nick_id) as knowers
            from skills_skills s
                join skills_nicks n using (skill_id)
            where s.name ~* ?
            group by s.name
            order by s.name asc
        }, $pattern);
    } else {
        $res = $self->bot->config->db->do(q{
            select s.name, count(n.nick_id) as knowers
            from skills_skills s
                join skills_nicks n using (skill_id)
            group by s.name
            order by s.name asc
        });
    }

    unless ($res) {
        $message->response->raise('Could not retrieve list of skills. Please try again.');
        return;
    }

    my @skills;

    while ($res->next) {
        push(@skills, sprintf('%s (%d)', $res->{'name'}, $res->{'knowers'}));
    }

    if (@skills < 1) {
        $message->response->push('No matching skills could be located.');
        return;
    }

    $message->response->push(sprintf('%d%s skills have been registered:', scalar(@skills), (defined $pattern ? ' matching' : '')));

    local $Text::Wrap::columns = 120;
    @skills = split(/\n/o, wrap('','',join(', ', @skills)));
    $message->response->push($_) for @skills;

    $message->response->collapsible(1);

    return;
}

sub skill_levels {
    my ($self, $message, $command) = @_;

    my $res = $self->bot->config->db->do(q{
        select name
        from skills_levels
        order by sort_order
    });

    $message->response->push('The following levels are available for use when registering your proficiency with a skill:');

    if ($res) {
        while ($res->next) {
            $message->response->push($res->{'name'});
        }
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;
