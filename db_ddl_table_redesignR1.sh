#!/bin/sh

# Copyright IBM Corp. 2011, 2013, 2014, 2015, 2018
# LICENSE: See licenses provided at download or with distribution for language or\and locale-specific licenses

if [ ! $SCRIPT_DIR ]; then
#   SCRIPT_DIR=`dirname \`which $0\`` ; source $SCRIPT_DIR/lib/CODE_init_script "$@" ;
   SCRIPT_DIR=/opt/ibm/migration_tools/db_toolkit ; source $SCRIPT_DIR/lib/CODE_init_script "$@" ;
#JAS    source $SCRIPT_DIR/lib/CODE_error_handling;
else
   export IFS=$'\n' ;
fi
#####################################################################################
if [ $DISPLAY_HELP ]; then cat <<end-of-help ; source $SCRIPT_DIR/lib/CODE_generic_help ; fi

Usage:    db_ddl_table_redesign  <database> [table]  [optional args]

Purpose:  Provide alternative DDL for a table that optimizes each column's datatype.

          For example:  Let's say you have a column in your original table that is
          defined as

               AGE  bigint,

          That is going to require 8 bytes of storage.  But do you really need 8 bytes?
          Wouldn't a BYTEINT have worked just as well (allowing an "age" of 127 years)?
          1 byte versus 8 bytes!  Now, with automatic data compression, this isn't going
          to be as much of a factor -- while the data is at rest on disk.  But assuming
          you ever want to do something with that data (that particular column) it has
          to be read + decompressed -- in which case it would once again be 8 bytes.
          Requiring more memory, more CPU cycles (to process 8 bytes instead of 1), more
          network overhead (to move 8 bytes across the fabric instead of 1).  Now, we're
          only talking 7 bytes here.  But if your table has 100B rows ... that would then
          be 700 GB of "waste" for this one column alone.

          The 'db_ddl_table' script provides the actual/original DDL for a table.  This
          script provides DDL that is fine-tuned (based on each individual column's datatype,
          based on the actual data contained within each column).

          These are just redesign recommendations provided by a script.  The final choice is
          up to you.  You need to decide what changes are appropriate for your environment.

          Regarding INTEGER/NUMERIC data: When you initially create + load your table, if
          you don't have a good idea as to what datatype to start out with (for a particular
          column) then try VARCHAR(40).  This script will then determine the best datatype/size
          for the column (be it INTEGER or NUMERIC, or that it should be kept as a VARCHAR).
          Do not use a floating point column for this purpose -- as that has limited precision
          (at most 14 digits) and may be lossy (depending on the data you load into the table).

          How does the script operate?  By doing a full table scan and extensively analyzing
          every value in every column.  This script is very CPU intensive and can take
          awhile to run.

          What sort of tests, and recommendations, will be performed?

          o     If the table is empty, it will not be processed.  The script cannot make
                any recommendations if it has no data to analyze.

          o     If a column contains NO null values, the DDL will include the "NOT NULL"
                specification.

          o     If a column contains ONLY null values, that will be flagged (why are you
                using an apparently unused column?).

          o     If a column contains ONLY one value ... and that value is a
                     0                   in the case of an INTEGER/NUMERIC/FLOAT datatype
                     0 length string     in the case of a text datatype
                     00:00:00 time       in the case of an INTERVAL/TIME/TIMETZ datatype
                that will be flagged (why are you using an apparently unused column?).

          o     INTEGER columns will be reduced to the smallest possible INTEGER datatype.
                     BIGINT ==> INTEGER ==> SMALLINT ==> BYTEINT
                     int8       int4        int2         int1

                -integer <any|skip>

                The default is "-integer any" ... wherein this script decides what to do.

                If you don't want to have INTEGER columns processed at all ... to preserve
                their original datatype definition ... then specify "-integer skip"

          o     NUMERIC columns will be reduced to the smallest possible (PRECISION,SCALE).
                For example, a NUMERIC(31,12) might be turned into a NUMERIC(7,2).

                -numeric <any|numeric|skip>

                The default is "-numeric any" ... wherein this script will decide whether
                to use NUMERIC or INTEGER.

                If the resultant SCALE=0, then an INTEGER datatype will be chosen instead
                (assuming the value can be stored within an INT datatype).  If you wish to
                keep the NUMERIC as a NUMERIC, then specify "-numeric numeric"

                If you don't want to have NUMERIC columns processed at all ... to preserve
                their original (PRECISION,SCALE) ... then specify "-numeric skip"

          o     FLOATING POINT columns (REAL/float4 and DOUBLE PRECISION/float8) will be
                reduced to the smallest possible NUMERIC(PRECISION,SCALE).

                -float <any|numeric|skip>

                The default is "-float any" ... wherein this script will decide whether to
                use NUMERIC or INTEGER.

                If the resultant SCALE=0, then an INTEGER datatype will be chosen instead.
                If you wish to always have a NUMERIC datatype used, then specify
                "-float numeric"

                Not all floating point values can be adequately represented as a NUMERIC
                datatype.  For example, your floating point number might be

                     -3.1415926535898e+173

                If scientific notation is used to store/represent the floating point number,
                then this script will leave the column defined as a floating point number.

                It is possible that the suggested NUMERIC datatype will actually be larger
                (byte wise) than the original floating point datatype.  For example, let's
                say you have a FLOAT4 column that contains the following values:
                     123456
                          0.654321
                In order for this data to be stored in a NUMERIC datatype it must be defined
                as a NUMERIC(12,6) ... which uses 8 bytes of storage, rather than the 4 bytes
                of storage associated with a FLOAT4.

                If you don't want to have the floating point columns processed at all ... then
                specify "-numeric skip"

          o     TIMESTAMP columns include both a DATE + TIME.  If the time value is always
                '00:00:00' (for all values in this column) then it will be suggested that
                this column can be redesigned as a DATE datatype.

          o     TEXT columns are
                     CHARACTER, CHARACTER VARYING, NATIONAL CHARACTER, NATIONAL CHARACTER VARYING
                     char     , varchar          , nchar             , nvarchar

                -trim <trim|rtrim|none|skip>

                The MAX(LENGTH()) of each column will be computed (and adjusted, as appropriate).
                This is done by triming all leading/trailing spaces from each string, before
                computing its length.  Sometimes, leading and/or trailing spaces might be
                considered significant.  You can control how the spaces are treated (and thus
                how the maximum length of the string is determined).

                     -trim trim      # The default.  TRIM() both leading and trailing spaces.
                     -trim rtrim     # Perform an RTRIM() to trim only trailing spaces on the right.
                     -trim none      # Leave the string alone ... do NOT trim any spaces from it.
                     -trim skip      # Skip this check entirely and maintain the original column width.

                     Note that CHAR/NCHAR columns (by definition) are always space padded to
                     the defined width of the column.  If "-trim none" is chosen, then the
                     defined widths of these column types will never be adjusted downwards.

                VARCHAR columns have 2 bytes of overhead, which are used to specify the
                length of the text string.  Because of this, fewer bytes will actually
                be used if certain columns are redefined as a CHAR datatype instead
                (with a fixed length).  So

                     VARCHAR(2)   will be redefined as   CHAR(2)
                     VARCHAR(1)   will be redefined as   CHAR(1)

                     Of course, a VARCHAR datatype is not quite the same thing as a CHAR
                     datatype.  Similar, but different.  It is up to you to make the
                     final determination as to whether, or not, this change is appropriate
                     for your needs.

                -text <any|numeric|utf8|skip>

                The default is "-text any" ... wherein this script will perform both of the
                following tests.

                Does the column contain only numeric strings ... which would allow it to be
                     redefined as a NUMERIC (or INTEGER) datatype?  If so, it will be.  If
                     you want only this test performed (and not the next one) specify
                     "-text numeric"

                NCHAR/NVARCHAR columns are typically used to store UTF8 data (which uses from
                     1 to 4 bytes of storage, per character).  If the data you are storing in
                     the column is simply LATIN9 data (which uses only 1 byte of storage per
                     character), then the column will be redesigned as a CHAR/VARCHAR column
                     instead.  If you want only this test performed (and not the above one)
                     specify "-text utf8"

                If you want to skip both of these tests, specify "-text skip"

          o     BINARY columns (BINARY VARYING and ST_GEOMETRY) will have their MAX(LENGTH())
                computed (and adjusted, as appropriate).

                -binary <any|skip>

                The default is "-binary any" ... wherein this script decides what to do.

                If you don't want to have BINARY columns processed at all ... to preserve
                their original (defined) column width ... then specify "-binary skip".

