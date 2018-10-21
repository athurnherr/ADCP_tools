#======================================================================
#                    R D I _ U T I L S . P L 
#                    doc: Wed Feb 12 10:21:32 2003
#                    dlm: Sat Jun  9 12:11:01 2018
#                    (c) 2003 A.M. Thurnherr
#                    uE-Info: 61 58 NIL 0 0 72 2 2 4 NIL ofnI
#======================================================================

# miscellaneous RDI-specific utilities

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
#	Dec  1, 2005: - renamed to RDI_Utils.pl
#				  - folded in mk_prof from [mkProfile]
#	Nov 30, 2007: - adapted ref_lr_w() to 3-beam solutions
#	Feb  1, 2008: - added comment
#	Feb 22, 2008: - added ssCorr()
#	Apr  9, 2008: - BUG: duplicate line of code (without effect) in find_seabed() 
#				  - BUG: seabed < max depth was possible
#	Jan     2010: - fiddled with seabed detection params (no conclusion)
#	May 23, 2010: - renamed Z to DEPTH
#	Sep 27, 2010: - made sure coord flags are changed correctly when data
#					are transferred to earth coords in mk_prof
#	Sep 29, 2010: - BUG: previous change was wrong, as ref_lr_w does
#						 not overwrite velocities
#	Oct 20, 2010: - BUG: w is now not integrated any more across gaps longer than 5s
#	Dec  8, 2010: - changed missing w warning to happen only if gap is longer than 15s
#	Dec 10, 2010: - beautified gap warning
#	Dec 16, 2010: - BUG: gaps at end caused mk_prof to throw away profile
#	May 12, 2011: - added code to skip ensembles with built-in-test errors in mk_prof()
#				  - immediately disabled this code becasue it does appear to make matters worse
#	Sep 21, 2011: - added calculation of RMS heave acceleration
#	Mar 27, 2013: - BUG: 3-beam solutions were not used in ref_lr_w
#				  - disabled apparently unused code
#	Apr 12, 2013: - added $min_pctg as optional parameter to mk_prof
#	May 14, 2013: - added incident-velocity, w12 & w34 to mkProfile
#	Jun  5, 2013: - BUG: incident-flow warning was printed repeatedly
#	Jun 20, 2013: - BUG: warning had used &antsInfo()
#	Feb 13, 2014: - replaced {DEPTH_BT} by {seabed}
#				  - added set_range_lim()
#	Feb 22, 2014: - changed gap heuristic
#			      - Earth coord beam-pair warning removed
#	May 29, 2014: - removed unused code (disabled warning) from ref_lr_w
#	Mar 22, 2015: - BUG: mk_prof could bomb because of division-by-zero in return statement
#	Jan  9, 2016: - renamed ref_lr_w to mk_prof_ref_lr_w because the old name conflicts
#				    with a sub in LADCP_w
#   May 19, 2016: - adapted to new velBeamToInstrument() usage
#	Aug  7, 2017: - added abmiguity velocity
#	Aug  8, 2017: - changed transducer frequency to kHz
#	Nov 27, 2017: - BUG: profile-restart heuristic did not work with P6#001
#	Mar 18, 2018: - added -ve dt consistency check
#	Jun  9, 2018: - added support for ENV{NO_GAP_WARNINGS}

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
my($min_dist) = 20;			# min dist to seabed for good data
my($z_offset) = 10000;		# shift z to ensure +ve array indices

