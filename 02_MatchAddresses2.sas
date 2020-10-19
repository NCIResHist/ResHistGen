/* Match vendor addresses part 2: add manual review results (if any) and combine matched addresses */

/* This program was developed by Westat, Inc. under NCI contracts HHSN261201500371P and HHSN261201600004B */
/* Version 2.1, copyright 2020 */
/* If you publish results based on these programs, please include the following citation:
    ResHistGen Residential History Generation Programs, Version 2.1 - October 2020;
    Surveillance Research Program, National Cancer Institute.
*/

/* The program is distributed under the terms of the GNU General Public License:

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details <http://www.gnu.org/licenses/>.
*/

/* Was manual review performed? */
%let ManReview = Yes;
/* Geocode_Level value for missing */
%let MissingGeoLevel = 9-UnableToMatch;

/* Matching parameters */
%let StNameDist = 1000;        /* Streetname match distance threshold in meters */
%let GeoLvlMax = 2;            /* Maximum geocoding precision level for streetname match */

/* Specify data path here: */
%let path=C:\ResHist_Work;

libname RHISTLIB "&path.";
ods pdf file="&path.\02_MatchAddresses2.pdf";


/* Get a copy of the match combo and dataset the original addresses */
data LN_MatchCombos;
    set RHISTLIB.LN_MatchCombos;
run;
data Hist_LN_OrigAddrs;
    set RHISTLIB.LexisNexis_Addresses;
run;


%MACRO GetManReviewResults;
%if &ManReview. = %quote(Yes) %then %do;
/* Import the StreetName manual review results */
PROC IMPORT OUT=LN_ReviewResults
            DATAFILE="&path.\LN_matchcombos_review.xlsx"
            DBMS=EXCEL REPLACE;
     RANGE="ReviewResults$";
     GETNAMES=YES;
     MIXED=NO;
     SCANTEXT=YES;
     USEDATE=YES;
     SCANTIME=YES;
run;
/* Merge the StreetName manual review results */
proc sort data=LN_MatchCombos nodupkeys; by f1AddrID f2AddrID; run;
proc sort data=LN_ReviewResults nodupkeys; by f1AddrID f2AddrID; run;
data LN_MatchCombos2;
    merge LN_MatchCombos (in=inOrig)
        LN_ReviewResults (in=inRev keep=f1AddrID f2AddrID);
    by f1AddrID f2AddrID;
    if inRev and not inOrig then putlog '*** Missing original combo for ' f1AddrID f2AddrID;
    if inRev and inOrig then StreetName_match = 1;
    if not inRev and inOrig and (StreetName_match = .) then StreetName_match = 0;
    if StreetName_match = . then putlog '*** Unexpected missing StreetName_match flag for ' f1AddrID f2AddrID;
run;
%end; /* &ManReview. = Yes */
%else %do; /* &ManReview. ^= Yes */
data LN_MatchCombos2;
    set LN_MatchCombos;
run;
%end; /* &ManReview. ^= Yes */
%MEND GetManReviewResults;

%GetManReviewResults;


/* Set final match flags */
data LN_MatchCombos3;
    set LN_MatchCombos2;
    /* Special test for valid alternative city names like Gaithersburg MD and N. Potomac MD: */
    if City_match = 0 and StreetName_match = 1 and LatLon_dist ^= . and LatLon_dist < 100 then do;
        City_match = 1;
        /* For debugging:
        putlog '*** Alt city names: ';
        putlog '    File1: ' f1StreetName f1City f1StAbbr f1ZIP_text;
        putlog '    File2: ' f2StreetName f2City f2StAbbr f2ZIP_text;
        putlog '    Dist: ' LatLon_dist;  /* End of code for debugging */
        end;
    if StreetAddr_match and StreetName_match and ((City_match and StAbbr_match) or (ZIP5_match)) then
        Full_match = 1;
    else Full_match = 0;
    if StreetName_match and ((City_match and StAbbr_match) or (ZIP5_match)) then
        StreetCityState_match = 1;
    else StreetCityState_match = 0;
    if (City_match and StAbbr_match) or ZIP5_match then
        CityState_match = 1;
    else CityState_match = 0;
run;

