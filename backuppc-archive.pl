#!/usr/bin/perl

# chkconfig: 3 95 05

# This script handles offsite archives of BackupPC hosts. It iterates through 
# all the hosts configured in BackupPC, and starts an offsite archive job for 
# each one, if three conditions are met:
#     A.  The host is not excluded from archives,
#     B.  The host is not already archived, and
#     C.  Another archive process is not already running.
#
# Dependencies:
#     A.  BackupPC (duh...)
#     B.  App::Daemon (available in EPEL)
#     C.  File::Find::Rule (available in Base)

use strict;
use vars qw($Hosts);
use App::Daemon qw( daemonize );
use Log::Log4perl;
use lib "/usr/local/BackupPC/lib";
use BackupPC::Lib;
use File::Find::Rule;

$App::Daemon::logfile    = "/var/log/BackupPC-Archive/bpc-archive.log";
$App::Daemon::pidfile    = "/var/run/BackupPC-Archive/bpc-archive.pid";
$App::Daemon::as_user    = "backuppc";
$App::Daemon::as_group   = "backuppc";
daemonize();

my $LOG = Log::Log4perl->get_logger();
# /mnt/offsite is a symbolic link to the actual directory, simply to keep this 
# script identical on different backuppc servers:
my $offsite = '/mnt/offsite';
my $debug = 0;
my $bpc;
my %Conf;
my $Hosts;
my %Jobs;
# These hosts will not be archived:
my @ignore_hosts = (
    'no-archive-1.zindilis.com',
    'no-archive-2.zindilis.com',
);

# Loop forever and ever and ever...
while () 
{
    # Wipe out all existing data:
    undef $bpc;
    undef %Conf;
    undef $Hosts;

    die("BackupPC::Lib->new failed\n") if ( !(my $bpc = BackupPC::Lib->new) );
    my %Conf = $bpc->Conf();
    my $Hosts = $bpc->HostInfoRead();

    # Begin iterating through all hosts:
    for my $host (sort keys %$Hosts)
    {
        # Ignore some hosts:
        if ($host ~~ @ignore_hosts)
        {
            if ($debug) { $LOG->info("Ignoring host $host."); }
            next;
        }

        # If another archive job is running, don't do anything else:
        sleep_if_already_archiving($bpc);

        # Get the backups information of this host, and only keep the latest:
        my @info = $bpc->BackupInfoRead($host);
        my $info = @info[-1];

        if (@info)
        {
            # If this host is already archived, skip it:
            if ($debug) { $LOG->info("Checking existence of $offsite/$host.$info->{'num'}.tar.gz"); }
            if (-e "$offsite/$host.$info->{'num'}.tar.gz") 
            {
                if ($debug) { $LOG->info("Archive $offsite/$host.$info->{'num'}.tar.gz already exists."); }
                next;
            }

            # This appends an "archive" job in the BPC queue. The job 
            # typically starts a few seconds after this command:
            $LOG->info("Beginning archive $offsite/$host.$info->{'num'}.tar.gz");
            system("/usr/local/BackupPC/bin/BackupPC_archiveStart archive backuppc $host");

            # This is to ensure that BPC has started the archive process 
            # before we proceed with anything else:
            sleep(600);

            # Wait for the archive job to finish, then delete old archives of this host:
            sleep_if_already_archiving($bpc);
            $LOG->info("Finished archive $offsite/$host.$info->{'num'}.tar.gz");
            delete_old_files($host);
        }
    }
}

sub sleep_if_already_archiving 
{
    # Check if an archive job is already running and wait for it to complete:
    $bpc = @_[0];
    undef %Jobs;
    my $err = $bpc->ServerConnect($Conf{ServerHost}, $Conf{ServerPort});
    my $reply = $bpc->ServerMesg("status jobs");
    eval $reply;

    if ( "archive" ~~ %Jobs )
    {
        if ($debug) { $LOG->info("An archive job is already running, going back to sleep."); }
        # Wait for 5 minutes, then check again:
        sleep(300);
        sleep_if_already_archiving($bpc);
    }
}

sub delete_old_files
{
    # Find files with the same filename pattern and only keep the newest one:
    my $host = @_[0];
    if ($debug) { $LOG->info("Checking for old archives of $host in $offsite..."); }
    my @files = File::Find::Rule->extras({ follow => 1 }) 
                                ->file()
                                ->name( "$host.*.tar.gz" )
                                ->in( $offsite );

    if (scalar @files > 1)
    {
        $a = @files[-1];
        $b = @files[-2];
        if ((stat($a))[9] < (stat($b))[9])
        {
            $LOG->info("Deleting old archived file $a.");
            unlink $a;
        }
        else
        {
            $LOG->info("Deleting old archived file $b.");
            unlink $b;
        }
        delete_old_files($host);
    }
}