sub find_seabed($$$)
{
	my($d,$be,$beamCoords) = @_;
	my($i,$dd,$sd,$nd);
	my(@guesses);

	return undef unless ($be-$search_width >= 0 &&
						 $be+$search_width <= $#{$d->{ENSEMBLE}});
	for ($i=$be-$search_width; $i<=$be+$search_width; $i++) {
		next unless (defined($d->{ENSEMBLE}[$i]->{DEPTH}) &&
					 defined($d->{ENSEMBLE}[$i]->{BT_RANGE}[0]) &&
					 defined($d->{ENSEMBLE}[$i]->{BT_RANGE}[1]) &&
					 defined($d->{ENSEMBLE}[$i]->{BT_RANGE}[2]) &&
					 defined($d->{ENSEMBLE}[$i]->{BT_RANGE}[3]));
		my(@BT) = $beamCoords ? velBeamToEarth($d,$i,@{$d->{ENSEMBLE}[$i]->{BT_VELOCITY}})
							  : velApplyHdgBias($d,$i,@{$d->{ENSEMBLE}[$i]->{BT_VELOCITY}});
		next unless (abs($BT[3]) < 0.05);
		$d->{ENSEMBLE}[$i]->{seabed} =
			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[0]/4 +
			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[1]/4 +
 			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[2]/4 +
			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[3]/4;
		next
			unless ($d->{ENSEMBLE}[$i]->{seabed} >= $min_dist);
		$d->{ENSEMBLE}[$i]->{seabed} *= -1
			if ($d->{ENSEMBLE}[$i]->{XDUCER_FACING_UP});
		$d->{ENSEMBLE}[$i]->{seabed} += $d->{ENSEMBLE}[$i]->{DEPTH};
		if ($d->{ENSEMBLE}[$i]->{seabed} > $d->{ENSEMBLE}[$be]->{DEPTH}) {
			$guesses[int($d->{ENSEMBLE}[$i]->{seabed})+$z_offset]++;
			$nd++;
		} else {
			undef($d->{ENSEMBLE}[$i]->{seabed});
		}
	}
	return undef unless ($nd>5);

	my($mode,$nmax);
	for ($i=0; $i<=$#guesses; $i++) {			# find mode
	$nmax=$guesses[$i],$mode=$i-$z_offset
			if ($guesses[$i] > $nmax);
	}

	$nd = 0;
	for ($i=$be-$search_width; $i<=$be+$search_width; $i++) {
		next unless defined($d->{ENSEMBLE}[$i]->{seabed});
		if (abs($d->{ENSEMBLE}[$i]->{seabed}-$mode) <= $mode_width) {
			$dd += $d->{ENSEMBLE}[$i]->{seabed};
			$nd++;
		} else {
			$d->{ENSEMBLE}[$i]->{seabed} = undef;
		}
	}
	return undef unless ($nd >= 2);

	$dd /= $nd;
	for ($i=$be-$search_width; $i<=$be+$search_width; $i++) {
		next unless defined($d->{ENSEMBLE}[$i]->{seabed});
		$sd += ($d->{ENSEMBLE}[$i]->{seabed}-$dd)**2;
	}

	return ($dd, sqrt($sd/($nd-1)));
}

#----------------------------------------------------------------------
# set_range_lim(d)
#	- set field range_lim
#----------------------------------------------------------------------

sub set_range_lim($)
{
	my($d) = @_;

	for (my($e)=0; $e<=$#{$d->{ENSEMBLE}}; $e++) {
		my($lastGood) = 1; my($b);
		for ($b=0; $b<$d->{N_BINS}; $b++) {
			if (defined($d->{ENSEMBLE}[$e]->{VELOCITY}[$b][0]) &&
				defined($d->{ENSEMBLE}[$e]->{VELOCITY}[$b][1]) &&
				defined($d->{ENSEMBLE}[$e]->{VELOCITY}[$b][2]) &&
				defined($d->{ENSEMBLE}[$e]->{VELOCITY}[$b][3])) {
					$lastGood = 1;
			} elsif ($lastGood) {
				$lastGood = 0;
			} else {
				last;
			}
	    }

		next unless ($b>=2) && defined($d->{ENSEMBLE}[$e]->{DEPTH});
	    $d->{ENSEMBLE}[$e]->{range_lim} =
			$d->{DISTANCE_TO_BIN1_CENTER} + ($b-2) * $d->{BIN_LENGTH};
		$d->{ENSEMBLE}[$e]->{range_lim} *= -1
			if ($d->{ENSEMBLE}[$e]->{XDUCER_FACING_UP});
		$d->{ENSEMBLE}[$e]->{range_lim} += $d->{ENSEMBLE}[$e]->{DEPTH};
	}
}

#======================================================================
# c = soundSpeed($salin,$temp,$depth)
#======================================================================

# Taken from the RDI BroadBand primer manual. The reference given there
# is Urick (1983).

sub soundSpeed($$$)
{
	my($salin,$temp,$depth) = @_;
	die("ERROR: soundSpeed($salin,$temp,$depth): non-numeric parameter\n")
		unless numberp($salin) && numberp($temp) && numberp($depth);
	return 1449.2 + 4.6*$temp -0.055*$temp**2  + 0.00029*$temp**3 +
				(1.34 - 0.01*$temp) * ($salin - 35) + 0.016*$depth;
}

#======================================================================
# fac = ssCorr($eRef,$salin,$temp,$depth)
#	$eRef :	reference to current ensemble
#	$salin: * -> use instrument salinity
#	$temp : * -> use instrument temperature
#	$depth: * -> use instrument PRESSURE(!)
#======================================================================

{ my($warned);
	sub ssCorr($$$$)
	{
		my($eRef,$S,$T,$D) = @_;
		$S = $eRef->{SALINITY} if ($S eq '*');
		$T = $eRef->{TEMPERATURE} if ($T eq '*');
		if ($D eq '*') {
			print(STDERR "WARNING: soundspeed correction using instrument pressure instead of depth!\n")
				unless ($warned);
			$warned = 1;
			$D = $eRef->{PRESSURE};
		}
		return soundSpeed($S,$T,$D) / $eRef->{SPEED_OF_SOUND};
	}
}

#======================================================================
# ambiguity_velocity(transducer_freq,beam_angle,sound_speed,transmit_lag_dist)
# 	- recipe provied by Jerry Mullison in August 2017
#	- transducer_freq in kHz
#	- sound speed can vary with ensemble
#======================================================================

sub ambiguity_velocity($$$$)
{
	my($xd_freq,$beam_angle,$speed_of_sound,$TL_distance) = @_;
	my($lambda) = $speed_of_sound / (1000*$xd_freq);
	my($D) = $speed_of_sound * cos(rad($beam_angle)) / 2;
	return $lambda * $D / (4 * $TL_distance);
}
	
#======================================================================
# ($firstgood,$lastgood,$atbottom,$w_gap_time,$zErr,$maxz) =
#	mk_prof($dta,$check,$filter,$lr_b0,$lr_b1,$min_corr,$max_e,$max_gap);
#======================================================================

# calculate reference-layer vertical and incident velocities

sub mk_prof_ref_lr_w($$$$$$$)
{
	my($dta,$ens,$rl_b0,$rl_b1,$min_corr,$max_e,$min_pctg) = @_;
	my($i,@n,@bn,@v,@vi,@vel,@veli,@bv,@w);
	my($w,$e,$nvi,$vi12,$vi43,@vbp,@velbp,@nbp,$w12,$w34,@w12,@w34);

	for ($i=$rl_b0; $i<=$rl_b1; $i++) {
		undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][0])
			if ($dta->{ENSEMBLE}[$ens]->{CORRELATION}[$i][0] < $min_corr);
		undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][1])
			if ($dta->{ENSEMBLE}[$ens]->{CORRELATION}[$i][1] < $min_corr);
		undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][2])
			if ($dta->{ENSEMBLE}[$ens]->{CORRELATION}[$i][2] < $min_corr);
		undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][3])
			if ($dta->{ENSEMBLE}[$ens]->{CORRELATION}[$i][3] < $min_corr);
		if ($dta->{BEAM_COORDINATES}) {
			undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][0])
				if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][0] < $min_pctg);
			undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][1])
				if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][1] < $min_pctg);
			undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][2])
				if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][2] < $min_pctg);
			undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][3])
	            if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][3] < $min_pctg);
	        @vi = velBeamToInstrument($dta,$ens,@{$dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i]});
			@v = velInstrumentToEarth($dta,$ens,@vi);
			@vbp = velBeamToBPEarth($dta,$ens,@{$dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i]});
		} else {
			next if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][0] > 0 ||
					 $dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][1] > 0 ||
					 $dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][2] > 0 ||
					 $dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][3] < $min_pctg);
			@v = @{$dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i]};
		}
		next if (defined($v[3]) && abs($v[3]) > $max_e);		# allow 3-beam solutions

		if (defined($v[2])) {									# valid vertical velocity
			$vel[2] += $v[2]; $n[2]++;							# vertical velocity
			$vel[3] += $v[3], $n[3]++ if defined($v[3]);		# error velocity
			push(@w,$v[2]); 									# save for stderr calculation
		}

		if (defined($vbp[1])) {									# beam-pair vertical velocities
			$velbp[0] += $vbp[1]; $nbp[0]++;
			push(@w12,$vbp[1]);
		}
		if (defined($vbp[3])) {
			$velbp[1] += $vbp[3]; $nbp[1]++;
			push(@w34,$vbp[1]);
		}
		
		if (defined($vi[0])) { 									# incident velocity
			$veli[0] += $vi[0];
			$veli[1] += $vi[1];
			$nvi++;
		}