/* Select the true matches */
data LN_TrueMatches;
    set LN_MatchCombos3;
    Match_pattern = put(Full_match,1.) || '-' ||
        put(StreetCityState_match,1.) || '-' ||
        put(CityState_match,1.) || '-' ||
        put(StAbbr_match,1.);
    /* Keep only full or street-level matches */
    if (Match_pattern ^= '1-1-1-1') and (Match_pattern ^= '0-1-1-1') then delete;
    f1GeoLvlNum = input(substr(f1Geocode_Level,1,1),BEST.);
    f2GeoLvlNum = input(substr(f2Geocode_Level,1,1),BEST.);
    /* Delete street-level matches with good geocodes where the distance is more than &StNameDist. meters */
    if (Match_pattern = '0-1-1-1') and
        (f1GeoLvlNum <= &GeoLvlMax.) and (f2GeoLvlNum <= &GeoLvlMax.) and
        (LatLon_dist > &StNameDist.) then delete;
    keep PersID f1: f2: LatLon_dist Match_pattern;
    format LatLon_dist 10.3;
run;

/* Create groups of commons addresses */
proc sort data=LN_TrueMatches; by PersID f1AddrID; run;
data Hist_LN_MergedAddrs;
    length PersID AddrGrp 8 OutAddr1-OutAddr50
        r1c1-r1c50 r2c1-r2c50 r3c1-r3c50 r4c1-r4c50 r5c1-r5c50
        r6c1-r6c50 r7c1-r7c50 r8c1-r8c50 r9c1-r9c50 r10c1-r10c50
        r11c1-r11c50 r12c1-r12c50 r13c1-r13c50 r14c1-r14c50 r15c1-r15c50
        r16c1-r16c50 r17c1-r17c50 r18c1-r18c50 r19c1-r19c50 r20c1-r20c50 $8;
    array OutAddr{50} OutAddr1-OutAddr50;
    array Tbl{20,50} r1c1-r1c50 r2c1-r2c50 r3c1-r3c50 r4c1-r4c50 r5c1-r5c50
        r6c1-r6c50 r7c1-r7c50 r8c1-r8c50 r9c1-r9c50 r10c1-r10c50
        r11c1-r11c50 r12c1-r12c50 r13c1-r13c50 r14c1-r14c50 r15c1-r15c50
        r16c1-r16c50 r17c1-r17c50 r18c1-r18c50 r19c1-r19c50 r20c1-r20c50;
    retain r1c1-r1c50 r2c1-r2c50 r3c1-r3c50 r4c1-r4c50 r5c1-r5c50
        r6c1-r6c50 r7c1-r7c50 r8c1-r8c50 r9c1-r9c50 r10c1-r10c50
        r11c1-r11c50 r12c1-r12c50 r13c1-r13c50 r14c1-r14c50 r15c1-r15c50
        r16c1-r16c50 r17c1-r17c50 r18c1-r18c50 r19c1-r19c50 r20c1-r20c50 ''
        found_f1_r found_f2_r .;
    set LN_TrueMatches;
    by PersID;
    /* Search for f1AddrID and f2AddrID in the Tbl array for this PersID */
    r=1; c=1;
    do while (Tbl(r,1) ^= '');
        c=1;
        do while (Tbl(r,c) ^= '');
            if Tbl(r,c) = f1AddrID then found_f1_r = r;
            if Tbl(r,c) = f2AddrID then found_f2_r = r;
            c+1;
            if c > 50 then putlog '*** Exceeded column array limit, PersID=' PersID;
            end;
        r+1;
        if r > 20 then putlog '*** Exceeded row array limit, PersID=' PersID;
        end;
    /* For debugging */
    /* if PersID = 44 then putlog '*** PersID=' PersID ' r=' r ' c=' c
        ' found_f1_r=' found_f1_r ' found_f2_r=' found_f2_r; /* For debugging */
    /* Update the Tbl array for this matched pair */
    if (found_f1_r = .) and (found_f2_r = .) then do; /* Did not find either address */
        /* Add f1AddrID and f2AddrID to a new row */
        Tbl(r,1) = f1AddrID;
        Tbl(r,2) = f2AddrID;
        end;
    else if (found_f1_r ^= .) and (found_f2_r = .) then do; /* Just found f1AddrID */
        /* Add f2AddrID to the same row as f1AddrID */
        /* Find the first empty column in row found_f1_r */
        c=1;
        do while (Tbl(found_f1_r,c) ^= '');
            c+1;
            end;
        /* Check for overwrite */
        if Tbl(found_f1_r,c) ^= '' then
            putlog '*** Tbl array overwrite, PersID=' PersID ' row=' found_f1_r ' col=' c
                ' current_entry=' Tbl(found_f1_r,c) ' new_entry=' f2AddrID;
        /* Add the entry */
        Tbl(found_f1_r,c) = f2AddrID;
        end;
    else if (found_f1_r = .) and (found_f2_r ^= .) then do; /* Just found f2AddrID */
        /* Add f1AddrID to the same row as f2AddrID */
        /* Find the first empty column in row found_f2_r */
        c=1;
        do while (Tbl(found_f2_r,c) ^= '');
            c+1;
            end;
        /* Check for overwrite */
        if Tbl(found_f2_r,c) ^= '' then
            putlog '*** Tbl array overwrite, PersID=' PersID ' row=' found_f2_r ' col=' c
                ' current_entry=' Tbl(found_f2_r,c) ' new_entry=' f1AddrID;
        /* Add the entry */
        Tbl(found_f2_r,c) = f1AddrID;
        end;
    /* Else, found both addresses - don't do anything */
    /* Clear the array for next PersID */
    if last.PersID then do;
        r=1;
        do while (Tbl(r,1) ^= '');
            AddrGrp = r;
            do c=1 to 50;
                OutAddr(c) = Tbl(r,c);
                end;
            output;
            do c=1 to 50;
                Tbl(r,c)='';
                end;
            r+1;
            if r > 20 then putlog '*** Exceeded row array limit, PersID=' PersID;
            end;
        end;
    found_f1_r=.; found_f2_r=.;
    keep PersID AddrGrp OutAddr1-OutAddr50;
