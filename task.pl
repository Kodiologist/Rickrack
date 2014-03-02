#!/usr/bin/perl -T

my %p;
%p = @ARGV; s/,\z// foreach values %p; # DEPLOYMENT SCRIPT EDITS THIS LINE

use strict;

use Tversky 'cat', 'randelm', 'shuffle';
use Rickrack_PBA_Density;

# ------------------------------------------------
# Parameters
# ------------------------------------------------

my $break_interval = 50;
  # We'll offer the subject a break after every
  # $break_interval trials.

# These are the medium-magnitude items from Table 3 (p. 81) of:
# Kirby, K. N., Petry, N. M., & Bickel, W. K. (1999). Heroin addicts have higher discount rates for delayed rewards than non-drug-using controls. Journal of Experimental Psychology: General, 128(1), 78-87. doi:10.1037/0096-3445.128.1.78
my @itf_ssr =       (54,   47,  54, 49, 40, 34, 27, 25, 20);
my @itf_llr =       (55,   50,  60, 60, 55, 50, 50, 60, 55);
my @itf_delaydiff = (117, 160, 111, 89, 62, 30, 21, 14,  7);
my $itf_trials = @itf_ssr;

my $itb_trials = 22;
  # Includes 2 catch trials.
my $itb_pc = .75;
my @itb_llrs = 15 .. 95;
  # N.B. The minimum must be at least 2, so SSR can always
  # safely be set to LLR - 1. The maximum cannot exceed 98,
  # so SSR can safely be set to 99 for SS catch trails.

my $itm_trials = 10;
my @itm_ssrs = 1 .. 95;

# ------------------------------------------------
# Declarations
# ------------------------------------------------

my $o; # Will be our Tversky object.

our $total_trials = 0;

sub p ($)
   {"<p>$_[0]</p>"}

sub maybe_offer_rest
   {$total_trials and $total_trials % $break_interval == 0 and
        $o->okay_page("break_s2.$total_trials",
            '<p>Feel free to take a break before continuing.</p>');}

sub decision
   {my ($key, $ssr, $ssd, $llr, $lld) = @_;
    if (defined $key)
       {maybe_offer_rest;
        $o->okay_page('it_forcedchoice_instructions_s2', cat map {"<p class='long'>$_</p>"}
            'In this task, you will answer a series of questions.',
            'Each trial will present you with a hypothetical choice between two amounts of money delivered to you at a given time in the future. Press the button for the option you would prefer.',
            'Even though these are completely hypothetical decisions, try your best to imagine what you would choose if you were really offered these choices.');}
    $_ = sprintf '%02d', $_ foreach $ssr, $llr;
    $o->multiple_choice_page($key,
        p 'Which would you prefer?',
        ['ss', 'A'] => "\$$ssr $ssd",
        ['ll', 'B'] => "\$$llr $lld");}

