/* Match vendor addresses part 1: create dataset of combination pairs and flag matches and possible matches */

/* This program was developed by Westat, Inc. under NCI contracts HHSN261201500371P and HHSN261201600004B */
/* Version 2.0, copyright 2018 */
/* If you publish results based on these programs, please include the following citation:
    ResHistGen Residential History Generation Programs, Version 2.0 - September 2018;
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

/* Matching thresholds */
%let StrNameHigh = 90;         /* Street name high threshold (accept match) */
%let StrNameLowSameCity = 30;  /* Street name low threshold same city (reject match) */
%let StrNameLowDiffCity = 60;  /* Street name low threshold different city (reject match) */
/* Set all three StrName thresholds to the same value for a fully automatic match (no review file) */
%let CitySpedis = 30;          /* City spelling distance threshold (accept if less than) */
%let DistThresh = 0;           /* Distance matching threshold in meters */
%let GeoLvlMax = 2;            /* Maximum geocoding precision level for distance matching */

/* LexisNexis address file characteristics: */
%let LNFileName = LexisNexis_Addresses.xlsx;  /* File name */
%let LNSheetName = Input_Addresses;  /* Worksheet name */

/* Specify data path here: */
%let path=C:\ResHist_Work;

libname RHISTLIB "&path.";
ods pdf file="&path.\01_MatchAddresses1.pdf";

/* LexisNexis address dataset - Excel file with column headers in the first row */
/* Assumes original LexisNexis data have been cleaned up and geocoded */
/* Should have at least the following columns (can be in any order):
    PersID: integer, unique person ID
    AddrID: text, up to 8 characters with a unique address ID
        (We used "LN" || 3-digit person ID || 3-digit address number.)
    Street: text, street address (street number and street name)
    City: text, city name
    StAbbr: text, two character state abbreviation
    ZIP_text: text, up to 9 characters with 5-digit (left-aligned) or 9-digit ZIP code
    From_date: date (mm/dd/yyyy), starting date at this address
    To_date: date (mm/dd/yyyy), ending date at this address
        (If LexisNexis reports only one date, we set the from and to date to the beginning and end
        of the reported time period (for example, Jan 2015 -> 1/1/2015 to 1/31/2015.  The To_date
        value might be constrained by the end of the study period or a date-of-death if available.)
    Geocode_Level: text, up to 15 characters, first character is a numeric geocoding accuracy level
        (Our geocoding values are: 1-PointAddr, 2-StreetAddr, 4-9digitZIP, 5-StreetName, etc.
        The code assumes levels from 1 to &GeoLvlMax are accurate enough geocodes to be used for matching.)
    Lat: number, geocoded latitude in decimal degrees
    Lon: number, geocoded longitude in decimal degrees
        (Lat and Lon values should be missing for addresses that could not be geocoded (rather than
        having values of 0). This might include addresses from US territories (AS, GU, MP, PR, or VI)
        and overseas addresses (AA, AE, AP).)
*/

/* Get a copy of the LexisNexis address dataset */
PROC IMPORT OUT= LexisNexis_Addresses
            DATAFILE= "&path.\&LNFileName."
            DBMS=EXCEL REPLACE;
     RANGE="&LNSheetName.";
     GETNAMES=YES;
     MIXED=NO;
     SCANTEXT=YES;
     USEDATE=YES;
     SCANTIME=YES;
run;
/* Clear formats, informats, and labels */
proc datasets lib=work nolist;
    MODIFY LexisNexis_Addresses; FORMAT _char_; INFORMAT _char_; ATTRIB _all_ label=''; run;
quit;

/* Prepare LexisNexis addresses for matching */
data LexisNexis_Addresses2;
    length PersID 8 StreetAddr $10 StreetName first_word $50 City $50 StAbbr $2 ZIP_text $9;
    set LexisNexis_Addresses;
    first_word = scan(Street,1,' ');
    if verify(first_word,'0123456789-/ ') = 0 then do;
        StreetAddr = first_word;
        StreetName = upcase(substr(Street,length(first_word)+2));
        end;
    else if (length(first_word) > 1) and
            (verify(substr(first_word,1,length(first_word)-1),'0123456789-/ ') = 0)
            then do; /* A number followed by a letter */
        StreetAddr = first_word;
        StreetName = upcase(substr(Street,length(first_word)+2));
        end;
    else StreetName = upcase(Street);
    if StreetName = "*NA*" then StreetName = '';
    if City = "*na*" then City = '';
    /* If the next-to-last word is APT or UNIT, remove it and what follows */
    if (scan(StreetName,-2,' ') = 'APT') and (scan(StreetName,1,' ') ^= 'APT') then
        StreetName = substr(StreetName,1,index(StreetName,' APT '));
    if (scan(StreetName,-2,' ') = 'UNIT') and (scan(StreetName,1,' ') ^= 'UNIT') then
        StreetName = substr(StreetName,1,index(StreetName,' UNIT '));
    City = upcase(City);
    keep PersID StreetAddr StreetName City StAbbr ZIP_text
        AddrID Geocode_Level Lat Lon;
run;


/* Generate combinations and identify possible matches */

