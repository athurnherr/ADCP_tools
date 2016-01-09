#======================================================================
#                    R D I _ P D 0 _ I O . P L 
#                    doc: Sat Jan 18 14:54:43 2003
#                    dlm: Sat Jan  9 13:22:46 2016
#                    (c) 2003 A.M. Thurnherr
#                    uE-Info: 70 34 NIL 0 0 72 2 2 4 NIL ofnI
#======================================================================

# Read RDI BroadBand Binary Data Files (*.[0-9][0-9][0-9])

# HISTORY:
#	Jan 18, 2003: - incepted aboard the Aurora Australis (KAOS)
#	Jan 19, 2003: - continued
#	Jan 20, 2003: - replaced INTENSITY by AMPLITUDE
#	Jan 21, 2003: - changed heading-correction field names
#	Jan 27, 2003: - cosmetics
#	Feb 14, 2003: - moved BT setup into header
#	Mar 15, 2003: - moved 10th xmit voltage into header as BATTERY field
#				  - removed again, because values are not meaningful
#	Feb 24, 2004: - continued aboard Nathaniel B. Palmer (Anslope II)
#				  - BUG: ensemble # was wrong on error messages
#	Feb 26, 2004: - removed ESW_ERROR and bitmasking of ERROR_STATUS_WORD
#	Feb 27, 2004: - removed some unused (commented-out) baggage
#	Mar 11, 2004: - BUG: renamed ACD -> ADC
#	Mar 18, 2004: - cosmetics
#	Mar 30, 2004: - rewrote to speed up reading; new version takes
#					~40% less time
#	Sep 14, 2005: - made BT data optional (NUMBER_OF_DATA_TYPES)
#				  - added DATA_FORMAT
#	Sep 15, 2005: - debugged
#				  - implement checksum to robustly find EOF
#				  - renamed to RDI_BB_Read.pl
#				  - BUG: had used POSIX::mktime with wrong month def!
#	Oct 30, 2005: - added WH300 FW16.27 file format
#				  - added DATA_FORMAT_VARIANT
#				  - changed semantics so that first valid ensemble is
#				    in E[0] (instead of E[$ensNo-1])
#	Nov  8, 2005: - replaced UNIXTIME by UNIX_TIME
#				  - added SECNO
#	Aug 31: 2006: - added DAYNO
#	Aug  1, 2007: - BUG: typo in monthLength()
#	Sep 18, 2007: - modified readHeader() readDta() WBRhdr() WBRens() to
#					conserve memory (no large arrays as retvals)
#	Jun  4, 2008: - BUG: BB150 code was not considered on Sep 18, 2007
#	Aug 15, 2010: - downgraded "unexpected number of data types" from error to warning
#				  - BUG: WBRcfn had not been set correctly
#				  - modified to allow processing files without time info
#	May 12, 2011: - added code to report built-in-test errors
#	Mar 19, 2013: - added support for WH600 data file (58 fixed leader bytes)
#	Mar 20, 2013: - removed DATA_FORMAT stuff
#				  - added support for BT data in subset of ensembles
#	Apr 29, 2013: - changed semantics to assume EOF when unexpected number of data types
#					are present in an ensemble
#	Nov 25, 2013: - renamed from [RDI_BB_Read.pl]
#				  - begin implementing WBWens()
#				  - checkEnsemble() expunged
#	Mar  3, 2014: - BUG: WBPens() did not handle incomple ensembles at EOF correctly
#	Mar  4, 2014: - added support for DATA_SOURCE_ID
#	Apr 24, 2014: - added debug statements to log %-GOOD values
#	May  6, 2014: - loosened input format checks
#	May  7, 2014: - removed BT_present flag
#	Sep  6, 2014: - adapted WBRhdr to >7 data types
#	Oct 15, 2014: - implemented work-around for readData() not recognizing
#					incomplete ensemble at the end, which seems to imply that there is
#				    a garbage final ensemble that passes the checksum test???
#	Oct  2, 2015: - added &skip_initial_trash()
#	Dec 18, 2015: - added most data types to WBPofs()
#				  - BUG: WBPens() requires round() for scaled values
#	Jan  9, 2016: - BUG: WBRhdr() did not set DATA_SOURCE_ID
#				  - added PRODUCER

# FIRMWARE VERSIONS:
#	It appears that different firmware versions generate different file
#	structures. Currently (Sep 2005) these routines have been tested
#	with the following firmware versions (as reported by [listHdr]):
#
#	Firmw.	DATA_FORMAT(_VARIANT)	Owner 	Cruise	FIXED_LEADER_LENGTH
#------------------------------------------------------------
#	05.52	BB150 (1)				UH 		CLIVAR/P16S 42
#	16.12	WH300 (1)				FSU 	A0304		53
#	16.21	WH300 (1)				LDEO 	NBP0402		53
#	16.27	WH300 (2)				Nash 	?			59

# PD0 FILE FORMAT EXTENSIONS:
#
#	- DATA_SOURCE_ID = 0x7F						original TRDI PD0 file
#
#	- DATA_SOURCE_ID = 0xA0 | PATCHED_MASK		produced by IMP+LADP 
#		PATCHED_MASK & 0x04:						pitch value has been patched
#		PATCHED_MASK & 0x02:						roll value has been patched
#		PATCHED_MASK & 0x01:						heading value has been patched
#			- PITCH & ROLL can be missing (0x8000 badval as in velocities)
#			- HEADING can be missing (0xF000 badval, as 0x8000 is valid 327.68 heading)
#
#	- DATA_SOURCE_ID = 0xB0 					produced by editPD0

# NOTES:
#	- RDI stores data in VAX/Intel byte order (little endian)
#	- the output data structure does not exactly mirror the file data
#	  structure; the header is not stored at all and the fixed leader
#	  data are not duplicated in every ensemble
#	- in the RDI files some fields that logically belong into the header
#	  or the fixed leader (e.g. BT_MIN_CORRELATION) appear in the 
#	  ensemble data --- these are not read on input
#	- the field names are generally unabbreviated except for
#	  BT (= Bottom Track), RL (= Reference Layer), MIN and MAX
#	- all arrays are 0-referenced, but the ensemble number is not!
#	- a list of filenames can be be passed to readData() so that
#	  files split onto several memory cards (typically .000 .001 &c)
#	  can be read --- not sure if this works, actually
#	- the RDI manuals are not entirely clear everywhere; I have made
#	  guesses in some cases, but they should not affect the main
#	  fields of interest
#	- some fields in the fixed leader are not really fixed in a LADCP
#	  setting (e.g. xducer orientation); I'v made an educated guess
#	  as to which fields to move to the ENS array
#	- all units except pressure are SI, i.e. in m and m/s
#	- I don't understand the ERROR_STATUS_WORD; here's what 3 different
#	  instruments returned:
#	  	0x88000100	FSU instrument during A0304 (Firmware 16.12)
#		0x88008180	LDEO uplooker (slave) during NBP0402 (Firmware 16.21)
#		0x00008180	LDEO downlooker (master) during NBP0402 (Firmware 16.21)
#	  According to the manual (January 2001 version) this would, for example,
#	  indicate power failures on both FSU and LDEO slave instruments...

