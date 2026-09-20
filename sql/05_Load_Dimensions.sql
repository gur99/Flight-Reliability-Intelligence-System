/*
    Flight Reliability Intelligence System
    Script: 05_Load_Dimensions.sql

    Purpose:
        Populate the dimension tables from the 12 monthly staging tables.

    Dimensions loaded:
        dim.Date
        dim.Airline
        dim.Airport

    Source:
        staging.Flights_2025_01
        staging.Flights_2025_02
        ...
        staging.Flights_2025_12

    Design notes:
        - dim.Date contains one row per calendar date.
        - dim.Airline contains one row per DOT airline.
        - dim.Airport contains one row per AirportID.
        - Origin and destination airport records are combined into the same
          role-playing Airport dimension.
        - MERGE preserves existing surrogate keys when this script is re-run.
        - This script does not load fact.Flights.

    Execution order:

        01_Create_Database_And_Schemas.sql
                ↓
        02_Create_Staging_Layer.sql
                ↓
        03_Load_Staging_Data.sql
                ↓
        04_Create_Dimensional_Model.sql
                ↓
        05_Load_Dimensions.sql
                ↓
        06_Load_FactFlights.sql
                ↓
        07_Data_Validation.sql
*/

USE FlightReliabilityIntelligence;
GO

SET NOCOUNT ON;
SET LANGUAGE us_english;
GO


/*==============================================================================
    1. Validate staging data
==============================================================================*/

DECLARE @Month INT = 1;
DECLARE @MonthText CHAR(2);
DECLARE @Sql NVARCHAR(MAX);
DECLARE @RowCount BIGINT;

WHILE @Month <= 12
BEGIN
    SET @MonthText = RIGHT('0' + CAST(@Month AS VARCHAR(2)), 2);

    SET @Sql = N'
        SELECT @RowCountOut = COUNT(*)
        FROM staging.'
        + QUOTENAME(N'Flights_2025_' + @MonthText)
        + N';';

    EXEC sys.sp_executesql
        @Sql,
        N'@RowCountOut BIGINT OUTPUT',
        @RowCountOut = @RowCount OUTPUT;

    IF @RowCount = 0
    BEGIN
        DECLARE @ErrorMessage NVARCHAR(4000);

        SET @ErrorMessage =
            N'staging.Flights_2025_'
            + @MonthText
            + N' is empty. Load all staging tables before running '
            + N'05_Load_Dimensions.sql.';

        THROW 50010, @ErrorMessage, 1;
    END;

    SET @Month = @Month + 1;
END;

PRINT N'All 12 staging tables contain data.';
GO


/*==============================================================================
    2. Load dim.Date

    Build a continuous calendar between the minimum and maximum FL_DATE found
    across all 12 staging tables.

    DateKey format:
        YYYYMMDD

    Example:
        2025-01-01 -> 20250101
==============================================================================*/

DECLARE @StartDate DATE;
DECLARE @EndDate DATE;

SELECT
    @StartDate = MIN(MinDate),
    @EndDate   = MAX(MaxDate)
FROM
(
    SELECT MIN(FL_DATE) AS MinDate, MAX(FL_DATE) AS MaxDate
    FROM staging.Flights_2025_01

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_02

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_03

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_04

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_05

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_06

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_07

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_08

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_09

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_10

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_11

    UNION ALL

    SELECT MIN(FL_DATE), MAX(FL_DATE)
    FROM staging.Flights_2025_12
) AS DateRanges;


IF OBJECT_ID(N'tempdb..#DateSpine') IS NOT NULL
    DROP TABLE #DateSpine;


CREATE TABLE #DateSpine
(
    [Date] DATE NOT NULL PRIMARY KEY
);


;WITH DateSpine AS
(
    SELECT @StartDate AS [Date]

    UNION ALL

    SELECT DATEADD(DAY, 1, [Date])
    FROM DateSpine
    WHERE [Date] < @EndDate
)
INSERT INTO #DateSpine ([Date])
SELECT [Date]
FROM DateSpine
OPTION (MAXRECURSION 0);


MERGE dim.[Date] AS Target
USING
(
    SELECT
        YEAR([Date]) * 10000
            + MONTH([Date]) * 100
            + DAY([Date]) AS DateKey,

        [Date],

        CAST(YEAR([Date]) AS SMALLINT) AS [Year],

        CAST(
            DATEPART(QUARTER, [Date])
            AS TINYINT
        ) AS [Quarter],

        CAST(
            CONCAT(
                'Q',
                DATEPART(QUARTER, [Date])
            )
            AS CHAR(2)
        ) AS QuarterName,

        CAST(
            MONTH([Date])
            AS TINYINT
        ) AS [Month],

        CAST(
            DATENAME(MONTH, [Date])
            AS VARCHAR(9)
        ) AS MonthName,

        YEAR([Date]) * 100
            + MONTH([Date]) AS YearMonth,

        CAST(
            DAY([Date])
            AS TINYINT
        ) AS DayOfMonth,

        CAST(
            (
                (
                    DATEPART(WEEKDAY, [Date])
                    + @@DATEFIRST
                    - 2
                ) % 7
            ) + 1
            AS TINYINT
        ) AS DayOfWeek,

        CAST(
            DATENAME(WEEKDAY, [Date])
            AS VARCHAR(9)
        ) AS DayName,

        CAST
        (
            CASE
                WHEN
                    (
                        (
                            DATEPART(WEEKDAY, [Date])
                            + @@DATEFIRST
                            - 2
                        ) % 7
                    ) + 1 IN (6, 7)
                THEN 1
                ELSE 0
            END
            AS BIT
        ) AS IsWeekend

    FROM #DateSpine
) AS Source

