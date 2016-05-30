#======================================================================
#                    A D C P _ T O O L S _ L I B . P L 
#                    doc: Tue Jan  5 10:45:47 2016
#                    dlm: Thu May 26 10:40:42 2016
#                    (c) 2016 A.M. Thurnherr
#                    uE-Info: 12 25 NIL 0 0 72 0 2 4 NIL ofnI
#======================================================================

# HISTORY:
#	Jan  5, 2015: - created

$ADCP_tools_version = 1.7;

die(sprintf("$0: obsolete ADCP_tools V%.1f; V%.1f required\n",
    $ADCP_tools_version,$ADCP_tools_minVersion))
        if (!defined($ADCP_tools_minVersion) || $ADCP_tools_minVersion>$ADCP_tools_version);

require "$ADCP_TOOLS/RDI_Coords.pl";
require "$ADCP_TOOLS/RDI_PD0_IO.pl";
require "$ADCP_TOOLS/RDI_Utils.pl";

