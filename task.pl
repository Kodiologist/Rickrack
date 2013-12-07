#!/usr/bin/perl -T

my %p;
%p = @ARGV; s/,\z// foreach values %p; # DEPLOYMENT SCRIPT EDITS THIS LINE

use strict;

use Tversky 'cat', 'randelm';
use Rickrack_PBA_Density;

# ------------------------------------------------
# Parameters
# ------------------------------------------------

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

sub p ($)
   {"<p>$_[0]</p>"}

sub decision
   {my ($key, $ssr, $ssd, $llr, $lld) = @_;
    $_ = sprintf '%02d', $_ foreach $ssr, $llr;
    $o->multiple_choice_page($key,
        p 'Which would you prefer?',
        ['ss', 'A'] => "\$$ssr $ssd",
        ['ll', 'B'] => "\$$llr $lld");}

sub matching_trial
   {my ($key, $ssr, $ssd, $lld) = @_;
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

sub rest
   {my $k = shift;
    $o->okay_page($k, p
       'Feel free to take a break before continuing.');}

sub intertemporal_bisection
   {my ($k, $ssd, $lld) = @_;

    $o->okay_page('itb_instructions', cat map {"<p class='long'>$_</p>"}
        'In this task, you will answer a series of questions.',
        'Each trial will present you with a hypothetical choice between two amounts of money delivered to you at a given time in the future. Press the button for the option you would prefer.',
        'Even though these are completely hypothetical decisions, try your best to imagine what you would choose if you were really offered these choices.');

    my $ss_catch_trial = $o->save_once("itb_${k}_catch_ss", sub
       {randelm 1 .. $itb_trials});
    my $ll_catch_trial = $o->save_once("itb_${k}_catch_ll", sub
       {randelm grep {$_ != $ss_catch_trial} 1 .. $itb_trials});

    $o->loop("itb_${k}_iter", sub
       {my $trial = $_ + 1;

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
            $llr, $lld;});}

sub intertemporal_matching
   {my ($k, $ssd, $lld) = @_;

    $o->okay_page('itm_instructions', cat
        '<p class="long">In this task, you will answer a series of questions.',
        '<p class="long">Each trial will present you with a hypothetical choice between two amounts of money delivered to you at a given time in the future. However, one of the amounts will be left blank. For example, a trial might be:',
            '<ul class="itm">',
            '<li>$20 today',
            '<li>$__ in 1 month',
            '</ul>',
        '<p class="long">Your task is fill in the blank with an amount that makes the two options equally appealing to you; that is, an amount that makes you indifferent between the two options.',
        '<p class="long">Even though these are completely hypothetical decisions, try your best to imagine what you would do if you were really offered these choices.');

    $o->loop("itm_${k}_iter", sub
       {my $trial = $_ + 1;

        my $ssr = $o->save_once("itm_${k}_ssr.$trial", sub
           {randelm @itm_ssrs});
        matching_trial "itm_${k}_response.$trial",
            $ssr, $ssd, $lld;

        $trial == $itm_trials and $o->done;});}

sub criterion_questionnaire
   {$o->buttons_page('gender', p
        'Are you male or female?',
        'Male', 'Female');
    $o->nonneg_int_entry_page('age', p
        'How old are you?');
    $o->length_entry_page('height_m', p
        'How tall are you?');
    $o->weight_entry_page('weight_kg', p
        'How much do you weigh?');
    $o->yesno_page('tobacco', p
        'Do you use tobacco?');
    $o->getu('tobacco') eq 'Yes'
        and $o->nonneg_int_entry_page('cigarette_packs_per_week', p
            q[How many packs of cigarettes do you smoke per week? (Enter 0 if you don't smoke cigarettes.)]);
    $o->nonneg_int_entry_page('exercise_hours_per_week', p
        'How many hours per week are you physically active (for example, walking, working around the house, working out)?');
    $o->percent_entry_page('healthy_meals', p
        'For how many of your meals do you choose the amount or kind of food you eat with health or fitness concerns in mind?');
    $o->nonneg_int_entry_page('floss_per_week', p
        'How many times per week do you use dental floss?');
    $o->yesno_page('credit_card', p
        'Have you used a credit card at all in the past two years?');
    if ($o->getu('credit_card') eq 'Yes')
       {$o->nonneg_int_entry_page('credit_card_late_fees', p
            'Over the past two years, how many times were you charged a late fee for making a credit card payment after the deadline?');
        $o->percent_entry_page('credit_card_subpayment', p
            'Over the past two years, how many of your credit-card payments were for less than your total balance?');}
    $o->percent_entry_page('income_saved', p
        'Over the past two years, how much of your income have you saved? (Please include savings into retirement plans and any other form of savings that you do.)');
    $o->nonneg_int_entry_page('gamble_days_per_month', p
        'On how many days per month do you gamble? (Gambling includes such activities as playing at casinos, playing cards for stakes. buying lottery tickets, and betting on sports.)');}

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
       {matching_trial undef, 20, 'today', 'in 1 month';},

    head => do {local $/; <DATA>},
    footer => "\n\n\n</body></html>\n",

    mturk => $p{mturk},
    assume_consent => $p{assume_consent},
    password_hash => $p{password_hash},
    password_salt => $p{password_salt});

$o->run(sub
   {intertemporal_matching 'near1', 'today', 'in 1 month';
    intertemporal_matching 'far1', 'in 1 month', 'in 2 months';
    rest 'break_between_itm';
    intertemporal_matching 'near2', 'today', 'in 1 month';
    intertemporal_matching 'far2', 'in 1 month', 'in 2 months';

    criterion_questionnaire;});

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
    div.multiple_choice_box > div.row > div.body
       {text-align: left;
        vertical-align: middle;}

    textarea.text_entry
       {width: 90%;}

    ul.itm
       {width: 10em;
        margin-left: auto;
        margin-right: auto;}

</style>