# &readData() returns perl obj (ref to anonymous hash) with the following
# structure:
#
#	DATA_SOURCE_ID					scalar		0x7f (Workhorse, also DVL)
#	NUMBER_OF_DATA_TYPES			scalar		6 (no BT) or 7
#	ENSEMBLE_BYTES					scalar		?, number of bytes w/o checksum
#	HEADER_BYTES					scalar		?
#	FIXED_LEADER_BYTES				scalar		42 for BB150; 53 for WH300, 58 for WH600, 59 for WH300(Nash)
#	VARIABLE_LEADER_BYTES			scalar		?
#	VELOCITY_DATA_BYTES				scalar		?
#	CORRELATION_DATA_BYTES			scalar		?
#	ECHO_INTENSITY_DATA_BYTES		scalar		?
#	PERCENT_GOOD_DATA_BYTES			scalar		?
#	BT_PRESENT						bool		NUMBER_OF_DATA_TYPES == 7
#	BT_DATA_BYTES					scalar		undefined, ? if BT_PRESENT
#	CPU_FW_VER						scalar		0--255
#	CPU_FW_REV						scalar		0--255
#	BEAM_FREQUENCY					scalar		75, 150, 300, 600, 1200, 2400 [kHz]
#	CONVEX_BEAM_PATTERN				bool		undefined, 1
#	CONCAVE_BEAM_PATTERN			bool		undefined, 1
#	SENSOR_CONFIG					scalar		1--3
#	XDUCER_HEAD_ATTACHED			bool		undefined, 1
#	BEAM_ANGLE						scalar		15,20,30,undefined=other [deg]
#	N_BEAMS							scalar		4--5
#	N_DEMODS						scalar		2--3(???),undefined=n/a
#	N_BINS							scalar		1--128
#	PINGS_PER_ENSEMBLE				scalar		0--16384
#	BIN_LENGTH						scalar		0.01--64 [m]
#	BLANKING_DISTANCE				scalar		0-99.99 [m]
#	MIN_CORRELATION					scalar		0--255
#	N_CODE_REPETITIONS				scalar		0--255
#	MIN_PERCENT_GOOD				scalar		1--100 [%]
#	MAX_ERROR_VELOCITY				scalar		0--5 [m/s]
#	TIME_BETWEEN_PINGS				scalar		0--? [s]
#	BEAM_COORDINATES				bool		undefined,1
#	INSTRUMENT_COORDINATES			bool		undefined,1
#	SHIP_COORDINATES				bool		undefined,1
#	EARTH_COORDINATES				bool		undefined,1
#	PITCH_AND_ROLL_USED				bool		undefined,1
#	USE_3_BEAM_ON_LOW_CORR			bool		undefined,1
#	BIN_MAPPING_ALLOWED				bool		undefined,1
#	HEADING_ALIGNMENT 				scalar		-179.99..180 [deg]
#	HEADING_BIAS			 		scalar		-179.99..180 [deg]
#	CALCULATE_SPEED_OF_SOUND		bool		undefined,1
#	USE_PRESSURE_SENSOR				bool		undefined,1
#	USE_COMPASS						bool		undefined,1
#	USE_PITCH_SENSOR				bool		undefined,1
#	USE_ROLL_SENSOR					bool		undefined,1
#	USE_CONDUCTIVITY_SENSOR			bool		undefined,1
#	USE_TEMPERATURE_SENSOR			bool		undefined,1
#	SPEED_OF_SOUND_CALCULATED		bool		undefined,1
#	PRESSURE_SENSOR_AVAILABLE		bool		undefined,1
#	COMPASS_AVAILABLE				bool		undefined,1
#	PITCH_SENSOR_AVAILABLE			bool		undefined,1
#	ROLL_SENSOR_AVAILABLE			bool		undefined,1
#	CONDUCTIVITY_SENSOR_AVAILABLE	bool		undefined,1
#	TEMPERATURE_SENSOR_AVAILABLE	bool		undefined,1
#	DISTANCE_TO_BIN1_CENTER			scalar		0--655.35 [m]
#	TRANSMITTED_PULSE_LENGTH		scalar		0--655.35 [m]
#	RL_FIRST_BIN					scalar		1--128
#	RL_LAST_BIN						scalar		1--128
#	FALSE_TARGET_THRESHOLD			scalar		0--254, undefined=disabled
#	LOW_LATENCY_SETTING				scalar		0--5(???)
#	TRANSMIT_LAG_DISTANCE			scalar		0--655.35 [m]
#	CPU_SERIAL_NUMBER				scalar		undefined, 0--65535 if WH300
#	NARROW_BANDWIDTH				bool		undefined,1 (only set if WH300)
#	WIDE_BANDWIDTH					bool		undefined,1 (only set if WH300)
#	TRANSMIT_POWER					scalar		undefined, 0--255(high) if WH300
#	TRANSMIT_POWER_HIGH				bool		undefined,1 (only set if WH300)
#	BT_PINGS_PER_ENSEMBLE			scalar		0--999
#	BT_DELAY_BEFORE_REACQUIRE		scalar		0--999
#	BT_MIN_CORRELATION				scalar		0--255
#	BT_MIN_EVAL_AMPLITUDE			scalar		0--255
#	BT_MIN_PERCENT_GOOD				scalar		0--100 [%]
#	BT_MODE							scalar		4,5,6(?)
#	BT_MAX_ERROR_VELOCITY			scalar		0--5 [m/s], undef=not screened
#	BT_RL_MIN_SIZE					scalar		0--99.9 [m]
#	BT_RL_NEAR						scalar		0--999.9 [m]
#	BT_RL_FAR						scalar		0--999.9 [m]
#	BT_MAX_TRACKING_DEPTH			scalar		8--999.9 [m]
#	ENSEMBLE[ensemble_no-1]			array		ensemble info
#		XDUCER_FACING_UP			bool		undefined, 1
#		XDUCER_FACING_DOWN			bool		undefined, 1
#		N_BEAMS_USED				scalar		3,4,5(?)
#		NUMBER						scalar		1--16777215
#		BUILT_IN_TEST_ERROR			scalar		?,undefined=none
#		SPEED_OF_SOUND				scalar		1400--1600 [m/s]
#		XDUCER_DEPTH				scalar		0.1--999.9 [m]
#		HEADING						scalar		0--359.99 [deg]    --- IMP EXTENSION: undef
#		PITCH						scalar		-20.00-20.00 [deg] --- IMP EXTENSION: undef
#		ROLL						scalar		-20.00-20.00 [deg] --- IMP EXTENSION: undef
#		SALINITY					scalar		0-40 [psu]
#		TEMPERATURE					scalar		-5.00--40.00 [deg]
#		MIN_PRE_PING_WAIT_TIME		scalar		? [s]
#		HEADING_STDDEV				scalar		0-180 [deg]
#		PITCH_STDDEV				scalar		0.0-20.0 [deg]
#		ROLL_STDDEV					scalar		0.0-20.0 [deg]
#		ADC_XMIT_CURRENT			scalar		0--255
#		ADC_XMIT_VOLTAGE			scalar		0--255
#		ADC_AMBIENT_TEMPERATURE		scalar		0--255
#		ADC_PRESSURE_PLUS			scalar		0--255
#		ADC_PRESSURE_MINUS			scalar		0--255
#		ADC_ATTITUDE_TEMPERATURE	scalar		0--255
#		ADC_ATTITUDE				scalar		0--255
#		ADC_CONTAMINATION			scalar		0--255
#		ERROR_STATUS_WORD			scalar		undefined, ? (only set if WH300)
#		PRESSURE					scalar		undefined, ?-? [dbar] (only set if WH300)
#		PRESSURE_STDDEV				scalar		undefined, ?-? [dbar] (only set if WH300)
#		DATE						string		MM/DD/YYYY
#		YEAR						scalar		?
#		MONTH						scalar		1--12
#		DAY							scalar		1--31
#		TIME						string		HH:MM:SS.hh
#		HOUR						scalar		0--23
#		MINUTE						scalar		0--59
#		SECONDS						scalar		0--59.99
#		UNIX_TIME					scalar		0--?
#		SECNO						scalar		0--? (number of seconds since daystart)
#		DAYNO						double		fractional day number since start of current year (1.0 is midnight Jan 1st)
#		VELOCITY[bin][beam]			scalars		-32.767--32.768 [m/s], undef=bad
#		CORRELATION[bin][beam]		scalars		1--255, undefined=bad
#		ECHO_AMPLITUDE[bin][beam]	scalars		0--255
#		PERCENT_GOOD[bin][beam]		scalars		0--255
#		BT_RANGE[beam]				scalars		tons [m]
#		BT_VELOCITY[beam]			scalars		see VELOCITY
#		BT_CORRELATION[beam]		scalars		see CORRELATION
#		BT_EVAL_AMPLITUDE[beam]		scalars		0--255
#		BT_PERCENT_GOOD[beam]		scalars		see PERCENT_GOOD
#		BT_RL_VELOCITY[beam]		scalars		see VELOCITY
#		BT_RL_CORRELATION[beam]		scalars		see CORRELATION
#		BT_RL_ECHO_AMPLITUDE[beam]	scalars		see ECHO_AMPLITUDE
#		BT_RL_PERCENT_GOOD[beam]	scalars		see PERCENT_GOOD
#		BT_SIGNAL_STRENGTH[beam]	scalars		0--255
#		HIGH_GAIN					bool		1, undefined
#		LOW_GAIN					bool		1, undefined

