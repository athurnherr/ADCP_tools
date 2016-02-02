#======================================================================
#                    R D I _ C O O R D S . P L 
#                    doc: Sun Jan 19 17:57:53 2003
#                    dlm: Sun Jan 31 12:42:43 2016
#                    (c) 2003 A.M. Thurnherr
#                    uE-Info: 185 0 NIL 0 0 72 0 2 4 NIL ofnI
#======================================================================

# RDI Workhorse Coordinate Transformations

# HISTORY:
#	Jan 19, 2003: - written
#	Jan 21, 2003: - made it obey HEADING_BIAS (magnetic declination)
#	Jan 22, 3003: - corrected magnetic declination
#	Feb 16, 2003: - use pitch correction from RDI manual
#	Oct 11, 2003: - BUG: return value of atan() had been interpreted
#					     as degrees instead of radians
#	Feb 27, 2004: - added velApplyHdgBias()
#				  - changed non-zero HEADING_ALIGNMENT from error to warning
#	Sep 16, 2005: - added deg() for [mkprofile]
#	Aug 26, 2006: - BUG: incorrect transformation for uplookers
#	Nov 30, 2007: - optimized &velInstrumentToEarth(), velBeamToInstrument()
#				  - added support for 3-beam solutions
#	Feb 12, 2008: - added threeBeamFlag
#	Mar 18, 2009: - added &gimbal_pitch(), &angle_from_vertical()
#	May 19, 2009: - added &velBeamToVertical()
#	May 23, 2009: - debugged & renamed to &velBeamToBPEarth
#	May 23, 2010: - changed prototypes of rad() & deg() to conform to ANTS
#	Dec 20, 2010: - cosmetics
#	Dec 23, 2010: - added &velBeamToBPInstrument
#	Jan 22, 2011: - made velApplyHdgBias calculate sin/cos every time to allow
#				    per-ensemble corrections
#	Jan 15, 2012: - replaced defined(@...) by (@...) to get rid of warning
#	Aug  7, 2013: - BUG: &velBeamToBPInstrument did not return any val unless
#						 all beam velocities are defined
#	Nov 27, 2013: - added &RDI_pitch(), &tilt_azimuth()
#	Mar  4, 2014: - added support for ensembles with missing PITCH/ROLL/HEADING
#	May 29, 2014: - BUG: vertical velocity can be calculated even without
#						 heading
#				  - removed some old debug statements
#				  - removed unused code from &velBeamToBPInstrument
#	Jan  5, 2016: - added &velEarthToInstrument(@), &velInstrumentToBeam(@)
#	Jan  9, 2016: - added &velEarthToBeam(), &velBeamToEarth()

use strict;
use POSIX;

my($PI) = 3.14159265358979;

sub rad(@) { return $_[0]/180 * $PI; }
sub deg(@) { return $_[0]/$PI * 180; }

$RDI_Coords::minValidVels = 3;			# 3-beam solutions ok

$RDI_Coords::threeBeam_1 = 0;			# stats
$RDI_Coords::threeBeam_2 = 0;
$RDI_Coords::threeBeam_3 = 0;
$RDI_Coords::threeBeam_4 = 0;
$RDI_Coords::fourBeam    = 0;

$RDI_Coords::threeBeamFlag = 0;			# flag last transformation

