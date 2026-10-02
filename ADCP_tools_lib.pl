#======================================================================
#                    A D C P _ T O O L S _ L I B . P L 
#                    doc: Tue Jan  5 10:45:47 2016
#                    dlm: Fri Oct  2 08:07:55 2026
#                    (c) 2016 A.M. Thurnherr
#                    uE-Info: 25 25 NIL 0 0 72 0 2 4 NIL ofnI
#======================================================================

# HISTORY:
#	Jan  5, 2015: - created
#	...
#	Aug 23, 2016: - updated to V1.8
#	Mar 12, 2017: - updated to V1.9 for LADCP_w 1.3
#	Nov 28, 2017: - updated to V2.0 for LADCP_w 1.4
#	Dec  7, 2017: - updated to V2.1 for improvements to listHdr
#	Feb  6, 2018: - updated to V2.2 for changes to PD0_IO
#	Apr 20, 2020: - updated to V2.3 after adaptating to work with IMPed moored ADCP data
#	Mar 23, 2021: - updated to V2.4 after starting adaption to Nortek produced PD0 files
#	Dec  6, 2022: - updated to V2.5 for LADCP_w V2.2
#	Mar 15, 2024: - updated to V2.6 for LADCP_w V2.4
#	Aug 23, 2024: - updated to V2.7 for GitHUB release
#	Oct 31, 2025: - updated to V2.8 for GitHUB update
#	Oct  2, 2026: - updated to V2.9 for GitHUB update

$ADCP_tools_version = 2.9;

die(sprintf("$0: obsolete ADCP_tools V%.1f; V%.1f required\n",
    $ADCP_tools_version,$ADCP_tools_minVersion))
        if (!defined($ADCP_tools_minVersion) || $ADCP_tools_minVersion>$ADCP_tools_version);

require "$ADCP_TOOLS/RDI_Coords.pl";
require "$ADCP_TOOLS/RDI_PD0_IO.pl";
require "$ADCP_TOOLS/RDI_Utils.pl";

