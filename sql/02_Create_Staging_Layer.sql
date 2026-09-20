/*

    Flight Reliability Intelligence System

    Script: 02_Create_Staging_Layer.sql



    Purpose:

        Create 12 monthly staging tables that serve as the SQL Server

        landing layer for the cleaned Python ETL output.



    Source of the data:

        Python already cleaned and validated the 2025 flight data.

        Each monthly CSV file maps directly to one staging table:



            data/2025_01_clean.csv  ->  staging.Flights_2025_01

            data/2025_02_clean.csv  ->  staging.Flights_2025_02

            ...

            data/2025_12_clean.csv  ->  staging.Flights_2025_12



    Execution order:

        01_Create_Database_And_Schemas.sql

                ↓

        02_Create_Staging_Layer.sql          <-- this script

                ↓

        03_Load_Staging_Data.sql

                ↓

        dimension loading (future script)

                ↓

        fact loading (future script)

                ↓

        analytics layer (future script)



    This script does not load CSV data.



    Design notes:

        - All 12 tables share the same column structure

        - Column names and types follow the Python export, not raw BTS files

        - No primary keys, foreign keys, or Star Schema relationships here

        - These tables are a landing zone only; they will be combined later

          with UNION ALL when the fact table is built

        - Safe to re-run: each table is dropped and recreated

*/



USE FlightReliabilityIntelligence;

GO



-- Remove leftover objects from the previous single-table architecture.

DROP PROCEDURE IF EXISTS staging.LoadFlightsFromRaw;

GO



DROP FUNCTION IF EXISTS staging.ConvertHhmmToTime;

GO



DROP TABLE IF EXISTS staging.Flights;

GO



/*------------------------------------------------------------------------------

    January template table: staging.Flights_2025_01



    Months 02 through 12 are cloned from this table so the column design

    stays in one place and is easy to maintain.

------------------------------------------------------------------------------*/



DROP TABLE IF EXISTS staging.Flights_2025_01;

GO



CREATE TABLE staging.Flights_2025_01

(

    -- Calendar attributes present on every processed row.

    [YEAR]                     SMALLINT     NOT NULL,

    [QUARTER]                  TINYINT      NOT NULL,

    [MONTH]                    TINYINT      NOT NULL,

    [DAY_OF_MONTH]             TINYINT      NOT NULL,

    [DAY_OF_WEEK]              TINYINT      NOT NULL,

    [FL_DATE]                  DATE         NOT NULL,



    -- Airline and flight identifiers.

    [OP_UNIQUE_CARRIER]        VARCHAR(10)  NOT NULL,

    [OP_CARRIER_AIRLINE_ID]    INT          NOT NULL,

    [OP_CARRIER]               VARCHAR(10)  NOT NULL,

    [TAIL_NUM]                 VARCHAR(10)  NULL,

    [OP_CARRIER_FL_NUM]        INT          NOT NULL,



    -- Origin airport identifiers and descriptive attributes.

    [ORIGIN_AIRPORT_ID]        INT          NOT NULL,

    [ORIGIN_AIRPORT_SEQ_ID]    INT          NOT NULL,

    [ORIGIN_CITY_MARKET_ID]    INT          NOT NULL,

    [ORIGIN]                   VARCHAR(3)   NOT NULL,

    [ORIGIN_CITY_NAME]         VARCHAR(50)  NOT NULL,

    [ORIGIN_STATE_ABR]         VARCHAR(2)   NOT NULL,

    [ORIGIN_STATE_NM]          VARCHAR(50)  NOT NULL,

    [ORIGIN_WAC]               SMALLINT     NOT NULL,



    -- Destination airport identifiers and descriptive attributes.

    [DEST_AIRPORT_ID]          INT          NOT NULL,

    [DEST_AIRPORT_SEQ_ID]      INT          NOT NULL,

    [DEST_CITY_MARKET_ID]      INT          NOT NULL,

    [DEST]                     VARCHAR(3)   NOT NULL,

    [DEST_CITY_NAME]           VARCHAR(50)  NOT NULL,

    [DEST_STATE_ABR]           VARCHAR(2)   NOT NULL,

    [DEST_STATE_NM]            VARCHAR(50)  NOT NULL,

    [DEST_WAC]                 SMALLINT     NOT NULL,



    -- Scheduled and actual departure. Actual times can be missing.

    [CRS_DEP_TIME]             TIME(0)      NOT NULL,

    [DEP_TIME]                 TIME(0)      NULL,

    [DEP_DELAY]                SMALLINT     NULL,

    [DEP_DELAY_NEW]            SMALLINT     NULL,

    [DEP_DEL15]                TINYINT      NULL,

    [DEP_TIME_BLK]             VARCHAR(9)   NOT NULL,

    [TAXI_OUT]                 SMALLINT     NULL,

    [WHEELS_OFF]               TIME(0)      NULL,



    -- Scheduled and actual arrival. Actual times can be missing.

    [WHEELS_ON]                TIME(0)      NULL,

    [TAXI_IN]                  SMALLINT     NULL,

    [CRS_ARR_TIME]             TIME(0)      NOT NULL,

    [ARR_TIME]                 TIME(0)      NULL,

    [ARR_DELAY]                SMALLINT     NULL,

    [ARR_DELAY_NEW]            SMALLINT     NULL,

    [ARR_DEL15]                TINYINT      NULL,

    [ARR_TIME_BLK]             VARCHAR(9)   NOT NULL,



    -- Flight status. Cancellation code is filled only when cancelled.

    [CANCELLED]                BIT          NOT NULL,

    [CANCELLATION_CODE]        VARCHAR(1)   NULL,

    [DIVERTED]                 BIT          NOT NULL,



    -- Duration in minutes and flight distance in miles.

    [CRS_ELAPSED_TIME]         SMALLINT     NULL,

    [ACTUAL_ELAPSED_TIME]      SMALLINT     NULL,

    [AIR_TIME]                 SMALLINT     NULL,

    [DISTANCE]                 SMALLINT     NOT NULL,



    -- Delay-cause minutes. Missing unless the flight has a 15+ minute

    -- arrival delay.

    [CARRIER_DELAY]            SMALLINT     NULL,

    [WEATHER_DELAY]            SMALLINT     NULL,

    [NAS_DELAY]                SMALLINT     NULL,

    [SECURITY_DELAY]           SMALLINT     NULL,

    [LATE_AIRCRAFT_DELAY]      SMALLINT     NULL,



    -- Diversion fields. Most flights are not diverted, so these are

    -- usually missing.

    [DIV_AIRPORT_LANDINGS]     TINYINT      NULL,

    [DIV_REACHED_DEST]         TINYINT      NULL,

    [DIV_ACTUAL_ELAPSED_TIME]  SMALLINT     NULL,

    [DIV_ARR_DELAY]            SMALLINT     NULL,

    [DIV_DISTANCE]             SMALLINT     NULL,

    [DIV1_AIRPORT]             VARCHAR(3)   NULL,

    [DIV1_AIRPORT_ID]          INT          NULL

);

