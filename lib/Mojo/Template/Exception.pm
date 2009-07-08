# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Template::Exception;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

__PACKAGE__->attr([qw/line lines_before lines_after/], default => sub { [] });
__PACKAGE__->attr('message', default => 'Exception!');

# Attempted murder? Now honestly, what is that?
# Do they give a Nobel Prize for attempted chemistry?
sub new {
    my $self = shift->SUPER::new();
    $self->message(shift);
    return $self;
}

sub parse_context {
    my ($self, $lines, $line) = @_;

    # Context
    my $code = $lines->[$line - 1];
    chomp $code;
    $self->line([$line, $code]);

    # -2
    my $previous_line = $line - 3;
    $code = $previous_line >= 0 ? $lines->[$previous_line] : undef;
    if (defined $code) {
        chomp $code;
        push @{$self->lines_before}, [$line - 2, $code];
    }

    # -1
    $previous_line = $line - 2;
    $code = $previous_line >= 0 ? $lines->[$previous_line] : undef;
    if (defined $code) {
        chomp $code;
        push @{$self->lines_before}, [$line - 1, $code];
    }

    # +1
    my $next_line = $line;
    $code = $next_line >= 0 ? $lines->[$next_line] : undef;
    if (defined $code) {
        chomp $code;
        push @{$self->lines_after}, [$line + 1, $code];
    }

    # +2
    $next_line = $line + 1;
    $code = $next_line >= 0 ? $lines->[$next_line] : undef;
    if (defined $code) {
        chomp $code;
        push @{$self->lines_after}, [$line + 2, $code];
    }

    return $self;
}

sub to_string {
    my $self = shift;

    my $string = '';

    # Header
    my $delim = '-' x 76;
    $string .= ('Error around line ' . $self->line->[0] . ".\n$delim\n")
      if $self->line->[0];

    # Before
    for my $line (@{$self->lines_before}) {
        $string .= $line->[0] . ': ' . $line->[1] . "\n";
    }

    # Line
    $string .= ($self->line->[0] . ': ' . $self->line->[1] . "\n")
      if $self->line->[0];

    # After
    for my $line (@{$self->lines_after}) {
        $string .= $line->[0] . ': ' . $line->[1] . "\n";
    }

    # Delim
    $string .= "$delim\n" if length $string;

    # Message
    $string .= $self->message if $self->message;

    return $string;
}

sub throw {
    my $self = shift->new(shift);

    # Lines
    my @lines = split /\n/, shift;
    my $line;

    # Caller
    my $caller = (caller)[0];

    # Search template in callstack
    my $i = 1;
    while (my ($p, $f, $l) = caller($i++)) {

        # Found?
        if ($p eq $caller && $f =~ /^\(eval\s+\d+\)$/) {

            # Done
            $line = $l;
            last;
        }
    }

    # Fallback to message parsing
    if (!$line && $self->message =~ /at\s+\(eval\s+\d+\)\s+line\s+(\d+)/) {
        $line = $1;
    }

    # Context
    $self->parse_context(\@lines, $line) if $line;

    # Die
    die $self;
}

1;
__END__

=head1 NAME

Mojo::Template::Exception - Template Exception

=head1 SYNOPSIS

    use Mojo::Template::Exception;
    my $e = Mojo::Template::Exception->new;

=head1 DESCRIPTION

L<Mojo::Template::Exception> is a container for template exceptions.

=head1 ATTRIBUTES

=head2 C<line>

    my $line = $e->line;
    $e       = $e->line([3, 'foo']);

=head2 C<lines_after>

    my $lines = $e->lines_after;
    $e        = $e->lines_after([[1, 'bar'], [2, 'baz']]);

=head2 C<lines_before>

    my $lines = $e->lines_before;
    $e        = $e->lines_before([[4, 'bar'], [5, 'baz']]);

=head2 C<message>

    my $message = $e->message;
    $e          = $e->message('oops!');

=head1 METHODS

L<Mojo::Template::Exception> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<new>

    my $e = Mojo::Loader::Exception->new('Oops!');

=head2 C<parse_context>

    $e = $e->parse_context($lines, $line);

=head2 C<to_string>

    my $string = $e->to_string;
    my $string = "$e";

=head2 C<throw>

    $e->throw('Oops!', $template);

=cut