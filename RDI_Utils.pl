#======================================================================
#                    R D I _ U T I L S . P L 
#                    doc: Wed Feb 12 10:21:32 2003
#                    dlm: Sun May 23 16:35:21 2010
#                    (c) 2003 A.M. Thurnherr
#                    uE-Info: 156 42 NIL 0 0 72 2 2 4 NIL ofnI
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
		my(@BT) = $beamCoords
				? velInstrumentToEarth($d,$i,
					velBeamToInstrument($d,
						@{$d->{ENSEMBLE}[$i]->{BT_VELOCITY}}))
				: velApplyHdgBias($d,$i,@{$d->{ENSEMBLE}[$i]->{BT_VELOCITY}});
		next unless (abs($BT[3]) < 0.05);
		$d->{ENSEMBLE}[$i]->{DEPTH_BT} =
			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[0]/4 +
			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[1]/4 +
 			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[2]/4 +
			 $d->{ENSEMBLE}[$i]->{BT_RANGE}[3]/4;
		next unless ($d->{ENSEMBLE}[$i]->{DEPTH_BT} >= $min_dist);
		$d->{ENSEMBLE}[$i]->{DEPTH_BT} *= -1
			if ($d->{ENSEMBLE}[$i]->{XDUCER_FACING_UP});
		$d->{ENSEMBLE}[$i]->{DEPTH_BT} += $d->{ENSEMBLE}[$i]->{DEPTH};
		if ($d->{ENSEMBLE}[$i]->{DEPTH_BT} > $d->{ENSEMBLE}[$be]->{DEPTH}) {
			$guesses[int($d->{ENSEMBLE}[$i]->{DEPTH_BT})+$z_offset]++;
			$nd++;
		} else {
			undef($d->{ENSEMBLE}[$i]->{DEPTH_BT});
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
# ($firstgood,$lastgood,$atbottom,$w_gap_time,$zErr,$maxz) =
#	mk_prof($dta,$check,$filter,$lr_b0,$lr_b1,$min_corr,$max_e,$max_gap);
#======================================================================

sub ref_lr_w($$$$$$)								# calc ref-level vert vels
{
	my($dta,$ens,$rl_b0,$rl_b1,$min_corr,$max_e) = @_;
	my($i,@n,@bn,@v,@vel,@bv,@w);

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
				if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][0] < 100);
			undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][1])
				if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][1] < 100);
			undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][2])
				if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][2] < 100);
			undef($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][3])
	            if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][3] < 100);
			@v = velInstrumentToEarth($dta,$ens,
					velBeamToInstrument($dta,
						@{$dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i]}));
		} else {
			next if ($dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][0] > 0 ||
					 $dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][1] > 0 ||
					 $dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][2] > 0 ||
					 $dta->{ENSEMBLE}[$ens]->{PERCENT_GOOD}[$i][3] < 100);
			@v = @{$dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i]};
			# NB: no need to apply heading bias, as long as we only use w!
		}
		next if (!defined($v[3]) || abs($v[3]) > $max_e);

		if (defined($v[2])) {							# valid w
			$vel[2] += $v[2]; $n[2]++;
			$vel[3] += $v[3], $n[3]++ if defined($v[3]);
			push(@w,$v[2]); 							# for stderr test
		}
		
		if ($dta->{BEAM_COORDINATES}) {
			$bv[0] += $dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][0], $bn[0]++
				if defined($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][0]);
			$bv[1] += $dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][1], $bn[1]++
				if defined($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][1]);
			$bv[2] += $dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][2], $bn[2]++
				if defined($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][2]);
			$bv[3] += $dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][3], $bn[3]++
	            if defined($dta->{ENSEMBLE}[$ens]->{VELOCITY}[$i][3]);
	    }
	}

	my($w) = $n[2] ? $vel[2]/$n[2] : undef;				# w uncertainty
	my($sumsq) = 0;
	for ($i=0; $i<=$#w; $i++) {
		$sumsq += ($w-$w[$i])**2;
	}
	my($stderr) = $n[2]>=2 ? sqrt($sumsq)/($n[2]-1) : undef;
#	The following stderr test introduces a huge gap near the bottom of
#	the profiles. Without it, they seem more reasonable.
#	next if ($stderr > 0.05);

	if (defined($w)) {									# valid w
		$dta->{ENSEMBLE}[$ens]->{W} = $w;
		$dta->{ENSEMBLE}[$ens]->{W_ERR} = $stderr;
	}
	if ($dta->{BEAM_COORDINATES}) {
		$dta->{ENSEMBLE}[$ens]->{V1} = $bn[0]>=2 ? $bv[0]/$bn[0] : undef;
		$dta->{ENSEMBLE}[$ens]->{V2} = $bn[1]>=2 ? $bv[1]/$bn[1] : undef;
		$dta->{ENSEMBLE}[$ens]->{V3} = $bn[2]>=2 ? $bv[2]/$bn[2] : undef;
	    $dta->{ENSEMBLE}[$ens]->{V4} = $bn[3]>=2 ? $bv[3]/$bn[3] : undef;
	}
}


sub mk_prof($$$$$$$$)										# make profile
{
	my($dta,$check,$filter,$lr_b0,$lr_b1,$min_corr,$max_e,$max_gap) = @_;
	my($firstgood,$lastgood,$atbottom,$w_gap_time,$zErr,$maxz);
	
	for (my($z)=0,my($e)=0; $e<=$#{$dta->{ENSEMBLE}}; $e++) {
		checkEnsemble($dta,$e) if ($check);
	
		filterEnsemble($dta,$e)
			if (defined($filter) &&
				$dta->{ENSEMBLE}[$e]->{PERCENT_GOOD}[0][0] > 0);
		ref_lr_w($dta,$e,$lr_b0,$lr_b1,$min_corr,$max_e);	# ref. layer w
	
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
	
		if ($dt > $max_gap) {
			printf(STDERR "WARNING: %d-s gap too long, profile restarted at ensemble $e\n",$dt);
			$firstgood = $lastgood = $e;
			$dta->{ENSEMBLE}[$e]->{ELAPSED_TIME} = 0;
			$z = $zErr = $maxz = 0;
			$dta->{ENSEMBLE}[$e]->{DEPTH} = $dta->{ENSEMBLE}[$e]->{DEPTH_ERR} = 0;
			$w_gap_time = 0;
			next;
		}
	
		#-----------------------------------
		# The current ensemble has a valid w
		#-----------------------------------
	
		$z += $dta->{ENSEMBLE}[$lastgood]->{W} * $dt;			# integrate
		$zErr += ($dta->{ENSEMBLE}[$lastgood]->{W_ERR} * $dt)**2;
		$dta->{ENSEMBLE}[$e]->{DEPTH} = $z;
		$dta->{ENSEMBLE}[$e]->{DEPTH_ERR} = sqrt($zErr);
	
		$atbottom = $e, $maxz = $z if ($z > $maxz); 
	
		$lastgood = $e;
	}
	
	filterEnsembleStats() if defined($filter);

	return ($firstgood,$lastgood,$atbottom,$w_gap_time,$zErr,$maxz);
}

#----------------------------------------------------------------------
# (true|false) = numberp(var)
#----------------------------------------------------------------------

sub numberp(@)
{ return  $_[0] =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/; }


1;