{ # STATIC SCOPE
	my(@B2I);

	sub velBeamToInstrument(@)
	{
		my($dta,$v1,$v2,$v3,$v4) = @_;
		return undef unless (defined($v1) + defined($v2) +
					   		 defined($v3) + defined($v4)
								>= $RDI_Coords::minValidVels);

		unless (@B2I) {
			my($a) = 1 / (2 * sin(rad($dta->{BEAM_ANGLE})));
			my($b) = 1 / (4 * cos(rad($dta->{BEAM_ANGLE})));
			my($c) = $dta->{CONVEX_BEAM_PATTERN} ? 1 : -1;
			my($d) = $a / sqrt(2);
			@B2I = ([$c*$a,	-$c*$a,	0,		0	 ],
				    [0,		0,		-$c*$a,	$c*$a],
				    [$b,	$b,		$b,		$b	 ],
				    [$d,	$d,		-$d,	-$d	 ]);
		}

		if (!defined($v1)) {					# 3-beam solutions
			$RDI_Coords::threeBeamFlag = 1;
			$RDI_Coords::threeBeam_1++;
			$v1 = -($v2*$B2I[3][1]+$v3*$B2I[3][2]+$v4*$B2I[3][3])/$B2I[3][0];
		} elsif (!defined($v2)) {
			$RDI_Coords::threeBeamFlag = 1;
			$RDI_Coords::threeBeam_2++;
			$v2 = -($v1*$B2I[3][0]+$v3*$B2I[3][2]+$v4*$B2I[3][3])/$B2I[3][1];
		} elsif (!defined($v3)) {
			$RDI_Coords::threeBeamFlag = 1;
			$RDI_Coords::threeBeam_3++;
			$v3 = -($v1*$B2I[3][0]+$v2*$B2I[3][1]+$v4*$B2I[3][3])/$B2I[3][2];
		} elsif (!defined($v4)) {
			$RDI_Coords::threeBeamFlag = 1;
			$RDI_Coords::threeBeam_4++;
			$v4 = -($v1*$B2I[3][0]+$v2*$B2I[3][1]+$v3*$B2I[3][2])/$B2I[3][3];
		} else {
			$RDI_Coords::threeBeamFlag = 0;
			$RDI_Coords::fourBeam++;
		}
		
		return ($v1*$B2I[0][0]+$v2*$B2I[0][1],
				$v3*$B2I[1][2]+$v4*$B2I[1][3],
				$v1*$B2I[2][0]+$v2*$B2I[2][1]+$v3*$B2I[2][2]+$v4*$B2I[2][3],
				$v1*$B2I[3][0]+$v2*$B2I[3][1]+$v3*$B2I[3][2]+$v4*$B2I[3][3]);
	}
} # STATIC SCOPE

{ # STATIC SCOPE
	my($hdg,$pitch,$roll,@I2E);

	sub velInstrumentToEarth(@)
	{
		my($dta,$ens,$v1,$v2,$v3,$v4) = @_;
		return undef unless (defined($v1) && defined($v2) &&
					   		 defined($v3) && defined($v4) &&
							 defined($dta->{ENSEMBLE}[$ens]->{PITCH}) &&
							 defined($dta->{ENSEMBLE}[$ens]->{ROLL}));
	
		unless (@I2E &&
				$pitch == $dta->{ENSEMBLE}[$ens]->{PITCH} &&
				$roll  == $dta->{ENSEMBLE}[$ens]->{ROLL}) {
			printf(STDERR "$0: warning HEADING_ALIGNMENT == %g ignored\n",
						  $dta->{HEADING_ALIGNMENT})
				if ($dta->{HEADING_ALIGNMENT});
			$hdg   = $dta->{ENSEMBLE}[$ens]->{HEADING} - $dta->{HEADING_BIAS}
				if defined($dta->{ENSEMBLE}[$ens]->{HEADING});
			$pitch = $dta->{ENSEMBLE}[$ens]->{PITCH};
			$roll  = $dta->{ENSEMBLE}[$ens]->{ROLL};
			my($rad_gimbal_pitch) = atan(tan(rad($pitch)) * cos(rad($roll)));
			my($sh,$ch) = (sin(rad($hdg)),cos(rad($hdg)))
				if defined($hdg);				
			my($sp,$cp) = (sin($rad_gimbal_pitch),cos($rad_gimbal_pitch));
			my($sr,$cr) = (sin(rad($roll)),	cos(rad($roll)));
			@I2E = $dta->{ENSEMBLE}[$ens]->{XDUCER_FACING_UP}
				 ? (
					[-$ch*$cr-$sh*$sp*$sr,	$sh*$cp,-$ch*$sr+$sh*$sp*$cr],
					[-$ch*$sp*$sr+$sh*$cr,	$ch*$cp, $sh*$sr+$ch*$sp*$cr],
					[+$cp*$sr,				$sp,	-$cp*$cr,			],
				 ) : (
					[$ch*$cr+$sh*$sp*$sr,	$sh*$cp, $ch*$sr-$sh*$sp*$cr],
					[$ch*$sp*$sr-$sh*$cr,	$ch*$cp,-$sh*$sr-$ch*$sp*$cr],
					[-$cp*$sr,				$sp,	 $cp*$cr,			],
				 );
		}
		return defined($dta->{ENSEMBLE}[$ens]->{HEADING})
			   ? ($v1*$I2E[0][0]+$v2*$I2E[0][1]+$v3*$I2E[0][2],
				  $v1*$I2E[1][0]+$v2*$I2E[1][1]+$v3*$I2E[1][2],
				  $v1*$I2E[2][0]+$v2*$I2E[2][1]+$v3*$I2E[2][2],
				  $v4)
			   : (undef,undef,
				  $v1*$I2E[2][0]+$v2*$I2E[2][1]+$v3*$I2E[2][2],
				  $v4);
	}
} # STATIC SCOPE