ON Target.DateKey = Source.DateKey

WHEN MATCHED THEN
    UPDATE SET
        Target.[Date]      = Source.[Date],
        Target.[Year]      = Source.[Year],
        Target.[Quarter]   = Source.[Quarter],
        Target.QuarterName = Source.QuarterName,
        Target.[Month]     = Source.[Month],
        Target.MonthName   = Source.MonthName,
        Target.YearMonth   = Source.YearMonth,
        Target.DayOfMonth  = Source.DayOfMonth,
        Target.DayOfWeek   = Source.DayOfWeek,
        Target.DayName     = Source.DayName,
        Target.IsWeekend   = Source.IsWeekend

WHEN NOT MATCHED BY TARGET THEN
    INSERT
    (
        DateKey,
        [Date],
        [Year],
        [Quarter],
        QuarterName,
        [Month],
        MonthName,
        YearMonth,
        DayOfMonth,
        DayOfWeek,
        DayName,
        IsWeekend
    )
    VALUES
    (
        Source.DateKey,
        Source.[Date],
        Source.[Year],
        Source.[Quarter],
        Source.QuarterName,
        Source.[Month],
        Source.MonthName,
        Source.YearMonth,
        Source.DayOfMonth,
        Source.DayOfWeek,
        Source.DayName,
        Source.IsWeekend
    );

PRINT N'dim.Date loaded successfully.';
GO


/*==============================================================================
    3. Load dim.Airline

    Business key:
        OP_CARRIER_AIRLINE_ID

    Mapping:

        staging.OP_CARRIER_AIRLINE_ID -> dim.Airline.DOTAirlineID
        staging.OP_UNIQUE_CARRIER     -> dim.Airline.UniqueCarrierCode
        staging.OP_CARRIER            -> dim.Airline.CarrierCode
==============================================================================*/

;WITH AirlineSource AS
(
    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_01

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_02

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_03

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_04

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_05

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_06

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_07

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_08

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_09

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_10

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_11

    UNION ALL

    SELECT
        OP_CARRIER_AIRLINE_ID,
        OP_UNIQUE_CARRIER,
        OP_CARRIER
    FROM staging.Flights_2025_12
),

AirlineCurrent AS
(
    SELECT
        OP_CARRIER_AIRLINE_ID AS DOTAirlineID,
        OP_UNIQUE_CARRIER     AS UniqueCarrierCode,
        OP_CARRIER            AS CarrierCode,

        ROW_NUMBER() OVER
        (
            PARTITION BY OP_CARRIER_AIRLINE_ID
            ORDER BY
                OP_UNIQUE_CARRIER,
                OP_CARRIER
        ) AS RowNum

    FROM AirlineSource

    WHERE OP_CARRIER_AIRLINE_ID IS NOT NULL
      AND OP_UNIQUE_CARRIER IS NOT NULL
      AND OP_CARRIER IS NOT NULL
)

MERGE dim.Airline AS Target
USING
(
    SELECT
        DOTAirlineID,
        UniqueCarrierCode,
        CarrierCode
    FROM AirlineCurrent
    WHERE RowNum = 1
) AS Source

ON Target.DOTAirlineID = Source.DOTAirlineID

WHEN MATCHED
     AND
     (
         Target.UniqueCarrierCode <> Source.UniqueCarrierCode
         OR
         Target.CarrierCode <> Source.CarrierCode
     )
THEN
    UPDATE SET
        Target.UniqueCarrierCode = Source.UniqueCarrierCode,
        Target.CarrierCode       = Source.CarrierCode

WHEN NOT MATCHED BY TARGET THEN
    INSERT
    (
        DOTAirlineID,
        UniqueCarrierCode,
        CarrierCode
    )
    VALUES
    (
        Source.DOTAirlineID,
        Source.UniqueCarrierCode,
        Source.CarrierCode
    );

PRINT N'dim.Airline loaded successfully.';
GO


/*==============================================================================
    4. Load dim.Airport

    Origin and destination airport records are combined.

    Business key:
        AirportID

    The highest AirportSeqID is used when multiple sequence IDs exist for the
    same AirportID.
==============================================================================*/