Inputs:   The database name is required.

          The table name is optional.  If specified, just that one table will be processed.
          Otherwise, every table in this database will be processed.

          -v|-verbose

          Include in the output the SQL query that gets generated to perform all of these
          analyses (in case you like looking at SQL).

          -sample <nn>

          By default the script samples all of the data in the table.  This can take a long
          time (but could result in the better analysis).  Instead, you can have the script
          sample a portion of the table (from 1 to 100 %) which could save a considerable
          amount of runtime.

          -insert

          Along with the CREATE TABLE statement, include a corresponding INSERT statement.
          i.e.     INSERT INTO <table> SELECT col_1, ..., col_n FROM <database>..<table>;

          Generally, the software will implicitly convert the data from the source column/
          datatype into the corresponding target column/datatype.  Explicit transformations
          will only need to be added to the INSERT statement to process text strings (to
          trim them, or to aid in their conversion to an integer/numeric datatype).

          When this script is used to process multiple tables at once, the CREATE TABLE
          statements will be listed first, and then the INSERT statements will follow.

          -orderby

          For the above INSERT statement, do you want it to include an optional ORDER BY
          clause?  If so, this script will chose the first column in the table that is of
          type DATE or TIMESTAMP, and add it to the INSERT statement.

          Sorted data increases the benefit of zonemap lookups and extent elimination.
          However, the data must be sorted on the right column(s) for this to be of the
          greatest benefit.
               -  you might want to choose a different date/timestamp column
               -  you might want to use a multi-column sort (ORDER BY) clause
               -  you might want to choose a column, or columns, of a different data type
          Edit the INSERT statement to make any changes appropriate to your environment.

          -round

          When processing NUMERIC/FLOATING POINT/TEXT columns, this script may suggest an
          alternative NUMERIC datatype.  By default, the (PRECISION,SCALE) of that new
          numeric will always use the smallest possible values that are appropriate for it.

          Note that a numeric with a
               Precision of  1..9  is always  4 bytes in size
               Precision of 10..18 is always  8 bytes in size
               Precision of 19..31 is always 16 bytes in size

          Include the "-round" switch if you want numerics to always have their PRECISION
          rounded up to the highest possible value for that data size -- either 9 / 18 / 31.

          For example, a NUMERIC(9,2) would be suggested rather than a NUMERIC(4,2).
          Storage wise, they are comparable.  In this example, they are both 4 bytes in
          size.  However, there are other aspects to this.

          If you multiply two NUMERIC(4,2) columns together, the default result would be a
          NUMERIC(9,4) column -- which is still 4 bytes in size.

          But if you instead multiplied two NUMERIC(9,2) columns, the default result
          would be a NUMERIC(19,4) column -- which is 16 bytes in size.

          So it makes a difference.  But what difference will the difference make to you?

          -integer   <any|skip>
          -numeric   <any|numeric|skip>
          -float     <any|numeric|skip>
          -text      <any|numeric|utf8|skip>
          -trim      <trim|rtrim|none|skip>
          -binary    <any|skip>

          These options were defined in detail under the Purpose section above.

          -columns <n>

          If your table contains more than 100 columns, it will be processed in groups
          of 100 columns at a time (one 'full table scan' is invoked, per group).  If
          you wish, you can control how many columns get processed (per scan) by
          specifying a number from 1..250.

Outputs:  SQL DDL (the modified CREATE TABLE statements) will be sent to standard out.
          It will include comments as to any + all DDL modifications that this script
          decides to suggest.  An example:


$ db_ddl_table_redesign test_database test_table

\echo
\echo *****  Creating table:  "TEST_TABLE"

CREATE TABLE  TEST_TABLE
(

--REDESIGN
--   CUSTOMER_ID                   bigint          ,
     CUSTOMER_ID                   bigint not null ,

--REDESIGN
--This column contains only NULL values, and could possibly be eliminated entirely.
--   NICKNAME                      character varying(30) ,
     NICKNAME                      character varying(1)  ,

--REDESIGN
--This column does not appear to contain any meaningful data, and could possibly be eliminated entirely.
--(All values are the same value ... and are either a 0, a string of 0..more spaces, a time of 00:00:00, etc ...)
--   NUMBER_OF_ELEPHANTS_OWNED     integer           ,
     NUMBER_OF_ELEPHANTS_OWNED     smallint not null ,

--REDESIGN
--   AGE                           smallint          ,
     AGE                           smallint not null ,

--REDESIGN
--   SALARY                        numeric(31,16)        ,
     SALARY                        numeric(8,2) not null ,

--REDESIGN
--   PHONE_NUMBER                  double precision ,
     PHONE_NUMBER                  integer not null ,

--REDESIGN
--   DOB                           timestamp     ,
     DOB                           date not null ,

--REDESIGN
--   STREET_ADDRESS                national character varying(100)  ,
     STREET_ADDRESS                character varying(68) not null   ,

--REDESIGN
--   PIN                           character(10)
     PIN                           smallint not null

)
DISTRIBUTE BY (CUSTOMER_ID)
;

end-of-help
#####################################################################################



# Change Log: 2014-02-05  If "skip"ing a datatype, don't make ANY changes to its definition.



#####################################################################################

# A bunch of subroutines follow

#####################################################################################


# If requested, round the new/computed NUMERIC precision up to 9 / 18 / 31 digits
# Which is the maximum precision for a 4 / 8 / 16 byte numeric datatype

round_up () {

        input_precision=$1
        output_precision=$1

        if [ "$ROUND_UP" = "TRUE" ]; then

                if [ $input_precision -ge  1 -a $input_precision -le  9 ]  2>/dev/null  ; then output_precision=9  ; fi   #  4 byte numeric
                if [ $input_precision -ge 10 -a $input_precision -le 18 ]  2>/dev/null  ; then output_precision=18 ; fi   #  8 byte numeric
                if [ $input_precision -ge 19 -a $input_precision -le 31 ]  2>/dev/null  ; then output_precision=31 ; fi   # 16 byte numeric

        fi

        echo $output_precision

}

################################################################################

# Extract the values out of the array

get_column_info () {
     offset=$1

            org_column_name="${ORG_COLUMN_NAME[$offset]}"
      org_column_definition="${ORG_COLUMN_DEFINITION[$offset]}"
         org_column_notnull="${ORG_COLUMN_NOTNULL[$offset]}"
         org_column_default="${ORG_COLUMN_DEFAULT[$offset]}"

                column_name="${COLUMN_NAME[$offset]}"
          column_definition="${COLUMN_DEFINITION[$offset]}"
             column_notnull="${COLUMN_NOTNULL[$offset]}"

            column_datatype="${COLUMN_DATATYPE[$offset]}"
           column_precision="${COLUMN_PRECISION[$offset]}"
               column_scale="${COLUMN_SCALE[$offset]}"

     # In case the column_name already has quotes around it, remove them
     quoted_column_name=`echo $column_name | tr -d "\""`
     # And now add quotes to the column_name
     quoted_column_name="\"$quoted_column_name\""

#JAS ADEBUG echo "exit get_col_info offset $offset: tbl: '$table_name' in col: '$org_column_name' arrayname = '${ORG_COLUMN_NAME[1]}' "
}

##################################################################################

# Print Distributoin

process_distribution() {
  AN_ERROR_OCCURRED="FALSE"
  schema=`echo "$1" | tr '[:lower:]' '[:upper:]'`
  table=$2
tbspace=`dbsql -q -X -A -t -c "
SELECT TBSPACE FROM SYSCAT.TABLES  WHERE  TABNAME='TABLE2' AND TABSCHEMA='$schema'"`
                        if [ "$?" != "0" ]; then
                                AN_ERROR_OCCURRED="TRUE"
                        fi
sptype=`echo "$tbspace" | tr -d '\n'`

parts=`dbsql -q -X -A -t -c "
SELECT COLNAME FROM SYSCAT.COLUMNS WHERE PARTKEYSEQ <> 0 AND TABNAME='$table' AND TABSCHEMA='$schema' ORDER BY PARTKEYSEQ "`
                        if [ "$?" != "0" ]; then
                                AN_ERROR_OCCURRED="TRUE"
                        fi
cols=`echo "$parts" | tr '\n' ',' |sed -e 's/,$//'`

torg=`dbsql -q -X -A -t -c "
SELECT case TABLEORG when 'C' then 'COLUMN' when 'R' then 'ROW' end FROM SYSCAT.TABLES  WHERE  TABNAME='$table' AND TABSCHEMA='$schema' "`
                        if [ "$?" != "0" ]; then
                                AN_ERROR_OCCURRED="TRUE"
                        fi
orgtype=`echo "$torg" | tr '\n' ',' |sed -e 's/,$//'`
if [ "$AN_ERROR_OCCURRED" = "TRUE" ]; then
        echo ""
        echo "-----"
        echo "----- NOTICE ----- NOTICE ----- NOTICE ----- NOTICE ----- NOTICE ----- NOTICE -----"
        echo "-----"
        echo "----- This script encountered an error (in the SQL that it uses to build distribution of the table)."
        echo "-----"
        echo "-----"
        echo ""
fi
if [ "$cols" = "RANDOM_DISTRIBUTION_KEY" ]; then
        echo  "    DISTRIBUTE BY RANDOM IN \"$sptype\""
else
        echo  "    DISTRIBUTE BY HASH( $cols ) IN \"$sptype\""
fi
echo "    ORGANIZE BY $orgtype  "
echo ";"
}
################################################################################

# Store the values into an array (for later access)

store_column_info () {
     offset=$1


              ORG_COLUMN_NAME[$offset]="$org_column_name"
        ORG_COLUMN_DEFINITION[$offset]="$org_column_definition"
           ORG_COLUMN_NOTNULL[$offset]="$org_column_notnull"
           ORG_COLUMN_DEFAULT[$offset]="$org_column_default"

                  COLUMN_NAME[$offset]="$column_name"
            COLUMN_DEFINITION[$offset]="$column_definition"
               COLUMN_NOTNULL[$offset]="$column_notnull"

              COLUMN_DATATYPE[$offset]="$column_datatype"
             COLUMN_PRECISION[$offset]="$column_precision"
                 COLUMN_SCALE[$offset]="$column_scale"
#JAS DEBUG echo "exit storeinfo offset $offset: tbl: '$table_name' in col: '$org_column_name' type = '${ORG_COLUMN_DEFINITION[$offset]}' "
}

################################################################################

