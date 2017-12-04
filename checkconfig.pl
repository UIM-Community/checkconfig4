use strict;
use warnings;
use lib "X:/Nimsoft/perllib";
use Data::Dumper;
use DBI;

use threads;
use Thread::Queue;
use threads::shared;

use Nimbus::API;
use Nimbus::PDS;

use perluim::logger;
use perluim::main;
use perluim::utils;
use database_manager;

# Read cfg file!
my $CFG                 = Nimbus::CFG->new("checkconfig.cfg");
my $STR_Login           = $CFG->{"setup"}->{"nim_login"} || "administrator";
my $STR_Password        = $CFG->{"setup"}->{"nim_password"};
my $INT_NBThreads       = $CFG->{"setup"}->{"nb_threads"};
my $BOOL_Getrobots      = $CFG->{"setup"}->{"require_robots"} || 1;
my $BOOL_Getprobes      = $CFG->{"setup"}->{"require_probes"} || 1;
my $BOOL_Getprobes_attr = $CFG->{"setup"}->{"require_probes_attr"} || 1;
my $STR_OutputDir       = $CFG->{"setup"}->{"output_dir"} || "output";
my $INT_OutputMaxTime   = $CFG->{"setup"}->{"output_maxtime"} || 345600;
my $INT_Loglevel        = $CFG->{"setup"}->{"loglevel"} || 5;
my $STR_Logfile         = $CFG->{"setup"}->{"logfile"} || "checkconfig";
my $STR_ExcludeProbes   = $CFG->{"setup"}->{"exclude_probes"};
my %ExcludesProbes      = ();
if(defined($STR_ExcludeProbes)) {
    %ExcludesProbes = map { $_ => 1 } split(',', $STR_ExcludeProbes);
}
$STR_ExcludeProbes = undef;

my %ParsingRules        = ();
foreach my $probeName (keys $CFG->{"cfg_monitoring"}) {
    $ParsingRules{$probeName} = {};
    foreach my $sectionName ( $CFG->getSections($CFG->{"cfg_monitoring"}->{$probeName}) ) {
        $ParsingRules{$probeName}->{$sectionName} = {
            get_keys => $CFG->{"cfg_monitoring"}->{$probeName}->{$sectionName}->{'get_keys'} || 0,
            select_sections => $CFG->{"cfg_monitoring"}->{$probeName}->{$sectionName}->{'sections'}
        };
    }
}

# Create log file
my $Console = new perluim::logger({
    file => "$STR_Logfile.log",
    level => $INT_Loglevel
});
$SIG{__DIE__} = \&scriptDieHandler;

# login to the hub
nimLogin("$STR_Login","$STR_Password") if defined($STR_Login) && defined($STR_Password);
$STR_Login = undef;
$STR_Password = undef;

# Check default value
if(not defined($INT_NBThreads)) {
    $Console->log(2,"Configuration property setup/nb_threads not detected :: Default value = 3");
    $INT_NBThreads = 3;
}

# Connect database!
sub connect_db {
    my $DB_User         = $CFG->{"database"}->{"user"};
    my $DB_Password     = $CFG->{"database"}->{"password"};
    my $DB_HOST         = $CFG->{"database"}->{"host"};
    my $DB_Database     = $CFG->{"database"}->{"database"};

    my $DB = DBI->connect("$DB_HOST;UID=$DB_User;PWD=$DB_Password",{
        RaiseError => 0,
        AutoCommit => 1,
        PrintError => 0
    });

    $DB->do("USE $DB_Database");
    return $DB;
}
my $DBManager = database_manager->new();
$DBManager->setDB(connect_db());

# Create a new PerlUIM Instance
my ($rc_getNimsoftDomain,$nimDomain) = nimGetVarStr(NIMV_HUBDOMAIN);
if($rc_getNimsoftDomain != NIME_OK) {
    $Console->log(0,"Failed to get hub domain... Returned Nimsoft Code => $rc_getNimsoftDomain");
    closeScript();
}
$Console->log(3,"hub domain => $nimDomain");
my $UIM = new perluim::main($nimDomain);
my $date = perluim::utils::getDate();
perluim::utils::createDirectory("$STR_OutputDir/$date");
my $outputDir = "$STR_OutputDir/$date";
$Console->cleanDirectory($STR_OutputDir,$INT_OutputMaxTime);

# Manage Threads
my $robotsQueue = Thread::Queue->new();
my $handleRobots = sub {
    $Console->log(3,"Thread started!");
    while ( defined ( my $robot = $robotsQueue->dequeue() ) ) {
        my $Cursor = database_manager->new();
        eval {
            $Cursor->setDB(connect_db());
            my ($RC) = $robot->getInfo();
            $Console->log(2, "Failed to get robot $robot->{name} information, Returned Nimsoft Code => $RC") if $RC != NIME_OK;
            getRobotProbes($robot, $Cursor) if $RC == NIME_OK;
        };
        $Console->log(1, $@) if $@;
        $Cursor->close;
    }
    $Console->log(2,"Thread finished!");
};

# Robots array!
my @robots = ();

# Die handler
sub scriptDieHandler {
    my ($err) = @_; 
    $Console->log(0, "Criticial error handled!");
    $Console->log(0, $err);
    closeScript();
}

# Close script
sub closeScript {
    $DBManager->close();
    $Console->log(3,"Checkconfig execution Terminated!");
    $Console->copyTo($outputDir);
    $Console->close();
    exit(0);
}

