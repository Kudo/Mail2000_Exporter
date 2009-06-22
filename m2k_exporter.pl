#!/usr/bin/perl -w
#
# Mail2000 data exporter
#
# Author: Kudo Chien <kudo@cna.ccu.edu.tw>
#
# Feature:
# 	User List
# 	User MD5 password
# 	User Mails
#
# Partial Complete:
# 	User address book
#
# Todo:
# 	User document
#
use strict;
use utf8;
use POSIX;
use FileHandle;
use File::Basename;
use File::Copy;
use Digest::MD5 qw /md5_hex/;
use Encode qw /encode decode/;

# Mail2000 Directory
my $M2KROOT = '/webmail';

# Backup Directory
my $DESTDIR = '/root/Backup';

# Hostname
my $HOSTNAME = 'alumnix.ccu.edu.tw';
#my $HOSTNAME = `hostname`;
#chomp $HOSTNAME;

my $pid = POSIX::getpid;

#
# Save Password
sub savePasswd {
    my ($udir, $userid) = @_;

    open userFH, ">> $DESTDIR/dovecot.users" or die "Open file $DESTDIR/dovecot.users failed: $!\n";
    open passwdFH, ">> $DESTDIR/dovecot.passwd" or die "Open file $DESTDIR/dovecot.passwd failed: $!\n";
    open vmapFH, ">> $DESTDIR/postfix.vmaps" or die "Open file $DESTDIR/postfix.vmaps failed: $!\n";
    open FH, "$udir/.passwd" or die "Open file $udir/.passwd failed: $!\n";
    while (<FH>) {
	chomp;
	my $passwd = unpack('Z*', $_);

	print userFH $userid.'@'.$HOSTNAME."::5000:5000::/mail/vmail/$HOSTNAME/:/bin/false::\n";
	print passwdFH $userid.'@'.$HOSTNAME.':'."$passwd\n";
	print vmapFH pack("A50 A*", $userid.'@'.$HOSTNAME, "$HOSTNAME/". lc substr($userid, 0, 2)."/$userid\n");
    }
    close FH;
    close vmapFH;
    close passwdFH;
    close userFH;
}