build_sql_to_test_this_subset_of_columns () {
#JAS DEBUG echo "in build SQL to test subset of columns"
        for ((loop=1;loop<=$number_of_columns;loop++)); do

                get_column_info $loop



                # EVERY column will include this test
                # To see whether (or not) the column contains any NULL values
                # But only if I am not skipping this column/datatype entirely

                not_null_sql="min(case when ${quoted_column_name} is null then '' else 'NOT NULL' end)"



                # Now, for each column I must do specific tests ...
                # Based on each column's datatype

                case $column_datatype in



                "byteint"|"smallint"|"integer"|"bigint" )
                #########################################

                if [ "$integer_processing_option" = "SKIP" ]; then

                        if [ "$column_datatype" = "byteint"  ];  then fixed_size=1 ; fi
                        if [ "$column_datatype" = "smallint" ];  then fixed_size=2 ; fi
                        if [ "$column_datatype" = "integer"  ];  then fixed_size=4 ; fi
                        if [ "$column_datatype" = "bigint"   ];  then fixed_size=8 ; fi

                        # Skip any tests against this column/datatype

                        sql="${sql}

,max('skip')
,${fixed_size}"

                else

                        # Test to see if the column contains all 0's and/or NULL's
                        # And to find the minimum INT<n> datatype that this column can fit into

                        sql="${sql}

,${not_null_sql}
,max(case when ${quoted_column_name} is null                              then -1
          when ${quoted_column_name} = 0                                  then  0
          when ${quoted_column_name} between         -128 and        127  then  1
          when ${quoted_column_name} between       -32768 and      32767  then  2
          when ${quoted_column_name} between  -2147483648 and 2147483647  then  4
                                                                   else  8 end)"

                fi
                        ;;



                "decimal"|"numeric" )
                ###########

                        let min_precision=$column_precision-$column_scale

if [ "$numeric_processing_option" = "SKIP" ]; then

# Don't touch the NUMERICS.  So, rather than using SQL, just "hardcode" what I want
# the resultant numbers to be.

sql="${sql}

,max('skip')
,16
,${min_precision}
,${column_scale}"

else

                        BigNumeric="numeric(31,0)"


                        # Test to see if the column contains all NULL's and/or 0's
                        # Test to see if the column can fit within a particular INT<n> datatype

                        sql="${sql}

,${not_null_sql}
,max(case when ${quoted_column_name}::${BigNumeric} is null                                                                              then -1
          when ${quoted_column_name} = 0::${BigNumeric}                                                                                  then  0
          when ${quoted_column_name}::${BigNumeric} between                  -128::${BigNumeric} and                 127::${BigNumeric}  then  1
          when ${quoted_column_name}::${BigNumeric} between                -32768::${BigNumeric} and               32767::${BigNumeric}  then  2
          when ${quoted_column_name}::${BigNumeric} between           -2147483648::${BigNumeric} and          2147483647::${BigNumeric}  then  4
          when ${quoted_column_name}::${BigNumeric} between  -9223372036854775808::${BigNumeric} and 9223372036854775807::${BigNumeric}  then  8
                                                                                                                                         else 16 end)"



                        # Find the MAX(precision) that I need to use for this NUMERIC

                        if [ $min_precision -eq 0 ]; then
                                sql="${sql}
,0"
                        else

                                if [ $column_scale -eq 0 ]; then

                                        sql="${sql}
,nvl(max(length(abs(${quoted_column_name}))),0)"

                                else
#NOTE:  DB2 and Netezza swap to and from in translate
                                        sql="${sql}
,nvl(max(length(ltrim(translate(substr(${quoted_column_name},1,strpos(${quoted_column_name},'.')),'  ','0-')))-1),0)"

                                fi

                        fi



                        # Find the MAX(scale) that I need to use for this NUMERIC

                        if [ $column_scale -eq 0 ]; then
                                sql="${sql}
,0"
                        else
#NOTE:  DB2 and Netezza swap to and from in translate

                                sql="${sql}
,nvl(max(length(trim(translate(substr(${quoted_column_name},strpos(${quoted_column_name},'.')),' ','0')))-1),0)"

                        fi
fi

                        ;;



                "decfloat"|"double"|"real"|"double precision" )
                ###########################

                        # Find out what type of data is in this column
                        #     -1 - column contains only NULL's
                        #      0 - column contains only NULL's and/or ZERO's
                        #      1 - column contains usable values
                        #      2 - column contains an exponent, which could be huge ... as in -1.2345678901235e+49 ... so I am not going to mess with it
                        # Find out the number of integer digits (could be 0)
                        # Find out the number of decimal digits (could be 0)

if [ "$float_processing_option" = "SKIP" ]; then
sql="${sql}

,max('skip')
,2
,0
,0"
else

                        sql="${sql}

,${not_null_sql}
,max(case when ${quoted_column_name} is null then -1 when ${quoted_column_name} = 0 then 0 when strpos(${quoted_column_name}::varchar(30),'e') > 0 then 2 else 1 end)
,max(nvl(case when abs(${quoted_column_name}) < 1::double then 0 else length(translate(substr(${quoted_column_name}::varchar(30), 1, strpos(${quoted_column_name}::varchar(30)||'.', '.')),'-.',''))  end,0))
,max(nvl(length(case when strpos(${quoted_column_name}::varchar(30),'.') = 0 then '' else substr(${quoted_column_name}::varchar(30),strpos(${quoted_column_name}::varchar(30),'.')+1,30)  end),0))"

fi
                        ;;



                "timestamp" )
                #############

                        # See if the time portion (of this date+time timestamp) is always 00:00:00

                        sql="${sql}

,${not_null_sql}
,max(case when ${quoted_column_name} is null then -1 when ${quoted_column_name}::time = '00:00:00' then 0 else 1 end)"

                        ;;



                "time with time zone" )
                #######################

                        # See if the time is always 00:00:00+00

                        sql="${sql}

,${not_null_sql}
,max(case when ${quoted_column_name} is null then -1 when ${quoted_column_name} = '00:00:00+00' then 0 else 1 end)"

                        ;;



                "time" | "interval" )
                #####################

                        # See if the time is always 00:00:00

                        sql="${sql}

,${not_null_sql}
,max(case when ${quoted_column_name} is null then -1 when ${quoted_column_name} = '00:00:00' then 0 else 1 end)"

                        ;;



                "date" | "boolean" )
                ####################

                        sql="${sql}

,${not_null_sql}
,max(case when ${quoted_column_name} is null then -1 else 1 end)"

                        ;;



                "binary varying" | "st_geometry" )
                ##################################

                        # These datatypes are (basically) like a VARCHAR datatype
                        # But they can NOT be trimmed
                        # About the only thing I can do is shorten their MAX(LENGTH()) ...
                        # And/or see if the column contains only NULL values

                        if [ "$binary_processing_option" = "SKIP" ]; then

                                sql="${sql}

,max('skip')
,${column_precision}"

                        else

                        # Check for NULLs / Compute the MAX(LENGTH(of_the_column))

                                sql="${sql}

,${not_null_sql}
,max(case when ${quoted_column_name} is null then -1 else length(${quoted_column_name}) end)"

                        fi

                        ;;



"graphic"|"varbinary"|"varchar"|"nvarchar"|"character" | "character varying" | "national character" | "national character varying" )
                #########################################################################################

                # Am I supposed to "skip" this column/datatype ?

                if [ "$text_processing_option" = "SKIP" ]; then

                        # If so, "skip" the null/notnull test
                        sql="${sql}

,max('skip')"
                else
                        # Otherwise, test for null/notnull
                        sql="${sql}

,${not_null_sql}"

                fi


                # Allow the user to decide whether I will do a
                #      TRIM ... trim spaces from both ends of the string
                #     RTRIM ... only trim spaces from the right end of the string
                #      none ... don't trim spaces at all
                # before attempting to determine the MAX(LENGTH(of_the_string))
                #
                # If the user specified
                #      SKIP ... then I'll skip this check and maintain the original column width/definition

                TRIM="$trim_for_strings"

                if [ "$trim_for_strings" = "SKIP" ]; then

                        sql="${sql}
,${column_precision}"

                else

                        # Check for NULLs / Compute the MAX(TRIM'ed(LENGTH(of_the_column)))

                                sql="${sql}
,max(case when ${quoted_column_name} is null then -1 else length($TRIM(${quoted_column_name})) end)"

                fi



                ################################################################################



                        if [ "$text_processing_option" = "ANY" -o "$text_processing_option" = "NUMERIC" ]; then

                                # See if the string contains only characters that "look like" it could be an integer/numeric number
                                # "can be very computationally expensive ... due to the translate ... if the text string is lengthy"
                                sql="${sql}
,max(case when ${quoted_column_name} is null then 0 when length(translate(${quoted_column_name},'1234567890+-. ','')) = 0 then 0 else 1 end)"

                                # How many characters/digits before the decimal point (if any)?
                                # "can be computationally expensive ... due to the translate ... if the text string is lengthy"
                                sql="${sql}
,max(nvl(length(ltrim(translate(substr(trim(${quoted_column_name}),1,strpos(trim(${quoted_column_name})||'.','.')),'0+-.',' '))),0))"

                                # How many characters/digits after the decimal point (if any)?
                                sql="${sql}
