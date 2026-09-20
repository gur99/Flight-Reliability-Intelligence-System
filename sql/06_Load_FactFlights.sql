/*
    Flight Reliability Intelligence System
    Script: 06_Load_FactFlights.sql

    Purpose:
        Populate fact.Flights from the 12 monthly staging tables.

    Responsibilities:
        - Combine the 12 monthly staging tables logically with UNION ALL
        - Resolve DateKey from dim.Date
        - Resolve AirlineKey from dim.Airline
        - Resolve OriginAirportKey from dim.Airport
        - Resolve DestinationAirportKey from dim.Airport
        - Load flight-level measures and status fields
        - Preserve the validated fact-table grain
        - Validate that no staging rows are lost during the dimension lookups

    Grain:
        One scheduled flight occurrence identified by:

            FL_DATE
            + OP_CARRIER_AIRLINE_ID
            + OP_CARRIER_FL_NUM
            + ORIGIN_AIRPORT_ID
            + DEST_AIRPORT_ID
            + CRS_DEP_TIME

    Notes:
        - The grain was validated across all 2025 staging data.
        - No duplicate grain combinations were found.
        - fact.Flights uses FlightKey as its surrogate primary key.
        - Dimension business keys are replaced by surrogate keys in the fact table.
        - This script performs a full refresh of fact.Flights.

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
GO


/*==============================================================================
    1. Count the expected number of source rows

    Every staging row should eventually become exactly one fact row.
==============================================================================*/

DECLARE @ExpectedRowCount BIGINT;

SELECT
    @ExpectedRowCount = SUM(Row_Count)
FROM
(
    SELECT COUNT_BIG(*) AS Row_Count FROM staging.Flights_2025_01
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_02
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_03
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_04
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_05
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_06
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_07
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_08
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_09
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_10
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_11
    UNION ALL
    SELECT COUNT_BIG(*) FROM staging.Flights_2025_12
) AS MonthlyCounts;

IF @ExpectedRowCount = 0
BEGIN
    ;THROW 50020,
        N'No staging rows were found. Load staging before running 06_Load_FactFlights.sql.',
        1;
END;

PRINT N'Expected fact rows: '
    + CAST(@ExpectedRowCount AS NVARCHAR(30));
GO


/*==============================================================================
    2. Validate dimension lookups

    Every staging record must have matching dimension rows for:
        - Date
        - Airline
        - Origin Airport
        - Destination Airport

    This check prevents INNER JOIN operations from silently dropping flights.
==============================================================================*/

DECLARE @MissingDateKeys BIGINT;
DECLARE @MissingAirlineKeys BIGINT;
DECLARE @MissingOriginAirportKeys BIGINT;
DECLARE @MissingDestinationAirportKeys BIGINT;


;WITH AllFlightKeys AS
(
    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_01

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_02

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_03

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_04

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_05

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_06

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_07

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_08

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_09

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_10

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_11

    UNION ALL

    SELECT
        FL_DATE,
        OP_CARRIER_AIRLINE_ID,
        ORIGIN_AIRPORT_ID,
        DEST_AIRPORT_ID
    FROM staging.Flights_2025_12
)

SELECT
    @MissingDateKeys =
        SUM(
            CASE
                WHEN d.DateKey IS NULL THEN 1
                ELSE 0
            END
        ),

    @MissingAirlineKeys =
        SUM(
            CASE
                WHEN a.AirlineKey IS NULL THEN 1
                ELSE 0
            END
        ),

    @MissingOriginAirportKeys =
        SUM(
            CASE
                WHEN oa.AirportKey IS NULL THEN 1
                ELSE 0
            END
        ),

    @MissingDestinationAirportKeys =
        SUM(
            CASE
                WHEN da.AirportKey IS NULL THEN 1
                ELSE 0
            END
        )

FROM AllFlightKeys AS f

LEFT JOIN dim.[Date] AS d
    ON d.[Date] = f.FL_DATE

LEFT JOIN dim.Airline AS a
    ON a.DOTAirlineID = f.OP_CARRIER_AIRLINE_ID

LEFT JOIN dim.Airport AS oa
    ON oa.AirportID = f.ORIGIN_AIRPORT_ID

LEFT JOIN dim.Airport AS da
    ON da.AirportID = f.DEST_AIRPORT_ID;


PRINT N'Missing Date lookups: '
    + CAST(@MissingDateKeys AS NVARCHAR(30));

PRINT N'Missing Airline lookups: '
    + CAST(@MissingAirlineKeys AS NVARCHAR(30));