# Get robots from hubs
sub getHubRobots {
    my ($hub) = @_;
    $| = 1;
    # retry 60 times with sleep 3 between each try!
    for(my $i = 0; $i<=60; $i++) {
        my ($RC, @robotsList) = $hub->robotsArray();
        if($RC != NIME_OK) {
            $Console->log(1, "[Try $i] Failed to get robots list for hub => $hub->{addr}, Returned Nimsoft Code => $RC");
            sleep 3;
            next;
        }
        push(@robots, $_) for @robotsList;
        last;
    }
}

# Get robot probes list!
sub getRobotProbes {
    my ($robot, $Cursor) = @_;
    my $robotDir = "$outputDir/$robot->{hubname}/$robot->{name}";
    perluim::utils::createDirectory($robotDir);
    my ($RC, @probesList) = $robot->probesArray();
    if($RC != NIME_OK) {
        $Console->log(2,"Failed to get probes list for robot => $robot->{name}");
        return;
    }
    $Console->log(3,"Processing robot $robot->{name}");
    $Cursor->updateProbe($_, $robot->{name}, $robot->{fk}) for @probesList;
    my ($RC_ROBOT) = $robot->getRobotCFG($robotDir);
    push(@probesList, 'robot') if $RC == NIME_OK;
    getProbeConfiguration($Cursor, $robot, $robotDir, $_) for @probesList;
}

# Get probe configuration
sub getProbeConfiguration {
    my ($Cursor, $robot, $dirPath, $probe) = @_;
    if($probe eq "robot") {
        parseCfg($Cursor, 'robot', $robot->{name}, "$dirPath/robot.cfg") if exists $ParsingRules{'robot'};
        return;
    }
    return if exists $ExcludesProbes{$probe->{name}};
    my ($RC) = $probe->getCfg($dirPath);
    if($RC != NIME_OK) {
        $Console->log(4,"Failed to get cfg of $probe->{name} on robot $robot->{name}, Returned Nimsoft Code => $RC");
        return;
    }
    parseCfg($Cursor, $probe->{name}, $robot->{name}, "$dirPath/$probe->{name}.cfg") if exists $ParsingRules{$probe->{name}} && $BOOL_Getprobes_attr == 1;
}

# Parse Configuration file !
sub parseCfg {
    my ($Cursor, $probeName, $robotName, $filePath) = @_;
    my $CFG = cfgOpen($filePath, 0);
    foreach my $pattern (keys $ParsingRules{$probeName}) {

        # Handle Keys
        if( $ParsingRules{$probeName}->{$pattern}->{get_keys} == 1 ) {
            my $lastChar = substr($pattern,length($pattern)-1,1);
            my $tmpPattern = $pattern;
            if($lastChar ne "/") {
                $tmpPattern = "$pattern/";
            }
            $tmpPattern =~ s/\\/#/g;

            my ($KeyArray) = cfgKeyList($CFG, $pattern);
            foreach my $keyName (@{$KeyArray}) {
                my $keyValue = cfgKeyRead($CFG, $pattern, $keyName) || '';
                $Cursor->updateProbeConfiguration($probeName, $robotName, "${tmpPattern}${keyName}", $keyValue);
            }
        }

        if( defined $ParsingRules{$probeName}->{$pattern}->{select_sections} ) {
            my %select_sections     = %{ $ParsingRules{$probeName}->{$pattern}->{select_sections} };
            my $select_count        = keys %select_sections;

            # Handle Sections
            my ($SectionArray) = cfgSectionList($CFG, $pattern);
            V1: foreach my $sectionName (@{$SectionArray}) {
                
                my ($ARR) = cfgKeyList($CFG, $sectionName);
                if($select_count > 0) {
                    my $match_count = 0;
                    V2: foreach my $keyName (@{$ARR}) {
                        if(exists $select_sections{$keyName}) {
                            if($select_sections{$keyName} ne '') {
                                my $keyValue = cfgKeyRead($CFG, $sectionName, $keyName) || '';
                                next V2 if $keyValue ne $select_sections{$keyName};
                            }
                            $match_count++;
                        }
                    }
                    next V1 if $match_count != $select_count;
                }
                my $tmpSectionName = $sectionName;
                $tmpSectionName =~ s/\\/#/g;
                foreach my $keyName (@{$ARR}) {
                    my $keyValue = cfgKeyRead($CFG, $sectionName, $keyName) || '';
                    $Cursor->updateProbeConfiguration($probeName, $robotName, "$tmpSectionName/$keyName", $keyValue);
                }
            }

        }
    }
    cfgSync($CFG);
    cfgClose($CFG);
}

# Main script!
sub checkconfig {
    $Console->log(3, "Retrieve hubslist...");
    my ($RC,@Hubs) = $UIM->getArrayHubs(undef,$nimDomain);
    if($RC != NIME_OK) {
        $Console->log(0, "Failed to get hubslist. Returned Nimsoft Code => $RC");
        return;
    }
    $Console->log(3, "Update hubs table...");
    $DBManager->updateHub($_) for @Hubs;
    return if $BOOL_Getrobots == 0;
    $Console->log(3, "Retrieve robots list!");
    getHubRobots($_) for @Hubs;
    $Console->log(3, "Update robots table...");
    $DBManager->updateRobot($_) for @robots;
    return if $BOOL_Getprobes == 0;
    foreach(@robots) {
        $_->{'fk'} = $DBManager->{'robot_fk'}->{$_->{name}};
    }
    $DBManager->{'robot_fk'} = undef;
    $robotsQueue->enqueue($_) for @robots;
    for(my $i = 0; $i <= $INT_NBThreads; $i++) {
        $robotsQueue->enqueue(undef);
    }
    $Console->log(3, "Retrieve probes list!");
    my @thr = map {
        threads->create(\&$handleRobots);
    } 1..$INT_NBThreads;
    $_->join() for @thr;
}
eval {
    checkconfig();
};
$Console->log(0,$@) if $@;
closeScript();