,max(case when ${quoted_column_name} is null then 0 when strpos(${quoted_column_name},'.') = 0 then 0 else length(rtrim(translate(substr(${quoted_column_name},strpos(${quoted_column_name},'.')+1),'0',' '))) end)"

                                # Determine what the minimum trimmed length of the column is.
                                # If 0 then, when converting this column to a INTEGER/NUMERIC,
                                # I must make sure that the column is defined as NULL'able
                                sql="${sql}
,nvl(min(length(trim(${quoted_column_name}))),0)"

                        else

                                # I do NOT want to process this column.  So I will hardcode a result now ... that I will ignore later.
                                # A 1 indicates the the column is definitely NOT a number.  That way ... I won't try to change it.
                                # In which case ... doesn't matter what I set the next three values to ... they are just placeholders.

                                sql="${sql}
,1
,0
,0
,0"

                        fi



                        ################################################################################



                        # If this is a UTF8 datatype, then I want to see if UTF8 is really needed.
                        # In other words, could this data have been stored in a LATIN9 column instead.

                        if [ "$column_datatype" = "national character" -o "$column_datatype" = "national character varying" ]; then
                        if [ "$text_processing_option" = "ANY" -o "$text_processing_option" = "UTF8" ]; then


                                tmp_datatype=`echo "$column_datatype" | sed -e "s/national //"`

                                sql="${sql}
,max(CASE WHEN ${quoted_column_name} is null then '' when ${quoted_column_name}::${tmp_datatype}(${column_precision})::${column_datatype}(${column_precision}) = ${quoted_column_name} THEN '' ELSE 'utf8' END)"

                        else

                                sql="${sql}
,'No Conversion'"

                        fi
                        fi

                        ;;



                        ################################################################################



                *)      # I don't exect to ever be here ... but just in case.

                        echo "ERROR:  The script encountered an unknown datatype ($column_definition) for column $column_name"
                        exit 1

                        ;;



                esac

        done

}



################################################################################



set_next_value() {
        let pointer++
        next_value=`echo "$RESULTS" | cut -d "|" -f $pointer`
}



################################################################################



provide_recommendations_for_this_subset_of_columns() {


        if [ "$AN_ERROR_OCCURRED" = "TRUE" ]; then
                echo ""
                echo "-----"
                echo "----- NOTICE ----- NOTICE ----- NOTICE ----- NOTICE ----- NOTICE ----- NOTICE -----"
                echo "-----"
                echo "----- This script encountered an error (in the SQL that it uses to analyze the table)."
                echo "----- Thus, it can't make any redesign recommendations for the next ${number_of_columns} columns."
                echo "-----"
                echo ""
                echo "/*"
                echo "${RESULTS}"
                echo "*/"
                echo ""
        fi


        # The first RESULTS column is just a filler ... need to skip it
        pointer=1


for ((loop=1;loop<=$number_of_columns;loop++)); do

         if [ "$loop" -lt "$number_of_columns" ] ; then
             eol_char=","
         else
             eol_char=""
         fi


        # Get the ORIGINAL column information/definition
        get_column_info $loop


        # An unused column will be one that contains all
        #       NULLs
        #       0's
        #       Strings that are 0 bytes in length or contain only spaces
        #       Times that are always '00:00:00' or '00:00:00+00' (time with time zone)
        # For now, assume that each column is used (unless set otherwise)
        unused_column=""

        NEW_column_precision=0
        NEW_column_scale=0


        if [ "$AN_ERROR_OCCURRED" = "TRUE" ]; then

                NEW_column_definition="$column_definition"
                NEW_column_notnull="$column_notnull"

                # This should cause the big CASE statement below to be bypassed
                # And the script will just spit out the current column definition ... as it is

                column_datatype="BYPASS THIS COLUMN"

        else

                # See if the column can be defined as "not null"
                # This check is the same for every column (and is the first test made for every column)
                # If I am skip'ing this column/datatype, preserve the original NULLABLE/NOT NULL setting

                set_next_value ; not_null_check=${next_value}

                if [ "$not_null_check" = "skip" ]; then NEW_column_notnull=$column_notnull
                                                   else NEW_column_notnull=$not_null_check
                fi

        fi



        # Optionally, I will also output an INSERT statement ... to insert the columns from the original table
        # into the newly redesigned table.
        #
        # In most cases, I don't need to do anything.  If the column datatypes don't match, NPS will do an
        # implicit transformation for me.
        #
        # The only exception will be when processing text columns (which will be handled later on).
        #
        insert_sql_column="   ${quoted_column_name}"



        # Now, process the query results (which are dependent upon the column's original datatype)
        case $column_datatype in



        "byteint"|"smallint"|"integer"|"bigint" )
        #########################################

                set_next_value ; size_check=${next_value}

                case $size_check in

                        -1|0)   unused_column=${size_check}
                                        # This column is 'unused'
                                        # So it can definitely fit into a byteint (if not eliminated alltogether)
                                # DB2 doess not have bbyteint so use smallint.
                                NEW_column_definition="SMALLINT"   ;;

                        1)      NEW_column_definition="SMALLINT"   ;;
                        2)      NEW_column_definition="SMALLINT"   ;;
                        4)      NEW_column_definition="INTEGER"    ;;
                        8)      NEW_column_definition="BIGINT"     ;;

                esac

                ;;



        "dec"|"decimal"|"numeric"|"NUMERIC"|"DECIMAL" )
        ###########

                set_next_value ; size_check=${next_value}               set_next_value ; NEW_column_precision=${next_value}
                set_next_value ; NEW_column_scale=${next_value}

                let NEW_column_precision=${NEW_column_precision}+${NEW_column_scale}

                # Handle the edge case (this will be the smallest possible numeric)
                if [ $NEW_column_precision -eq 0 ]; then NEW_column_precision=1 ; fi

                if [ "$numeric_processing_option" != "SKIP" ]; then
                        NEW_column_precision=`round_up ${NEW_column_precision}`
                fi

                NEW_column_definition="numeric(${NEW_column_precision},${NEW_column_scale})"



                # If the scale (# of decimal points) = 0, then see if this value can fit within an INT? datatype.
                # If the size_check value is 16, then NO ... we must continue to use a NUMERIC.

                if [ "$NEW_column_scale" = "0" ]; then

                        if [ $size_check -eq -1 -o $size_check -eq 0 ]; then
                                unused_column=$size_check
                        fi

                        if [ "$numeric_processing_option" = "ANY" ]; then
                                case $size_check in
                                       -1|0)    NEW_column_definition="SMALLINT"    ;;
                                        1)      NEW_column_definition="SMALLINT"    ;;
                                        2)      NEW_column_definition="SMALLINT"   ;;
                                        4)      NEW_column_definition="INTEGER"    ;;
                                        8)      NEW_column_definition="BIGINT"     ;;
                                esac
                        fi
                fi

                ;;



        "double"|"real"|"double precision")
        ###########################

                # float4 = 6 digits of  precision
                # float8 = 14 digits of precision       So, I know that I can always fit a FLOAT into a NUMERIC, which can have
                #                                       up to 31 digits of precision.  Only issue is with floats that employ
                #                                       scientific notation ... which I won't try to change.

                set_next_value ; sanity_check=${next_value}
                set_next_value ; NEW_column_precision=${next_value}
                set_next_value ; NEW_column_scale=${next_value}



                if [ $sanity_check -eq -1 -o $sanity_check -eq 0 ]; then
                        unused_column=$sanity_check
                fi



                if [ $sanity_check -eq 2 ]; then

                        # Exponents are involved.  Stick with the current floating point data type.
                        NEW_column_definition="$column_definition"

                else

                        if [ $NEW_column_scale -eq 0 -a "$float_processing_option" = "ANY" -a $NEW_column_precision -le 18 ]; then

                                # Use this code to redefine the column as an INT<n> datatype
                                #
                                # Technically, these aren't the tightest possible integer definitions.
                                # For example an INT2 ranges from -128 to 127
                                # So it can fit ALL numbers that are 2 digits, or less
                                # But just some of the numbers that are 3 digits.
                                # Going conservative for now ... making sure that the biggest number (of 'n' digits')
                                # will always fit in the integer datatype that I specify.

                                  if [ $NEW_column_precision -le 2 ]; then NEW_column_definition="byteint"
                                elif [ $NEW_column_precision -le 4 ]; then NEW_column_definition="smallint"
                                elif [ $NEW_column_precision -le 9 ]; then NEW_column_definition="integer"
                                else                                       NEW_column_definition="bigint"
                                  fi

                        else

                                # Use this code to redefine the column as a NUMERIC datatype
                                let NEW_column_precision=${NEW_column_precision}+${NEW_column_scale}

                                # Handle the edge case (this will be the smallest possible numeric)
                                if [ $NEW_column_precision -eq 0 ]; then NEW_column_precision=1 ; fi

                                NEW_column_precision=`round_up ${NEW_column_precision}`

                                NEW_column_definition="numeric(${NEW_column_precision},${NEW_column_scale})"

                                if [ "$column_definition" = "real"             -a $NEW_column_precision -gt  9 ]; then
                                        additional_message="--Note: The suggested NUMERIC datatype will actually be larger, byte wise."
                                fi
                                if [ "$column_definition" = "double precision" -a $NEW_column_precision -gt 18 ]; then
                                        additional_message="--Note: The suggested NUMERIC datatype will actually be larger, byte wise."
                                fi

                        fi

                fi

                ;;



        "time"|"time with time zone"|"interval")
        #############################################

                set_next_value ; sanity_check=${next_value}

                # There is no other data type that can be used for a TIME/TIMETZ/INTERVAL data type
                NEW_column_definition="$column_definition"

                # But do check to see if the column is needed (e.g, used) at all
                if [ $sanity_check -eq -1 -o $sanity_check -eq 0 ]; then
                        unused_column=$sanity_check
                fi

                ;;



        "timestamp" )
        #############

                set_next_value ; sanity_check=${next_value}

                # If the time portion (of this date+time timestamp) is always '00:00:00' ... then why not use a DATE datatype instead?
                if [ $sanity_check -eq -1 -o $sanity_check -eq 0 ]; then

                        NEW_column_definition="DATE"

                        if [ $sanity_check -eq -1 ]; then
                                unused_column=$sanity_check
                        fi

                else
                        NEW_column_definition="$column_definition"

                fi

                if [ "$insert_orderby_column" = "" -a "$column_datatype" = "timestamp" ]; then
                        insert_orderby_column="${quoted_column_name}"
                fi


                ;;



        "date"|"boolean")
        ##################

                set_next_value ; sanity_check=${next_value}

                if [ $sanity_check -eq -1 ]; then
                        unused_column=$sanity_check
                fi

                # There is no other data type that can be used for a TIME/TIMETZ/INTERVAL data type
                NEW_column_definition="$column_definition"


                if [ "$insert_orderby_column" = "" -a "$column_datatype" = "date" ]; then
                        insert_orderby_column="${quoted_column_name}"
                fi

                ;;



        "binary varying"|"st_geometry")
        ################################

                set_next_value ; size_check=${next_value}                       # -1 = all nulls, 0 = 0 length strings, else <n> = new max str length

                if [ $size_check -eq -1 -o $size_check -eq 0 ]; then

                        # We are not storing anything in the string (other than NULLs or 0 length strings
                        # A length of (1) is more than enough

                        unused_column=$size_check
                        NEW_column_definition="${column_datatype}(1)"

                else

                        NEW_column_definition="${column_datatype}(${size_check})"

                fi

                ;;



