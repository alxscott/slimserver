#!/usr/bin/perl
#
# Stand-alone interface to GDResizer
#
# TODO:
# Better error handling
#

use strict;
use FindBin qw($Bin);
use lib $Bin;

use constant RESIZER      => 1;
use constant SLIM_SERVICE => 0;
use constant PERFMON      => 0;
use constant SCANNER      => 0;
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant DEBUG        => ( grep { /--debug/ } @ARGV ) ? 1 : 0;
use constant SOCKET_PATH  => '/tmp/sbs_artwork';

# Copied from Slim::bootstrap to reduce memory overhead of unnecessary stuff
BEGIN {
	use Config;
	use File::Spec::Functions qw(catdir);
	use Slim::Utils::OSDetect;	# XXX would be nice to do without this
	
	my $libPath = $Bin;
	my @SlimINC = ();
	
	Slim::Utils::OSDetect::init();
	
	if (my $libs = Slim::Utils::OSDetect::dirsFor('libpath')) {
		# On Debian, RH and SUSE, our CPAN directory is located in the same dir as strings.txt
		$libPath = $libs;
	}

	# NB: The user may be on a platform who's perl reports a
	# different x86 version than we've supplied - but it may work
	# anyways.
	my $arch = $Config::Config{'archname'};
	   $arch =~ s/^i[3456]86-/i386-/;
	   $arch =~ s/gnu-//;
	
	# Some ARM platforms use different arch strings, just assume any arm*linux system
	# can run our binaries, this will fail for some people running invalid versions of Perl
	# but that's OK, they'd be broken anyway.
	if ( $arch =~ /^arm.*linux/ ) {
		$arch = 'arm-linux-gnueabi-thread-multi';
	}
	
	# Same thing with PPC
	if ( $arch =~ /^(?:ppc|powerpc).*linux/ ) {
		$arch = 'powerpc-linux-thread-multi';
	}

	my $perlmajorversion = $Config{'version'};
	   $perlmajorversion =~ s/\.\d+$//;

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
};

use IO::Socket::UNIX;
use Slim::Utils::ArtworkCache;
use Slim::Utils::GDResizer;

DEBUG && require Time::HiRes;

our ($faster);

while ($_ = shift @ARGV) {
	if ($_ eq '--faster') {
		$faster = 1;
	}
}

# Remove socket if it didn't get cleaned up
if ( -e SOCKET_PATH ) {
	unlink SOCKET_PATH || die "Unable to remove old socket";
}

# Open UNIX domain socket
my $socket = IO::Socket::UNIX->new(
	Type   => SOCK_STREAM,
	Local  => SOCKET_PATH,
	Listen => SOMAXCONN,
) || die "Unable to open socket: $!";

$SIG{TERM} = $SIG{INT} = sub {
	unlink SOCKET_PATH if -e SOCKET_PATH;
	exit 0;
};

DEBUG && warn "$0 listening on " . SOCKET_PATH . "\n";

while (1) {
	my $client = $socket->accept();
	
	eval {
		# get command
		my $buf = <$client>;
	
		my ($file, $spec, $cacheroot, $cachekey) = unpack 'Z*Z*Z*Z*', $buf;
		DEBUG && warn "file=$file, spec=$spec, cacheroot=$cacheroot, cachekey=$cachekey\n";
		
		if ( !$file || !$spec || !$cacheroot || !$cachekey ) {
			die "Invalid parameters: $file, $spec, $cacheroot, $cachekey\n";
		}
	
		my @spec = split ',', $spec;
	
		DEBUG && (my $tv = Time::HiRes::time());
	
		# do resize
		Slim::Utils::GDResizer->gdresize(
			file     => $file,
			debug    => DEBUG,
			faster   => $faster,
			cache    => Slim::Utils::ArtworkCache->new($cacheroot),
			cachekey => $cachekey,
			spec     => \@spec,
		);
	
		# send result
		print $client "OK\015\012";
		
		DEBUG && warn "OK (" . (Time::HiRes::time() - $tv) . " seconds)\n";
	};
	
	if ( $@ ) {
		syswrite $client, "Error: $@\015\012";
		warn "$@\n";
	}
}

__END__

=head1 NAME

gdresized.pl - Artwork resizer daemon

=head1 SYNOPSIS

Resize normal image file or an audio file's embedded tags:

Options:

  --debug          Display debug information
  --faster         Use ugly but fast copyResized function

=cut
