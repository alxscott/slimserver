package Slim::Utils::Update;

use strict;
use Time::HiRes;
use File::Spec::Functions qw(splitpath catdir);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
use Slim::Utils::Unicode;

my $prefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'server.update',
	'defaultLevel' => 'DEBUG',
});

my $os = Slim::Utils::OSDetect->getOS();

my $versionFile = catdir( scalar($os->dirsFor('updates')), 'squeezecenter.version' );

sub checkVersion {

	# clean up old download location
	Slim::Utils::Misc::deleteFiles($prefs->get('cachedir'), qr/^SqueezeCenter.*\.(dmg|exe)(\.tmp)?$/i);			

	# reset update download status in case our system is up to date
	my $installer = getUpdateInstaller() || '';
	
	if ( isUpToDate($installer) || !$prefs->get('checkVersion') ) {
		
		$log->info("We're up to date (v$::VERSION, r$::REVISION). Reset update notifiers.") if $prefs->get('checkVersion');
		
		$::newVersion = undef;
		setUpdateInstaller();
		
		return unless $prefs->get('checkVersion');
	}

	my $lastTime = $prefs->get('checkVersionLastTime');
	
	$os->initUpdate() if $os->canAutoUpdate() && $prefs->get('autoDownloadUpdate');

	if ($lastTime) {

		my $delta = Time::HiRes::time() - $lastTime;

		if (($delta > 0) && ($delta < $prefs->get('checkVersionInterval'))) {

			if ( $log->is_info ) {
				$log->info(sprintf("Checking version in %s seconds",
					($lastTime + $prefs->get('checkVersionInterval') + 2 - Time::HiRes::time())
				));
			}

			Slim::Utils::Timers::setTimer(0, $lastTime + $prefs->get('checkVersionInterval') + 2, \&checkVersion);

			return;
		}
	}

	$log->info("Checking version now.");

	my $url  = "http://"
		. Slim::Networking::SqueezeNetwork->get_server("update")
		. sprintf(
			"/update/?version=%s&revision=%s&lang=%s&geturl=%s&os=%s", 
			$::VERSION, 
			$::REVISION, 
			Slim::Utils::Strings::getLanguage(),
			$os->canAutoUpdate() && $prefs->get('autoDownloadUpdate') ? '1' : '',
			$os->installerOS(),
		);
		
	$log->debug("Using URL: $url");
	
	my $http = Slim::Networking::SqueezeNetwork->new(\&checkVersionCB, \&checkVersionError);

	# will call checkVersionCB when complete
	$http->get($url);

	$prefs->set('checkVersionLastTime', Time::HiRes::time());
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $prefs->get('checkVersionInterval'), \&checkVersion);
}

# called when check version request is complete
sub checkVersionCB {
	my $http = shift;

	# store result in global variable, to be displayed by browser
	if ($http->{code} =~ /^2\d\d/) {

		my $version = Slim::Utils::Unicode::utf8decode( $http->content() );
		chomp($version);
		
		$log->debug($version || 'No new SqueezeCenter version available');

		# reset the update flag
		setUpdateInstaller();

		# trigger download of the installer if available
		if ($version && $prefs->get('autoDownloadUpdate')) {
			
			$log->info('Triggering automatic SqueezeCenter update download...');
			getUpdate($version);
		}
		
		elsif ($version) {
			$::newVersion = $version;
		}
	}
	else {
		$::newVersion = 0;
		$log->warn(sprintf(Slim::Utils::Strings::string('CHECKVERSION_PROBLEM'), $http->{code}));
	}
}

# called only if check version request fails
sub checkVersionError {
	my $http = shift;

	$log->error(Slim::Utils::Strings::string('CHECKVERSION_ERROR') . "\n" . $http->error);
}


# download the installer
sub getUpdate {
	my $url = shift;
	
	my $params = $os->getUpdateParams();
	
	return unless $params;
	
	$params->{path} ||= scalar ( $os->dirsFor('updates') );
	
	cleanup($params->{path}, 'tmp');

	if ( $url && Slim::Music::Info::isURL($url) ) {
		
		$log->info("URL to download update from: $url");

		my ($a, $b, $file) = Slim::Utils::Misc::crackURL($url);
		($a, $b, $file) = splitpath($file);

		# don't re-download if we're up to date
		if (isUpToDate($file)) {
			$log->info("We're up to date (v$::VERSION, r$::REVISION). Reset update notifiers.");
			
			setUpdateInstaller();
			return;
		}

		$file = catdir($params->{path}, $file);

		# don't re-download if file exists already
		if ( -e $file ) {
			$log->info("We already have the latest installer file: $file");
			
			setUpdateInstaller($file);
			return;
		}
		
		my $tmpFile = "$file.tmp";

		setUpdateInstaller();

		# Save to a tmp file so we can check SHA
		my $download = Slim::Networking::SimpleAsyncHTTP->new(
			\&downloadAsyncDone,
			\&checkVersionError,
			{
				saveAs => $tmpFile,
				file   => $file,
				params => $params,
			},
		);
		
		$download->get( $url );
	}
	else {
		$log->error("Didn't receive valid update URL: " . substr($url, 0, 50) . (length($url) > 50 ? '...' : ''));
	}
}

sub downloadAsyncDone {
	my $http = shift;
	
	my $file    = $http->params('file');
	my $tmpFile = $http->params('saveAs');
	my $params  = $http->params('params');
	
	my $path    = $params->{'path'};
	
	# make sure we got the file
	return if !-e $tmpFile;

	if (-s _ != $http->headers->content_length()) {
		$log->warn( sprintf("SqueezeCenter installer file size mismatch: expected size %s bytes, actual size %s bytes", $http->headers->content_length(), -s _) );
		unlink $tmpFile;
		return;
	}

	cleanup($path);

	$log->info("Successfully downloaded update installer file. Saving as $file");
	rename $tmpFile, $file;
	setUpdateInstaller($file) if -e $file;
	
	if ($params && ref($params->{cb}) eq 'CODE') {
		$params->{cb}->($file);
	}

	cleanup($path, 'tmp');
}

sub setUpdateInstaller {
	my $file = shift;
	
	if ($file && open(UPDATEFLAG, ">$versionFile")) {
		
		$log->debug("Setting update version file to: $file");
		
		print UPDATEFLAG $file;
		close UPDATEFLAG;
	}
	
	elsif ($file) {
		
		$log->warn("Unable to update version file: $versionFile");
	}
	
	else {
	
		unlink $versionFile;
	}
}


sub getUpdateInstaller {
	
	$log->debug("Reading update installer path from $versionFile");
	
	open(UPDATEFLAG, $versionFile) || return '';
	
	my $updateInstaller = '';
	
	while ( <UPDATEFLAG> ) {

		chomp;
		
		if (/SqueezeCenter.*/) {
			$updateInstaller = $_;
			last;
		}
	}
		
	close UPDATEFLAG;
	
	$log->debug("Found update installer path: '$updateInstaller'");
	
	return $updateInstaller;
}

sub isUpToDate {
	my $installer = shift;

	return ( $::REVISION eq 'TRUNK'											# we'll consider TRUNK to always be up to date
		|| ($installer !~ /\d{5,}/ && $installer =~ /$::VERSION/)			# no revision number, but same version
		|| ($installer =~ /$::REVISION/ && $installer =~ /$::VERSION/) )	# same revision
	
}

sub cleanup {
	my ($path, $additionalExt) = @_;

	my $ext = $os->installerExtension() . ($additionalExt ? "\.$additionalExt" : '');

	Slim::Utils::Misc::deleteFiles($path, qr/^SqueezeCenter.*\.$ext$/i);
}

1;