#	The following code calculates beam-averaged ref-lr velocities.
#	I do not recall what this was implemented for. Disabled Mar 27, 2013.
#
#		if ($dta->{BEAM_COORDINATES}) {
#			$bv[0] += $dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][0], $bn[0]++
#				if defined($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][0]);
#			$bv[1] += $dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][1], $bn[1]++
#				if defined($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][1]);
#			$bv[2] += $dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][2], $bn[2]++
#				if defined($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][2]);
#			$bv[3] += $dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][3], $bn[3]++
#	            if defined($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][3]);
#	    }
	} # loop over ref-lr bins

	$w = ($n[2] > 0) ? $vel[2]/$n[2] : undef;					# calc means
	$e = ($n[3] > 0) ? $vel[3]/$n[3] : undef;
	if ($nvi > 0) {						
		$vi12 = $veli[0] / $nvi;
		$vi43 = $veli[1] / $nvi;
	} else {
		$vi12 = $vi43 = undef;
	}
	$w12 = ($nbp[0] > 0) ? $velbp[0]/$nbp[0] : undef;
	$w34 = ($nbp[1] > 0) ? $velbp[1]/$nbp[1] : undef;

	if (@w12) {													# w uncertainty
		my($sumsq) = 0;
		for ($i=0; $i<=$#w12; $i++) {
			$sumsq += ($w12-$w12[$i])**2;
		}
		$dta->{ENSEMBLE}[$ens]->{W12} = $w12;
		$dta->{ENSEMBLE}[$ens]->{W12_ERR} = sqrt($sumsq)/($nbp[0]-1)
			if ($nbp[0]>=2);
	}

	if (@w34) {													# w uncertainty
		my($sumsq) = 0;
		for ($i=0; $i<=$#w34; $i++) {
			$sumsq += ($w34-$w34[$i])**2;
		}
		$dta->{ENSEMBLE}[$ens]->{W34} = $w34;
		$dta->{ENSEMBLE}[$ens]->{W34_ERR} = sqrt($sumsq)/($nbp[1]-1)
			if ($nbp[1]>=2);
	}

	my($sumsq) = 0;												# w uncertainty
	for ($i=0; $i<=$#w; $i++) {
		$sumsq += ($w-$w[$i])**2;
	}
	my($stderr) = $n[2]>=2 ? sqrt($sumsq)/($n[2]-1) : undef;

