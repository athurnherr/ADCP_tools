#======================================================================
#                    W O R K H O R S E U T I L S . P L 
#                    doc: Wed Feb 12 10:21:32 2003
#                    dlm: Sun May 23 16:32:37 2010
#                    (c) 2003 A.M. Thurnherr
#                    uE-Info: 142 42 NIL 0 0 72 2 2 4 NIL ofnI
#======================================================================

# miscellaneous Workhorse-specific utilities

# History:
#	Feb 12, 2003: - created
#	Feb 14, 2003: - added check for short (bad) data files
#	Feb 26, 2004: - added Earth-coordinate support
#				  - added ensure_BT_RANGE()
#	Mar 17, 2004: - set bad BT ranges to undef in ensure_BT_RANGE
#				  - calc mean/stddev in ensure_BT_RANGE
#	Mar 20, 2004: - BUG: find_seabed() could bomb when not enough
#					bottom guesses passed the mode_width test
#	Mar 30, 2004: - added &soundSpeed()
#	Nov  8, 2005: - WATER_DEPTH => Z_BT
#	May 23, 2010: - Z* -> DEPTH*

use strict;

#======================================================================
# fake_BT_RANGE(dta ptr)
#======================================================================

# During cruise NBP0204 it was found that one of Visbeck's RDIs consistently
# returns zero as the bottom-track range, even thought the BT velocities
# are good. This functions calculates the ranges if they are missing.

sub cBTR($$$)
{
	my($d,$e,$b) = @_;
	my($maxamp) = -9e99;
	my($maxi);

	for (my($i)=0; $i<$d->{N_BINS}; $i++) {
		next unless ($d->{ENSEMBLE}[$e]->{ECHO_AMPLITUDE}[$i][$b] > $maxamp);
		$maxamp = $d->{ENSEMBLE}[$e]->{ECHO_AMPLITUDE}[$i][$b];
		$maxi = $i;
	}
	$d->{ENSEMBLE}[$e]->{BT_RANGE}[$b] =
		$d->{DISTANCE_TO_BIN1_CENTER} + $maxi * $d->{BIN_LENGTH};
}

sub ensure_BT_RANGE($)
{
	my($d) = @_;
	for (my($e)=0; $e<=$#{$d->{ENSEMBLE}}; $e++) {
		my($sum) = my($n) = 0;
		if (defined($d->{ENSEMBLE}[$e]->{BT_VELOCITY}[0])) {
			for (my($b)=0; $b<4; $b++) {
				cBTR($d,$e,$b)
					unless defined($d->{ENSEMBLE}[$e]->{BT_RANGE}[$b]);
				$sum += $d->{ENSEMBLE}[$e]->{BT_RANGE}[$b]; $n++;
			}
		} else {
			for (my($b)=0; $b<4; $b++) {
				$d->{ENSEMBLE}[$e]->{BT_RANGE}[$b] = undef;
			}
		}
		$d->{ENSEMBLE}[$e]->{BT_MEAN_RANGE} = $sum/$n if ($n == 4);
	}
}

#======================================================================
# (seabed depth, stddev) = find_seabed(dta ptr, btm ensno, coord flag)
#======================================================================

# NOTE FOR YOYOS:
#	- this routine only detects the BT around the depeest depth!
#	- this is on purpose, because it is used for [listBT]

# This is a PAIN:
# 	if the instrument is too close to the bottom, the BT_RANGE
#	readings are all out; the only solution is to have a sufficiently
#	large search width (around the max(depth) ensemble) so that
#	a part of the up (oops, I forgot to finish this comment one year
#	ago during A0304 and now I don't understand it any more :-)

my($search_width) = 200;	# # of ensembles around bottom to search
my($mode_width) = 10;		# max range of bottom around mode
my($z_offset) = 10000;		# shift z to ensure +ve array indices

sub find_seabed($$$)
{
	my($d,$be,$beamCoords) = @_;
	my($i,$dd,$sd,$nd);
	my(@guesses);

	return undef unless ($be-$search_width >= 0 &&
						 $be+$search_width <= $#{$d->{ENSEMBLE}});
	for ($i=$be-$search_width; $i<=$be+$search_width; $i++) {
		next unless (defined($d->{ENSEMBLE}[$i]->{BT_RANGE}[0]) &&
					 defined($d->{ENSEMBLE}[$i]->{BT_RANGE}[1]) &&
					 defined($d->{ENSEMBLE}[$i]->{BT_RANGE}[2]) &&
					 defined($d->{ENSEMBLE}[$i]->{BT_RANGE}[3]));
		my(@BT) = $beamCoords
				? velInstrumentToEarth($d,$i,
					velBeamToInstrument($d,
						@{$d->{ENSEMBLE}[$i]->{BT_VELOCITY}}))
				: velApplyHdgBias($d,$i,@{$d->{ENSEMBLE}[$i]->{BT_VELOCITY}});
		next unless (abs($BT[3]) < 0.05);
		$d->{ENSEMBLE}[$i]->{DEPTH_BT} =
		$d->{ENSEMBLE}[$i]->{DEPTH_BT} =
			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[0]/4 +
			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[1]/4 +
 			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[2]/4 +
			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[3]/4;
		$d->{ENSEMBLE}[$i]->{DEPTH_BT} *= -1
			if ($d->{ENSEMBLE}[$i]->{XDUCER_FACING_UP});
		$d->{ENSEMBLE}[$i]->{DEPTH_BT} += $d->{ENSEMBLE}[$i]->{DEPTH};
		$guesses[int($d->{ENSEMBLE}[$i]->{DEPTH_BT})+$z_offset]++;
		$nd++;
	}
	return undef unless ($nd>5);

	my($mode,$nmax);
	for ($i=0; $i<=$#guesses; $i++) {			# find mode
		$nmax=$guesses[$i],$mode=$i-$z_offset
			if ($guesses[$i] > $nmax);
	}

	$nd = 0;
	for ($i=$be-$search_width; $i<=$be+$search_width; $i++) {
		next unless defined($d->{ENSEMBLE}[$i]->{DEPTH_BT});
		if (abs($d->{ENSEMBLE}[$i]->{DEPTH_BT}-$mode) <= $mode_width) {
			$dd += $d->{ENSEMBLE}[$i]->{DEPTH_BT};
			$nd++;
		} else {
			$d->{ENSEMBLE}[$i]->{DEPTH_BT} = undef;
		}
	}
	return undef unless ($nd >= 2);

	$dd /= $nd;
	for ($i=$be-$search_width; $i<=$be+$search_width; $i++) {
		next unless defined($d->{ENSEMBLE}[$i]->{DEPTH_BT});
		$sd += ($d->{ENSEMBLE}[$i]->{DEPTH_BT}-$dd)**2;
	}

	return ($dd, sqrt($sd/($nd-1)));
}

#======================================================================
# c = soundSpeed()
#======================================================================

# Taken from the RDI BroadBand primer manual. The reference given there
# is Urick (1983).

sub soundSpeed($$$)
{
	my($salin,$temp,$depth) = @_;
	return 1449.2 + 4.6*$temp -0.055*$temp**2  + 0.00029*$temp**3 +
				(1.34 - 0.01*$temp) * ($salin - 35) + 0.016*$depth;
}

1;