#
# Save mbox
sub saveMbox {
    my ($dir, $OH) = @_;
    my $mailItem;
    my $mailBody;

    open DH, "$dir/.DIR" or return;

    while (read(DH, $mailItem, 256)) {
	my ($timestamp, $file, $from) =  unpack('H8x8Z10x10Z40', $mailItem);

	if ($timestamp =~ /^([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/) {
	    $timestamp = hex "$4$3$2$1";
	} else {
	    $timestamp = time;
	}

	my $date = POSIX::strftime("%a %b %d %H:%M:%S %Y", localtime($timestamp));

	if ($from =~ /^\s*$/) {
	    $from = 'MAILER-DAEMON';
	}

	print $OH "From $from $date\n";

	open FH, "$dir/$file" or die "open $dir/$file error: $!\n";
	while (read(FH, $mailBody, 8242880)) {
	    print $OH $mailBody;
	}
	print $OH "\n";
	close FH;
    }

    close DH;
}

#
# Save Maildir
sub saveMaildir {
    my ($dir, $targetDir) = @_;
    my $mailItem;
    my $mailBody;

    open DH, "$dir/.DIR" or return;

    while (read(DH, $mailItem, 256)) {
	my ($timestamp, $file) =  unpack('H8x8Z10', $mailItem);

	if ($timestamp =~ /^([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/) {
	    $timestamp = hex "$4$3$2$1";
	} else {
	    $timestamp = time;
	}

	copy("$dir/$file", "$targetDir/$timestamp.".$pid."_0.$HOSTNAME") or die "copy $dir/$file error: $!\n";
    }

    close DH;
}

#
# parse folder infomations
sub parseFolder {
    my ($userhome) = @_;
    my %dirHash;

    my $folderItem;
    $dirHash{"@"} = "收件匣";
    $dirHash{"@.backup"} = "舊信匣";
    $dirHash{"@.draft"} = "草稿匣";
    $dirHash{"@.sent"} = "送信匣";
    #$dirHash{"@.trash"} = "回收筒";

    if (open FH, "$userhome/.FOLDER") {

	while (read(FH, $folderItem, 72)) {
	    my $folder = substr($folderItem, 0, 4);
	    my $folderName = unpack('Z*', substr($folderItem, 32, 38));
	    $dirHash{$folder} = $folderName;
	}

	close FH;
    }

    return %dirHash;
}

#
# Convert maill2000 mail to mbox format
sub convertToMbox {
    my ($userhome, $userid) = @_;

    # get folder
    my %dirHash = parseFolder($userhome);

    mkdir "$DESTDIR/$userid", 0755 or warn "mkdir for $userid warning: $!\n";
    chdir "$DESTDIR/$userid" or die "$!\n";

    open folderFH, "> folderList";

    foreach my $folder (sort {$a cmp $b} keys %dirHash) {
	print folderFH "$folder\t$dirHash{$folder}\n";

	# convert mails to mbox
	my $dirFH = new FileHandle "> $folder" or die "$!\n";
	saveMbox("$userhome/$folder", $dirFH);
	$dirFH->close;
    }

    close folderFH;
}

#
# Convert mail2000 mails to maildir format
sub convertToMaildir {
    my ($userhome, $userid) = @_;

    # get folder
    my %dirHash = parseFolder($userhome);

    my $dir = "$DESTDIR/" . lc substr($userid, 0, 2) . "/$userid";

    mkdir dirname($dir), 0755;
    mkdir $dir, 0755 or warn "mkdir for $userid warning: $!\n";
    chdir $dir or die "$!\n";

    foreach my $folder (sort {$a cmp $b} keys %dirHash) {
	# convert mails to maildir
	mkdir 'cur', 0755;
	mkdir 'new', 0755;
	mkdir 'tmp', 0755;
	saveMaildir("$userhome/$folder", 'cur');
    }
}

####################################################################################
# Convert Address Book Routines
####################################################################################
sub getFileInfo {
    my ($fname) = @_;
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($fname);
    return ($size, $ctime);
}

sub parseAddressFile {
    my ($data) = @_;
    my @keys = ('UID', 'UGENDER', 'UEMAIL', 'UURL', 'UPHOTO', 'UFNAME', 'UADDRESS', 'UCOMPANY', 'UHOME_TEL', 'UOFFICE_TEL', 'UFAX', 'UBIRTHDAY', 'UMOBIL', 'UPAGER', 'UCATEGORY_INDEX', 'UMEMO', 'UCOMPANY_ADDR', 'UCOMPANY_URL', 'UCOMPANY_ZIP', 'UCOMPANY_EMAIL', 'UCOMPANY_TEL2', 'UHOME_ZIP', 'UHOME_FAX', 'UHOME_TEL2');
    my %hash;

    if (defined($data))
    {
	foreach my $line (split /\n/, $data)
	{
	    my ($key, $value) = split(/:\s*/, $line);
	    $hash{$key} = "'".decode('big5', $value)."'";
	}
    }

    foreach my $key (@keys)
    {
	if (!exists($hash{$key}))
	{
	    $hash{$key} = 'NULL';
	}
    }
    return %hash;
}

sub makeJSON {
    my (@md5List) = @_;
    my $count = @md5List;
    my $result = "a:$count:{";
    my $i = 0;

    foreach my $md5 (@md5List)
    {
	$result .= "i:$i;s:32:\"$md5\";";
	$i++;
    }
    $result .= '}';
}

sub makeTurbaAddrSQL {
    my ($user, $ctime, $addrRef, $personInfoRef, $nick2MD5Ref) = @_;
    my ($fname, $nickName, $realName, $email, $categoryID) = @{$addrRef};

    $nickName = decode('big5', $nickName);
    $realName = decode('big5', $realName);
    $email = decode('big5', $email);

    my $date = POSIX::strftime("%Y%m%d%H%M%S", localtime($ctime));
    my $object_id = md5_hex($email.rand());
    ${$nick2MD5Ref}{$nickName} = $object_id;

    return "INSERT INTO turba_objects (object_id, owner_id, object_type, object_uid, object_members, object_name, object_alias, object_email, object_homeaddress, object_workaddress, object_homephone, object_workphone, object_cellphone, object_fax, object_title, object_company, object_notes) VALUES ('$object_id', '$user', 'Object', '$date.\@$HOSTNAME', NULL, '$nickName', ${$personInfoRef}{'UCOMPANY_EMAIL'}, '$email', ${$personInfoRef}{'UADDRESS'}, ${$personInfoRef}{'UCOMPANY_ADDR'}, ${$personInfoRef}{'UHOME_TEL'}, ${$personInfoRef}{'UOFFICE_TEL'}, ${$personInfoRef}{'UMOBIL'}, ${$personInfoRef}{'UHOME_FAX'}, ${$personInfoRef}{'UFNAME'}, ${$personInfoRef}{'UCOMPANY'}, ${$personInfoRef}{'UMEMO'});\n";
}

sub makeTurbaGroupSQL {
    my ($user, $groupName, $md5JSON) = @_;

    my $date = POSIX::strftime("%Y%m%d%H%M%S", localtime);
    my $object_id = md5_hex(encode('utf8', $groupName.rand()));
    return "INSERT INTO turba_objects (object_id, owner_id, object_type, object_uid, object_members, object_name) VALUES ('$object_id', '$user', 'Group', '$date.\@$HOSTNAME', '$md5JSON', '$groupName');\n";
}

sub exportAddrBook {
    my ($userhome, $userid, $OH) = @_;
    my @addresses;
    my @groups;
    my %categories;
    my %nick2MD5;

    my $item;
    my $buf;

    open FH, "$userhome/@.address/.CATEGORY" or warn "Open $userhome/@.address/.CATEGORY failed: $!\n";

    while (read(FH, $item, 56)) {
	my ($categoryID, $categoryName) =  unpack('IZ52', $item);
	$categoryName = decode('big5', $categoryName);
	$categories{$categoryID} = $categoryName;
    }

    close FH;

    open FH, "$userhome/@.address/.AIDX" or warn "Open $userhome/@.address/.AIDX failed: $!\n";

    while (read(FH, $item, 504)) {
	my @data =  unpack('Z32Z64Z256Z128Z24', $item);
	push(@addresses, \@data);
    }

    close FH;

    foreach my $address (@addresses)
    {
	my ($fname, $nickName, $realName, $email, $categoryID) = @{$address};

	$nickName = decode('big5', $nickName);
	$realName = decode('big5', $realName);
	$email = decode('big5', $email);

	open AH, "$userhome/@.address/$fname" or warn "Open $userhome/@.address/$fname failed: $!\n"; 
	my ($fileSize, $fileCtime) = getFileInfo("$userhome/@.address/$fname");
	read(AH, $buf, $fileSize);
	if ($fileSize >= 5242880)
	{
	    warn "$fname is larger than 5BM\n";
	}
	my %personInfo = parseAddressFile($buf);

	print $OH makeTurbaAddrSQL($userid, $fileCtime, $address, \%personInfo, \%nick2MD5);
	close AH;
    }


#or warn "Open $userhome/@.address/groupinfo failed: $!\n";
    if (open(FH, "$userhome/@.address/groupinfo"))
    {
	read(FH, $item, 4);
	my ($groupCount) = unpack('I', $item);
	my $i = 0;
	while ($i++ < $groupCount && read(FH, $item, 140)) {
	    my @data =  unpack('IZ100x28II', $item);
	    push(@groups, \@data);
	}

	foreach my $group (@groups)
	{
	    my $filePos = tell(FH);
	    my ($groupID, $groupName, $offBegin, $offEnd) = @{$group};
	    my @md5List;

	    $groupName = decode('big5', $groupName);
	    if ($filePos != $offBegin)
	    {
		seek(FH, $offBegin, 0);
		$filePos = $offBegin;
	    }

	    while (<FH>)
	    {
		chomp;
		my $name = $_;
		if (!exists($nick2MD5{$name}))
		{
		    my @addrArr = (NULL, $name, NULL, $name, 10001);
		    my %personInfo = parseAddressFile();
		    warn "Warning in ConvAddrBooks: no address ($name) exists, we will insert now.\n";
		    print $OH makeTurbaAddrSQL($userid, time(), \@addrArr,  \%personInfo, \%nick2MD5);
		}
		push(@md5List, $nick2MD5{$_});
		$filePos = tell(FH);
		if ($filePos > $offEnd)
		{
		    last;
		}
	    }

	    print $OH makeTurbaGroupSQL($userid, $groupName, makeJSON(@md5List));
	}
	close FH;
    }
}

sub main {
    chdir $DESTDIR or die "$!\n";
    POSIX::setlocale(LC_ALL, 'en_US.ISO_8859-1');
    unlink "$DESTDIR/turbaAddrBooks.sql" or die "Unlink $DESTDIR/turbaAddrBooks.sql Failed: $!\n";

    #open USERD, "find $M2KROOT/usr -depth 3 -type d -print |" or die "$!";
    #open USERD, "find $M2KROOT/usr/8 -depth 2 -type d -print |" or die "$!\n";
    open USERD, "find $M2KROOT/usr/8/76 -depth 1 -type d -print |" or die "$!\n";

    my $turbaSQLFH = new FileHandle ">> $DESTDIR/turbaAddrBooks.sql" or die "Open $DESTDIR/turbaAddrBooks.sql failed: $!\n";
    binmode($turbaSQLFH, ':encoding(utf8)');

    while (<USERD>) {
	chomp;

	my $userhome = $_;
	my $userid = basename($userhome);

	# get passwords
	savePasswd($userhome, $userid);

	# convertToMbox or convertToMaildir
	#convertToMbox($userhome, $userid);
	convertToMaildir($userhome, $userid);

	# convert Address Book to horde turba SQL
	exportAddrBook($userhome, $userid, $turbaSQLFH);
    }
    $turbaSQLFH->close;
    close USERD;
}

main();
