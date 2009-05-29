package Slim::Utils::Light;

# $Id:  $

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This module provides some functions compatible with functions
# from the core SqueezeCenter code, without their overhead.
# These functions are called by helper applications like SqueezeTray
# or the control panel. 

use Exporter::Lite;
@ISA = qw(Exporter);

use Config;
use FindBin qw($Bin);
use File::Spec::Functions qw(catdir);

our @EXPORT = qw(string getPref);
my ($os, $language, %strings);

BEGIN {
	my @SlimINC = ();

	# NB: The user may be on a platform who's perl reports a
	# different x86 version than we've supplied - but it may work
	# anyways.
	my $arch = $Config::Config{'archname'};
	   $arch =~ s/^i[3456]86-/i386-/;
	   $arch =~ s/gnu-//;

	my $perlmajorversion = $Config{'version'};
	   $perlmajorversion =~ s/\.\d+$//;

	my $libPath = $Bin;

	use Slim::Utils::OSDetect;
	Slim::Utils::OSDetect::init();

	if (my $libs = Slim::Utils::OSDetect::dirsFor('libpath')) {
		# On Debian, RH and SUSE, our CPAN directory is located in the same dir as strings.txt
		$libPath = $libs;
	};

	@SlimINC = (
		catdir($libPath,'CPAN','arch',$perlmajorversion, $arch),
		catdir($libPath,'CPAN','arch',$perlmajorversion, $arch, 'auto'),
		catdir($libPath,'CPAN','arch',$Config{'version'}, $Config::Config{'archname'}),
		catdir($libPath,'CPAN','arch',$Config{'version'}, $Config::Config{'archname'}, 'auto'),
		catdir($libPath,'CPAN','arch',$perlmajorversion, $Config::Config{'archname'}),
		catdir($libPath,'CPAN','arch',$perlmajorversion, $Config::Config{'archname'}, 'auto'),
		catdir($libPath,'CPAN','arch',$Config::Config{'archname'}),
		catdir($libPath,'lib'), 
		catdir($libPath,'CPAN'), 
		$libPath,
	);

	# This works like 'use lib'
	# prepend our directories to @INC so we look there first.
	unshift @INC, @SlimINC;

	$os = Slim::Utils::OSDetect->getOS();
}

my $serverPrefFile = catdir($os->dirsFor('prefs'), 'server.prefs');

# return localised version of string token
sub string {
	my $name = shift;
	
	$language ||= getPref('language') || $os->getSystemLanguage();
		
	my $lang = shift || $language;
	
	my $string = $strings{ $name }->{ $lang } || $strings{ $name }->{ $language } || $strings{ $name }->{'EN'} || $name;
	
	if ( @_ ) {
		$string = sprintf( $string, @_ );
	}	
	
	return $string;
}

sub loadStrings {
	my $string     = '';
	my $language   = '';
	my $stringname = '';

	# server string file
	my $file;

	# let's see whether this is a PerlApp/Tray compiled executable
	if (defined $PerlApp::VERSION) {
		$file = PerlApp::extract_bound_file('strings.txt');
	}
	elsif (defined $PerlTray::VERSION) {
		$file = PerlTray::extract_bound_file('strings.txt');
	}
	
	# try to find the strings.txt file from our installation
	unless ($file && -f $file) {
		my $path = $os->dirsFor('strings');
		$file = catdir($path, 'strings.txt');
	}
	
	open(STRINGS, "<:utf8", $file) || do {
		warn "Couldn't open file [$file]!";
		return;
	};

	foreach my $line (<STRINGS>) {

		chomp($line);
		
		next if $line =~ /^#/;
		next if $line !~ /\S/;

		if ($line =~ /^(\S+)$/) {

			$stringname = $1;
			$string = '';
			next;

		} elsif ($line =~ /^\t(\S*)\t(.+)$/) {

			$language = uc($1);
			$string   = $2;

			$strings{$stringname}->{$language} = $string;
		}
	}

	close STRINGS;
}

# Read pref from the server preference file - lighter weight than loading YAML
# don't call this too often, it's in no way optimized for speed
sub getPref {
	my $pref = shift;
	my $prefFile = shift;

	if ($prefFile) {
		$prefFile = catdir($os->dirsFor('prefs'), 'plugin', $prefFile);
	}
	else {
		$prefFile = $serverPrefFile;
	}

	my $ret;

	if (-r $prefFile) {

		if (open(PREF, $prefFile)) {

			while (<PREF>) {
			
				# read YAML (server) and old style prefs (installer)
				if (/^$pref(:| \=)? (.+)$/) {
					$ret = $2;
					$ret =~ s/^''$//;
					chomp($ret);
					last;
				}
			}

			close(PREF);
		}
	}

	return $ret;
}

loadStrings();


1;