"graphic"|"character"|"character varying"|"national character"|"national character varying"|"varchar"|"nvarchar"|"varbinary" )
        ###################################################################################

                set_next_value ; size_check=${next_value}                       # -1 = all nulls, 0 = 0 length strings, else <n> = new max str length

                set_next_value ; possibly_a_number=${next_value}                # If 0, maybe a number.  If 1, it is definitely NOT a number
                set_next_value ; NEW_column_precision=${next_value}
                set_next_value ; NEW_column_scale=${next_value}
                set_next_value ; minimum_string_length=${next_value}            # The trimmed minimum string length

                # This value (this check) was only done for datatypes NCHAR/NVARCHAR ... to see if they are truly UTF8 (or just plain old latin9)
                if [ "$column_datatype" = "national character" -o "$column_datatype" = "national character varying" ]; then
                        set_next_value ; utf8_test=${next_value}
                else
                        utf8_test=""
                fi

                it_is_a_number="FALSE"



                if [ $size_check -eq -1 -o $size_check -eq 0 ]; then

                        # If we are not storing anything in the string (other than NULLs or spaces)
                        # Then we don't need to use a 'N'ational datatype ... CHAR/VARCHAR will do just fine
                        # And a length of (1) is more than enough
                        unused_column=$size_check
                        NEW_column_definition="`echo "${column_datatype}" | sed -e "s/national //"`(1)"

                else



                        if [ "$utf8_test" = "" ]; then
                                # The column does NOT appear to contain any UTF8 data in it
                                # So, "IF" it was previously defined as a 'N'ational datatype ... strip off the 'national '
                                # And set the new max column width
                                NEW_column_definition="`echo "${column_datatype}" | sed -e "s/national //"`(${size_check})"
                        else
                                # Else, just set the new max column width
                                NEW_column_definition="${column_datatype}(${size_check})"
                        fi



                        # A VARCHAR column has a 2-byte overhead ... that specifies the length of column/text string
                        # If I redefine the column as CHAR I can save those 2 bytes
                        # But don't make this change if I was supposed to skip over this column in the first place
                        if [ "$not_null_check" != "skip" ]; then
                                if [ "$NEW_column_definition" = "character varying(1)" ]; then NEW_column_definition="character(1)" ; fi
                                if [ "$NEW_column_definition" = "CHARACTER VARYING(1)" ]; then NEW_column_definition="CHARACTER(1)" ; fi
                                if [ "$NEW_column_definition" = "character varying(2)" ]; then NEW_column_definition="character(2)" ; fi
                                if [ "$NEW_column_definition" = "CHARACTER VARYING(2)" ]; then NEW_column_definition="CHARACTER(2)" ; fi
                                if [ "$NEW_column_definition" = "VARCHAR(2)" ]; then NEW_column_definition="CHARACTER(2)" ; fi
                                if [ "$NEW_column_definition" = "varchar(1)" ]; then NEW_column_definition="char(1)   " ; fi
                                if [ "$NEW_column_definition" = "varchar(2)" ]; then NEW_column_definition="char(2)   " ; fi
                                if [ "$NEW_column_definition" = "VARCHAR(1)" ]; then NEW_column_definition="CHARACTER(1)" ; fi
                        fi


                        # Did the string contain ONLY the following characters     "0123456789. +-"
                        # In which case ... it might possible be able to be stored in an INT<n> or NUMERIC datatype
                        if [ $possibly_a_number -eq 0 ]; then

                                test_column_definition=""

                                if [ $NEW_column_scale -eq 0 -a $NEW_column_precision -le 18 ]; then

                                        # See if it looks like an INT<n> datatype
                                        # (These aren't the biggest possible values that could fit into these INT<n>'s ... just the safest)

                                         if [ $NEW_column_precision -le 2 ]; then test_column_definition="byteint"
                                       elif [ $NEW_column_precision -le 4 ]; then test_column_definition="smallint"
                                       elif [ $NEW_column_precision -le 9 ]; then test_column_definition="integer"
                                       else                                       test_column_definition="bigint"
                                         fi

                                else

                                        # See if it looks like a NUMERIC datatype

                                        let NEW_column_precision=${NEW_column_precision}+${NEW_column_scale}

                                        NEW_column_precision=`round_up ${NEW_column_precision}`

                                        # Make sure the precision + scale are within bounds (31,0) to (31,31) before bothering to actually use it

                                        if [ $NEW_column_precision -ge 1 -a $NEW_column_precision -le 31 ]; then
                                                test_column_definition="numeric(${NEW_column_precision},${NEW_column_scale})"
                                        fi

                                fi

                                # So ... the NEW_column_definition has already been tweaked.
                                # Now ... I want to test the test_column_definition to see if it truly is an INT<n> or NUMERIC.
                                # To see if I can use it instead.
                                # And the only way to do that is to run another query against the table (against this column).
                                # And see if the conversion is successful (or not).

                                if [ "$test_column_definition" != "" ]; then

                                        # I don't need to do anything with the output of this query
                                        # I just want to see if dbsql throws a runtime error, or not


                                        sql1="select max(case when length(trim(${quoted_column_name})) = 0 then null else trim(${quoted_column_name})::${test_column_definition} end) from ${table_name} ${SAMPLE};"

                                        if [ "$verbose" = "TRUE" ]; then
                                                echo "/*"
                                                echo "${sql1}"
                                                echo "*/"
                                                echo ""
                                        fi

                                        dbsql -q -X -A -t -c "${sql1}" >/dev/null 2>&1

                                        if [ $? -eq 0 ]; then

                                                # It appears to be an INT<n> or NUMERIC datatype.  Use this column definition instead.
                                                NEW_column_definition="${test_column_definition}"

                                                # Should the column be defined as nullable or NOT NULL ?
                                                # Regardless of any prior decisions ...
                                                # if any of the trimmed strings have a length of 0, then I am going to treat them as a null.
                                                # Because converting it to 0 isn't the right thing to do.
                                                if [ $minimum_string_length -eq 0 ]; then NEW_column_notnull="" ; fi

                                                it_is_a_number="TRUE"

                                        fi
                                fi

                        fi
                fi



                if [ "$it_is_a_number" = "TRUE" ]; then
                        insert_sql_column="case when length(trim(${quoted_column_name})) = 0 then null else ${quoted_column_name} end"

                elif [ "$trim_for_strings" = "TRIM" ]; then
                        insert_sql_column="   trim(${quoted_column_name})"

                elif [ "$trim_for_strings" = "RTRIM" ]; then
                        insert_sql_column="   rtrim(${quoted_column_name})"

                fi

                ;;



        esac



        ################################################################################



        insert_logger "${insert_sql_column}${eol_char}${NEWLINE}"



        if [ "$NEW_column_definition" = "$column_definition" -a "$NEW_column_notnull" = "$column_notnull" -a "$unused_column" = "" ]; then

                last_column_was_redesigned="FALSE"

                # The column is already optimal.  Display the original values/strings.
                echo "  ${org_column_name}      ${org_column_definition} ${org_column_notnull} ${org_column_default} "

        else

                if [ "$last_column_was_redesigned" = "FALSE" ]; then
                        echo ""
                fi
                last_column_was_redesigned="TRUE"

                echo "--REDESIGN"

                if [ "$unused_column" = "-1" ]; then
                echo "--This column contains only NULL values, and could possibly be eliminated entirely."
                fi

                if [ "$unused_column" = "0" -a "$NEW_column_notnull" = "NOT NULL" ]; then
                echo "--This column does not appear to contain any meaningful data, and could possibly be eliminated entirely."
                echo "--(All values are the same value ... and are either a 0, a string of 0..more spaces, a time of 00:00:00, etc ...)"
                fi

                if [ "$additional_message" != "" ]; then
                        echo "$additional_message"
                fi
                additional_message=""   # reset it

                # Drop two space from the beginning of the line
                # So I can replace them with the SQL comment characters --
                # So the alignment will remain the same
                #org_column_name=`echo "${org_column_name}" | cut -b3-`

                if [ "$NEW_column_definition" = "$column_definition" ]; then
                        # If the column definition has NOT changed, then use the original column definition
                        # (with original spacing ... to try to preserve alignment on the line)
                        NEW_column_definition="$org_column_definition"
                else
                        # Else, use the new column definition
                        # I am using sed simply to attempt to (try to) maintain the spacing/alignment on the line
                        NEW_column_definition=`echo "${org_column_definition}" | sed -e "s/${column_definition}/${NEW_column_definition}/"`
                fi

                if [ "$NEW_column_notnull" = "$column_notnull" ]; then
                        NEW_column_notnull="${org_column_notnull}"
                fi

                echo "  --${org_column_name} ${org_column_definition} ${org_column_notnull} ${org_column_default}${eol_char}"
                echo "    ${org_column_name} ${NEW_column_definition} ${NEW_column_notnull} ${org_column_default}${eol_char}"
                echo ""
        fi

        ################################################################################