use strict;
use Time::Local;						# timegm()

#----------------------------------------------------------------------
# Time Conversion Subroutines
#----------------------------------------------------------------------

sub monthLength($$)										# of days in month
{
    my($Y,$M) = @_;

    return 31 if ($M==1 || $M==3 || $M==5 || $M==7 ||
                  $M==8 || $M==10 || $M==12);
    return 30 if ($M==4 || $M==6 || $M==9 || $M==11);
    return 28 if ($Y%4 != 0);
    return 29 if ($Y%100 != 0);
    return 28 if ($Y%400 > 0);
    return 29;
}

{ my($epoch,$lM,$lD,$lY,$ldn);							# static scope

  sub dayNo($$$$$$)
  {
	  my($Y,$M,$D,$h,$m,$s) = @_;
	  my($dn);
  
	  if ($Y==$lY && $M==$lM && $D==$lD) {				# same day as last samp
		  $dn = $ldn;
	  } else {											# new day
		  $epoch = $Y unless defined($epoch);			# 1st call
		  $lY = $Y; $lM = $M; $lD = $D;					# store
  
		  for ($dn=0,my($cY)=$epoch; $cY<$Y; $cY++) {	# multiple years
			  $dn += 337 + &monthLength($Y,$M);
		  }
  
		  $dn += $D;									# day in month
		  while (--$M > 0) {							# preceding months
			  $dn += &monthLength($Y,$M);
		  }

		  $ldn = $dn;									# store
	  }
	  return $dn + $h/24 + $m/24/60 + $s/24/3600;
  }

} # static scope

#----------------------------------------------------------------------
# Read Data
#----------------------------------------------------------------------

my($WBRcfn,$WBPcfn);									# current file names for reading/patching
my($BIT_errors) = 0;									# built-in-test errors

my($FmtErr) = "%s: illegal %s Id 0x%04x at ensemble %d";

#----------------------------------------------------------------------
# skip to first valid ensemble (skip over initial garbage)
#----------------------------------------------------------------------

sub skip_initial_trash(@)
{
	my($quiet) = @_;
	my($buf,$dta);

	my($found) = 0;										# zero consecutive 0x7f found
	my($skipped) = 0;
	while ($found < 2) {
		sysread(WBRF,$buf,1) == 1 || last;
		($dta) = unpack('C',$buf);
		if ($dta == 0x7f) {
			$found++;
		} elsif ($found == 0) {
			$skipped++;
		} else {
			$skipped += $found;
			$found = 0;
		}
	}
	die("$WBRcfn: no valid ensemble header found [$!]\n")
		if ($found < 2);
	printf(STDERR "WARNING: %d bytes of initial garbage\n",$skipped)
		if ($skipped > 0 && !$quiet);
	return sysseek(WBRF,-2,1);
}

#----------------------------------------------------------------------
# readHeader(file_name,^dta) WBRhdr(^data)
#	- read header data
#	- also includes some data from 1st ens
#----------------------------------------------------------------------

sub readHeader(@)
{
	my($fn,$dta) = @_;
	$WBRcfn = $fn;
    open(WBRF,$WBRcfn) || die("$WBRcfn: $!");
    WBRhdr($dta);    
}