run;

/* Decompose into individual records and add location and date info */
data Hist_LN_SingleAddrs;
    set Hist_LN_MergedAddrs;
    array OutAddr{50} OutAddr1-OutAddr50;
    i=1;
    do while (OutAddr(i) ^= '');
        AddrID = OutAddr(i);
        output;
        i+1;
        end;
    keep PersID AddrGrp AddrID;
run;
/* Add geocoded location info and from/to dates */
proc sort data=Hist_LN_SingleAddrs; by PersID AddrID; run;
proc sort data=Hist_LN_OrigAddrs; by PersID AddrID; run;
data Hist_LN_SingleAddrs2;
    merge Hist_LN_SingleAddrs (in=inSingle)
        Hist_LN_OrigAddrs (in=inOrig);
    by PersID AddrID;
    if inSingle;
    if not inOrig then putlog '*** Missing original address, PersID=' PersID ' AddrID=' AddrID;
run;

/* Calculate preferred location for each group */
proc sort data=Hist_LN_SingleAddrs2; by PersID AddrGrp; run;
data Hist_LN_GrpPrefLocs;
    length PersID AddrGrp num_in num_used 8 Pref_GeoLevel $15;
    retain num_in num_used 0
        Pref_Lat Pref_Lon . Pref_GeoLevel ''
        From_date_1stAddr To_date_1stAddr .;
    set Hist_LN_SingleAddrs2;
    by PersID AddrGrp;
    num_in+1;
    if Pref_GeoLevel = '' then do;
        Pref_Lat = Lat;
        Pref_Lon = Lon;
        Pref_GeoLevel = Geocode_Level;
        num_used = 1;
        end;
    else if substr(Geocode_Level,1,1) < substr(Pref_GeoLevel,1,1) then do;
        Pref_Lat = Lat;
        Pref_Lon = Lon;
        Pref_GeoLevel = Geocode_Level;
        num_used = 1;
        end;
    else if (Geocode_Level = Pref_GeoLevel) and (Geocode_Level ^= "&MissingGeoLevel.") then do;
        if (Pref_Lat = .) or (Lat = .) or (Pref_Lon = .) or (Lon = .) then
            putlog '*** Unexpected missing lat/lon value1, PersID=' PersID ' AddrGrp=' Addrgrp;
        Pref_Lat = Pref_Lat + Lat;
        Pref_Lon = Pref_Lon + Lon;
        num_used+1;
        end;
    /* Else do nothing */
    if (From_date_1stAddr = .) and (From_date ^= .) then do;
        From_date_1stAddr = From_date;
        To_date_1stAddr = To_date;
        end;
    if last.AddrGrp then do;
        if num_used = 0 then putlog '*** No selected locations, PersID=' PersID ' AddrGrp=' Addrgrp;
        if num_used > 1 then do;
            if (Pref_Lat = .) or (Pref_Lon = .) then
                putlog '*** Unexpected missing lat/lon value2, PersID=' PersID ' AddrGrp=' Addrgrp;
            Pref_Lat = Pref_Lat / num_used;
            Pref_Lon = Pref_Lon / num_used;
            end;
        output;
        num_in=0; num_used=0;
        Pref_Lat=.; Pref_Lon=.; Pref_GeoLevel='';
        From_date_1stAddr=.; To_date_1stAddr=.;
        end;
    keep PersID AddrGrp num_in num_used Pref: From_date_1stAddr To_date_1stAddr;
    format From_date_1stAddr To_date_1stAddr DATE9.;