done

}



################################################################################



throw_an_error () {

        echo ""
        echo "ERROR:  dbsql reported an error when trying to access table ${table_name} in database ${DB_DATABASE}.${DB_SCHEMA}"
        echo ""
        echo "$RESULTS"
        echo ""
        echo "This script is exiting ..."
        exit 1

}



################################################################################



# This is the main body of work that controls everything

process_the_original_ddl () {
at_eof="FALSE"
in_a_table="TRUE"
once="FALSE"
IFS='|'
save_table=""
number_of_columns=0
while true; do

#JAS_BYPASS#    read -r a_line
#JAS_BYPASS     read -r org_table org_column_name org_column_definition org_column_notnull org_column_default
#JAS_BYPASS     if [ "$org_table" = "<eof>" ]; then at_eof="TRUE" ; fi
#JAS_BYPASS#    test_str=`echo "$a_line" | cut -b 1-12`
#JAS_BYPASS
#JAS_BYPASS#    if [ "$test_str" != "CREATE TABLE" ]; then
#JAS_BYPASS#            echo "$a_line" | sed -e "s/ .~.//g"
#JAS_BYPASS#    else
#JAS_BYPASS#            echo "$a_line"
#JAS_BYPASS#    table_name=`echo "$a_line" | cut -d'.' -f2 | cut -d' ' -f1` ; # we have schema so use the dot name is elimited.
#JAS_BYPASS#    schema_name=`echo "$a_line" | cut -d'.' -f1 | cut -d' ' -f3` ; # we have schema so use the dot name is elimited.
#JAS_BYPASS     table_name=$org_table
#JAS_BYPASS     column_name=$org_column_name
#JAS_BYPASS     column_definition=$org_column_definition
#JAS_BYPASS        column_notnull=$org_column_notnull
#JAS_BYPASS     column_default=$org_column_default
#JAS_BYPASS        str1=`echo "$column_definition"`
#JAS_BYPASS        str2=`echo "$str1" | cut -d "(" -f1`
#JAS_BYPASS        column_datatype=`echo "$str2" | tr '[:upper:]' '[:lower:]'`
#JAS_BYPASS        if [ "$str1" = "$str2" ]; then
#JAS_BYPASS            column_scale=0
#JAS_BYPASS            column_precision=0
#JAS_BYPASS        else
#JAS_BYPASS            str3=`echo "$str1" | cut -d "(" -f2 | cut -d ")" -f1`
#JAS_BYPASS            str4=`echo "$str3" | cut -d "," -f1`
#JAS_BYPASS            column_precision=$str4
#JAS_BYPASS            if [ "$str3" = "$str4" ]; then
#JAS_BYPASS               column_scale=0
#JAS_BYPASS            else
#JAS_BYPASS               column_scale=`echo "$str3" | cut -d "," -f2`
#JAS_BYPASS            fi
#JAS_BYPASS        fi
#JAS_BYPASS
#JAS_BYPASS
#JAS_BYPASS
#JAS_BYPASS#JAS  echo "read: $org_table $org_column_name $org_column_definition $org_column_notnull $org_column_default"
#JAS_BYPASS
#JAS_BYPASS     # I added the <eof> to the end of the ddl file ... as a flag ... to let me know when I'm done
#JAS_BYPASS#JAS         if [ "$a_line" = "<eof>" ]; then return ; fi
#JAS_BYPASS
#JAS_BYPASS#    test_str=`echo "$a_line" | cut -b 1-12`
#JAS_BYPASS#    test_str=`echo "$a_line" | cut -b 1-12`
#JAS_BYPASS
#JAS_BYPASS#    if [ "$test_str" = "CREATE TABLE" ]; then
#JAS_BYPASS
#JAS_BYPASS#    echo "CREATE TABLE  $org_table
#JAS_BYPASS#(
#JAS_BYPASS#    $org_column_name        $org_column_definition  $org_ccolumn_notnull $org_column_default,"
#JAS_BYPASS
#JAS_BYPASS#            table_name=`echo "$a_line" | cut -d'.' -f2 | cut -d' ' -f1`
#JAS_BYPASSecho "SQL Limit 1 table name is '$table_name'"
#JAS_BYPASS                RESULTS=`dbsql -q -X -A -t -c "select 'ok' from ${table_name} limit 1;" 2>&1`
#JAS_BYPASS
#JAS_BYPASS             if [ "$?" != "0" ]; then
#JAS_BYPASS                     throw_an_error
#JAS_BYPASS             fi
#JAS_BYPASS
#JAS_BYPASS                if [ "$RESULTS" = "ok" ]; then
#JAS_BYPASS                     in_a_table="TRUE"
#JAS_BYPASS                     number_of_columns=1
#JAS_BYPASS                     store_column_info $number_of_columns
#JAS_BYPASS                     last_column_was_redesigned="FALSE"
#JAS_BYPASS
#JAS_BYPASS                     insert_logger="INSERT INTO ${org_table}${NEWLINE}SELECT${NEWLINE}"
#JAS_BYPASS
#JAS_BYPASS                     insert_orderby_column=""
#JAS_BYPASS
#JAS_BYPASS             else
#JAS_BYPASS                     in_a_table="FALSE"
#JAS_BYPASS                     echo "--REDESIGN:  This table contains no data.  No recommendations can be made."
#JAS_BYPASS                fi
#JAS_BYPASS
#JAS_BYPASS#            echo "$a_line"                  # The CREATE TABLE statement
#JAS_BYPASS
#JAS_BYPASS#            read -r a_line
#JAS_BYPASS#            echo "$a_line"                  # The "(" that immediately follows it
#JAS_BYPASS
#JAS_BYPASSecho "   $org_column_name    $org_column_definition  $org_ccolumn_notnull $org_column_default,"
#JAS_BYPASS     #       echo "$a_line" | sed -e "s/ .~.//g"
#JAS_BYPASS     fi
#JAS_BYPASS
#JAS_BYPASS
        while [ "$in_a_table" = "TRUE" ]; do

                process_the_columns="FALSE"

#               read -r a_line
#
        read -r in_table in_column_name in_column_definition in_column_notnull in_column_default
        if [ "$in_table" = "<eof>" ] ; then
                at_eof="TRUE"
        fi
        if [ "$at_eof" = "FALSE" ] ; then
            RESULTS=`dbsql -q -X -A -t -c "select 'ok' from ${in_table} limit 1;" 2>&1`
            if [ "$?" != "0" ]; then
                   throw_an_error
            fi
           if [ "$RESULTS" != "ok" ]; then
                in_a_table="FALSE"
                echo "--REDESIGN:  Table $table_name contains no data.  No recommendations can be made."
           fi
        fi
        if [ "$once" = "FALSE" ] ; then
                once="TRUE"
                save_table=$in_table
                table_name=$in_table
                last_column_was_redesigned="FALSE"
        fi

#
#
#JAS    echo "Col_read $number_of_columns: $org_table $org_column_name $org_column_definition $org_column_notnull $org_column_default"

#               if [ "$a_line" = ")" -o "$a_line" = "" ]; then
                if [ "$save_table" != "$in_table"  ]; then

                        in_a_table="FALSE"
                        process_the_columns="TRUE"
                        save_table="$in_table"
                else
                        let number_of_columns++

                        # Extract the individual columns from this line

                        org_table=$in_table
                        org_column_name=$in_column_name
                        org_column_definition=$in_column_definition
                        org_column_notnull=$in_column_notnull
                        if [ "$in_column_default" = "" ] ; then
                           org_column_default=$in_column_default
                        else
                           org_column_default=`echo "WITH DEFAULT ${in_column_default}"`
                        fi

                        # Remove leading/trailing spaces
                        column_name=`      echo "$org_column_name"       | sed -e 's/^ *//' -e 's/ *$//'`
                        column_definition=`echo "$org_column_definition" | sed -e 's/^ *//' -e 's/ *$//'`
                        column_notnull=`   echo "$org_column_notnull"    | sed -e 's/^ *//' -e 's/ *$//'`
                        column_default=`   echo "$org_column_default"    | sed -e 's/^ *//' -e 's/ *$//'`

                        # Split the definition up into its component parts     NUMERIC(s,p)  CHAR(s)

                        str1=`echo "$column_definition"`
                        str2=`echo "$str1" | cut -d "(" -f1`
                        column_datatype=`echo "$str2" | tr '[:upper:]' '[:lower:]'`
                        if [ "$str1" = "$str2" ]; then
                                column_scale=0
                                column_precision=0
                        else str3=`echo "$str1" | cut -d "(" -f2 | cut -d ")" -f1` str4=`echo "$str3" | cut -d "," -f1`
                                column_precision=$str4
                                if [ "$str3" = "$str4" ]; then
                                        column_scale=0
                                else
                                        column_scale=`echo "$str3" | cut -d "," -f2`
                                fi
                        fi
#JAS DEBUG echo "SKIER datatype '$column_datatype' scale '$column_scale' prec '$column_precision' org '$column_definition'"
#JAS DEBUG echo "Column name: '$column_name' , Col_def '$column_definition' , not_null '$column_notnull' "
#JAS DEBUG echo "Sleeping 5"; sleep 5

                        # Store everything in an array
                        store_column_info $number_of_columns

                        # Process (no more than) 'N' columns at a time (by default, N = 250)
                        # As each column/datatype will result in multiple column values being returned
                        # And I can't exceed the limit of 1,600 columns
                        if [ $number_of_columns -ge $MAX_COLUMNS_TO_PROCESS ]; then
                                process_the_columns="TRUE"
                        fi

                fi

                ################################################################################


                if [ "$process_the_columns" = "TRUE" ]; then
                    echo "CREATE TABLE $table_name"
                    echo "   ("
                   if [ "$INSERT" = "TRUE" ]; then
                        insert_logger "INSERT INTO ${table_name}${NEWLINE}SELECT${NEWLINE}"
                        insert_orderby_column=""
                   fi
                        sql="select 'ok' as filler"

                        build_sql_to_test_this_subset_of_columns

                        # I seem to have a flow control issue
                        # For example, if I am processing 1 column at a time ...
                        # then I will end up issuing this SQL once, at the end, for NO column at all
                        # And if it is a big table, that could take awhile
                        # So ... make sure I don't do too much extra work here.
                        # Just issue one dummy sql statement that does NOT hit the table.
                        # I'll fix the other logic later
                        if [ "$sql" = "select 'ok' as filler" ]; then
                                true
                        else
                                sql="${sql}

FROM ${table_name} ${SAMPLE};"
                        fi

                        if [ "$verbose" = "TRUE" ]; then
                                echo ""
                                echo "/*"
                                echo "${sql}"
                                echo "*/"
                                echo ""
                        fi


                        AN_ERROR_OCCURRED="FALSE"

                        RESULTS=`dbsql -q -X -A -t <<eof 2>&1
${sql}
eof
`

                        if [ "$?" != "0" ]; then
                                AN_ERROR_OCCURRED="TRUE"
                        fi

                #JAS fi

                        provide_recommendations_for_this_subset_of_columns

                        # Reset this ... so I can do the next batch of columns in this table (if any)
                        number_of_columns=0

                fi

                ################################################################################

                if [ "$in_a_table" = "FALSE" ]; then

                                        # I am done (with this table) ... I am no longer in/processing the table  ... so
#                       echo "$a_line"  # Echo out the last line just read from the table (after all of the column definitions)

                        insert_logger "FROM ${DB_DATABASE}.${DB_SCHEMA}.${table_name}${NEWLINE}"

                        if [ "$ORDERBY" = "TRUE" -a "$insert_orderby_column" != "" ]; then
                                insert_logger "ORDER BY ${insert_orderby_column}${NEWLINE}"
                        fi

                        insert_logger ";${NEWLINE}${NEWLINE}"

                fi

                ################################################################################

        done    # Processing each line of the table (column)
echo "  )"
process_distribution ${DB_SCHEMA} $table_name
echo ""
echo ""
if [ "$at_eof" = "TRUE" ]; then return ; fi
# Remove leading/trailing spaces

org_table=$in_table
table_name=$in_table
org_column_name=$in_column_name
org_column_definition=$in_column_definition
org_column_notnull=$in_column_notnull
org_column_default=$in_column_default
column_name=`      echo "$org_column_name"       | sed -e 's/^ *//' -e 's/ *$//'`
column_definition=`echo "$org_column_definition" | sed -e 's/^ *//' -e 's/ *$//'`
column_notnull=`   echo "$org_column_notnull"    | sed -e 's/^ *//' -e 's/ *$//'`
column_default=`   echo "$org_column_default"    | sed -e 's/^ *//' -e 's/ *$//'`

# Split the definition up into its component parts     NUMERIC(s,p)  CHAR(s)

str1=`echo "$column_definition"`
str2=`echo "$str1" | cut -d "(" -f1`
column_datatype=`echo "$str2" | tr '[:upper:]' '[:lower:]'`
if [ "$str1" = "$str2" ]; then
        column_scale=0
        column_precision=0
else
        str3=`echo "$str1" | cut -d "(" -f2 | cut -d ")" -f1`
        str4=`echo "$str3" | cut -d "," -f1`
        column_precision=$str4
        if [ "$str3" = "$str4" ]; then
                column_scale=0
        else
                column_scale=`echo "$str3" | cut -d "," -f2`
        fi
fi
number_of_columns=1
store_column_info  $number_of_columns

table_name=$save_table
in_a_table="TRUE"
done            # Processing each line of the DDL file
}



