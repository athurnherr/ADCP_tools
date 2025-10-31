#======================================================================
#                    M A K E F I L E 
#                    doc: Tue May 15 18:12:31 2012
#                    dlm: Fri Oct 31 18:35:02 2025
#                    (c) 2012 A.M. Thurnherr
#                    uE-Info: 11 34 NIL 0 0 72 0 2 4 NIL ofnI
#======================================================================

.PHONY: version
version:
	@grep 'ADCP_tools_version = ' ADCP_tools_lib.pl

.PHONY: publish
publish:
	cd ..; \
	scp -Cr ADCP_tools miles:public_hg