PRINT N'Missing Origin Airport lookups: '
    + CAST(@MissingOriginAirportKeys AS NVARCHAR(30));

PRINT N'Missing Destination Airport lookups: '
    + CAST(@MissingDestinationAirportKeys AS NVARCHAR(30));


IF @MissingDateKeys > 0
   OR @MissingAirlineKeys > 0
   OR @MissingOriginAirportKeys > 0
   OR @MissingDestinationAirportKeys > 0
BEGIN
    ;THROW 50021,
        N'One or more staging rows cannot be resolved to dimension surrogate keys.',
        1;
END;

PRINT N'All dimension lookups validated successfully.';
GO


/*==============================================================================
    3. Load fact.Flights

    Full refresh:
        TRUNCATE fact.Flights
        INSERT all 2025 staging records

    Surrogate-key lookups:
        FL_DATE               -> DateKey
        OP_CARRIER_AIRLINE_ID -> AirlineKey
        ORIGIN_AIRPORT_ID     -> OriginAirportKey
        DEST_AIRPORT_ID       -> DestinationAirportKey
==============================================================================*/

BEGIN TRY

    BEGIN TRANSACTION;


    TRUNCATE TABLE fact.Flights;


    ;WITH AllFlights AS
    (
        SELECT * FROM staging.Flights_2025_01

        UNION ALL

        SELECT * FROM staging.Flights_2025_02

        UNION ALL

        SELECT * FROM staging.Flights_2025_03

        UNION ALL

        SELECT * FROM staging.Flights_2025_04

        UNION ALL

        SELECT * FROM staging.Flights_2025_05

        UNION ALL

        SELECT * FROM staging.Flights_2025_06

        UNION ALL

        SELECT * FROM staging.Flights_2025_07

        UNION ALL

        SELECT * FROM staging.Flights_2025_08

        UNION ALL

        SELECT * FROM staging.Flights_2025_09

        UNION ALL

        SELECT * FROM staging.Flights_2025_10

        UNION ALL

        SELECT * FROM staging.Flights_2025_11

        UNION ALL

        SELECT * FROM staging.Flights_2025_12
    )

    INSERT INTO fact.Flights
    (
        DateKey,
        AirlineKey,
        OriginAirportKey,
        DestinationAirportKey,

        FlightNumber,
        TailNumber,
        ScheduledDepTime,
        ScheduledArrTime,
        ScheduledDepTimeBlock,
        ScheduledArrTimeBlock,
        CancellationCode,

        IsCancelled,
        IsDiverted,
        IsDepDelayed15,
        IsArrDelayed15,

        ActualDepTime,
        ActualArrTime,
        WheelsOffTime,
        WheelsOnTime,

        DepDelayMinutes,
        DepDelayNonNegative,
        ArrDelayMinutes,
        ArrDelayNonNegative,

        TaxiOutMinutes,
        TaxiInMinutes,

        ScheduledElapsedMinutes,
        ActualElapsedMinutes,
        AirTimeMinutes,
        DistanceMiles,

        CarrierDelayMinutes,
        WeatherDelayMinutes,
        NasDelayMinutes,
        SecurityDelayMinutes,
        LateAircraftDelayMinutes,

        DivertedAirportLandings,
        DivertedReachedDestination,
        DivertedElapsedMinutes,
        DivertedArrDelayMinutes,
        DivertedDistanceMiles,
        DivertedAirportID1,
        DivertedAirportCode1
    )

    SELECT
        d.DateKey,
        a.AirlineKey,
        oa.AirportKey,
        da.AirportKey,

        f.OP_CARRIER_FL_NUM,
        f.TAIL_NUM,
        f.CRS_DEP_TIME,
        f.CRS_ARR_TIME,
        f.DEP_TIME_BLK,
        f.ARR_TIME_BLK,
        f.CANCELLATION_CODE,

        f.CANCELLED,
        f.DIVERTED,
        CAST(f.DEP_DEL15 AS BIT),
        CAST(f.ARR_DEL15 AS BIT),

        f.DEP_TIME,
        f.ARR_TIME,
        f.WHEELS_OFF,
        f.WHEELS_ON,

        f.DEP_DELAY,
        f.DEP_DELAY_NEW,
        f.ARR_DELAY,
        f.ARR_DELAY_NEW,

        f.TAXI_OUT,
        f.TAXI_IN,

        f.CRS_ELAPSED_TIME,
        f.ACTUAL_ELAPSED_TIME,
        f.AIR_TIME,
        f.DISTANCE,

        f.CARRIER_DELAY,
        f.WEATHER_DELAY,
        f.NAS_DELAY,
        f.SECURITY_DELAY,
        f.LATE_AIRCRAFT_DELAY,

        f.DIV_AIRPORT_LANDINGS,
        CAST(f.DIV_REACHED_DEST AS BIT),
        f.DIV_ACTUAL_ELAPSED_TIME,
        f.DIV_ARR_DELAY,
        f.DIV_DISTANCE,
        f.DIV1_AIRPORT_ID,
        f.DIV1_AIRPORT

    FROM AllFlights AS f

    INNER JOIN dim.[Date] AS d
        ON d.[Date] = f.FL_DATE

    INNER JOIN dim.Airline AS a
        ON a.DOTAirlineID = f.OP_CARRIER_AIRLINE_ID

    INNER JOIN dim.Airport AS oa
        ON oa.AirportID = f.ORIGIN_AIRPORT_ID

    INNER JOIN dim.Airport AS da
        ON da.AirportID = f.DEST_AIRPORT_ID;


    DECLARE @LoadedRowCount BIGINT;

    SELECT
        @LoadedRowCount = COUNT_BIG(*)
    FROM fact.Flights;


    DECLARE @ExpectedRows BIGINT;

    SELECT
        @ExpectedRows = SUM(Row_Count)
    FROM
    (
        SELECT COUNT_BIG(*) AS Row_Count FROM staging.Flights_2025_01
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_02
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_03
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_04
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_05
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_06
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_07
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_08
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_09
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_10
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_11
        UNION ALL
        SELECT COUNT_BIG(*) FROM staging.Flights_2025_12
    ) AS MonthlyCounts;


    IF @LoadedRowCount <> @ExpectedRows
    BEGIN
        ;THROW 50022,
            N'fact.Flights row count does not match the staging row count.',
            1;
    END;


    COMMIT TRANSACTION;

    PRINT N'fact.Flights loaded successfully.';
    PRINT N'Fact rows loaded: '
        + CAST(@LoadedRowCount AS NVARCHAR(30));