################################################################################



# If the user specified "-insert" ... I will write out the
#      insert into new_table select col1, col2, coln from old_table
# statements to a disk file ... to be displayed later on.

insert_logger() {

        if [ "$INSERT" = "TRUE" ]; then
                echo -n "$1" >> ${TMPFILE}.insert
        fi

}



################################################################################

MANDATORY_DATABASE_NAME=""
OPTIONAL_TABLE_NAME=""

verbose="FALSE"
integer_processing_option="ANY"
numeric_processing_option="ANY"
float_processing_option="ANY"
text_processing_option="ANY"
trim_for_strings="TRIM"
binary_processing_option="ANY"

ROUND_UP="FALSE"

MAX_COLUMNS_TO_PROCESS=100

export INSERT="FALSE"
export ORDERBY="FALSE"
export SAMPLE=""
while [ "$1" != "" ]; do

        OPTION=$1
        case $OPTION in

                "-ins"|"-insert" )
                        shift
                        export INSERT="TRUE"
                        ;;

                "-order"|"-orderby"|"-order-by"|"-order_by" )
                        shift
                        export ORDERBY="TRUE"
                        ;;

                "-col"|"-cols"|"-column"|"-columns" )

                        shift

                        TMP_VALUE=$1

                        if [ $TMP_VALUE -ge 1 -a $TMP_VALUE -le 250 ]  2>/dev/null ; then
                                MAX_COLUMNS_TO_PROCESS=$TMP_VALUE
                        else
                                echo "Invalid argument: -columns '$1'"
                                echo "Try \"`basename $0` -h\" for more information."
                                exit 1
                        fi

                        shift ;;

                "-sample" )

                        shift

                        TMP_VALUE=$1

                        if [ $TMP_VALUE -ge 1 -a $TMP_VALUE -le 100 ]  2>/dev/null ; then
                                SAMPLE=$TMP_VALUE
                        else
                                echo "Invalid argument: -sample '$1'"
                                echo "Try \"`basename $0` -h\" for more information."
                                exit 1
                        fi

                        shift ;;

                "-v"|"-verbose" )
                        shift
                        verbose="TRUE"
                        ;;

                "-int"|"-integer"|"-integers" )
                        shift

                        astring=`echo $1 | dd conv=lcase 2>/dev/null`
                        if [ "$astring" = "any" ]; then
                                integer_processing_option="ANY"
                        elif [ "$astring" = "skip" ]; then
                                integer_processing_option="SKIP"
                        else
                                echo "ERROR:  Invalid option, -integer '$1'"
                                exit 1
                        fi
                        shift

                        ;;

                "-num"|"-numeric"|"-numerics"|"-number" )
                        shift

                        astring=`echo $1 | dd conv=lcase 2>/dev/null`
                        if [ "$astring" = "num" -o "$astring" = "numeric" ]; then
                                numeric_processing_option="NUMERIC"
                        elif [ "$astring" = "any" ]; then
                                numeric_processing_option="ANY"
                        elif [ "$astring" = "skip" ]; then
                                numeric_processing_option="SKIP"
                        else
                                echo "ERROR:  Invalid option, -numeric '$1'"
                                exit 1
                        fi
                        shift

                        ;;

                "-float"|"-floats" )
                        shift

                        astring=`echo $1 | dd conv=lcase 2>/dev/null`
                        if [ "$astring" = "num" -o "$astring" = "numeric" ]; then
                                float_processing_option="NUMERIC"
                        elif [ "$astring" = "any" ]; then
                                float_processing_option="ANY"
                        elif [ "$astring" = "skip" ]; then
                                float_processing_option="SKIP"
                        else
                                echo "ERROR:  Invalid option, -float '$1'"
                                exit 1
                        fi
                        shift

                        ;;

                "-text"|"-char"|"-character" )
                        shift

                        astring=`echo $1 | dd conv=lcase 2>/dev/null`
                        if [ "$astring" = "num" -o "$astring" = "numeric" ]; then
                                text_processing_option="NUMERIC"
                        elif [ "$astring" = "any" ]; then
                                text_processing_option="ANY"
                        elif [ "$astring" = "skip" ]; then
                                text_processing_option="SKIP"
                        elif [ "$astring" = "utf8" ]; then
                                text_processing_option="UTF8"
                        else
                                echo "ERROR:  Invalid option, -text '$1'"
                                exit 1
                        fi
                        shift

                        ;;

                "-trim" )
                        shift

                        astring=`echo $1 | dd conv=lcase 2>/dev/null`
                        if [ "$astring" = "trim" ]; then
                                trim_for_strings="TRIM"
                        elif [ "$astring" = "rtrim" ]; then
                                trim_for_strings="RTRIM"
                        elif [ "$astring" = "none" ]; then
                                trim_for_strings=""
                        elif [ "$astring" = "skip" ]; then
                                trim_for_strings="SKIP"
                        else
                                echo "ERROR:  Invalid option, -trim '$1'"
                                exit 1
                        fi
                        shift

                        ;;

                "-round"|"-rounded"|"-roundup"|"-round_up" )
                        shift

                        ROUND_UP="TRUE"

                        ;;

                "-binary" )
                        shift

                        astring=`echo $1 | dd conv=lcase 2>/dev/null`
                        if [ "$astring" = "any" ]; then
                                binary_processing_option="ANY"
                        elif [ "$astring" = "skip" ]; then
                                binary_processing_option="SKIP"
                        else
                                echo "ERROR:  Invalid option, -binary '$1'"
                                exit 1
                        fi
                        shift

                        ;;

                * )
                          if [ "$MANDATORY_DATABASE_NAME" = "" ]; then MANDATORY_DATABASE_NAME=$1
                        elif [ "$OPTIONAL_TABLE_NAME" = "" ];     then OPTIONAL_TABLE_NAME=$1
                                                                  else source $SCRIPT_DIR/lib/ERR_command_line_arg $1
                          fi
                        shift
                        ;;
        esac