sub WBRhdr($)
{
	my($dta) = @_;
	my($start_ens,$buf,$hid,$did,$Ndt,$B,$W,$i,$dummy,$id,@WBRofs);
	my($B1,$B2,$B3,$B4,$B5,$B6,$B7,$W1,$W2,$W3,$W4,$W5);
	
	#--------------------
	# HEADER
	#--------------------

	$start_ens = skip_initial_trash();
	sysread(WBRF,$buf,6) == 6 || die("$WBRcfn: $!");
	($hid,$did,$dta->{ENSEMBLE_BYTES},$dummy,$dta->{NUMBER_OF_DATA_TYPES})
		= unpack('CCvCC',$buf);
	$hid == 0x7f || die(sprintf($FmtErr,$WBRcfn,"Header",$hid,0));
	$dta->{DATA_SOURCE_ID} = $did;
	if ($did == 0x7f) {
		$dta->{PRODUCER} = 'TRDI ADCP';
	} elsif ($did&0xF0 == 0xA0) {
		$dta->{PRODUCER} = 'IMP+LADCP';
	} elsif ($did&0xF0 == 0xB0) {
		$dta->{PRODUCER} = 'editPD0';
	} else {
		$dta->{PRODUCER} = 'unknown';
	}

	printf(STDERR "WARNING: unexpected number of data types (%d)\n",
		$dta->{NUMBER_OF_DATA_TYPES})
			unless ($dta->{NUMBER_OF_DATA_TYPES} == 6 ||
					$dta->{NUMBER_OF_DATA_TYPES} == 7);
##	$dta->{BT_PRESENT} = ($dta->{NUMBER_OF_DATA_TYPES} == 7);
	$dta->{BT_PRESENT} = ($dta->{NUMBER_OF_DATA_TYPES} >= 7);
					  
	sysread(WBRF,$buf,2*$dta->{NUMBER_OF_DATA_TYPES})
		== 2*$dta->{NUMBER_OF_DATA_TYPES}
			|| die("$WBRcfn: $!");
	@WBRofs = unpack("v$dta->{NUMBER_OF_DATA_TYPES}",$buf);

	$dta->{HEADER_BYTES} 					= $WBRofs[0];
	$dta->{FIXED_LEADER_BYTES} 				= $WBRofs[1] - $WBRofs[0];
	$dta->{VARIABLE_LEADER_BYTES}			= $WBRofs[2] - $WBRofs[1];
	$dta->{VELOCITY_DATA_BYTES}				= $WBRofs[3] - $WBRofs[2];
	$dta->{CORRELATION_DATA_BYTES}			= $WBRofs[4] - $WBRofs[3];
	$dta->{ECHO_INTENSITY_DATA_BYTES}		= $WBRofs[5] - $WBRofs[4];
	if ($dta->{BT_PRESENT}) {
		$dta->{PERCENT_GOOD_DATA_BYTES}		= $WBRofs[6] - $WBRofs[5];
		$dta->{BT_DATA_BYTES}				= $dta->{ENSEMBLE_BYTES} - 4 - $WBRofs[6];
	} else {
		$dta->{PERCENT_GOOD_DATA_BYTES}		= $dta->{ENSEMBLE_BYTES} - 4 - $WBRofs[5];
	}

	if ($dta->{FIXED_LEADER_BYTES} == 42) {				# Eric Firing's old instrument I used in 2004
		$dta->{INSTRUMENT_TYPE} = 'BB150';
	} elsif ($dta->{FIXED_LEADER_BYTES} == 53) {		# old firmware: no serial numbers
		$dta->{INSTRUMENT_TYPE} = 'Workhorse';	
	} elsif ($dta->{FIXED_LEADER_BYTES} == 59) {		# new firmware: with serial numbers
		$dta->{INSTRUMENT_TYPE} = 'Workhorse';
    } elsif ($dta->{FIXED_LEADER_BYTES} == 58) {		# DVL
		$dta->{INSTRUMENT_TYPE} = 'Explorer';
    } 

#	for ($i=0; $i<$dta->{NUMBER_OF_DATA_TYPES}; $i++) {
#		printf(STDERR "\nWBRofs[$i] = %d",$WBRofs[$i]);
#	}

	#----------------------------------
	# Check Data Format of 1st Ensemble
	#----------------------------------

	sysseek(WBRF,$start_ens+$WBRofs[1],0) || die("$WBRcfn: $!");
	sysread(WBRF,$buf,2) == 2 || die("$WBRcfn: $!");
	$id = unpack('v',$buf);
	$id == 0x0080 || printf(STDERR $FmtErr."\n",$WBRcfn,"Variable Leader",$id,1);

	sysseek(WBRF,$start_ens+$WBRofs[2],0) || die("$WBRcfn: $!");
	sysread(WBRF,$buf,2) == 2 || die("$WBRcfn: $!");
	$id = unpack('v',$buf);
	$id == 0x0100 || printf(STDERR $FmtErr."\n",$WBRcfn,"Velocity Data",$id,1);

	sysseek(WBRF,$start_ens+$WBRofs[3],0) || die("$WBRcfn: $!");
	sysread(WBRF,$buf,2) == 2 || die("$WBRcfn: $!");
	$id = unpack('v',$buf);
	$id == 0x0200 || printf(STDERR $FmtErr."\n",$WBRcfn,"Correlation Data",$id,1);
    
	sysseek(WBRF,$start_ens+$WBRofs[4],0) || die("$WBRcfn: $!");
	sysread(WBRF,$buf,2) == 2 || die("$WBRcfn: $!");
	$id = unpack('v',$buf);
	$id == 0x0300 || printf(STDERR $FmtErr."\n",$WBRcfn,"Echo Intensity",$id,1);

	sysseek(WBRF,$start_ens+$WBRofs[5],0) || die("$WBRcfn: $!");
	sysread(WBRF,$buf,2) == 2 || die("$WBRcfn: $!");
	$id = unpack('v',$buf);
	$id == 0x0400 || printf(STDERR $FmtErr."\n",$WBRcfn,"Percent-Good Data",$id,1);

	my($BT_dt);
	if ($dta->{BT_PRESENT}) {
		for ($BT_dt=6; $BT_dt<$dta->{NUMBER_OF_DATA_TYPES}; $BT_dt++) {										# scan until BT found
			sysseek(WBRF,$start_ens+$WBRofs[$BT_dt],0) || die("$WBRcfn: $!");
			sysread(WBRF,$buf,2) == 2 || die("$WBRcfn: $!");
			$id = unpack('v',$buf);
			last if ($id == 0x0600);
		}

		if ($BT_dt == $dta->{NUMBER_OF_DATA_TYPES}) {
			printf(STDERR "WARNING: no BT data found\n");die;
			undef($dta->{BT_PRESENT});
		}
    }

	#--------------------
	# FIXED LEADER
	#--------------------

	sysseek(WBRF,$start_ens+$WBRofs[0],0) || die("$WBRcfn: $!");
	sysread(WBRF,$buf,42) == 42 || die("$WBRcfn: $!");
	($id,$dta->{CPU_FW_VER},$dta->{CPU_FW_REV},$B1,$B2,$dummy,$dummy,$dummy,
	 $dta->{N_BINS},$dta->{PINGS_PER_ENSEMBLE},$dta->{BIN_LENGTH},
	 $dta->{BLANKING_DISTANCE},$dummy,$dta->{MIN_CORRELATION},
	 $dta->{N_CODE_REPETITIONS},$dta->{MIN_PERCENT_GOOD},
	 $dta->{MAX_ERROR_VELOCITY},$dta->{TIME_BETWEEN_PINGS},$B3,$B4,$B5,
	 $dta->{HEADING_ALIGNMENT},$dta->{HEADING_BIAS},$B6,$B7,
	 $dta->{DISTANCE_TO_BIN1_CENTER},$dta->{TRANSMITTED_PULSE_LENGTH},
	 $dta->{REF_LAYER_FIRST_BIN},$dta->{REF_LAYER_LAST_BIN},
	 $dta->{FALSE_TARGET_THRESHOLD},$dta->{LOW_LATENCY_SETTING},
	 $dta->{TRANSMIT_LAG_DISTANCE}) =
		unpack('vCCCCC3CvvvCCCCvCCCCvvCCvvCCCCv',$buf);

	$id == 0x0000 || printf(STDERR $FmtErr."\n",$WBRcfn,"Fixed Leader",$id,0);

    $dta->{BEAM_FREQUENCY} = 2**($B1 & 0x07) * 75;
    $dta->{CONVEX_BEAM_PATTERN} = 1 if ($B1 & 0x08);
    $dta->{CONCAVE_BEAM_PATTERN} = 1 if (!($B1 & 0x08));
    $dta->{SENSOR_CONFIG} = ($B1 & 0x30) >> 4;
    $dta->{XDUCER_HEAD_ATTACHED} = 1 if ($B1 & 0x40);

	if	  (($B2 & 0x03) == 0x00) { $dta->{BEAM_ANGLE} = 15; }
	elsif (($B2 & 0x03) == 0x01) { $dta->{BEAM_ANGLE} = 20; }
	elsif (($B2 & 0x03) == 0x02) { $dta->{BEAM_ANGLE} = 30; }
	if	  (($B2 & 0xF0) == 0x40) { $dta->{N_BEAMS} = 4; }
	elsif (($B2 & 0xF0) == 0x50) { $dta->{N_BEAMS} = 5; $dta->{N_DEMODS} = 3; }
    elsif (($B2 & 0xF0) == 0xF0) { $dta->{N_BEAMS} = 5; $dta->{N_DEMODS} = 2; }
    
    $dta->{BIN_LENGTH} /= 100;
    $dta->{BLANKING_DISTANCE} /= 100;

    $dta->{MAX_ERROR_VELOCITY} /= 1000;
    $dta->{TIME_BETWEEN_PINGS} *= 60;
	$dta->{TIME_BETWEEN_PINGS} += $B3 + $B4/100;

	$dta->{BEAM_COORDINATES}		  = 1 if (($B5 & 0x18) == 0x00);
	$dta->{INSTRUMENT_COORDINATES}	  = 1 if (($B5 & 0x18) == 0x08);
	$dta->{SHIP_COORDINATES}		  = 1 if (($B5 & 0x18) == 0x10);
	$dta->{EARTH_COORDINATES}		  = 1 if (($B5 & 0x18) == 0x18);
	$dta->{PITCH_AND_ROLL_USED} 	  = 1 if ($B5 & 0x04);
	$dta->{USE_3_BEAM_ON_LOW_CORR}	  = 1 if ($B5 & 0x02);
    $dta->{BIN_MAPPING_ALLOWED}       = 1 if ($B5 & 0x01);
        
	$dta->{HEADING_ALIGNMENT} =
		($dta->{EARTH_COORDINATES} || $dta->{SHIP_COORDINATES}) ?
			$dta->{HEADING_ALIGNMENT} / 100 : undef;
	$dta->{HEADING_BIAS} =
		($dta->{EARTH_COORDINATES} || $dta->{SHIP_COORDINATES}) ?
			$dta->{HEADING_BIAS} / 100 : undef;

	$dta->{CALCULATE_SPEED_OF_SOUND}  = 1 if ($B6 & 0x40); 
	$dta->{USE_PRESSURE_SENSOR} 	  = 1 if ($B6 & 0x20); 
	$dta->{USE_COMPASS} 			  = 1 if ($B6 & 0x10); 
	$dta->{USE_PITCH_SENSOR}		  = 1 if ($B6 & 0x08); 
	$dta->{USE_ROLL_SENSOR} 		  = 1 if ($B6 & 0x04); 
	$dta->{USE_CONDUCTIVITY_SENSOR}   = 1 if ($B6 & 0x02); 
    $dta->{USE_TEMPERATURE_SENSOR}    = 1 if ($B6 & 0x01); 

	$dta->{SPEED_OF_SOUND_CALCULATED}	  = 1 if ($B7 & 0x40); 
	$dta->{PRESSURE_SENSOR_AVAILABLE}	  = 1 if ($B7 & 0x20); 
	$dta->{COMPASS_AVAILABLE}			  = 1 if ($B7 & 0x10); 
	$dta->{PITCH_SENSOR_AVAILABLE}		  = 1 if ($B7 & 0x08); 
	$dta->{ROLL_SENSOR_AVAILABLE}		  = 1 if ($B7 & 0x04); 
	$dta->{CONDUCTIVITY_SENSOR_AVAILABLE} = 1 if ($B7 & 0x02); 
    $dta->{TEMPERATURE_SENSOR_AVAILABLE}  = 1 if ($B7 & 0x01); 

    $dta->{DISTANCE_TO_BIN1_CENTER}  /= 100;
    $dta->{TRANSMITTED_PULSE_LENGTH} /= 100;

    $dta->{FALSE_TARGET_THRESHOLD} = undef
		if ($dta->{FALSE_TARGET_THRESHOLD} == 255);
    $dta->{TRANSMIT_LAG_DISTANCE} /= 100;

	if ($dta->{INSTRUMENT_TYPE} eq 'Workhorse') {
		sysread(WBRF,$buf,11) == 11 || die("$WBRcfn: $!");
		($W1,$W2,$W3,$W4,$W5,$dta->{TRANSMIT_POWER}) = 
			unpack('vvvvvC',$buf);

		$dta->{CPU_SERIAL_NUMBER} = sprintf("%04X%04X%04X%04X",$W1,$W2,$W3,$W4);
	
		$dta->{NARROW_BANDWIDTH} = ($W5 == 1);
		$dta->{WIDE_BANDWIDTH}	 = ($W5 == 0);
	    $dta->{TRANSMIT_POWER_HIGH} = ($dta->{TRANSMIT_POWER} == 255);

		if ($dta->{FIXED_LEADER_BYTES} == 59) {					# new style with serial number
			sysread(WBRF,$buf,6) == 6 || die("$WBRcfn: $!");
			($dummy,$dta->{SERIAL_NUMBER},$dummy) =				# last bytes is beam angle, but that info has
				unpack('CVC',$buf);								# already been provided above
		}
    }

	if ($dta->{INSTRUMENT_TYPE} eq 'Explorer') {
		sysread(WBRF,$buf,16) == 16 || die("$WBRcfn: $!");
		($dummy,$dummy,$W5,$dummy,$dta->{SERIAL_NUMBER}) = 
			unpack('VVvvV',$buf);
		$dta->{NARROW_BANDWIDTH} = ($W5 == 1);
		$dta->{WIDE_BANDWIDTH}	 = ($W5 == 0);
    }

	#-----------------------
	# 1st ENSEMBLE, BT Setup
	#-----------------------

	if ($dta->{BT_PRESENT}) {
		sysseek(WBRF,$start_ens+$WBRofs[$BT_dt],0) || die("$WBRcfn: $!");
		sysread(WBRF,$buf,12) == 12 || die("$WBRcfn: $!");
		($id,$dta->{BT_PINGS_PER_ENSEMBLE},$dta->{BT_DELAY_BEFORE_REACQUIRE},
		 $dta->{BT_MIN_CORRELATION},$dta->{BT_MIN_EVAL_AMPLITUDE},
		 $dta->{BT_MIN_PERCENT_GOOD},$dta->{BT_MODE},
		 $dta->{BT_MAX_ERROR_VELOCITY}) = unpack('vvvCCCCv',$buf);
		 
		$id == 0x0600 ||
			printf(STDERR $FmtErr."\n",$WBRcfn,"Bottom Track",$id,0,tell(WBRF));
	
		$dta->{BT_MAX_ERROR_VELOCITY} =
			$dta->{BT_MAX_ERROR_VELOCITY} ? $dta->{BT_MAX_ERROR_VELOCITY} / 1000
										  : undef;
	
		sysseek(WBRF,28,1) || die("$WBRcfn: $!");
		sysread(WBRF,$buf,6) == 6 || die("$WBRcfn: $!");
		($dta->{BT_RL_MIN_SIZE},$dta->{BT_RL_NEAR},$dta->{BT_RL_FAR})
			= unpack('vvv',$buf);
	
		$dta->{BT_RL_MIN_SIZE} /= 10;
		$dta->{BT_RL_NEAR} /= 10;
		$dta->{BT_RL_FAR} /= 10;
	    
		sysseek(WBRF,20,1) || die("$WBRcfn: $!");		# skip data
		sysread(WBRF,$buf,2) == 2 || die("$WBRcfn: $!");
	    $dta->{BT_MAX_TRACKING_DEPTH} = unpack('v',$buf) / 10;
    }
    
    return $dta;
}