/* Create cross-product of all combinations by PersID */
proc sql;
 create table LN_matchcombos as
 select f1.PersID,
            f1.StreetAddr as f1StreetAddr,
            f1.StreetName as f1StreetName,
            f1.City as f1City,
            f1.StAbbr as f1StAbbr,
            f1.ZIP_text as f1ZIP_text,
            f1.AddrID as f1AddrID,
            f1.Geocode_Level as f1Geocode_Level,
            f1.Lat as f1Lat,
            f1.Lon as f1Lon,
        f2.StreetAddr as f2StreetAddr,
            f2.StreetName as f2StreetName,
            f2.City as f2City,
            f2.StAbbr as f2StAbbr,
            f2.ZIP_text as f2ZIP_text,
            f2.AddrID as f2AddrID,
            f2.Geocode_Level as f2Geocode_Level,
            f2.Lat as f2Lat,
            f2.Lon as f2Lon
  from LexisNexis_Addresses2 as f1,
       LexisNexis_Addresses2 as f2
  where f1.PersID eq f2.PersID;
quit;

/* Add match score for StreetName based on SPEDIS, SOUNDEX, and COMPARE values */
data LN_matchcombos2;
    set LN_matchcombos;
    /* Delete records where f1AddrID = f2AddrID */
    if f1AddrID = f2AddrID then delete;
    /* Match score for StreetName */
    spedis_value = spedis(f1StreetName, f2StreetName); /*** cost to convert ***/
    sound_f1 = soundex(f1StreetName);
    sound_f2 = soundex(f2StreetName);
    /* See if soundex value is embedded in either value */
    if (0 ne index( trim(substr(sound_f1,2 )) , trim(substr(sound_f2,2 )) ) )
    or (0 ne index( trim(substr(sound_f2,2 )) , trim(substr(sound_f1,2 )) ) )
    then sound_match = 1 ; /*** we have a strong likely match based upon soundex ***/
    compare_score = abs(compare(strip(f1StreetName), strip(f2StreetName), 'IL:'));
    match_score = 95 - min(spedis_value,95);
    if sound_match then match_score = match_score + 5;
    if compare_score = 0 then /* Shortest matches first part of longest */
        match_score = max(match_score, 80);
    else match_score = min(match_score + 2 *(compare_score-1), 90);
    /* Override the match score if either street name is blank */
    if (f1StreetName = '') or (f2StreetName = '') then match_score = 0;
    /* Calculate the geographic distance between them in meters */
    if (f1Lat ^= .) and (f1Lon ^= .) and (f2Lat ^= .) and (f2Lon ^= .) then
        LatLon_dist = geodist(f1Lat, f1Lon, f2Lat, f2Lon) * 1000; /* Distance in meters */
    f1GeoLvlNum = input(substr(f1Geocode_Level,1,1),best.);
    f2GeoLvlNum = input(substr(f2Geocode_Level,1,1),best.);
    /* Pre-mark the likely matches and non-matches */
    if match_score >= &StrNameHigh. then StreetName_match = 1;
    else if (LatLon_dist <= &DistThresh.) and
        (f1GeoLvlNum <= &GeoLvlMax.) and (f2GeoLvlNum <= &GeoLvlMax.)
        then StreetName_match = 1;
    else if (match_score < &StrNameLowDiffCity.) and (spedis(f1City, f2City) > &CitySpedis.)
        then StreetName_match = 0;
    else if (match_score < &StrNameLowSameCity.) then StreetName_match = 0;
    /* Otherwise, StreetName_match will be missing => manual review */
    drop sound_f1 sound_f2 f1GeoLvlNum f2GeoLvlNum;
run;

/* Add other field matching info */
data LN_matchcombos3;
    set LN_matchcombos2;
    if (f1StreetAddr = f2StreetAddr) and (f1StreetAddr ^= '') then StreetAddr_match = 1;
    else StreetAddr_match = 0;
    if (spedis(f1City, f2City) <= &CitySpedis.) and (f1City ^= '') then City_match = 1;
    else City_match = 0;
    if (f1StAbbr = f2StAbbr) and (f1StAbbr ^= '') then StAbbr_match = 1;
    else StAbbr_match = 0;
    if (substr(f1ZIP_text,1,5) = substr(f2ZIP_text,1,5)) and
        (substr(f1ZIP_text,1,5) ^= '') then ZIP5_match = 1;
    else ZIP5_match = 0;
run;

/* Get the StreetName matches that need manual review */
data LN_matchcombos_rev;
    set LN_matchcombos3;
    if StreetName_match = .;
run;
/* Specify the order of the variables */
proc sql;
    create table LN_matchcombos_rev2 as
    select match_score,
        f1StreetAddr, f1StreetName, f1City, f1StAbbr,
        f2StreetAddr, f2StreetName, f2City, f2StAbbr,
        PersID, f1AddrID, f2AddrID
    from LN_matchcombos_rev;
/* run; */


/* Save match combo dataset and export review dataset to Excel */

/* Keep copy of the address dataset and match combo dataset for after the manual review */
data RHISTLIB.LexisNexis_Addresses;
    set LexisNexis_Addresses;
run;
data RHISTLIB.LN_matchcombos;
    set LN_matchcombos3;
run;

/* Export StreetName review data to Excel for manual review */
/* For manual review, copy to a new sheet called "ReviewResults" and delete rows
    where the streetname does not match (don't worry about the street number) */
PROC EXPORT DATA= LN_matchcombos_rev2
            OUTFILE= "&path.\LN_matchcombos_review.xlsx"
            DBMS=EXCEL REPLACE;
     SHEET="ToBeReviewed";
run;


/* Summary statistics */

title1 "01_MatchAddresses1 - Summary statistics for matching LexisNexis addresses";

proc freq data=RHISTLIB.LN_matchcombos;
    tables StreetAddr_match / missing;
    tables StreetName_match / missing;
    tables City_match / missing;
    tables StAbbr_match / missing;
    tables ZIP5_match / missing;
run;

proc means data=RHISTLIB.LN_matchcombos maxdec=2;
    var match_score LatLon_dist;
run;


ods pdf close;
