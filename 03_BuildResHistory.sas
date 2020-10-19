/* Step 3: Build residential histories from vendor data */

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

/* Specify data path here: */
%let path=C:\ResHist_Work;

/* This algorithm generates an address history from address data that is assumed to have
    duplicate addresses and gaps in time.  The resulting history describes how people move from
    one place to the next over time.  The algorithm does not have support for people with more than
    one residence at a particular point of time or people who move back to a former residence. */

/* Optional algoithm parameters - see tech report for more information: */
/* Trimming limits used for combining time-frames */
%let lowertimepct=0;
%let uppertimepct=100;
/* Restrict trimming of time-frames to groups of addresses */
%let trimgrpsonly=True;
/* Address duration minimum in days */
%let durInMin=32;  /* Input address minimum in days (1 month) */
%let durOutMin=0;  /* Output address minimum in days */

libname RHISTLIB "&path.";
ods pdf file="&path.\03_BuildResHistory.pdf";

/* Macro to check the validity of the generated histories (no gaps or overlaps) */
%macro CheckHist(Dataset);
proc sort data=&dataset.; by PersID From_date; run;
data _null_;
    retain prev_To_date .;
    set &dataset. end = eof;
    by PersID;
    if (prev_To_date ^= .) and (From_date ^= prev_To_date) then do;
            putlog "*** Warning From_date not equal to previous To_date for PersID: " PersID;
            putlog "***     From_date=" From_date " prev_To_date=" prev_To_date;
    end;
    if last.PersID then prev_To_date = .;
    else prev_To_date = To_date;
    format prev_To_date DATE9.;
run;
%mend CheckHist;

/* Get copies of the OrigAddrs and the final MergedAddrs datasets */
data Hist_LN_OrigAddrs;
    set RHISTLIB.Hist_LN_OrigAddrs;
run;

data Hist_LN_MergedAddrs;
    set RHISTLIB.Hist_LN_MergedAddrs;
run;

/* For each address group, combine time frames */

/* Decompose into individual address records */
data Hist_LN_SingleAddrs;
    set Hist_LN_MergedAddrs;
    array OutAddr{50} OutAddr1-OutAddr50;
    i=1;
    do while (OutAddr(i) ^= '');
        AddrID = OutAddr(i);
        output;
        i+1;
        end;
    keep PersID GrpID AddrID;
run;

/* Add individual from/to dates */
proc sort data=Hist_LN_SingleAddrs; by PersID AddrID; run;
proc sort data=Hist_LN_OrigAddrs; by PersID AddrID; run;
data Hist_LN_SingleAddrs2;
    merge Hist_LN_SingleAddrs (in=inSingle)
        Hist_LN_OrigAddrs (in=inOrig keep=PersID AddrID From_date To_date);
    by PersID AddrID;
    if inSingle;
    if not inOrig then putlog '*** Missing original address, PersID=' PersID ' AddrID=' AddrID;
run;

/* Write a record for each month in the input time period */
data Hist_LN_SingleMonths;
    set Hist_LN_SingleAddrs2 /* (obs=5) */ ;
    if (From_date = .) then output;
    else do;
        this_yyyymm = mdy(month(From_date),1,year(From_date));
        do while (this_yyyymm < To_date);
            this_year = year(this_yyyymm);
            this_month = month(this_yyyymm);
            output;
            this_yyyymm = intnx('month',this_yyyymm,1);
            end; /* Do while */
        end; /* From_date not missing */
    keep PersID GrpID AddrID this_yyyymm this_year this_month; /* Comment out for testing */
    format this_yyyymm YYMMD7.;
run;
/* Sort by month within PersID and GrpID */
proc sort data=Hist_LN_SingleMonths;
    by PersID GrpID this_yyyymm;
run;
/* Get total months for each group */
data Hist_LN_GrpSumMonths;
    retain SumMonths 0 NumDates 0 MaxNumDates 0;
    set Hist_LN_SingleMonths;
    by PersID GrpID this_yyyymm;
    if (this_yyyymm ^= .) then do;
        SumMonths = SumMonths + 1;
        NumDates = NumDates + 1;
        end;
    if last.this_yyyymm then do;
        if NumDates > MaxNumDates then MaxNumDates = NumDates;
        NumDates = 0;
        end;
    if last.GrpID then do;
        output;
        SumMonths = 0;
        MaxNumDates = 0;
        end;
    keep PersID GrpID SumMonths MaxNumDates;
