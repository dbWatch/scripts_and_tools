#! perl

# ================================================================================================================
#   Per Christopher Undheim
#   per.christopher@dbwatch.com
#   dbWatch AS (c) 2019
#   10.12.2019
#   Nagios Fileread for dbWatch
#   Version 1.0
#   This script is used by Nagios to read the file created by the Nagios extension for dbWatch. 
# ================================================================================================================

# This is the filename of the file to read by the script. This is could be spesified as a variable or hardcoded 
# into this script. Using a hardcoded value would change the check_command from check_nrpe2args to check_nrpe1arg
$filename = $ARGV[0];
# Format 1 = short output (default), 2 = medium output, 3 = long output 
$format_output=1;
# List seperated by comma
# example: $exclude_instances = "homon_94, lytton_11g";
$exclude_instances = "";
# Lost connection text string
$LC_TEXT="LOST CONNECTION:";
# Alarm text string
$ALARM_TEXT="ALARM:";
# Warning text string
$WARNING_TEXT="WARNING:";
# OK text string
$OK_TEXT="OK:0";


# Non adjustable parameters follow

$return=0;
$warn;
$LC_CNT=0;
$ALARM_CNT=0;
$WARNING_CNT=0;
$DET_MSG=0;
$DET_OUT="";
@DET_DB;
@DET_CHK;
@DET_STAT;
@DET_DETAILS;
$DET_CNT=0;
@HEAD_ARR;



open(INFILE, $filename) or die "Error, cant open file ".$filename."\n";
while (<INFILE>) {
	chomp;
	$line = $_;
	if ($lastline =~ "=== DBWATCH SUMMARY ===") {
		
		$head=$line;
		
	}
	if ($DET_MSG == 1){
		if (($line !~ "CheckStatus=OK") && ($line !~ "DBStatus=OK") && ($line !~ "DBStatus=NOT CONNECTED"))  {
		    if (length($exclude_instances) > 0) {
		    my $EX_THIS=0;
			my @exclude_inst = split(',', $exclude_instances);
			while(scalar(@exclude_inst) !=0) {
			$excl=shift(@exclude_inst);
			$excl =~ s/^\s+|\s+$//g;
	 		     if ($line =~ $excl) {
	 		        $EX_THIS=1;
	 		     }
	 		     
	 		    }    
	 		    print "EX:".$EX_THIS." LINE: ".$line."\n";    
	 		    if ($EX_THIS==0) {    
			     	push @DET_DB, $line =~ m/DbName=(.*?)\; /;
		           	push @DET_STAT, $line =~ m/CheckStatus=(.*?)\; /;
		           	push @DET_CHK, $line =~ m/CheckName=(.*?)\; /;
		         	push @DET_DETAILS, $line =~ m/Description=(.*?)\;/;
			   	}
			
		    }
		    else {
		          push @DET_DB, $line =~ m/DbName=(.*?)\; /;
		          push @DET_STAT, $line =~ m/CheckStatus=(.*?)\; /;
		           	push @DET_CHK, $line =~ m/CheckName=(.*?)\; /;
		         	push @DET_DETAILS, $line =~ m/Description=(.*?)\;/;
		    }
		
			
		}
	}
	elsif (($line =~ "=== DBWATCH DETAILS ===") && ($format_output == 1)){
		@HEAD_ARR=split(/;/,$head);

		$OK_TEXT=$HEAD_ARR[3];
		print $LC_TEXT.$LC_CNT.";".$ALARM_TEXT.$ALARM_CNT.";".$WARNING_TEXT.$WARNING_CNT.";".$OK_TEXT."\n";
		close(INFILE);
		if (($WARNING_CNT > 0)) { $return=1; }
		if (($LC_CNT > 0) || ($ALARM_CNT > 0)) { $return=2; }

		exit $return;
	}
	elsif (($line =~ "=== DBWATCH DETAILS ===") && ($format_output > 1)){
	       @HEAD_ARR=split(/;/,$head);

		$OK_TEXT=$HEAD_ARR[3];
		$DET_MSG=1;
	}
	elsif (($line !~ "=== DBWATCH DETAILS ===") || ($line !~ "=== DBWATCH SUMMARY ==="))  {
		if (length($exclude_instances) > 0) {
			my @exclude_inst = split(',', $exclude_instances);
			while(scalar(@exclude_inst) !=0) {
			
			$excl=shift(@exclude_inst);
			$excl =~ s/^\s+|\s+$//g;
			if ($line =~ $excl) {
					$line=~ s/$excl\;//g;
				}
			}
		}
		my @CNT=split("\;",$line);
		my $CNT=0;
		#print "LINE:".$line."\n";
		$CNT++ while ($line =~ m/;/g);
		if ($line=~$LC_TEXT) {$LC_CNT=$CNT;}
		if ($line=~$ALARM_TEXT) {$ALARM_CNT=$CNT;}
		if ($line=~$WARNING_TEXT) {$WARNING_CNT=$CNT;}
		if ($line !~ "=== DBWATCH SUMMARY ===") {$out=$out." ".$line;}
	}
	
	$lastline=$line;
	
	
} 
if ($format_output == 2) {
	print $LC_TEXT.$LC_CNT.";".$ALARM_TEXT.$ALARM_CNT.";".$WARNING_TEXT.$WARNING_CNT.";".$OK_TEXT;
	
	foreach $DB(@DET_DB) {
	        if ($DET_CNT == 0) { print "; Database: "; }       
	        print $DET_STAT[$DET_CNT].":";
			print $DB." - ";
			print $DET_CHK[$DET_CNT]."; ";
			$DET_CNT=$DET_CNT + 1;
	}
	if (($WARNING_CNT > 0)) { $return=1; }
	if (($LC_CNT > 0) || ($ALARM_CNT > 0)) { $return=2; }
}
elsif ($format_output == 3) {
	print $LC_TEXT.$LC_CNT.";".$ALARM_TEXT.$ALARM_CNT.";".$WARNING_TEXT.$WARNING_CNT.";".$OK_TEXT;
	foreach $DB(@DET_DB) {
        	if ($DET_CNT == 0) { print "; Database: "; } 
	        print $DET_STAT[$DET_CNT].":";
			print $DB." - ";
			print $DET_CHK[$DET_CNT]." - ";
			print $DET_DETAILS[$DET_CNT]."; ";
			$DET_CNT=$DET_CNT + 1;
	}
    if (($WARNING_CNT > 0)) { $return=1; }
	if (($LC_CNT > 0) || ($ALARM_CNT > 0)) { $return=2; }
}

exit $return;