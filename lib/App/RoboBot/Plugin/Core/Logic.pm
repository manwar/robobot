package App::RoboBot::Plugin::Core::Logic;

use v5.20;

use namespace::autoclean;

use Moose;
use MooseX::SetOnce;

extends 'App::RoboBot::Plugin';

=head1 core.logic

Exports logic, bitwise, and boolean functions.

=cut

has '+name' => (
    default => 'Core::Logic',
);

has '+description' => (
    default => 'Provides logic, bitwise, and boolean functions.',
);

=head2 and

=head3 Description

Returns a true value only if all expressions are also true.

=head3 Usage

<expression> [<expression> ...]

=head3 Examples

    (and (> 20 1) (> 40 20))

=head2 or

=head3 Description

Returns a true value if at least one expression is true.

=head3 Usage

<expression> [<expression> ...]

=head3 Examples

    (or (> 20 1) (> 1 20))

=head2 not

=head3 Description

Returns the logical negation of the value provided.

=head3 Usage

<expression>

=head3 Examples

    (not (> 1 20))

=cut

has '+commands' => (
    default => sub {{
        'and' => { method      => 'bool_binary',
                   description => 'Returns a true value only if both expressions are also true. Currently does not short-circuit.',
                   usage       => '(<expression>) (<expression>)',
                   example     => '(> 20 1) (> 1 20)',
                   result      => '0' },

        'or' => { method      => 'bool_binary',
                  description => 'Returns a true value if either expression is true. Currently does not short-circuit.',
                  usage       => '(<expression>) (<expression>)',
                  example     => '(> 20 1) (> 1 20)',
                  result      => '1' },

        'not' => { method      => 'bool_unary',
                   description => 'Returns the logical negation of the value provided.',
                   usage       => '(<expression>)',
                   example     => '1',
                   result      => '0' },

    }},
);

sub bool_binary {
    my ($self, $message, $op, $rpl, @args) = @_;

    # TODO make these short-circuit, which will require separating method handlers out since short-circuiting
    # conditions vary

    return unless $self->has_two_values($message, @args);

    $op = '&&' if lc($op) eq 'and';
    $op = '||' if lc($op) eq 'or';

    my $r;
    eval '$r = $args[0] ' . $op . ' $args[1];';
    return $r ? 1 : 0;
}

sub bool_unary {
    my ($self, $message, $op, $rpl, @args) = @_;

    return unless $self->has_one_value($message, @args);

    $op = '!' if lc($op) eq 'not';

    my $r;
    eval '$r = ' . $op . ' $args[0];';
    return $r ? 1 : 0;
}

sub has_one_value {
    my ($self, $message, @args) = @_;

    return 0 unless @args && @args == 1;
    return 1;
}

sub has_two_values {
    my ($self, $message, @args) = @_;

    return 0 unless @args && @args == 2;
    return 1;
}

__PACKAGE__->meta->make_immutable;

1;