END TRY

BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO


/*==============================================================================
    4. Fact-table validation
==============================================================================*/

SELECT
    COUNT_BIG(*) AS FactRowCount
FROM fact.Flights;
GO


/*------------------------------------------------------------------------------
    Validate key coverage.
------------------------------------------------------------------------------*/

SELECT
    SUM(CASE WHEN DateKey IS NULL THEN 1 ELSE 0 END)
        AS MissingDateKeys,

    SUM(CASE WHEN AirlineKey IS NULL THEN 1 ELSE 0 END)
        AS MissingAirlineKeys,

    SUM(CASE WHEN OriginAirportKey IS NULL THEN 1 ELSE 0 END)
        AS MissingOriginAirportKeys,

    SUM(CASE WHEN DestinationAirportKey IS NULL THEN 1 ELSE 0 END)
        AS MissingDestinationAirportKeys

FROM fact.Flights;
GO


/*------------------------------------------------------------------------------
    Validate the fact-table grain.

    Expected result:
        No rows.
------------------------------------------------------------------------------*/

SELECT
    DateKey,
    AirlineKey,
    FlightNumber,
    OriginAirportKey,
    DestinationAirportKey,
    ScheduledDepTime,
    COUNT(*) AS DuplicateCount

FROM fact.Flights

GROUP BY
    DateKey,
    AirlineKey,
    FlightNumber,
    OriginAirportKey,
    DestinationAirportKey,
    ScheduledDepTime

HAVING COUNT(*) > 1;
GO


/*------------------------------------------------------------------------------
    Basic status validation.
------------------------------------------------------------------------------*/

SELECT
    COUNT_BIG(*) AS TotalFlights,

    SUM(
        CASE
            WHEN IsCancelled = 1 THEN 1
            ELSE 0
        END
    ) AS CancelledFlights,

    SUM(
        CASE
            WHEN IsDiverted = 1 THEN 1
            ELSE 0
        END
    ) AS DivertedFlights

FROM fact.Flights;
GO



USE FlightReliabilityIntelligence;
GO

SELECT
    name AS File_Name,
    type_desc AS File_Type,
    physical_name AS File_Path,
    size * 8.0 / 1024 AS Size_MB
FROM sys.database_files;
GO

/*
fact.Flights loaded successfully with 7,001,619 rows.

All dimension surrogate-key lookups were resolved successfully.
No missing Date, Airline, Origin Airport, or Destination Airport keys were found.

No duplicate records were found at the validated fact-table grain.

The loaded dataset contains:
- 102,876 cancelled flights
- 19,258 diverted flights
*/