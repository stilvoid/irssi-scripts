# hipchat_complete.pl - (c) 2013 John Morrissey <jwm@horde.net>
#                       (c) 2014 Steve Engledow <steve@offend.me.uk>
#                       (c) 2014 Jeremie Laval <jeremie.laval@gmail.com>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# About
# =====
#
# Adds Hipchat tab completion support.
# 
# By default, Hipchat's XMPP interface sets user nicks to their full names,
# not their "mention names," so you always have to recall and manually type
# a user's mention name so Hipchat highlights the message, sends them e-mail
# if they're away, etc.
#
# This plugin tab-completes mention names and tab-translates name-based
# nicks to their corresponding "mention names."
#
# Names can be matched from any position in the name, not jus the beginning.
#
# If you have typed an @, if will be removed before matching
#
# For example, if JohnMorrissey has a mention name of @jwm, all of these
# tab complete to @jwm:
#
#   John<tab>
#   @John<tab>
#   Morr<tab>
#   jw<tab>
#   wm<tab>
#
# To use
# ======
#
# 1. Install the HTTP::Message, JSON, and LWP Perl modules.
#
# 2. /script load hipchat_completion.pl
#
# 3. Get a Hipchat auth token (hipchat.com -> Account settings -> API
#    access). In irssi:
#
#    /set hipchat_auth_token some-hex-value
#
# 4. If your Hipchat server isn't in the "bitlbee" chatnet (the 'chatnet'
#    parameter in your irssi server list for the IRC server you use to
#    connect to Hipchat), specify the name of the chatnet:
#
#    /set hipchat_chatnet some-chatnet-name

use strict;

use HTTP::Request;
use Irssi;
use JSON;
use LWP::UserAgent;

my $VERSION = '1.0';
my %IRSSI = (
    author => 'John Morrissey',
    contact => 'jwm@horde.net',
    name => 'hipchat_complete',
    description => 'Translate nicks to HipChat "mention names"',
    licence => 'BSD',
);

my %NICK_TO_MENTION;
my $LAST_MAP_UPDATED = 0;

sub get_hipchat_people {
    my $ua = LWP::UserAgent->new;
    $ua->timeout(5);

    my $auth_token = Irssi::settings_get_str('hipchat_auth_token');
    if (!$auth_token) {
        return;
    }
    my $api_url = Irssi::settings_get_str('hipchat_api_url');
    my $offset = 0;
    my $json;

    do {
        my $r = HTTP::Request->new('GET', $api_url . "/user?auth_token=$auth_token&max-results=100&start-index=$offset");
        my $response = $ua->request($r);

        $json = from_json($response->decoded_content);
        my $hipchat_users = $json->{items};
        foreach my $user (@{$hipchat_users}) {
            my $name = $user->{name};
            $NICK_TO_MENTION{$name} = $user->{mention_name};
        }
        $offset += 100;
    } while (exists($json->{links}) && exists($json->{links}->{'next'}));
    $LAST_MAP_UPDATED = time();
}

sub sig_complete_hipchat_nick {
    my ($complist, $window, $word, $linestart, $want_space) = @_;

    my $wi = Irssi::active_win()->{active};
    return unless ref $wi and $wi->{type} eq 'CHANNEL';
    return unless $wi->{server}->{chatnet} eq
        Irssi::settings_get_str('hipchat_chatnet');

    # Reload the nick -> mention name map periodically,
    # so we pick up new users.
    if (($LAST_MAP_UPDATED + 4 * 60 * 60) < time()) {
        get_hipchat_people();
    }

    if ($word =~ /^@/) {
        $word =~ s/^@//;
    }

    my %matches;

    # People in the chan
    # Match first part
    foreach my $nick ($wi->nicks()) {
        if ($nick->{nick} =~ /^\Q$word\E/i) {
            my $mention = $NICK_TO_MENTION{$nick->{nick}};

            if(not $matches{$mention}) {
                $matches{"$mention"} = 1;
                push(@$complist, "\@$mention");
            }
        }
    }

    # Match anywhere
    foreach my $nick ($wi->nicks()) {
        if ($nick->{nick} =~ /\Q$word\E/i) {
            my $mention = $NICK_TO_MENTION{$nick->{nick}};

            if(not $matches{$mention}) {
                $matches{"$mention"} = 1;
                push(@$complist, "\@$mention");
            }
        }
    }

    # Auto-complete other mentions
    # Match first part
    while (my ($nick, $mention) = each %NICK_TO_MENTION) {
        if ($nick =~ /^\Q$word\E/i || $mention =~ /^\Q$word\E/i) {
            if(not $matches{$mention}) {
                $matches{"$mention"} = 1;
                push(@$complist, "\@$mention");
            }
        }
    }

    # Match anywhere
    while (my ($nick, $mention) = each %NICK_TO_MENTION) {
        if ($nick =~ /\Q$word\E/i || $mention =~ /\Q$word\E/i) {
            if(not $matches{$mention}) {
                $matches{"$mention"} = 1;
                push(@$complist, "\@$mention");
            }
        }
    }
}

Irssi::settings_add_str('hipchat_complete', 'hipchat_auth_token', '');
Irssi::settings_add_str('hipchat_complete', 'hipchat_chatnet', 'bitlbee');
Irssi::settings_add_str('hipchat_complete', 'hipchat_api_url', 'https://api.hipchat.com/v2/');
get_hipchat_people();
Irssi::signal_add('complete word', \&sig_complete_hipchat_nick);
