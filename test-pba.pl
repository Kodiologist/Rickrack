#!/usr/bin/perl

use utf8;
use warnings;
use strict;

use Rickrack_PBA_Density;

use List::Util 'sum';
use Test::More;
use Test::Deep;

# ------------------------------------------------------------
# * Setup
# ------------------------------------------------------------

sub is_approx
   {cmp_deeply($_[0], num($_[1], 1e-8), $_[2])}

sub ilogit
   {1 / (1 + exp(-$_[0]))}

sub mean
   {sum(@_) / @_}

my $pc = .75;

my $d = Rickrack_PBA_Density->new(lo => 0, hi => 1, pc => $pc);

sub diff
   {my @x = @_;
    map {$x[$_ + 1] - $x[$_]} 0 .. $#x - 1}

sub integral_ok
   {my $d = shift;
    my $integral = 0;
    my @diffs = diff(@{$d->{x}}, 1);
    $integral += $diffs[$_] * $d->{density}[$_]
        foreach 0 .. $#diffs;
    is_approx $integral, 1;}

# ------------------------------------------------------------
# * Multiple probes of the same x-value
# ------------------------------------------------------------

cmp_deeply
    $d->update(.7, 1)->update(.7, 1)->update(.7, 1)->update(.3, 0)->{x},
    [0, .3, .7];

# ------------------------------------------------------------
# * Medians of known densities
# ------------------------------------------------------------

sub dhm
   {my $d2 = $d->clone(x => $_[0], density => $_[1]);
    integral_ok $d2;
    $d2->median}

is_approx dhm([0], [1]), .5;
is_approx dhm([0, .5], [1, 1]), .5;
is_approx dhm([0, .5], [2/3, 4/3]), .625;
is_approx
    dhm([map {$_/10} 0 .. 9],
        [(.5) x 5, 1, 1.5, 2, 2.5, .5]),
    .7;

# ------------------------------------------------------------
# * Comparison to Monte Carlo medians
# ------------------------------------------------------------

foreach (
        [[.5, 1], [2/3, 0], [1/7, 1]],
        [[.5, 1], [.3, 1], [.5, 0]])

   {my @obs = @$_;
    my $d2 = $d;

    foreach (@obs)
       {$d2 = $d2->update(@$_);
        integral_ok $d2;}

    my @samples;
    my $n_samples = 100_001;
    SAMPLE: while (@samples < $n_samples)
       {my $θ = rand;
        foreach (@obs)
           {my ($x, $y_needed) = @$_;
            my $y_obt = $x < $θ ? rand() < $pc : rand() > $pc;
            $y_obt == $y_needed or next SAMPLE;}
        push @samples, $θ;}
    my $mc_median = (sort {$a cmp $b} @samples)[int($n_samples/2)];

    cmp_deeply $d2->median, num($mc_median, .005);}

# ------------------------------------------------------------
# * Serialization
# ------------------------------------------------------------

cmp_deeply $d, Rickrack_PBA_Density->deserialize($d->serialize);
is $d->serialize, Rickrack_PBA_Density->deserialize($d->serialize)->serialize;

my $d2 = $d;
$d2->update(@$_) foreach [[.5, 1], [2/3, 0], [1/7, 1]];
cmp_deeply $d2, Rickrack_PBA_Density->deserialize($d2->serialize);
is $d2->serialize, Rickrack_PBA_Density->deserialize($d2->serialize)->serialize;

# ------------------------------------------------------------
# * Medians as point estimates of θ
# ------------------------------------------------------------

# These tests aren't enforced. They're just for you to eyeball
# the results so you can get a sense of the algorithm's
# performance on simulated data.

my $trials = 20;
sub estimate
   {my $decider = shift;
    my $d = $d;
    foreach (1 .. $trials)
       {my $med = $d->median;
        my $higher = $decider->($med);
        $d = $d->update($med, $higher);}
    $d->median}

sub multi_estimate
   {my $decider = shift;
    my @estimates =
        sort {$a <=> $b}
        map {estimate($decider)}
        1 .. 100;
    sprintf '[%.03f -- %.03f -- %.03f]',
        $estimates[2], mean(@estimates), $estimates[97];}

note multi_estimate sub {rand() > ilogit(20*$_[0] - 5)};

note multi_estimate sub {rand() > ilogit(10*20*$_[0] - 10*15)};

# ------------------------------------------------------------

done_testing;