#----------------------------------------------------------------------
# velEarthToInstrument() transforms earth to instrument coordinates
#	- based on manually inverted rotation matrix M (Sec 5.6 in coord-trans manual)
#	- missing heading data (IMP) causes undef beam velocities
#----------------------------------------------------------------------

{ # STATIC SCOPE
	my($hdg,$pitch,$roll,@E2I);

	sub velEarthToInstrument(@)
	{
		my($dta,$ens,$u,$v,$w,$ev) = @_;

		unless (@E2I) {
			$hdg = $dta->{ENSEMBLE}[$ens]->{HEADING} - $dta->{HEADING_BIAS} 
				if defined($dta->{ENSEMBLE}[$ens]->{HEADING});
			$pitch = $dta->{ENSEMBLE}[$ens]->{PITCH};
			$roll  = $dta->{ENSEMBLE}[$ens]->{ROLL};
			my($rad_gimbal_pitch) = atan(tan(rad($pitch)) * cos(rad($roll)));
			my($sh,$ch) = (sin(rad($hdg)),cos(rad($hdg)))
				if defined($hdg);				
			my($sp,$cp) = (sin($rad_gimbal_pitch),cos($rad_gimbal_pitch));
			my($sr,$cr) = (sin(rad($roll)),	cos(rad($roll)));
			@E2I = $dta->{ENSEMBLE}[$ens]->{XDUCER_FACING_UP}
				 ? (
					[$ch*-$cr+$sh*$sp*-$sr,	 $ch*$sp*-$sr-$sh*-$cr,	$cp*-$sr],
				    [$sh*$cp,				 $ch*$cp,				$sp		],
				    [$ch*-$sr-$sh*$sp*-$cr,	-$sh*-$sr-$ch*$sp*-$cr,	$cp*-$cr]
				 ) : (
					[$ch*$cr+$sh*$sp*$sr,	 $ch*$sp*$sr-$sh*$cr,	$cp*$sr	],
				    [$sh*$cp,				 $ch*$cp,				$sp		],
				    [$ch*$sr-$sh*$sp*$cr,	-$sh*$sr-$ch*$sp*$cr,	$cp*$cr	]
				 );
		}

		return defined($dta->{ENSEMBLE}[$ens]->{HEADING})
			   ? ($u*$E2I[0][0]+$v*$E2I[0][1]+$w*$E2I[0][2],
				  $u*$E2I[1][0]+$v*$E2I[1][1]+$w*$E2I[1][2],
				  $u*$E2I[2][0]+$v*$E2I[2][1]+$w*$E2I[2][2],
				  $ev)
			   : (undef,undef,undef,undef);

	}
} # STATIC SCOPE

#----------------------------------------------------------------------
# velInstrumentToBeam() transforms instrument to beam coordinates
#	- based on manually solved eq system in sec 5.3 of coord manual
#	- does not implement bin-remapping
#	- does not work for 3-beam solutions, as it is not known which
#	  beam was bad
#----------------------------------------------------------------------

{ # STATIC SCOPE
	my($a,$b,$c,$d);

	sub velInstrumentToBeam(@)
	{
		my($dta,$x,$y,$z,$ev) = @_;
		return undef unless (defined($x) + defined($y) +
					   		 defined($z) + defined($ev) == 4);

		unless (defined($a)) {
			$a = 1 / (2 * sin(rad($dta->{BEAM_ANGLE})));
			$b = 1 / (4 * cos(rad($dta->{BEAM_ANGLE})));
			$c = $dta->{CONVEX_BEAM_PATTERN} ? 1 : -1;
			$d = $a / sqrt(2);
		}

		return ( $x/(2*$a*$c) + $z/(4*$b) + $ev/(4*$d),
				-$x/(2*$a*$c) + $z/(4*$b) + $ev/(4*$d),
				-$y/(2*$a*$c) + $z/(4*$b) - $ev/(4*$d),
				 $y/(2*$a*$c) + $z/(4*$b) - $ev/(4*$d));

	}
} # STATIC SCOPE