run;

/* Add the results to the MergedAddrs dataset */
proc sort data=Hist_LN_MergedAddrs; by PersID AddrGrp; run;
proc sort data=Hist_LN_GrpPrefLocs; by PersID AddrGrp; run;
data Hist_LN_MergedAddrs2;
    length PersID AddrGrp NumAddrs 8;
    merge Hist_LN_MergedAddrs (in=inMerged)
        Hist_LN_GrpPrefLocs (in=inGrpPrefs);
    by PersID AddrGrp;
    if inMerged;
    if not inGrpPrefs then
        putlog '*** Missing preferred location info, PersID=' PersID ' AddrGrp=' Addrgrp;
    NumAddrs = num_in;
    drop num_in num_used;
run;

/* Add unmatched addresses - addresses that were not matched in the combo dataset */
data Hist_LN_MatchedAddrs;
    set LN_TrueMatches;
    AddrID = f1AddrID;
    output;
    AddrID = f2AddrID;
    output;
    keep PersID AddrID;
run;
proc sort data=Hist_LN_MatchedAddrs nodupkeys out=Hist_LN_MatchedAddrs2;
    by PersID AddrID;
run;
proc sort data=Hist_LN_OrigAddrs; by PersID AddrID; run;
data Hist_LN_UnMatched;
    merge Hist_LN_OrigAddrs (in=inAllAddrs)
        Hist_LN_MatchedAddrs2 (in=inMatched);
    by PersID AddrID;
    if inAllAddrs and not inMatched;
    NumAddrs = 1;
    keep PersID NumAddrs AddrID Geocode_Level Lat Lon From_date To_date;
    rename
        AddrID=OutAddr1
        Geocode_Level=Pref_GeoLevel
        Lat=Pref_Lat
        Lon=Pref_Lon
        From_date=From_date_1stAddr
        To_date=To_date_1stAddr;
run;
/* Append UnMatched addresses to MergedAddr2 and add a Group ID */
data Hist_LN_MergedAddrs3;
    length PersID AddrGrp 8 GrpID $8 NumAddrs 8;
    set Hist_LN_MergedAddrs2
        Hist_LN_UnMatched;
    if AddrGrp = . then GrpID = OutAddr1;
    else GrpID = 'GP' || put(PersID,z3.) || put(AddrGrp,z3.);
run;
proc sort data=Hist_LN_MergedAddrs3;
    by PersID From_date_1stAddr;
run;


/* Keep a copy of the OrigAddrs and the final MergedAddrs datasets */
data RHISTLIB.Hist_LN_OrigAddrs;
    set Hist_LN_OrigAddrs;
run;
data RHISTLIB.Hist_LN_MergedAddrs;
    set Hist_LN_MergedAddrs3;
run;


/* Summary statistics */

title1 "02_MatchAddresses2 - Summary statistics";
title2 "Final combined results with unmatched addresses";
proc freq data=Hist_LN_MergedAddrs3;
    tables AddrGrp / missing;
    tables NumAddrs / missing;
run;
proc summary data=Hist_LN_MergedAddrs3 noprint nway;
    class PersID;
    output out=Summ_LN_PersID;
run;
data Summ_LN_PersID2;
    set Summ_LN_PersID;
    Num_MergedAddrs = _FREQ_;
    drop _TYPE_ _FREQ_;
    label Num_MergedAddrs = 'Number of addresses (rows) per person';
run;
proc freq data=Summ_LN_PersID2;
    tables Num_MergedAddrs / missing;
run;
data Summ_temp;
    set Hist_LN_MergedAddrs3;
    label NumAddrs = 'Number of addresses per row';
run;
proc freq data=Summ_temp;
    tables NumAddrs / missing;
run;
title2 "Combined results without unmatched addresses";
proc freq data=Hist_LN_MergedAddrs2;
    tables AddrGrp / missing;
    tables NumAddrs / missing;
run;
proc summary data=Hist_LN_MergedAddrs2 noprint nway;
    class PersID;
    output out=Summ_LN_PersID;
run;
data Summ_temp1;
    set Summ_LN_PersID;
    Num_MergedAddrs = _FREQ_;
    drop _TYPE_ _FREQ_;
    label Num_MergedAddrs = 'Number of addresses (rows) per person';
run;
proc freq data=Summ_temp1;
    tables Num_MergedAddrs / missing;
run;
data Summ_temp2;
    set Hist_LN_MergedAddrs2;
    label NumAddrs = 'Number of addresses per row';
run;
proc freq data=Summ_temp2;
    tables NumAddrs / missing;
run;


ods pdf close;
