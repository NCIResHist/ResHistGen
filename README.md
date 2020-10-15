# ResHistGen
NCI software to generate residential histories from address data

As part of the National Cancer Institute’s residential history pilot project, Westat created “ResHistGen,” a set of open-source SAS programs that will help researchers and others reconcile data from commercial vendors and generate residential histories of study participants. 

The steps to use the ResHistGen programs for the creation of residential histories of research subjects can be performed by staff at the cancer registry, members of the research team, or staff at a third-party contractor. Individual patient identifiers are needed for this process. It is essential that the researcher follow established procedures to protect the privacy of human subjects.

1.	Submit subject names and identifiers for relevant cases to the vendor.
2.	Geocode the addresses received from the commercial vendor. All U.S. cancer registries have access to the North American Association of Central Cancer Registries (NAACCR) geocoder, but any batch geocoder can be used.
3.	Run the first SAS program (01_MatchAddresses1.sas) to match common addresses. For a study with a small number of study subjects, possible matches can be reviewed manually in a two-step process. For a study with a large number of subjects, this can be done automatically in a single step.
4.	If a manual review is desired, edit the “LN_matchcombos_review.xlsx” created by the first program by deleting rows that are not matches. This review can be guided by the NCI SEER Manual Address Comparison Guidelines.
5.	Run the second SAS program (02_MatchAddresses2.sas) to add any results from the manual review and combine matched addresses.
6.	Run the third SAS program (03_BuildResHistory.sas) to reconcile addresses and generate a derived residential history.

The current release of these programs is Version 2.1.  For a summary of changes since the previous release, see Version 2.1 Changes.txt.

In the ResHistGen programs, local file locations are specified in the first few lines of each program to facilitate portability. The programs have been written to avoid any data conversion or divide-by-zero warning messages; if these occur, there is an error. There are tests for unexpected conditions, and messages are generated with three asterisks if any unexpected conditions are encountered.

The ResHistGen programs are released under the GNU General Public License. For questions, limited support is available by email at NCI.ResidentialHistory@westat.com; enhancements may also be shared via this email address and if found to be beneficial, they will be included in a future release. By the terms of the license, you may distribute your changes on your own provided you include a prominent notice that you have modified the original.

If you publish results based on these programs, please include the following citation: ResHistGen Residential History Generation Programs, Version 2.1 - October 2020; Surveillance Research Program, National Cancer Institute.