#----------------------------------------------------------------------
# readData(file_name,^data) WBRens(nbins,fixed_leader_bytes,^data)
# 	- read all ensembles
#----------------------------------------------------------------------

sub readData(@)
{
	my($fn,$dta) = @_;
	$WBRcfn = $fn;
    open(WBRF,$WBRcfn) || die("$WBRcfn: $!");
    WBRhdr($dta);
	WBRens($dta->{N_BINS},$dta->{FIXED_LEADER_BYTES},
		   \@{$dta->{ENSEMBLE}});
	print(STDERR "$WBRcfn: $BIT_errors built-in-test errors\n")
		if ($BIT_errors);
}

sub WBRens($$$)
{
	my($nbins,$fixed_leader_bytes,$E) = @_;
	my($start_ens,$B1,$B2,$B3,$B4,$I,$id,$bin,$beam,$buf,$dummy,@dta,$i,$cs,@WBRofs);
	my($ens,$ensNo,$dayStart,$ens_length,$hid,$did,$ndt);

    sysseek(WBRF,0,0) || die("$WBRcfn: $!");
	$start_ens = skip_initial_trash(1);
	for ($ens=0; 1; $ens++,$start_ens+=$ens_length+2) {
#		print(STDERR "ens = $ens\n");
#		print(STDERR "start_ens = $start_ens\n");

		#----------------------------------------
		# Get ensemble length and # of data types 
		#----------------------------------------

		sysseek(WBRF,$start_ens,0) || die("$WBRcfn: $!");
		sysread(WBRF,$buf,6) == 6 || last;
		($hid,$did,$ens_length,$dummy,$ndt) = unpack('CCvCC',$buf);
		$hid == 0x7f || die(sprintf($FmtErr,$WBRcfn,"Header",$hid,0));
		${$E}[$ens]->{DATA_SOURCE_ID} = $did;
		if ($did == 0x7f) {
			${$E}[$ens]->{PRODUCER} = 'TRDI ADCP';
		} elsif ($did&0xF0 == 0xA0) {
			${$E}[$ens]->{PRODUCER} = 'IMP+LADCP (Thurnherr software)';
		} elsif ($did&0xF0 == 0xB0) {
			${$E}[$ens]->{PRODUCER} = 'editPD0 (Thurnherr software)';
		} else {
			${$E}[$ens]->{PRODUCER} = 'unknown';
	    }

##		printf(STDERR "\n$WBRcfn: WARNING: unexpected number of data types (%d, ens=$ens)\n",$ndt),last
##				unless ($ndt == 6 || $ndt == 7);
		sysread(WBRF,$buf,2*$ndt) == 2*$ndt || die("$WBRcfn: $!");
		@WBRofs = unpack("v$ndt",$buf);
		$fixed_leader_bytes = $WBRofs[1] - $WBRofs[0];
#		print(STDERR "@WBRofs\n");
	
		#-------------------------------
		# Make Sure Ensemble is Complete
		#-------------------------------

		# UH BB150 writes incomplete ensembles (i.e. short read
		# indicates EOF). FSU WH300 has bogus data in incomplete
		# final ensemble.

		sysseek(WBRF,$start_ens,0) || die("$WBRcfn: $!");
		sysread(WBRF,$buf,$ens_length) == $ens_length || last;

		sysread(WBRF,$cs,2) == 2 || last;
		last unless (unpack('%16C*',$buf) == unpack('v',$cs));

		#------------------------------
		# Variable Leader
		#------------------------------
	
		sysseek(WBRF,$start_ens+$WBRofs[1],0) || die("$WBRcfn: $!");
		sysread(WBRF,$buf,4) == 4 || die("$WBRcfn: $!");
		($id,$ensNo) = unpack("vv",$buf);

		$id == 0x0080 ||
			die(sprintf($FmtErr,$WBRcfn,"Variable Leader",$id,$ensNo+1));

		if ($fixed_leader_bytes==42 || $fixed_leader_bytes==58) {			# BB150 & Explorer DVL
			sysread(WBRF,$buf,7) == 7 || die("$WBRcfn: $!");
			(${$E}[$ens]->{YEAR},${$E}[$ens]->{MONTH},
			 ${$E}[$ens]->{DAY},${$E}[$ens]->{HOUR},${$E}[$ens]->{MINUTE},
			 ${$E}[$ens]->{SECONDS},$B4) = unpack('CCCCCCC',$buf);
			${$E}[$ens]->{SECONDS} += $B4/100;
			${$E}[$ens]->{YEAR} += (${$E}[$ens]->{YEAR} > 80) ? 1900 : 2000;
		} else {
			sysseek(WBRF,7,1) || die("$WBRcfn: $!");							# use Y2K RTC instead
		}

		sysread(WBRF,$buf,1) == 1 || die("$WBRcfn: $!");
		$ensNo += unpack('C',$buf) << 16;
		${$E}[$ens]->{NUMBER} = $ensNo;
		
		sysread(WBRF,$buf,30) == 30 || die("$WBRcfn: $!");
		(${$E}[$ens]->{BUILT_IN_TEST_ERROR},${$E}[$ens]->{SPEED_OF_SOUND},
		 ${$E}[$ens]->{XDUCER_DEPTH},${$E}[$ens]->{HEADING},
		 ${$E}[$ens]->{PITCH},${$E}[$ens]->{ROLL},
		 ${$E}[$ens]->{SALINITY},${$E}[$ens]->{TEMPERATURE},
		 ${$E}[$ens]->{MIN_PRE_PING_WAIT_TIME},$B1,$B2,
		 ${$E}[$ens]->{HEADING_STDDEV},${$E}[$ens]->{PITCH_STDDEV},
		 ${$E}[$ens]->{ROLL_STDDEV},${$E}[$ens]->{ADC_XMIT_CURRENT},
		 ${$E}[$ens]->{ADC_XMIT_VOLTAGE},${$E}[$ens]->{ADC_AMBIENT_TEMPERATURE},
		 ${$E}[$ens]->{ADC_PRESSURE_PLUS},${$E}[$ens]->{ADC_PRESSURE_MINUS},
		 ${$E}[$ens]->{ADC_ATTITUDE_TEMPERATURE},${$E}[$ens]->{ADC_ATTITUDE},
		 ${$E}[$ens]->{ADC_CONTAMINATION})
			= unpack('vvvvvvvvCCCCCCCCCCCCCC',$buf);

		${$E}[$ens]->{BUILT_IN_TEST_ERROR} = undef
			unless (${$E}[$ens]->{BUILT_IN_TEST_ERROR});
		$BIT_errors++ if (${$E}[$ens]->{BUILT_IN_TEST_ERROR});

		${$E}[$ens]->{XDUCER_DEPTH} /= 10;

		#-------------------------------------------------
		# IMP EXTENSION: PITCH/ROLL/HEADING CAN BE MISSING
		#-------------------------------------------------
		
		${$E}[$ens]->{HEADING} = (${$E}[$ens]->{HEADING} == 0xF000)
							   ? undef
							   : ${$E}[$ens]->{HEADING} / 100;
		${$E}[$ens]->{PITCH} = (${$E}[$ens]->{PITCH} == 0x8000)
							 ? undef
							 : unpack('s',pack('S',${$E}[$ens]->{PITCH})) / 100;
		${$E}[$ens]->{ROLL}  = (${$E}[$ens]->{ROLL} == 0x8000)
                             ? undef
                             : unpack('s',pack('S',${$E}[$ens]->{ROLL})) / 100;
                             
		${$E}[$ens]->{TEMPERATURE} = unpack('s',pack('S',${$E}[$ens]->{TEMPERATURE})) / 100;
		${$E}[$ens]->{MIN_PRE_PING_WAIT_TIME} *= 60;
		${$E}[$ens]->{MIN_PRE_PING_WAIT_TIME} += $B1 + $B2/100;
		${$E}[$ens]->{PITCH_STDDEV} /= 10;
		${$E}[$ens]->{ROLL_STDDEV} /= 10;

		if ($fixed_leader_bytes==53 || $fixed_leader_bytes==59) {			# Workhorse instruments
			sysread(WBRF,$buf,23) == 23 || die("$WBRcfn: $!");
			(${$E}[$ens]->{ERROR_STATUS_WORD},
		 	 $dummy,${$E}[$ens]->{PRESSURE},${$E}[$ens]->{PRESSURE_STDDEV},
			 $dummy,${$E}[$ens]->{YEAR},$B3,${$E}[$ens]->{MONTH},
			 ${$E}[$ens]->{DAY},${$E}[$ens]->{HOUR},${$E}[$ens]->{MINUTE},
			 ${$E}[$ens]->{SECONDS},$B4)
				= unpack('VvVVCCCCCCCCC',$buf);

			${$E}[$ens]->{PRESSURE} /= 1000;
			${$E}[$ens]->{PRESSURE_STDDEV} /= 1000;
			${$E}[$ens]->{YEAR} *= 100; ${$E}[$ens]->{YEAR} += $B3;
			${$E}[$ens]->{SECONDS} += $B4/100;
		}

		pop(@{$E}),last if (${$E}[$ens]->{MONTH}>12);						# 10/15/2014; IWISE#145 UL ???

		if ($fixed_leader_bytes == 58) {									# Explorer DVL
			sysread(WBRF,$buf,14) == 14 || die("$WBRcfn: $!");
			(${$E}[$ens]->{ERROR_STATUS_WORD},
		 	 $dummy,${$E}[$ens]->{PRESSURE},${$E}[$ens]->{PRESSURE_STDDEV})
				= unpack('VvVV',$buf);
			${$E}[$ens]->{PRESSURE} /= 1000;
			${$E}[$ens]->{PRESSURE_STDDEV} /= 1000;
		}
		
		${$E}[$ens]->{DATE}
			= sprintf("%02d/%02d/%d",${$E}[$ens]->{MONTH},
									 ${$E}[$ens]->{DAY},
									 ${$E}[$ens]->{YEAR});
		${$E}[$ens]->{TIME}
			= sprintf("%02d:%02d:%05.02f",${$E}[$ens]->{HOUR},
										  ${$E}[$ens]->{MINUTE},
									 	  ${$E}[$ens]->{SECONDS});
		${$E}[$ens]->{DAYNO}
			= &dayNo(${$E}[$ens]->{YEAR},${$E}[$ens]->{MONTH},${$E}[$ens]->{DAY},
					 ${$E}[$ens]->{HOUR},${$E}[$ens]->{MINUTE},${$E}[$ens]->{SECONDS});

		# when analyzing an STA file from an OS75 SADCP (Poseidion),
		# I noticed that there is no time information. This causes
		# timegm to bomb. 
		if (${$E}[$ens]->{MONTH} == 0) {					# no time info
			${$E}[$ens]->{UNIX_TIME} = 0;
			${$E}[$ens]->{SECNO} = 0;
        } else {
			${$E}[$ens]->{UNIX_TIME}
				= timegm(0,${$E}[$ens]->{MINUTE},
						   ${$E}[$ens]->{HOUR},
						   ${$E}[$ens]->{DAY},
						   ${$E}[$ens]->{MONTH}-1,			# timegm jan==0!!!
						   ${$E}[$ens]->{YEAR})
				  + ${$E}[$ens]->{SECONDS};
	
			$dayStart = timegm(0,0,0,${$E}[$ens]->{DAY},
									 ${$E}[$ens]->{MONTH}-1,
									 ${$E}[$ens]->{YEAR})
				unless defined($dayStart);
	        ${$E}[$ens]->{SECNO} = ${$E}[$ens]->{UNIX_TIME} - $dayStart;
        }

		sysseek(WBRF,$start_ens+$WBRofs[0]+4,0)		# System Config / Fixed Leader
			|| die("$WBRcfn: $!");

		sysread(WBRF,$buf,5) == 5 || die("$WBRcfn: $!");
		($B1,$dummy,$dummy,$dummy,${$E}[$ens]->{N_BEAMS_USED})
			= unpack('CCCCC',$buf);		
		${$E}[$ens]->{XDUCER_FACING_UP}   = 1 if     ($B1 & 0x80);
		${$E}[$ens]->{XDUCER_FACING_DOWN} = 1 unless ($B1 & 0x80);

		#--------------------
		# Velocity Data
		#--------------------

		my($ndata) = $nbins * 4;

		sysseek(WBRF,$start_ens+$WBRofs[2],0) || die("$WBRcfn: $!");
		sysread(WBRF,$buf,2+$ndata*2) == 2+$ndata*2 || die("$WBRcfn: $!");
		($id,@dta) = unpack("vv$ndata",$buf);

		$id == 0x0100 ||
			die(sprintf($FmtErr,$WBRcfn,"Velocity Data",$id,$ens));
		
		for ($i=0,$bin=0; $bin<$nbins; $bin++) {
			for ($beam=0; $beam<4; $beam++,$i++) {
				${$E}[$ens]->{VELOCITY}[$bin][$beam] =
					unpack('s',pack('S',$dta[$i])) / 1000
						if ($dta[$i] != 0x8000);
			}
		}

		#--------------------
		# Correlation Data
		#--------------------

		sysseek(WBRF,$start_ens+$WBRofs[3],0) || die("$WBRcfn: $!");
		sysread(WBRF,$buf,2+$ndata) == 2+$ndata || die("$WBRcfn: $!");
		($id,@dta) = unpack("vC$ndata",$buf);

		$id == 0x0200 ||
			die(sprintf($FmtErr,$WBRcfn,"Correlation Data",$id,$ens));
		
		for ($i=0,$bin=0; $bin<$nbins; $bin++) {
			for ($beam=0; $beam<4; $beam++,$i++) {
				${$E}[$ens]->{CORRELATION}[$bin][$beam] = $dta[$i]
					if ($dta[$i]);
			}
		}

		#--------------------
		# Echo Intensity Data
		#--------------------

		sysseek(WBRF,$start_ens+$WBRofs[4],0) || die("$WBRcfn: $!");
		sysread(WBRF,$buf,2+$ndata) == 2+$ndata || die("$WBRcfn: $!");
		($id,@dta) = unpack("vC$ndata",$buf);

		$id == 0x0300 ||
			die(sprintf($FmtErr,$WBRcfn,"Echo Intensity",$id,$ens));

		for ($i=0,$bin=0; $bin<$nbins; $bin++) {
			for ($beam=0; $beam<4; $beam++,$i++) {
				${$E}[$ens]->{ECHO_AMPLITUDE}[$bin][$beam] = $dta[$i];
			}
		}

		#--------------------
		# Percent Good Data
		#--------------------

		sysseek(WBRF,$start_ens+$WBRofs[5],0) || die("$WBRcfn: $!");
		sysread(WBRF,$buf,2+$ndata) == 2+$ndata || die("$WBRcfn: $!");
		($id,@dta) = unpack("vC$ndata",$buf);

		$id == 0x0400 ||
			die(sprintf($FmtErr,$WBRcfn,"Percent-Good Data",$id,$ens));

		for ($i=0,$bin=0; $bin<$nbins; $bin++) {
#			printf(STDERR "%-GOOD($bin): ");
			for ($beam=0; $beam<4; $beam++,$i++) {
#				printf(STDERR "$dta[$i] ");
				${$E}[$ens]->{PERCENT_GOOD}[$bin][$beam] = $dta[$i];
			}
#			printf(STDERR "\n");
		}

		#-----------------------------------------
		# Bottom-Track Data
		#	- scan through remaining data types
		#-----------------------------------------

		my($nxt);
		for ($nxt=6; $nxt<$ndt; $nxt++) {										# scan until BT found
			sysseek(WBRF,$start_ens+$WBRofs[$nxt],0) || die("$WBRcfn: $!");
			sysread(WBRF,$buf,2) == 2 || die("$WBRcfn: $!");
			$id = unpack('v',$buf);
			last if ($id == 0x0600);
		}

		next if ($nxt == $ndt);													# no BT found => next ens

		sysseek(WBRF,14,1) || die("$WBRcfn: $!");								# BT config

		sysread(WBRF,$buf,28) == 28 || die("$WBRcfn: $!");
		@dta = unpack('v4v4C4C4C4',$buf);
	    
		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_RANGE}[$beam] = $dta[$beam] / 100
					if ($dta[$beam]);
		}
		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_VELOCITY}[$beam] =
				unpack('s',pack('S',$dta[4+$beam])) / 1000
					if ($dta[4+$beam] != 0x8000);
		}
		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_CORRELATION}[$beam] = $dta[8+$beam]
				if ($dta[8+$beam]);
		}
		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_EVAL_AMPLITUDE}[$beam] = $dta[12+$beam];
		}
		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_PERCENT_GOOD}[$beam] = $dta[16+$beam];
		}

		sysseek(WBRF,6,1) || die("$WBRcfn: $!");		# BT config

		sysread(WBRF,$buf,20) == 20 || die("$WBRcfn: $!");
		@dta = unpack('v4C4C4C4',$buf);

		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_RL_VELOCITY}[$beam] =
				unpack('s',pack('S',$dta[$beam])) / 1000
					if ($dta[$beam] != 0x8000);
		}
		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_RL_CORRELATION}[$beam] = $dta[4+$beam]
				if ($dta[4+$beam]);
		}
		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_RL_ECHO_AMPLITUDE}[$beam] = $dta[8+$beam];
		}
		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_RL_PERCENT_GOOD}[$beam] = $dta[12+$beam];
		}

		sysseek(WBRF,2,1) || die("$WBRcfn: $!");		# BT config

		sysread(WBRF,$buf,9) == 9 || die("$WBRcfn: $!");
		@dta = unpack('C4CC4',$buf);

		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_SIGNAL_STRENGTH}[$beam] = $dta[$beam];
		}
		${$E}[$ens]->{HIGH_GAIN} if    ($dta[4]);
		${$E}[$ens]->{LOW_GAIN} unless ($dta[4]);
		for ($beam=0; $beam<4; $beam++) {
			${$E}[$ens]->{BT_RANGE}[$beam] += $dta[5+$beam] * 655.36
				if ($dta[5+$beam]);
		}
	} # ens loop
}

