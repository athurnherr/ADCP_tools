#======================================================================
#                    A D C P _ T O O L S _ L I B . P L 
#                    doc: Tue Jan  5 10:45:47 2016
#                    dlm: Mon Nov 20 10:21:30 2017
#                    (c) 2016 A.M. Thurnherr
#                    uE-Info: 14 57 NIL 0 0 72 0 2 4 NIL ofnI
#======================================================================

# HISTORY:
#	Jan  5, 2015: - created
#	...
#	Aug 23, 2016: - updated to V1.8
#	Mar 12, 2017: - updated to V1.9 for LADCP_w 1.3
#	Nov 20, 2017: - updated to V2.0 to include [patchPD0]

$ADCP_tools_version = 2.0;

die(sprintf("$0: obsolete ADCP_tools V%.1f; V%.1f required\n",
    $ADCP_tools_version,$ADCP_tools_minVersion))
        if (!defined($ADCP_tools_minVersion) || $ADCP_tools_minVersion>$ADCP_tools_version);

require "$ADCP_TOOLS/RDI_Coords.pl";
require "$ADCP_TOOLS/RDI_PD0_IO.pl";
require "$ADCP_TOOLS/RDI_Utils.pl";