sub matching_trial
   {my ($key, $ssr, $ssd, $lld) = @_;
    if (defined $key)
       {maybe_offer_rest;
        $o->okay_page('itm_instructions_s2', cat
            '<p class="long">In this task, you will answer a series of questions.',
            '<p class="long">Each trial will present you with a hypothetical choice between two amounts of money delivered to you at a given time in the future. However, one of the amounts will be left blank. For example, a trial might be:',
                '<ul class="itm">',
                '<li>$20 today',
                '<li>$__ in 1 month',
                '</ul>',
            '<p class="long">Your task is fill in the blank with an amount that makes the two options equally appealing to you; that is, an amount that makes you indifferent between the two options.',
        '<p class="long">Even though these are completely hypothetical decisions, try your best to imagine what you would do if you were really offered these choices.');}
    $o->dollars_entry_page($key,
        q(<p>Fill in the blank so you're indifferent between:</p>) .
        '<ul class="itm">' .
        sprintf('<li>$%02d %s', $ssr, $ssd) .
        "<li>\$__ $lld" .
        '</ul>');}

sub round
   {my $x = shift;
    int($x + ($x < 0 ? -0.5 : 0.5));}

# ------------------------------------------------
# Tasks
# ------------------------------------------------

sub intertemporal_fixed
   {my ($k, $front_end_delay) = @_;

    $o->save_once_atomic("itf_${k}_setup", sub
       {my @is = shuffle 0 .. $itf_trials - 1;
        foreach (1 .. $itf_trials)
           {$o->save("itf_${k}_ssr.$_", $itf_ssr[$is[$_ - 1]]);
            $o->save("itf_${k}_llr.$_", $itf_llr[$is[$_ - 1]]);
            $o->save("itf_${k}_delaydiff.$_", $itf_delaydiff[$is[$_ - 1]]);}
        1});

    $o->loop("itf_${k}_iter", sub
       {my $trial = $_ + 1;
        local $total_trials = $total_trials + $trial - 1;

        decision "itf_${k}_choice.$trial",
            $o->getu("itf_${k}_ssr.$trial"),
            $front_end_delay ? "in $front_end_delay days" : 'today',
            $o->getu("itf_${k}_llr.$trial"),
            sprintf('in %d days',
                $o->getu("itf_${k}_delaydiff.$trial") + $front_end_delay);

        $trial == $itf_trials and $o->done;});

    $total_trials += $itf_trials;}

sub intertemporal_bisection
   {my ($k, $ssd, $lld) = @_;

    my $ss_catch_trial = $o->save_once("itb_${k}_catch_ss", sub
       {randelm 1 .. $itb_trials});
    my $ll_catch_trial = $o->save_once("itb_${k}_catch_ll", sub
       {randelm grep {$_ != $ss_catch_trial} 1 .. $itb_trials});

    $o->loop("itb_${k}_iter", sub
       {my $trial = $_ + 1;
        local $total_trials = $total_trials + $trial - 1;

        my $discount = $o->save_once_atomic("itb_${k}_discount.$trial", sub
           {my $json = $o->maybe_getu("itb_${k}_density");
            my $density = $json
              ? Rickrack_PBA_Density->deserialize($json)
              : Rickrack_PBA_Density
                    ->new(lo => 0, hi => 1, pc => $itb_pc)
                    ->clone(x => [0, .75], density => [2/3, 2]);
            $trial > 1 and $density = $density->update(
                $o->getu("itb_${k}_ssr." . ($trial - 1)) /
                    $o->getu("itb_${k}_llr." . ($trial - 1)),
                  # We use this ratio instead of itb_${k}_density
                  # itself to account for the effect of rounding
                  # the SSR and LLR.
                $o->getu("itb_${k}_choice." . ($trial - 1)) eq 'll');
            $o->save("itb_${k}_density", $density->serialize);
            $density->median});

        $trial > $itb_trials and $o->done;

        if ($trial == $ss_catch_trial or $trial == $ll_catch_trial)
           {# Push ahead the real discount.
            $o->save_once("itb_${k}_discount." . ($trial + 1), sub
               {$discount});
            # Set $discount according to the type of catch trial.
            $discount = $trial == $ll_catch_trial ? 0.07 : 1.13;}

        my $llr = $o->save_once("itb_${k}_llr.$trial", sub
           {randelm @itb_llrs});
        my $ssr = $o->save_once("itb_${k}_ssr.$trial", sub
           {my $x = round($llr * $discount);
                $x < 1
              ? 1
              : $x > 99 # Cap at two digits.
              ? 99
              : $x >= $llr && $trial != $ss_catch_trial
              ? $llr - 1
              : $x});

        decision "itb_${k}_choice.$trial",
            $ssr, $ssd,
            $llr, $lld;});

    $total_trials += $itb_trials;}

sub intertemporal_matching
   {my ($k, $ssd, $lld) = @_;

    $o->loop("itm_${k}_iter", sub
       {my $trial = $_ + 1;
        local $total_trials = $total_trials + $trial - 1;

        my $ssr = $o->save_once("itm_${k}_ssr.$trial", sub
           {randelm @itm_ssrs});
        matching_trial "itm_${k}_response.$trial",
            $ssr, $ssd, $lld;

        $trial == $itm_trials and $o->done;});

    $total_trials += $itm_trials;}

my %tasks =
   (itf_near => sub {intertemporal_fixed "near$_", 0},
    itf_far => sub {intertemporal_fixed "far$_", 30},
    itb_near => sub {intertemporal_bisection "near$_", 'today', 'in 1 month'},
    itb_far => sub {intertemporal_bisection "far$_", 'in 1 month', 'in 2 months'},
    itm_near => sub {intertemporal_matching "near$_", 'today', 'in 1 month'},
    itm_far => sub {intertemporal_matching "far$_", 'in 1 month', 'in 2 months'});

# ------------------------------------------------
# Mainline code
# ------------------------------------------------

$o = new Tversky
   (cookie_name_suffix => 'Rickrack',
    here_url => $p{here_url},
    database_path => $p{database_path},
    consent_path => $p{consent_path},
    task => $p{task},

    preview => sub
       {decision undef, 20, 'today', 60, 'in 1 month';},

    after_consent_prep => sub
       {my $o = shift;
        $o->assign_permutation('task_order_3', ',', keys %tasks);},

    head => do {local $/; <DATA>},
    footer => "\n\n\n</body></html>\n",

    mturk => $p{mturk},
    assume_consent => $p{assume_consent},
    password_hash => $p{password_hash},
    password_salt => $p{password_salt});

$o->run(sub

   {foreach (3)
       {foreach my $task (split qr/,/, $o->getu("task_order_$_"))
           {$tasks{$task}->();}}});

__DATA__

<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>Decision-Making</title>

<style type="text/css">

    h1, form, div.expbody p
       {text-align: center;}

    div.expbody p.long
       {text-align: left;}

    input.consent_statement
       {border: thin solid black;
        background-color: white;
        color: black;
        margin-bottom: .5em;}

    div.multiple_choice_box
       {display: table;
        margin-left: auto; margin-right: auto;}
    div.multiple_choice_box > div.row
       {display: table-row;}
    div.multiple_choice_box > div.row > div
       {display: table-cell;}
    div.multiple_choice_box > div.row > div.button
       {padding-right: 1em;
        vertical-align: middle;}
    div.multiple_choice_box > div.row > .body
       {text-align: left;
        vertical-align: middle;}

    input.text_entry, textarea.text_entry
       {border: thin solid black;
        background-color: white;
        color: black;}

    textarea.text_entry
       {width: 90%;}

    ul.itm
       {width: 10em;
        margin-left: auto;
        margin-right: auto;}

</style>