#----------------------------------------------------------------------
# velEarthToBeam() combines velEarthToInstrument and velInstrumentToBeam
#----------------------------------------------------------------------

sub velEarthToBeam(@)
{
	my($dta,$ens,$u,$v,$w,$ev) = @_;
	return velInstrumentToBeam($dta,
				velEarthToInstrument($dta,$ens,$u,$v,$w,$ev));
}

#======================================================================
# velBeamToBPEarth(@) calculates the vertical- and horizontal vels
# from the two beam pairs separately. Note that (w1+w2)/2 is 
# identical to the w estimated according to RDI without 3-beam 
# solutions.
#======================================================================

{ # STATIC SCOPE
	my($TwoCosBAngle,$TwoSinBAngle);

	sub velBeamToBPEarth(@)
	{
		my($dta,$ens,$b1,$b2,$b3,$b4) = @_;
		my($v12,$w12,$v34,$w34);

		return (undef,undef,undef,undef) 
			unless (defined($dta->{ENSEMBLE}[$ens]->{PITCH}) &&
                    defined($dta->{ENSEMBLE}[$ens]->{ROLL}));

		unless (defined($TwoCosBAngle)) {
			$TwoCosBAngle = 2 * cos(rad($dta->{BEAM_ANGLE}));
			$TwoSinBAngle = 2 * sin(rad($dta->{BEAM_ANGLE}));
		}
		my($roll)  = rad($dta->{ENSEMBLE}[$ens]->{ROLL});							
		my($sr) = sin($roll); my($cr) = cos($roll);
		my($pitch) = atan(tan(rad($dta->{ENSEMBLE}[$ens]->{PITCH})) * $cr);	# gimbal pitch
		my($sp) = sin($pitch); my($cp) = cos($pitch);

		# Sign convention:
		#	- refer to Coord manual Fig. 3
		#	- v12 is horizontal velocity from beam1 to beam2, i.e. westward for upward-looking ADCP
		#	  with beam 3 pointing north (heading = 0)
		#	- w is +ve upward, regardless of instrument orientation

		my($v12_ic) = ($b1-$b2)/$TwoSinBAngle;							# instrument coords with w vertical up
		my($w12_ic) = ($b1+$b2)/$TwoCosBAngle;
		$w12_ic *= -1 if ($dta->{ENSEMBLE}[$ens]->{XDUCER_FACING_UP});
		my($v34_ic) = ($b3-$b4)/$TwoSinBAngle;
		my($w34_ic) = ($b3+$b4)/$TwoCosBAngle;
		$w34_ic *= -1 if ($dta->{ENSEMBLE}[$ens]->{XDUCER_FACING_UP});
	    
		if ($dta->{ENSEMBLE}[$ens]->{XDUCER_FACING_UP}) {				# beampair Earth coords
			$w12 = $w12_ic*$cr + $v12_ic*$sr - $v34_ic*$sp;
			$v12 = $v12_ic*$cr - $w12_ic*$sr + $w34_ic*$sp;
			$w34 = $w34_ic*$cp - $v34_ic*$sp + $v12_ic*$sr;
    	    $v34 = $v34_ic*$cp + $w34_ic*$sp - $w12_ic*$sr;
		} else {
			$w12 = $w12_ic*$cr - $v12_ic*$sr - $v34_ic*$sp;
			$v12 = $v12_ic*$cr + $w12_ic*$sr + $w34_ic*$sp;
			$w34 = $w34_ic*$cp - $v34_ic*$sp - $v12_ic*$sr;
        	$v34 = $v34_ic*$cp + $w34_ic*$sp + $w12_ic*$sr;
		}

		$v12=$w12=undef unless (defined($b1) && defined($b2));
		$v34=$w34=undef unless (defined($b3) && defined($b4));

		return ($v12,$w12,$v34,$w34);
	}
}

#===================================================================
# velBeamToBPInstrument(@) calculates the instrument-coordinate vels
# from the two beam pairs separately.
#===================================================================