GO



/*------------------------------------------------------------------------------

    Create the remaining 11 monthly staging tables with the same structure.

------------------------------------------------------------------------------*/



DECLARE @Month INT = 2;

DECLARE @MonthText CHAR(2);

DECLARE @TableName SYSNAME;

DECLARE @Sql NVARCHAR(MAX);



WHILE @Month <= 12

BEGIN

    SET @MonthText = RIGHT(N'0' + CAST(@Month AS NVARCHAR(2)), 2);

    SET @TableName = N'staging.Flights_2025_' + @MonthText;



    SET @Sql = N'DROP TABLE IF EXISTS ' + QUOTENAME(N'staging') + N'.' + QUOTENAME(N'Flights_2025_' + @MonthText) + N';';

    EXEC sys.sp_executesql @Sql;



    SET @Sql =

        N'SELECT * INTO ' + QUOTENAME(N'staging') + N'.' + QUOTENAME(N'Flights_2025_' + @MonthText)

        + N' FROM staging.Flights_2025_01 WHERE 1 = 0;';



    EXEC sys.sp_executesql @Sql;



    SET @Month = @Month + 1;

END;

GO



/*------------------------------------------------------------------------------

    Confirm that all 12 monthly staging tables exist.

------------------------------------------------------------------------------*/



SELECT

    t.TABLE_SCHEMA AS table_schema,

    t.TABLE_NAME AS table_name

FROM INFORMATION_SCHEMA.TABLES AS t

WHERE t.TABLE_SCHEMA = N'staging'

  AND t.TABLE_NAME LIKE N'Flights_2025_%'

ORDER BY t.TABLE_NAME;

GO



-- Show the column design from the January template table.

SELECT

    c.ORDINAL_POSITION AS column_position,

    c.COLUMN_NAME AS column_name,

    c.DATA_TYPE AS data_type,

    c.CHARACTER_MAXIMUM_LENGTH AS character_length,

    c.DATETIME_PRECISION AS time_precision,

    c.IS_NULLABLE AS is_nullable

FROM INFORMATION_SCHEMA.COLUMNS AS c

WHERE c.TABLE_SCHEMA = N'staging'

  AND c.TABLE_NAME = N'Flights_2025_01'

ORDER BY c.ORDINAL_POSITION;

GO