#	The following stderr test introduces a huge gap near the bottom of
#	the profiles. Without it, they seem more reasonable.
#	next if ($stderr > 0.05);

	if (defined($w)) {											# valid velocity
		$dta->{ENSEMBLE}[$ens]->{W} = $w;
		$dta->{ENSEMBLE}[$ens]->{W_ERR} = $stderr;
	}
	$dta->{ENSEMBLE}[$ens]->{ERR_VEL} = $e if (defined($e));
	
	$dta->{ENSEMBLE}[$ens]->{W12} = $w12 if (defined($w12));
	$dta->{ENSEMBLE}[$ens]->{W34} = $w34 if (defined($w34));

	if (defined($vi12)) {
		$dta->{ENSEMBLE}[$ens]->{INCIDENT_VEL_T12} = $vi12;
		$dta->{ENSEMBLE}[$ens]->{INCIDENT_VEL_T43} = $vi43;
	}

#	The following code calculates beam-averaged ref-lr velocities.
#	I do not recall what this was implemented for. Disabled Mar 27, 2013.
#
#	if ($dta->{BEAM_COORDINATES}) {
#		$dta->{ENSEMBLE}[$ens]->{V1} = $bn[0]>=2 ? $bv[0]/$bn[0] : undef;
#		$dta->{ENSEMBLE}[$ens]->{V2} = $bn[1]>=2 ? $bv[1]/$bn[1] : undef;
#		$dta->{ENSEMBLE}[$ens]->{V3} = $bn[2]>=2 ? $bv[2]/$bn[2] : undef;
#	    $dta->{ENSEMBLE}[$ens]->{V4} = $bn[3]>=2 ? $bv[3]/$bn[3] : undef;
#	}

}


