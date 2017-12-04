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

my %ParsingRules        = ();
foreach my $probeName (keys $CFG->{"cfg_monitoring"}) {
    $ParsingRules{$probeName} = {};
    foreach my $sectionName ( $CFG->getSections( $CFG->{"cfg_monitoring"}->{$probeName} ) ) {
        my $strKeys = $CFG->{"cfg_monitoring"}->{$probeName}->{$sectionName}->{'keys'};
        my @keys = defined($strKeys) ? split(',', $strKeys) : ();
        $ParsingRules{$probeName}->{$sectionName} = {
            pattern => $CFG->{"cfg_monitoring"}->{$probeName}->{$sectionName}->{'pattern'},
            select_keys => \@keys
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
if(defined($STR_Login) && defined($STR_Password)) {
    my ($rc) = nimLogin("$STR_Login","$STR_Password");
    if($rc != NIME_OK) {
        $Console->log(0,"Failed to authenticate Checkconfig to the hub with login: $STR_Login and password: $STR_Password! Returned Nimsoft Code => $rc");
        goto Terminated;
    }
}
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
    goto Terminated;
}
$Console->log(3,"hub domain => $nimDomain");
my $UIM = new perluim::main($nimDomain);
$Console->cleanDirectory($STR_OutputDir,$INT_OutputMaxTime);
my $date = perluim::utils::getDate();
perluim::utils::createDirectory("$STR_OutputDir/$date");
my $outputDir = "$STR_OutputDir/$date";

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
    $Console->log(0, $err);
    exit(1);
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
    foreach my $ruleName (keys $ParsingRules{$probeName}) {
        my $pattern         = $ParsingRules{$probeName}->{$ruleName}->{'pattern'};
        my @arr_keys        = @{ $ParsingRules{$probeName}->{$ruleName}->{'select_keys'} };
        my %select_keys     = map { $_ => 1 } @arr_keys;
        my $select_count    = keys %select_keys;

        my ($KeyArray) = cfgKeyList($CFG, $pattern);
        foreach my $keyName (@{$KeyArray}) {
            if($select_count > 0) {
                next if not exists $select_keys{$keyName};
            }
            my $keyValue = cfgKeyRead($CFG, $pattern, $keyName);
            my $lastChar = substr($pattern,length($pattern)-1,1);
            if($lastChar ne "/") {
                $pattern = "$pattern/";
            }
            $Cursor->updateProbeConfiguration($probeName, $robotName, "${pattern}${keyName}", $keyValue);
        }

        my ($SectionArray) = cfgSectionList($CFG, $pattern);
        foreach my $sectionName (@{$SectionArray}) {
            if($select_count > 0) {
                next if not exists $select_keys{$sectionName};
            }
            $Cursor->updateProbeConfiguration($probeName, $robotName, $sectionName, 'PDS');
        }
    }
    cfgSync($CFG);
    cfgClose($CFG);
}

# Main script!
sub checkconfig {
    my ($RC,@Hubs) = $UIM->getArrayHubs();
    if($RC != NIME_OK) {
        $Console->log(0, "Failed to get hubslist. Returned Nimsoft Code => $RC");
        return;
    }
    $DBManager->updateHub($_) for @Hubs;
    return if $BOOL_Getrobots == 0;
    getHubRobots($_) for @Hubs;
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
    my @thr = map {
        threads->create(\&$handleRobots);
    } 1..$INT_NBThreads;
    $_->join() for @thr;
}
eval {
    checkconfig();
};
$Console->log(0,$@) if $@;
Terminated:
$DBManager->close();
$Console->log(3,"Checkconfig execution terminated!");
$Console->copyTo($outputDir);
$Console->close();