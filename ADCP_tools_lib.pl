#======================================================================
#                    A D C P _ T O O L S _ L I B . P L 
#                    doc: Tue Jan  5 10:45:47 2016
#                    dlm: Tue Dec  6 12:34:10 2022
#                    (c) 2016 A.M. Thurnherr
#                    uE-Info: 21 25 NIL 0 0 72 0 2 4 NIL ofnI
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

$ADCP_tools_version = 2.5;

die(sprintf("$0: obsolete ADCP_tools V%.1f; V%.1f required\n",
    $ADCP_tools_version,$ADCP_tools_minVersion))
        if (!defined($ADCP_tools_minVersion) || $ADCP_tools_minVersion>$ADCP_tools_version);

require "$ADCP_TOOLS/RDI_Coords.pl";
require "$ADCP_TOOLS/RDI_PD0_IO.pl";
require "$ADCP_TOOLS/RDI_Utils.pl";

