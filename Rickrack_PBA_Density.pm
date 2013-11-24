package Rickrack_PBA_Density;

# Implements the probabilistic bisection algorithm for known
# constant noise, as described on page 14 of:
#   Waeber, R. (2013). Probabilistic bisection search for stochastic root-finding (PhD thesis). Cornell University. Retrieved from http://people.orie.cornell.edu/shane/theses/ThesisRolfWaeber.pdf

# Objects of this class represent density functions.
# Methods return new objects rather than mutating the invocant.

use strict;

use List::MoreUtils 'firstidx';
use JSON::XS 'encode_json', 'decode_json';

sub new
# 'lo' and 'hi' are the bounds of the density function's domain.
# 'pc' is a tuning parameter.
   {my $invocant = shift;
    my %h = @_;
    join(' ', sort(keys %h)) eq 'hi lo pc' or die;
    $h{lo} < $h{hi} or die;
    .5 < $h{pc} and $h{pc} < 1 or die;
    # For each $i, $h{density}[$i] will give the density
    # from $h{x}[$i] to $h{x}[$i + 1].
    $h{x} = [$h{lo}];
    $h{density} = [1];
    bless \%h, ref($invocant) || $invocant}

sub clone
   {my $self = shift;
    bless {%$self, @_}, ref $self}

sub serialize
   {my $self = shift;
    # Numify everything before encoding.
    $_ += 0 foreach @{$self}{qw(hi lo pc)};
    $_ = [map {$_ + 0} @$_] foreach @{$self}{qw(x density)};
    encode_json {%$self}}

sub deserialize
   {my $invocant = shift;
    my $s = shift;
    bless decode_json($s), ref($invocant) || $invocant}

sub median
   {my $self = shift;
    my @x = @{$self->{x}};
    my @density = @{$self->{density}};

    my $mass = 0;
    foreach (0 .. $#x)
       {my $newlen = ($_ == $#x ? $self->{hi} : $x[$_ + 1]) - $x[$_];
        my $newmass = $density[$_] * $newlen;
        $mass + $newmass >= .5
            and return $x[$_] + $newlen * (.5 - $mass)/$newmass;
        $mass += $newmass;}}

sub update
# $higher is a boolean saying whether the signal we got from
# $new_x suggests the root is above or below $x.
   {my $self = shift;
    my ($new_x, $higher) = @_;
    my @x = @{$self->{x}};
    my @density = @{$self->{density}};

    # Add the new x-value if necessary.
    my $i = firstidx {$_ > $new_x} @x;
    $i == -1 and $i = @x;
    unless ($x[$i - 1] == $new_x)
       {splice @x, $i, 0, $new_x;
        splice @density, $i, 0, $density[$i - 1];}

    # Now update all the densities. First upweight or downweight
    # them, according to whether their x-value is less than or
    # greater than $new_x. Then normalize the whole thing to
    # have integral 1.
    my $mass = 0;
    foreach (0 .. $#x)
       {$density[$_] *= ($x[$_] >= $new_x) == $higher
          ? $self->{pc}
          : 1 - $self->{pc};
        $mass += $density[$_] *
            (($_ == $#x ? $self->{hi} : $x[$_ + 1]) - $x[$_]);}
    $_ /= $mass foreach @density;

    return $self->clone(x => \@x, density => \@density);}

1;