run;
/* Add SumMonths to the SingleMonths dataset and calculate the cummulative percent */
proc sort data=Hist_LN_SingleMonths; by PersID GrpID this_yyyymm; run;
proc sort data=Hist_LN_GrpSumMonths; by PersID GrpID; run;
data Hist_LN_SingleMonths2;
    retain CummMonths 0;
    merge Hist_LN_SingleMonths (in=inSingle)
        Hist_LN_GrpSumMonths (in=inGrpSum);
    by PersID GrpID;
    if inSingle;
    if not inGrpSum then putlog '*** Month sum missing, PersID=' PersID ' GrpID=' GrpID;
    if SumMonths ^= 0 then do;
        if this_yyyymm ^= . then CummMonths = CummMonths + 1;
        CummPct = (CummMonths * 100) / SumMonths;
        end;
    if last.GrpID then CummMonths = 0;
    format CummMonths 8.1 CummPct 8.3;
    drop CummMonths SumMonths; /* Keep for testing */
run;
/* Get Comb_From_date and Comb_To_date for each GrpID */
proc sort data=Hist_LN_SingleMonths2; by PersID GrpID this_yyyymm; run;
%MACRO CombDates; /* Macro needed for the %if &trimgrpsonly. test */
data Hist_LN_GrpCombDates;
    retain Comb_From_date and Comb_To_date .;
    set Hist_LN_SingleMonths2;
    by PersID GrpID;
    LowerLimit = &lowertimepct.;
    UpperLimit = &uppertimepct.;
    %if &trimgrpsonly. = %quote(True) %then %do;
        if substr(GrpID,1,2) ^= 'GP' then do;
            LowerLimit = 0;
            UpperLimit = 100;
            end;
    %end;
    if (Comb_From_date = .) and (CummPct >= LowerLimit) then
        Comb_From_date = this_yyyymm; /* First day of the month */
    if (Comb_To_date = .) and (CummPct >= UpperLimit) then
        Comb_To_date = intnx('month',this_yyyymm,1) - 1; /* Last day of the month */
    if last.GrpID then do;
        output;
        Comb_From_date = .;
        Comb_To_date = .;
        end;
    keep PersID GrpID Comb_From_date Comb_To_date MaxNumDates
        /* LowerLimit UpperLimit /* Keep for testing */;
    format Comb_From_date Comb_To_date DATE9.;
run;
%MEND CombDates;
%CombDates;
/* Add the results to the MergedAddrs dataset */
proc sort data=Hist_LN_MergedAddrs; by PersID GrpID; run;
proc sort data=Hist_LN_GrpCombDates; by PersID GrpID; run;
data Hist_LN_MergedAddrs2;
    length PersID AddrGrp 8 GrpID $8 NumAddrs 8;
    merge Hist_LN_MergedAddrs (in=inMerged)
        Hist_LN_GrpCombDates (in=inGrpCombs);
    by PersID GrpID;
    if inMerged;
    if not inGrpCombs then
        putlog '*** Missing combined date info, PersID=' PersID ' GrpID=' GrpID;
run;


/* Weed out short duration addresses based on "&durInMin" and those with missing date info */
data Hist_LN_MergedAddrs3;
    set Hist_LN_MergedAddrs2;
    if (Comb_From_date = .) or (Comb_To_date = .) then delete;
    Comb_Durdays = Comb_To_date - Comb_From_date + 1;
    if Comb_Durdays < &durInMin. then delete;
run;


/* Generate the residential history - determine the processing order and adjust the dates */

/* Identify the current (most-recent) address */
proc sort data=Hist_LN_MergedAddrs3;
    by PersID Comb_To_date Comb_From_date NumAddrs;
run;
data Hist_LN_Working1;
    set Hist_LN_MergedAddrs3;
    by PersID Comb_To_date Comb_From_date NumAddrs;
    if last.PersID then Order = 1;
    drop Out: From_date_1stAddr To_date_1stAddr;
run;
/* Set the procesing order for the rest in descending order by From-date */
proc sort data=Hist_LN_Working1;
    by PersID descending Comb_From_date descending NumAddrs descending Comb_Durdays;
run;
data Hist_LN_Working2;
    retain prev_Order 1;
    set Hist_LN_Working1;
    by PersID descending Comb_From_date descending NumAddrs descending Comb_Durdays;
    if Order = . then Order = prev_Order + 1;
    output;
    if last.PersID then prev_Order = 1;
    else if Order ^= 1 then prev_Order = Order;
    drop prev_Order;
run;
/* Set adjusted dates so there are no overlaps */
proc sort data=Hist_LN_Working2;
    by PersID Order;
