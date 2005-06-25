require 'lib/Net/IMAP/Simple.pm';
print "Square brackets: [] indicate optional arguments\n\n";
print "IMAP Server[:port] [localhost]: ";

while(<>){
	chomp;
	$_ ||= 'localhost';
	$imap = Net::IMAP::Simple->new($_, port => 143, timeout => 90) || die "$Net::IMAP::Simple::errstr\n";
	if($imap){
		print "Connected.\n";
		last;
	} else {
		print "Connection to $_ failed: $Net::IMAP::Simple::errstr\n";
		print "IMAP Server[:port]: ";
	}
}

print "User: ";
while(<>){
	chomp;
	$user = $_;
	if(!$user){
		print "Blank user not allowed\n";
		print "User: ";
	} else {
		last;
	}
}

print "Password: ";
system("stty -echo");
while(<>){
	chomp;
	if(!$imap->login($user, $_)){
		print "Login failed: " . $imap->errstr . "\n";
	} else {
		my $msgs = $imap->select("INBOX");
		print "Messages in INBOX: $msgs\n";
		last;
	}
}

system("stty echo");

print "Mail boxes:\n";
for($imap->mailboxes){
	s/\./ -> /g;
	print "BOX: $_\n";
}

print "Recent: " . $imap->recent . "\n";
print " Flags: " . $imap->flags . "\n";
print "Flag List: " . join(" ", $imap->flags) . "\n";

$imap->quit;