{ # STATIC SCOPE
	my($TwoCosBAngle,$TwoSinBAngle);

	sub velBeamToBPInstrument(@)
	{
		my($dta,$ens,$b1,$b2,$b3,$b4) = @_;
		my($v12,$w12,$v34,$w34);

		return (undef,undef,undef,undef) 
			unless (defined($dta->{ENSEMBLE}[$ens]->{PITCH}) &&
                    defined($dta->{ENSEMBLE}[$ens]->{ROLL}));

		unless (defined($TwoCosBAngle)) {
			$TwoCosBAngle = 2 * cos(rad($dta->{BEAM_ANGLE}));
			$TwoSinBAngle = 2 * sin(rad($dta->{BEAM_ANGLE}));
		}

		# Sign convention:
		#	- refer to Coord manual Fig. 3
		#	- v12 is horizontal velocity from beam1 to beam2
		#	- w is +ve upward, regardless of instrument orientation

		if (defined($b1) && defined($b2)) {
			$v12 = ($b1-$b2)/$TwoSinBAngle;
			$w12 = ($b1+$b2)/$TwoCosBAngle;
			$w12 *= -1 if ($dta->{ENSEMBLE}[$ens]->{XDUCER_FACING_UP});
		}
		if (defined($b3) && defined($b4)) {
			$v34 = ($b3-$b4)/$TwoSinBAngle;
			$w34 = ($b3+$b4)/$TwoCosBAngle;
			$w34 *= -1 if ($dta->{ENSEMBLE}[$ens]->{XDUCER_FACING_UP});
		}

		return ($v12,$w12,$v34,$w34);
	}
}

#======================================================================
# velApplyHdgBias() applies the heading bias, which is used to correct
# for magnetic declination for data recorded in Earth-coordinates ONLY.
# Bias correction for beam-coordinate data is done in velInstrumentToEarth()
#======================================================================

sub velApplyHdgBias(@)
{
	my($dta,$ens,$v1,$v2,$v3,$v4) = @_;
	return (undef,undef,undef,undef) 
		unless (defined($v1) && defined($v2) &&
				defined($dta->{ENSEMBLE}[$ens]->{HEADING}));

	my($sh) = sin(rad(-$dta->{HEADING_BIAS}));
	my($ch) = cos(rad(-$dta->{HEADING_BIAS}));

	return ( $v1*$ch + $v2*$sh,
			-$v1*$sh + $v2*$ch,
			 $v3			  ,
			 $v4			  );
}

#----------------------------------------------------------------------
# Pitch/Roll Functions
#----------------------------------------------------------------------

sub gimbal_pitch($$)	# RDI coord trans manual
{
	my($RDI_pitch,$RDI_roll) = @_;
	return 'nan' unless defined($RDI_pitch) && defined($RDI_roll);
	return deg(atan(tan(rad($RDI_pitch)) * cos(rad($RDI_roll))));
}

sub RDI_pitch($$)
{
	my($gimbal_pitch,$roll) = @_;
	return 'nan' unless defined($gimbal_pitch) && defined($roll);
	return deg(atan(tan(rad($gimbal_pitch))/cos(rad($roll))));
}

sub tilt_azimuth($$)
{
	my($gimbal_pitch,$roll) = @_;
	return 'nan' unless defined($gimbal_pitch) && defined($roll);
	return angle(deg(atan2(sin(rad($gimbal_pitch)),sin(rad($roll)))));
}

# - angle from vertical is home grown
# - angle between two unit vectors given by acos(v1 dot v2)
# - vertical unit vector v1 = (0 0 1) => dot product = z-component of v2
# - when vertical unit vector is pitched in x direction, followed by
#	roll in y direction:
#		x = sin(pitch)
#		y = cos(pitch) * sin(roll)
#		z = cos(pitch) * cos(roll)
#			has been checked with sqrt(x^2+y^2+z^2) == 1
# - for small angles, this is very similar to sqrt(pitch^2+roll^2)

sub angle_from_vertical($$)
{
	my($RDI_pitch,$RDI_roll) = @_;
	return 'nan' unless defined($RDI_pitch) && defined($RDI_roll);
	my($rad_pitch) = atan(tan(rad($RDI_pitch)) * cos(rad($RDI_roll)));
	return deg(acos(cos($rad_pitch) * cos(rad($RDI_roll))));
}

1;