run;
data Hist_LN_Working3;
    retain prev_From_date .;
    set Hist_LN_Working2;
    by PersID Order;
    format Adj_From_date Adj_To_date DATE9.;
    /* Set Adj_To_date: use previous From_date unless this is the first one */
    if prev_From_date ^= . then
         Adj_To_date = prev_From_date;
    else Adj_To_date = Comb_To_date;
    /* Set Adj_From_date: use this From-date unless it is within &durOutMin. days of this (adjusted) To-date */
    if (Adj_To_date - Comb_From_date) <= &durOutMin. then
         Adj_From_date = Adj_To_date; /* Duration will be zero days */
    else Adj_From_date = Comb_From_date;
    /* Set Adj_Durdays: we will remove any addresses with zero days duration */
    Adj_Durdays = Adj_To_date - Adj_From_date;
    output;
    prev_From_date = Adj_From_date;
    if last.PersID then prev_From_date=.;
    drop prev_From_date;
run;

/* Remove any with zero days duration and save as final history */
proc sort data=Hist_LN_Working3;
    by PersID Adj_From_date;
run;
data Hist_LN_ResHist;
    set Hist_LN_Working3;
    if Adj_Durdays <= 0 then delete;
    rename GrpID=AddrID;
    label NumAddrs = 'Number of original addresses used per history address';
    drop AddrGrp;
run;

/* Add original address info to the residential histories */

/* Create a list of address references (for groups, use the first address) */
data Hist_LN_AddrRefs; /* Create a list of address references */
    set Hist_LN_MergedAddrs;
    if AddrGrp = . then AddrRef = GrpID;
    else                AddrRef = OutAddr1;
    keep PersID GrpID AddrRef;
    rename GrpID = AddrID;
run;
/* Add AddrRef to the residential history */
proc sort data=Hist_LN_ResHist; by PersID AddrID; run;
proc sort data=Hist_LN_AddrRefs; by PersID AddrID; run;
data Hist_LN_ResHist2;
    merge Hist_LN_ResHist (in=inHist)
        Hist_LN_AddrRefs (in=inRefs);
    by PersID AddrID;
    if inHist;
    if not inRefs then putlog '*** Missing address reference info, PersID: ' PersID AddrID;
run;

/* Add address info to the residential history */
proc sort data=Hist_LN_ResHist2; by PersID AddrRef; run;
proc sort data=Hist_LN_OrigAddrs; by PersID AddrID; run;
data Hist_LN_ResHist3;
    merge Hist_LN_ResHist2 (in=inHist)
        Hist_LN_OrigAddrs (in=inAddrs rename=(AddrID=AddrRef) keep=PersID AddrID Street City StAbbr ZIP_text);
    by PersID AddrRef;
    if inHist;
    if not inAddrs then putlog '*** Missing address info, PersID: ' PersID AddrID;
    rename
        Adj_From_date = From_date
        Adj_To_date = To_date
        Adj_Durdays = Durdays
        Pref_GeoLevel = GeoLevel
        Pref_Lat = Lat
        Pref_Lon = Lon;
run;

/* Specify the order of the variables and keep just what we need */
proc sql;
    create table Hist_LN_ResHist4 as
    select PersID,
        From_date, To_date, Durdays,
        NumAddrs, Street, City, StAbbr, ZIP_text,
        GeoLevel, Lat, Lon
    from Hist_LN_ResHist3;
/* run; */
/* Final sort */
proc sort data=Hist_LN_ResHist4;
    by PersID From_date;
run;

/* Keep a copy of the final history dataset */
data RHISTLIB.Hist_LN_ResHist;
    set Hist_LN_ResHist4;
run;

/* QC - 8/4/2020 */
%CheckHist(RHISTLIB.Hist_LN_ResHist);
/* QC Ends; */

/* Summary statistics */
title1 "03_BuildResHistory - Summary statistics";
title2 "Original address input";
proc freq data=Hist_LN_MergedAddrs2;
    tables AddrGrp / missing;
    tables NumAddrs / missing;
    tables MaxNumDates / missing;
run;

title2 "After weeding short duration addresses, duration min = &durInMin.";
proc freq data=Hist_LN_MergedAddrs3;
    tables AddrGrp / missing;
    tables NumAddrs / missing;
    tables MaxNumDates / missing;
run;
ods pdf STARTPAGE=NO;
proc means data=Hist_LN_MergedAddrs3 maxdec=2;
    var Comb_durdays;
run;
ods pdf STARTPAGE=YES;

title2 "Final address history output";
proc freq data=Hist_LN_ResHist;
    tables NumAddrs / missing;
    tables MaxNumDates / missing;
    tables Order / missing;
run;
ods pdf STARTPAGE=NO;
proc means data=Hist_LN_ResHist maxdec=2;
    var Comb_durdays;
run;
ods pdf STARTPAGE=YES;


ods pdf close;
