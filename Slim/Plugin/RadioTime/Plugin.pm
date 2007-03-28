package Slim::Plugin::RadioTime::Plugin;

# $Id: Plugin.pm 11021 2006-12-21 22:28:39Z dsully $

# SlimServer Copyright (c) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Plugin::Base);

use URI::Escape qw(uri_escape);

use Slim::Plugin::RadioTime::Settings;

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Utils::Strings qw( string );
use Slim::Web::XMLBrowser;

my $FEED = 'http://opml.radiotime.com/Index.aspx';
my $cli_next;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.radiotime',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

	Slim::Plugin::RadioTime::Settings->new;

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['radiotime', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['radiotime', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next = Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);
}

sub getDisplayName {
	return 'PLUGIN_RADIOTIME_MODULE_NAME';
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header   => 'PLUGIN_RADIOTIME_LOADING',
		modeName => 'RadioTime Plugin',
		url      => radioTimeURL($client),
		title    => $client->string(getDisplayName()),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam('handledTransition', 1);
}

sub radioTimeURL {
	my $client = shift;
	
	my $username;
	
	if ( $ENV{SLIM_SERVICE} ) { # SqueezeNetwork
		$username = $client->prefGet('plugin_radiotime_username', undef, 1);
	}
	else {
		$username = Slim::Utils::Prefs::get('plugin_radiotime_username');
	}
	
	my $url = $FEED;
	
	if ( $username ) {
		$url .= '?username=' . uri_escape($username);
	}
	
	# RadioTime's listing defaults to giving us mp3 and wma streams.
	# If AlienBBC is installed we can ask for Real streams too.
	if ( exists $INC{'Plugins/Alien/Plugin.pm'} ) {
		$url .= ( $url =~ /\?/ ) ? '&' : '?';
		$url .= 'Filters=mp3,wma,real';
	}
	
	return $url;
}

# Web pages

sub webPages {
	my $class = shift;

	my $title = 'PLUGIN_RADIOTIME_MODULE_NAME';
	my $url   = 'plugins/RadioTime/index.html';
	
	Slim::Web::Pages->addPageLinks('radio', { $title => $url });
	
	Slim::Web::HTTP::addPageFunction($url, sub {

		my $client = $_[0];
		my $url = radioTimeURL($client);

		Slim::Web::XMLBrowser->handleWebIndex( {
			feed   => $url,
			title  => $title,
			args   => \@_
		} );
	});
}

sub cliQuery {
	my $request = shift;
	
	Slim::Buttons::XMLBrowser::cliQuery('radiotime', radioTimeURL(), $request);
}

sub cliRadiosQuery {
	my $request = shift;
	
	# what we want the query to report about ourself
	my $data = {
		'cmd'  => 'radiotime',
		'name' => Slim::Utils::Strings::string(getDisplayName()),
		'type' => 'xmlbrowser',
	};

	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

1;