sub mk_prof(...)											# make profile
{
	my($dta,$check,$filter,$lr_b0,$lr_b1,$min_corr,$max_e,$max_gap,$min_pctg) = @_;
	my($firstgood,$lastgood,$atbottom,$w_gap_time,$zErr,$maxz);
	my($rms_heave_accel_ssq,$rms_heave_accel_nsamp);

	$min_pctg = 100 unless defined($min_pctg);
	
	for (my($z)=0,my($e)=0; $e<=$#{$dta->{ENSEMBLE}}; $e++) {
		checkEnsemble($dta,$e) if ($check);
###		The following line of code, which can only have an effect if check is disabled,
###		seems reasonable but has been found to make matters worse with one particular
###		data file from a BB150. 
###		next if ($dta->{ENSEMBLE}[$e]->{BUILT_IN_TEST_ERROR});
	
		filterEnsemble($dta,$e)
			if (defined($filter) &&
				$dta->{ENSEMBLE}[$e]->{PERCENT_GOOD}[0][0] > 0);
		mk_prof_ref_lr_w($dta,$e,$lr_b0,$lr_b1,$min_corr,$max_e,$min_pctg);	# ref. layer w
	
		if (defined($firstgood)) {
			$dta->{ENSEMBLE}[$e]->{ELAPSED_TIME} =			# time since start
				$dta->{ENSEMBLE}[$e]->{UNIX_TIME} -
				$dta->{ENSEMBLE}[$firstgood]->{UNIX_TIME};
		} else {
			if (defined($dta->{ENSEMBLE}[$e]->{W})) {		# start of prof.
				$firstgood = $lastgood = $e;		    
				$dta->{ENSEMBLE}[$e]->{ELAPSED_TIME} = 0;
				$dta->{ENSEMBLE}[$e]->{DEPTH} = $dta->{ENSEMBLE}[$e]->{DEPTH_ERR} = 0;
			}
			next;
		}
	
		#--------------------------------------------------
		# within profile: both $firstgood and $lastgood set
		#--------------------------------------------------
	
		if (!defined($dta->{ENSEMBLE}[$e]->{W})) {			# gap
			$w_gap_time += $dta->{ENSEMBLE}[$e]->{UNIX_TIME} -
						   $dta->{ENSEMBLE}[$e-1]->{UNIX_TIME};
			next;
		}
	
		my($dt) = $dta->{ENSEMBLE}[$e]->{UNIX_TIME} -		# time step since
				  $dta->{ENSEMBLE}[$lastgood]->{UNIX_TIME}; # ... last good ens

		die(sprintf("PANIC: negative dt = $dt between ensembles %d and %d\n",
			$dta->{ENSEMBLE}[$lastgood]->{NUMBER},$dta->{ENSEMBLE}[$e]->{NUMBER}))
				if ($dt < 0);
	
		if ($dt > $max_gap) {
			# 2nd heuristic test added Nov 2017 for P06 profile #001
			if ((@{$dta->{ENSEMBLE}}-$e < @{$dta->{ENSEMBLE}}/2) &&
				($maxz > 25 && $z < $maxz/2)) {
					printf(STDERR "WARNING: %.1f-s gap in 2nd half of profile is too long; profile ended at ensemble $lastgood\n",$dt);
#					printf(STDERR "\t[#ens = %d, end-of-gap = $e]\n",scalar(@{$dta->{ENSEMBLE}}));
					last;
			}
			printf(STDERR "WARNING: %.1f-s gap beginning at ens#%d in first half of profile is too long; profile restarted at ensemble %d\n",
				$dt,$dta->{ENSEMBLE}[$lastgood+1]->{NUMBER},$dta->{ENSEMBLE}[$e]->{NUMBER});
			$firstgood = $lastgood = $e;
			$dta->{ENSEMBLE}[$e]->{ELAPSED_TIME} = 0;
			$z = $zErr = $maxz = 0;
			$dta->{ENSEMBLE}[$e]->{DEPTH} = $dta->{ENSEMBLE}[$e]->{DEPTH_ERR} = 0;
			$w_gap_time = 0;
			$rms_heave_accel_ssq = $rms_heave_accel_nsamp = 0;
			next;
		}

		#-----------------------------------
		# The current ensemble has a valid w
		#-----------------------------------

		if ($dt < 5) {												# no or short gap
			$z += $dta->{ENSEMBLE}[$lastgood]->{W} * $dt;			# integrate w to get depth
			$zErr += ($dta->{ENSEMBLE}[$lastgood]->{W_ERR} * $dt)**2;
			$rms_heave_accel_ssq += (($dta->{ENSEMBLE}[$e]->{W}-$dta->{ENSEMBLE}[$lastgood]->{W})/$dt)**2;
			$rms_heave_accel_nsamp++;
		} elsif ($dt > 15) {
	       	printf(STDERR "WARNING: long-ish w gap at ens#%d-%d (dt=%.1fs)\n",
				$dta->{ENSEMBLE}[$lastgood+1]->{NUMBER},$dta->{ENSEMBLE}[$e-1]->{NUMBER},$dt)
					unless defined($ENV{NO_GAP_WARNINGS});
		}
	
		$dta->{ENSEMBLE}[$e]->{DEPTH} = $z;
		$dta->{ENSEMBLE}[$e]->{DEPTH_ERR} = sqrt($zErr);
	
		$atbottom = $e, $maxz = $z if ($z > $maxz); 
	
		$lastgood = $e;
	}
	
	filterEnsembleStats() if defined($filter);

	return ($firstgood,$lastgood,$atbottom,$w_gap_time,$zErr,$maxz,
			($rms_heave_accel_nsamp>0) ? sqrt($rms_heave_accel_ssq/$rms_heave_accel_nsamp) : 'nan');
}

#----------------------------------------------------------------------
# (true|false) = numberp(var)
#----------------------------------------------------------------------

sub numberp(@)
{ return  $_[0] =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/; }


1;