#----------------------------------------------------------------------
# writeData(output_file_name,^data) WBPens(nbins,fixed_leader_bytes,^data)
#	- writeData() copies file previously read with readData() to output_file_name
# 	- WBPens() patches new PD0 file with ^data
#		- ^data is modified!!!!
#		- output file must already exist and have correct structure
#		- only subset of data structure is patched:
#			- Header: Data Source Id
#			- Var Ldr: Soundspeed, Depth, Heading, Pitch, Roll, Temp, Salin
#			- Data: Velocity, Correlation, Echo Amp, %-Good, 
#----------------------------------------------------------------------

sub writeData(@)
{
	my($fn,$dta) = @_;

	die("writeData() needs \$WBRcfn from previous readData()")
		unless (-r $WBRcfn);
	$WBPcfn = $fn;
	system("cp $WBRcfn $WBPcfn");

	open(WBPF,"+<$WBPcfn") || die("$WBPcfn: $!");
    WBPens($dta->{N_BINS},$dta->{FIXED_LEADER_BYTES},
	                   \@{$dta->{ENSEMBLE}});
}

sub round(@)
{
	return $_[0] >= 0 ? int($_[0] + 0.5)
					  : int($_[0] - 0.5);
}


sub WBPens($$$)
{
	my($nbins,$fixed_leader_bytes,$E) = @_;
	my($start_ens,$B1,$B2,$B3,$B4,$I,$id,$bin,$beam,$buf,$dummy,@dta,$i,$cs,@WBPofs);
	my($ens,$ensNo,$dayStart,$ens_length,$hid,$ndt);

	for ($ens=$start_ens=0; $ens<=$#{$E}; $ens++,$start_ens+=$ens_length+2) {

		#------------------------------
		# Patch Header (Data Source Id)
		#------------------------------

		sysseek(WBPF,$start_ens,0) || die("$WBPcfn: $!");
		sysread(WBPF,$buf,1) || die("$WBPcfn: unexpected EOF");
		($hid) = unpack('C',$buf);
		$hid == 0x7f || die(sprintf($FmtErr,$WBPcfn,"Header",$hid,$ens));

		$buf = pack('C',${$E}[$ens]->{DATA_SOURCE_ID});
		my($nw) = syswrite(WBPF,$buf,1);
		$nw == 1 || die("$WBPcfn: $nw bytes written ($!)");

		sysread(WBPF,$buf,4) == 4 || die("$WBPcfn: unexpected EOF");
		($ens_length,$dummy,$ndt) = unpack('vCC',$buf);
		printf(STDERR "\n$WBPcfn: WARNING: unexpected number of data types (%d, ens=$ens)\n",$ndt),last
				unless ($ndt == 6 || $ndt == 7);

		sysread(WBPF,$buf,2*$ndt) == 2*$ndt || die("$WBPcfn: $!");
		@WBPofs = unpack("v$ndt",$buf);
		$fixed_leader_bytes = $WBPofs[1] - $WBPofs[0];
	
		#------------------------------
		# Variable Leader
		#------------------------------
	
		sysseek(WBPF,$start_ens+$WBPofs[1]+12,0) || die("$WBPcfn: $!");
		
		${$E}[$ens]->{XDUCER_DEPTH} = round(${$E}[$ens]->{XDUCER_DEPTH}*10);

		#-----------------------------
		# IMP allows for missing value
		#-----------------------------

		${$E}[$ens]->{HEADING} = defined(${$E}[$ens]->{HEADING})
							   ? round(${$E}[$ens]->{HEADING}*100)
							   : 0xF000;
		${$E}[$ens]->{PITCH} = defined(${$E}[$ens]->{PITCH})
							 ? unpack('S',pack('s',round(${$E}[$ens]->{PITCH}*100)))
							 : 0x8000;
		${$E}[$ens]->{ROLL} = defined(${$E}[$ens]->{ROLL})
						    ? unpack('S',pack('s',round(${$E}[$ens]->{ROLL}*100)))
						    : 0x8000;

		${$E}[$ens]->{TEMPERATURE} =
			unpack('S',pack('s',round(${$E}[$ens]->{TEMPERATURE}*100)));

		sysseek(WBPF,2,1);			# skip built-in test which reads as 0 but is usually undef		
									# this was found not to matter, but there is no reason to edit
#		my($b1);					# this field
#		sysread(WBPF,$b1,14);
#		sysseek(WBPF,-14,1);
#		my($sos,$xd,$hdg,$pit,$rol,$sal,$tem) = unpack('vvvvvvv',$b1);

		$buf = pack('vvvvvvv',
			 ${$E}[$ens]->{SPEED_OF_SOUND},
			 ${$E}[$ens]->{XDUCER_DEPTH},${$E}[$ens]->{HEADING},
			 ${$E}[$ens]->{PITCH},${$E}[$ens]->{ROLL},
			 ${$E}[$ens]->{SALINITY},${$E}[$ens]->{TEMPERATURE});

		my($nw) = syswrite(WBPF,$buf,14);
		$nw == 14 || die("$WBPcfn: $nw bytes written ($!)");


		#--------------------
		# Velocity Data
		#--------------------

		sysseek(WBPF,$start_ens+$WBPofs[2]+2,0) || die("$WBRcfn: $!");	# skip velocity data id (assume it is correct)
		for ($bin=0; $bin<$nbins; $bin++) {
			for ($beam=0; $beam<4; $beam++) {
				${$E}[$ens]->{VELOCITY}[$bin][$beam] = defined(${$E}[$ens]->{VELOCITY}[$bin][$beam])
							   						 ? round(${$E}[$ens]->{VELOCITY}[$bin][$beam]*1000)
							   						 : 0x8000;
				$buf = pack('v',unpack('S',pack('s',${$E}[$ens]->{VELOCITY}[$bin][$beam])));
				my($nw) = syswrite(WBPF,$buf,2);
				$nw == 2 || die("$WBPcfn: $nw bytes written ($!)");
			}
		}

		#--------------------
		# Correlation Data
		#--------------------

		sysseek(WBPF,$start_ens+$WBPofs[3]+2,0) || die("$WBRcfn: $!");
		for ($bin=0; $bin<$nbins; $bin++) {
			for ($beam=0; $beam<4; $beam++) {
				$buf = pack('C',${$E}[$ens]->{CORRELATION}[$bin][$beam]);
				my($nw) = syswrite(WBPF,$buf,1);
				$nw == 1 || die("$WBPcfn: $nw bytes written ($!)");
			}
		}

		#--------------------
		# Echo Intensity Data
		#--------------------

		sysseek(WBPF,$start_ens+$WBPofs[4]+2,0) || die("$WBRcfn: $!");

		for ($bin=0; $bin<$nbins; $bin++) {
			for ($beam=0; $beam<4; $beam++) {
				$buf = pack('C',${$E}[$ens]->{ECHO_AMPLITUDE}[$bin][$beam]);
				my($nw) = syswrite(WBPF,$buf,1);
				$nw == 1 || die("$WBPcfn: $nw bytes written ($!)");
			}
		}

		#--------------------
		# Percent Good Data
		#--------------------

		sysseek(WBPF,$start_ens+$WBPofs[5]+2,0) || die("$WBRcfn: $!");

		for ($i=0,$bin=0; $bin<$nbins; $bin++) {
			for ($beam=0; $beam<4; $beam++,$i++) {
				$buf = pack('C',${$E}[$ens]->{PERCENT_GOOD}[$bin][$beam]);
				my($nw) = syswrite(WBPF,$buf,1);
				$nw == 1 || die("$WBPcfn: $nw bytes written ($!)");
			}
		}

		#-----------------------------------------
		# Bottom-Track Data
		#	- scan through remaining data types
		#-----------------------------------------

		my($nxt);
		for ($nxt=6; $nxt<$ndt; $nxt++) {										# scan until BT found
			sysseek(WBPF,$start_ens+$WBPofs[$nxt],0) || die("$WBRcfn: $!");
			sysread(WBPF,$buf,2) == 2 || die("$WBRcfn: $!");
			$id = unpack('v',$buf);
			last if ($id == 0x0600);
		}

		unless ($nxt == $ndt) {													# BT found
			sysseek(WBPF,14,1) || die("$WBRcfn: $!");							# skip BT config
			# NOT YET IMPLEMENTED
		}


		#----------------
		# Update Checksum
		#----------------

		sysseek(WBPF,$start_ens,0) || die("$WBPcfn: $!");
		sysread(WBPF,$buf,$ens_length) == $ens_length || die("$WBPcfn: $!");
		$cs = unpack('%16C*',$buf);
		$buf = pack('v',$cs);
		$nw = syswrite(WBPF,$buf,2);
		$nw == 2 || die("$WBPcfn: $nw bytes written, ens=$ens ($!)");

	} # ens loop
}

1;      # return true for all the world to see