done
if [  "$MANDATORY_DATABASE_NAME" = ""  -a  "$GLOBAL_ENV_NZ_DATABASE" != "" ]; then
     MANDATORY_DATABASE_NAME="$GLOBAL_ENV_NZ_DATABASE"
fi
if [ "$MANDATORY_DATABASE_NAME" = "" ]; then
        echo "ERROR:  No database name was specified."
        exit 1
fi

export DB_DATABASE=$MANDATORY_DATABASE_NAME

#if [ ! $NPS_VERSION ]; then source $SCRIPT_DIR/lib/CODE_basic_connection ; fi
#if [ ! $NPS_VERSION ]; then source /opt/ibm/npssupport/bin/lib/CODE_basic_connection ; fi

# You can sample the data ... from 1 to 100% of the data
# Which will be converted into an extent number from 1-24
if [ "$SAMPLE" != "" ]; then
        SAMPLE=`dbsql -q -X -A -t -c "select to_char(${SAMPLE}.00 / 4.166667, '999');"`
        if [ $SAMPLE -eq 0 ]; then SAMPLE=1 ; fi
        SAMPLE="where mod(_PAGEID, 32) <= $SAMPLE"
fi

if [ "$OPTIONAL_TABLE_NAME" = "" ]; then
        TABLE=""
else
#       TABLE=`db_get_table_name $OPTIONAL_TABLE_NAME`
        check_table_or_view_exists $OPTIONAL_TABLE_NAME "table"
        TABLE=$OPTIONAL_TABLE_NAME
        if [ "$TABLE" = "" ]; then
                echo "ERROR:  No such table '$OPTIONAL_TABLE_NAME'"
                exit 1
        fi
fi



# I will run db_ddl_table to obtain the true/original ddl for the table(s).
# That output will be saved off to disk ... which I will then process.
# When invoking db_ddl_table, I need to tell it to add special delimiters between the "columns of output" so it is easier for me to parse.

export TMPFILE="/tmp/tmp.`date +%Y%m%d%H%M%S`.$$"
export INVOKED_VIA_DB_DDL_TABLE_REDESIGN="TRUE"
if [ $NZ_SCRIPT_NAME ]; then
        unset NZ_SCRIPT_NAME
fi
SAVE_SCRIPT_DIR=$SCRIPT_DIR
unset SCRIPT_DIR

#JAS if [ "$TABLE" = "" ]; then
#JAS    /usr/bin/db_ddl_table  -db $DB_DATABASE             >${TMPFILE}.redesign
#JAS else
#JAS    /usr/bin/db_ddl_table  -db BLUDB -tb REDESIGN  >${TMPFILE}.redesign
#JAS fi
if [ "$TABLE" = "" ]; then
   SQL="SELECT A.TABNAME, COLNAME, CASE WHEN TYPENAME IN ('CHARACTER','VARCHAR','GRAPHIC','VARGRAPHIC','FLOAT','DECFLOAT','BINARY','VARBINARY') THEN CONCAT(CONCAT(CONCAT(TYPENAME,'('),LENGTH),')') WHEN TYPENAME = 'DECIMAL' THEN CONCAT(CONCAT(CONCAT(CONCAT(CONCAT(TYPENAME,'('),LENGTH),','),SCALE),')') ELSE TYPENAME END, CASE WHEN NULLS='Y' THEN '' ELSE 'NOT NULL' END, DEFAULT FROM SYSCAT.COLUMNS  A JOIN SYSCAT.TABLES B on A.TABNAME = B.TABNAME AND A.TABSCHEMA = B.TABSCHEMA AND B.TYPE = 'T' WHERE A.TABSCHEMA = CURRENT_SCHEMA ORDER BY A.TABNAME, COLNO"
else
   SQL="SELECT A.TABNAME, COLNAME, CASE WHEN TYPENAME IN ('CHARACTER','VARCHAR','GRAPHIC','VARGRAPHIC','FLOAT','DECFLOAT','BINARY','VARBINARY') THEN CONCAT(CONCAT(CONCAT(TYPENAME,'('),LENGTH),')') WHEN TYPENAME = 'DECIMAL' THEN CONCAT(CONCAT(CONCAT(CONCAT(CONCAT(TYPENAME,'('),LENGTH),','),SCALE),')') ELSE TYPENAME END, CASE WHEN NULLS='Y' THEN '' ELSE 'NOT NULL' END, DEFAULT FROM SYSCAT.COLUMNS A JOIN SYSCAT.TABLES B on A.TABNAME = B.TABNAME AND A.TABSCHEMA = B.TABSCHEMA AND B.TYPE = 'T' WHERE A.TABNAME='$TABLE' AND A.TABSCHEMA = CURRENT_SCHEMA ORDER BY A.TABNAME, COLNO"
fi
dbsql -Atc $SQL > ${TMPFILE}.redesign
echo "<eof>" >> ${TMPFILE}.redesign
export NZ_USER=$GLOBAL_ENV_NZ_USER
export NZ_PASSWORD=$GLOBAL_ENV_NZ_PASSWORD
export NZ_DATABASE=$GLOBAL_ENV_NZ_DATABASE
export NZ_SCHEMA=$GLOBAL_ENV_NZ_SCHEMA

if [ ! ${SAVE_SCRIPT_DIR} ]; then
        SCRIPT_DIR=${SAVE_SCRIPT_DIR}
        echo "SCRIPT_DIR"
fi

cat ${TMPFILE}.redesign | process_the_original_ddl
exit_code=$?



if [ "$INSERT" = "TRUE" ]; then
echo "

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

"
cat ${TMPFILE}.insert
fi



#rm -rf ${TMPFILE}.*
exit $exit_code



#
# For example ... the before (TPCH100) and after (TPCH100_REDESIGNED) databases
# Wherein I accepted all of the changes as suggested by this script
#
# Notice that the Compressed Size isn't all that different.  Which goes to show how good compression is.
# But sometimes that data needs to be read from disk and decompressed so you can do something with it.
# And the Uncompressed Size difference is much greater.
#
#   Database: TPCH100
#
#   Table/MView Name                 Ratio   Compressed Size    Uncompressed Size    Size Difference
#   ================================ ===== =================== =================== ===================
#   CUSTOMER                          2.16       1,343,750,144       2,904,107,002       1,560,356,858
#   LINEITEM                          2.83      30,722,359,296      86,808,132,958      56,085,773,662
#   ORDERS                            2.52       8,102,739,968      20,416,200,056      12,313,460,088
#   PART                              2.57       1,211,105,280       3,109,656,600       1,898,551,320
#   PARTSUPP                          2.06       6,803,292,160      14,018,396,268       7,215,104,108
#   SUPPLIER                          2.15          80,740,352         173,605,954          92,865,602
#   ================================ ===== =================== =================== ===================
#   Total: TPCH100                    2.64      48,263,987,200     127,430,098,838      79,166,111,638
#
#
#   Database: TPCH100_REDESIGNED
#
#   Table/MView Name                 Ratio   Compressed Size    Uncompressed Size    Size Difference
#   ================================ ===== =================== =================== ===================
#   CUSTOMER                          2.07       1,343,750,144       2,784,816,508       1,441,066,364
#   LINEITEM                          2.40      30,200,954,880      72,353,420,957      42,152,466,077
#   ORDERS                            2.37       8,103,264,256      19,218,768,960      11,115,504,704
#   PART                              2.42       1,202,454,528       2,909,478,995       1,707,024,467
#   PARTSUPP                          1.99       6,803,554,304      13,530,013,538       6,726,459,234
#   SUPPLIER                          2.05          80,740,352         165,704,836          84,964,484
#   ================================ ===== =================== =================== ===================
#   Total: TPCH100_REDESIGNED         2.32      47,734,718,464     110,962,203,794      63,227,485,330
#