;WITH AirportSource AS
(
    /* January - Origin */

    SELECT
        ORIGIN_AIRPORT_ID       AS AirportID,
        ORIGIN_AIRPORT_SEQ_ID   AS AirportSeqID,
        ORIGIN                  AS AirportCode,
        ORIGIN_CITY_NAME        AS CityName,
        ORIGIN_CITY_MARKET_ID   AS CityMarketID,
        ORIGIN_STATE_ABR        AS StateCode,
        ORIGIN_STATE_NM         AS StateName,
        ORIGIN_WAC              AS WorldAreaCode
    FROM staging.Flights_2025_01

    UNION ALL

    /* January - Destination */

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_01


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_02

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_02


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_03

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_03


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_04

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_04


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_05

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_05


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_06

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_06


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_07

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_07


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_08

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_08


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_09

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_09


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_10

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_10


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_11

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_11


    UNION ALL


    SELECT
        ORIGIN_AIRPORT_ID,
        ORIGIN_AIRPORT_SEQ_ID,
        ORIGIN,
        ORIGIN_CITY_NAME,
        ORIGIN_CITY_MARKET_ID,
        ORIGIN_STATE_ABR,
        ORIGIN_STATE_NM,
        ORIGIN_WAC
    FROM staging.Flights_2025_12

    UNION ALL

    SELECT
        DEST_AIRPORT_ID,
        DEST_AIRPORT_SEQ_ID,
        DEST,
        DEST_CITY_NAME,
        DEST_CITY_MARKET_ID,
        DEST_STATE_ABR,
        DEST_STATE_NM,
        DEST_WAC
    FROM staging.Flights_2025_12
),

AirportCurrent AS
(
    SELECT
        AirportID,
        AirportSeqID,
        AirportCode,
        CityName,
        CityMarketID,
        StateCode,
        StateName,
        WorldAreaCode,

        ROW_NUMBER() OVER
        (
            PARTITION BY AirportID
            ORDER BY AirportSeqID DESC
        ) AS RowNum

    FROM AirportSource

    WHERE AirportID IS NOT NULL
      AND AirportCode IS NOT NULL
      AND CityName IS NOT NULL
      AND StateCode IS NOT NULL
      AND StateName IS NOT NULL
)

MERGE dim.Airport AS Target
USING
(
    SELECT
        AirportID,
        AirportSeqID,
        AirportCode,
        CityName,
        CityMarketID,
        StateCode,
        StateName,
        WorldAreaCode

    FROM AirportCurrent

    WHERE RowNum = 1
) AS Source

ON Target.AirportID = Source.AirportID

WHEN MATCHED THEN
    UPDATE SET
        Target.AirportSeqID  = Source.AirportSeqID,
        Target.AirportCode   = Source.AirportCode,
        Target.CityName      = Source.CityName,
        Target.CityMarketID  = Source.CityMarketID,
        Target.StateCode     = Source.StateCode,
        Target.StateName     = Source.StateName,
        Target.WorldAreaCode = Source.WorldAreaCode

WHEN NOT MATCHED BY TARGET THEN
    INSERT
    (
        AirportID,
        AirportSeqID,
        AirportCode,
        CityName,
        CityMarketID,
        StateCode,
        StateName,
        WorldAreaCode
    )
    VALUES
    (
        Source.AirportID,
        Source.AirportSeqID,
        Source.AirportCode,
        Source.CityName,
        Source.CityMarketID,
        Source.StateCode,
        Source.StateName,
        Source.WorldAreaCode
    );

PRINT N'dim.Airport loaded successfully.';
GO


/*==============================================================================
    5. Dimension validation
==============================================================================*/

SELECT
    N'dim.Date' AS TableName,
    COUNT(*) AS Row_Count
FROM dim.[Date]

UNION ALL

SELECT
    N'dim.Airline',
    COUNT(*)
FROM dim.Airline

UNION ALL

SELECT
    N'dim.Airport',
    COUNT(*)
FROM dim.Airport;
GO


/*------------------------------------------------------------------------------
    Validate Date dimension coverage.
------------------------------------------------------------------------------*/

SELECT
    MIN([Date]) AS MinDate,
    MAX([Date]) AS MaxDate,
    COUNT(*) AS NumberOfDates
FROM dim.[Date];
GO


/*------------------------------------------------------------------------------
    Validate business-key uniqueness.
------------------------------------------------------------------------------*/

SELECT
    DOTAirlineID,
    COUNT(*) AS DuplicateCount
FROM dim.Airline
GROUP BY DOTAirlineID
HAVING COUNT(*) > 1;
GO


SELECT
    AirportID,
    COUNT(*) AS DuplicateCount
FROM dim.Airport
GROUP BY AirportID
HAVING COUNT(*) > 1;
GO

/*
Dimension loading completed successfully.

dim.Date contains 365 rows covering the full 2025 calendar year.
dim.Airline contains 14 unique airlines.
dim.Airport contains 352 unique airports.

No duplicate DOTAirlineID values were found.
No duplicate AirportID values were found.
*/