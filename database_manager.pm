package database_manager;

# Table Names...
our %TableName = (
    hub => "Audit_Hubs",
    robot => "Audit_Robots",
    probe => "Audit_Probes",
    probe_attr => "Audit_Probes_Attr"
);

sub new {
    my ($class) = @_;
    return bless({
        hub_fk => {},
        robot_fk => {},
        probe_fk => {}
    },ref($class) || $class);
}

sub setDB {
    my ($this, $DB) = @_;
    $this->{'DB'} = $DB;
}

sub close {
    my ($this) = @_;
    $this->{'DB'}->disconnect;
}

sub updateHub {
    my ($this,$hub) = @_;
    my $DB = $this->{'DB'};
    my ($id, $sth, $rows);

    $sth = $DB->prepare("SELECT id FROM $TableName{hub} WHERE name = ?");
    $sth->execute($hub->{name});
    $rows = $sth->rows;

    if($rows == -1) {
        while(my @Arr = $sth->fetchrow_array) {
            $id = $Arr[0];
            last;
        }
    }
    $sth->finish();

    if($rows == -1) {
        $sth = $DB->prepare("UPDATE $TableName{hub} SET domain=?,robot=?,ip=?,port=?,version=?,origin=?,change_time=getdate() WHERE name = ?");
        $sth->execute(
            $hub->{domain},
            $hub->{robotname},
            $hub->{ip},
            $hub->{port},
            $hub->{version},
            $hub->{origin},
            $hub->{name}
        );
        $sth->finish();
        $this->{'hub_fk'}->{$hub->{name}} = $id;
    }
    else {
        $sth = $DB->prepare("INSERT INTO $TableName{hub} (domain,name,robot,ip,port,version,origin) VALUES (?,?,?,?,?,?,?)");
        $sth->execute(
            $hub->{domain},
            $hub->{name},
            $hub->{robotname},
            $hub->{ip},
            $hub->{port},
            $hub->{version},
            $hub->{origin}
        );
        $sth->finish();
        my @rowID = $DB->selectrow_array('SELECT @@IDENTITY');
        $this->{'hub_fk'}->{$hub->{name}} = $rowID[0];
    }
}

sub updateRobot {
    my ($this,$robot) = @_;
    my $DB = $this->{'DB'};
    my ($id, $sth, $rows);

    $sth = $DB->prepare("SELECT id FROM $TableName{robot} WHERE name = ?");
    $sth->execute($robot->{name});
    $rows = $sth->rows;

    if($rows == -1) {
        while(my @Arr = $sth->fetchrow_array) {
            $id = $Arr[0];
            last;
        }
    }
    $sth->finish();
    my $hubid = $this->{'hub_fk'}->{$robot->{hubname}};

    if($rows == -1) {
        $sth = $DB->prepare("UPDATE $TableName{robot} SET domain=?,status=?,ip=?,version=?,origin=?,change_time=getdate() WHERE name = ?");
        $sth->execute(
            $robot->{domain},
            $robot->{status},
            $robot->{ip},
            $robot->{version},
            $robot->{origin},
            $robot->{name}
        );
        $this->{'robot_fk'}->{$robot->{name}} = $id;
    }
    else {
        $sth = $DB->prepare("INSERT $TableName{robot} (hub_id,domain,name,status,ip,version,origin) VALUES (?,?,?,?,?,?,?)");
        $sth->execute(
            $hubid,
            $robot->{domain},
            $robot->{name},
            $robot->{status},
            $robot->{ip},
            $robot->{version},
            $robot->{origin}
        );
        my @rowID = $DB->selectrow_array('SELECT @@IDENTITY');
        $this->{'robot_fk'}->{$robot->{name}} = $rowID[0];
    }
}

sub updateProbe {
    my ($this,$probe,$robotName,$robotid) = @_;
    my $DB = $this->{'DB'};
    my ($id, $sth, $rows);

    $sth = $DB->prepare("SELECT id FROM $TableName{probe} WHERE name = ? AND robot_id = ?");
    $sth->execute($probe->{name}, $robotid);
    $rows = $sth->rows;
    if($rows == -1) {
        while(my @Arr = $sth->fetchrow_array) {
            $id = $Arr[0];
            last;
        }
    }
    $sth->finish();

    if($rows == -1) {
        $sth = $DB->prepare("UPDATE $TableName{probe} SET active=?,version=?,build=?,process_state=?,change_time=getdate() WHERE name = ? and robot_id = ?");
        $sth->execute(
            $probe->{active},
            $probe->{pkg_version},
            $probe->{pkg_build},
            $probe->{process_state},
            $probe->{name},
            $id
        );
        $this->{'probe_fk'}->{"${robotName}_$probe->{name}"} = $id;
    }
    else {
        $sth = $DB->prepare("INSERT INTO $TableName{probe} (robot_id,name,active,version,build,process_state) VALUES (?,?,?,?,?,?)");
        $sth->execute(
            $robotid,
            $probe->{name},
            $probe->{active},
            $probe->{pkg_version},
            $probe->{pkg_build},
            $probe->{process_state}
        );
        my @rowID = $DB->selectrow_array('SELECT @@IDENTITY');
        $this->{'probe_fk'}->{"${robotName}_$probe->{name}"} = $rowID[0];
    }
}

sub updateProbeConfiguration {
    my ($this, $probeName, $robotName, $keyName, $keyValue) = @_;
    my $DB = $this->{'DB'};
    my ($id, $sth, $rows);
    if($probeName eq "robot") {
        $probeName = "controller";
    }

    my $probeId = $this->{'probe_fk'}->{"${robotName}_${probeName}"};
    $sth = $DB->prepare("SELECT id FROM $TableName{probe_attr} WHERE cfg_key = ? AND probe_id = ?");
    $sth->execute($keyName, $probeId);
    $rows = $sth->rows;
    if($rows == -1) {
        while(my @Arr = $sth->fetchrow_array) {
            $id = $Arr[0];
            last;
        }
    }
    $sth->finish();

    if($rows == -1) {
        $sth = $DB->prepare("UPDATE $TableName{probe_attr} SET cfg_value=? WHERE cfg_key = ? and probe_id = ?");
        $sth->execute(
            $keyValue,
            $keyName,
            $probeId
        );
        $this->{'probe_fk'}->{"${robotName}_$probe->{name}"} = $id;
    }
    else {
        $sth = $DB->prepare("INSERT INTO $TableName{probe_attr} (probe_id,cfg_key,cfg_value) VALUES (?,?,?)");
        $sth->execute(
            $probeId,
            $keyName,
            $keyValue
        );
    }
}

1;