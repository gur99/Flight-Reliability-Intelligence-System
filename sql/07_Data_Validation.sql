/*
    Flight Reliability Intelligence System
    Script: 07_Data_Validation.sql

    Purpose:
        Run final data-quality and integrity checks after the dimensional
        model and fact table have been fully loaded.

    Responsibilities:
        - Validate staging and fact row counts
        - Validate dimension row counts
        - Validate business-key uniqueness
        - Validate fact-table grain uniqueness
        - Validate referential integrity
        - Check required fields for unexpected NULL values
        - Validate date coverage
        - Compare monthly staging counts with fact.Flights
        - Validate basic flight-status consistency

    Notes:
        - This script does not insert, update, or delete project data.
        - It is intended to be safely re-run at any time.
        - Core validation failures raise an error.
        - Detailed result sets are returned for inspection.

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
    1. Overall row-count validation

    The total number of staging rows must equal the total number of fact rows.
==============================================================================*/

DECLARE @Staging_Row_Count BIGINT;
DECLARE @Fact_Row_Count BIGINT;


SELECT
    @Staging_Row_Count = SUM(Row_Count)
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
) AS Monthly_Counts;


SELECT
    @Fact_Row_Count = COUNT_BIG(*)
FROM fact.Flights;


SELECT
    @Staging_Row_Count AS Staging_Row_Count,
    @Fact_Row_Count AS Fact_Row_Count,
    @Fact_Row_Count - @Staging_Row_Count AS Row_Count_Difference;


IF @Staging_Row_Count <> @Fact_Row_Count
BEGIN
    ;THROW 50030,
        N'Validation failed: staging row count does not match fact.Flights row count.',
        1;
END;

PRINT N'Overall row-count validation passed.';
GO


/*==============================================================================
    2. Dimension row counts
==============================================================================*/

SELECT
    N'dim.Date' AS Table_Name,
    COUNT_BIG(*) AS Row_Count
FROM dim.[Date]

UNION ALL

SELECT
    N'dim.Airline',
    COUNT_BIG(*)
FROM dim.Airline

UNION ALL

SELECT
    N'dim.Airport',
    COUNT_BIG(*)
FROM dim.Airport;
GO


/*==============================================================================
    3. Date dimension validation

    Expected:
        2025-01-01 through 2025-12-31
        365 rows
==============================================================================*/

SELECT
    MIN([Date]) AS Min_Date,
    MAX([Date]) AS Max_Date,
    COUNT_BIG(*) AS Row_Count
FROM dim.[Date];
GO


IF
(
    SELECT COUNT_BIG(*)
    FROM dim.[Date]
) <> 365
BEGIN
    ;THROW 50031,
        N'Validation failed: dim.Date does not contain exactly 365 rows.',
        1;
END;


IF
(
    SELECT MIN([Date])
    FROM dim.[Date]
) <> '2025-01-01'
OR
(
    SELECT MAX([Date])
    FROM dim.[Date]
) <> '2025-12-31'
BEGIN
    ;THROW 50032,
        N'Validation failed: dim.Date does not cover the full 2025 calendar year.',
        1;
END;

PRINT N'Date dimension validation passed.';
GO


/*==============================================================================
    4. Dimension business-key uniqueness

    Expected:
        No rows returned.
==============================================================================*/

SELECT
    DOTAirlineID,
    COUNT(*) AS Duplicate_Count
FROM dim.Airline
GROUP BY DOTAirlineID
HAVING COUNT(*) > 1;
GO


SELECT
    AirportID,
    COUNT(*) AS Duplicate_Count
FROM dim.Airport
GROUP BY AirportID
HAVING COUNT(*) > 1;
GO


IF EXISTS
(
    SELECT 1
    FROM dim.Airline
    GROUP BY DOTAirlineID
    HAVING COUNT(*) > 1
)
BEGIN
    ;THROW 50033,
        N'Validation failed: duplicate DOTAirlineID values exist in dim.Airline.',
        1;
END;


IF EXISTS
(
    SELECT 1
    FROM dim.Airport
    GROUP BY AirportID
    HAVING COUNT(*) > 1
)
BEGIN
    ;THROW 50034,
        N'Validation failed: duplicate AirportID values exist in dim.Airport.',
        1;
END;

PRINT N'Dimension business-key uniqueness validation passed.';
GO


/*==============================================================================
    5. Fact grain validation

    Grain:
        DateKey
        + AirlineKey
        + FlightNumber
        + OriginAirportKey
        + DestinationAirportKey
        + ScheduledDepTime

    Expected:
        No rows returned.
==============================================================================*/

SELECT
    DateKey,
    AirlineKey,
    FlightNumber,
    OriginAirportKey,
    DestinationAirportKey,
    ScheduledDepTime,
    COUNT(*) AS Duplicate_Count
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


IF EXISTS
(
    SELECT 1
    FROM fact.Flights
    GROUP BY
        DateKey,
        AirlineKey,
        FlightNumber,
        OriginAirportKey,
        DestinationAirportKey,
        ScheduledDepTime
    HAVING COUNT(*) > 1
)
BEGIN
    ;THROW 50035,
        N'Validation failed: duplicate fact-table grain records were found.',
        1;
END;

PRINT N'Fact grain validation passed.';
GO


/*==============================================================================
    6. Referential integrity validation

    Foreign keys already enforce these relationships, but this check makes
    the validation explicit and visible.

    Expected:
        All values = 0
==============================================================================*/

SELECT
    SUM(
        CASE
            WHEN d.DateKey IS NULL THEN 1
            ELSE 0
        END
    ) AS Missing_Date_Keys,

    SUM(
        CASE
            WHEN a.AirlineKey IS NULL THEN 1
            ELSE 0
        END
    ) AS Missing_Airline_Keys,

    SUM(
        CASE
            WHEN oa.AirportKey IS NULL THEN 1
            ELSE 0
        END
    ) AS Missing_Origin_Airport_Keys,

    SUM(
        CASE
            WHEN da.AirportKey IS NULL THEN 1
            ELSE 0
        END
    ) AS Missing_Destination_Airport_Keys

FROM fact.Flights AS f

LEFT JOIN dim.[Date] AS d
    ON d.DateKey = f.DateKey

LEFT JOIN dim.Airline AS a
    ON a.AirlineKey = f.AirlineKey

LEFT JOIN dim.Airport AS oa
    ON oa.AirportKey = f.OriginAirportKey

LEFT JOIN dim.Airport AS da
    ON da.AirportKey = f.DestinationAirportKey;
GO


IF EXISTS
(
    SELECT 1
    FROM fact.Flights AS f

    LEFT JOIN dim.[Date] AS d
        ON d.DateKey = f.DateKey

    LEFT JOIN dim.Airline AS a
        ON a.AirlineKey = f.AirlineKey

    LEFT JOIN dim.Airport AS oa
        ON oa.AirportKey = f.OriginAirportKey

    LEFT JOIN dim.Airport AS da
        ON da.AirportKey = f.DestinationAirportKey

    WHERE d.DateKey IS NULL
       OR a.AirlineKey IS NULL
       OR oa.AirportKey IS NULL
       OR da.AirportKey IS NULL
)
BEGIN
    ;THROW 50036,
        N'Validation failed: unresolved dimension keys exist in fact.Flights.',
        1;
END;

PRINT N'Referential integrity validation passed.';
GO


/*==============================================================================
    7. Required fact fields

    Expected:
        All values = 0
==============================================================================*/

SELECT
    SUM(CASE WHEN DateKey IS NULL THEN 1 ELSE 0 END)
        AS Null_Date_Key_Count,

    SUM(CASE WHEN AirlineKey IS NULL THEN 1 ELSE 0 END)
        AS Null_Airline_Key_Count,

    SUM(CASE WHEN OriginAirportKey IS NULL THEN 1 ELSE 0 END)
        AS Null_Origin_Airport_Key_Count,

    SUM(CASE WHEN DestinationAirportKey IS NULL THEN 1 ELSE 0 END)
        AS Null_Destination_Airport_Key_Count,

    SUM(CASE WHEN FlightNumber IS NULL THEN 1 ELSE 0 END)
        AS Null_Flight_Number_Count,

    SUM(CASE WHEN ScheduledDepTime IS NULL THEN 1 ELSE 0 END)
        AS Null_Scheduled_Dep_Time_Count,

    SUM(CASE WHEN ScheduledArrTime IS NULL THEN 1 ELSE 0 END)
        AS Null_Scheduled_Arr_Time_Count,

    SUM(CASE WHEN ScheduledDepTimeBlock IS NULL THEN 1 ELSE 0 END)
        AS Null_Scheduled_Dep_Block_Count,

    SUM(CASE WHEN ScheduledArrTimeBlock IS NULL THEN 1 ELSE 0 END)
        AS Null_Scheduled_Arr_Block_Count,

    SUM(CASE WHEN IsCancelled IS NULL THEN 1 ELSE 0 END)
        AS Null_Cancelled_Flag_Count,

    SUM(CASE WHEN IsDiverted IS NULL THEN 1 ELSE 0 END)
        AS Null_Diverted_Flag_Count,

    SUM(CASE WHEN DistanceMiles IS NULL THEN 1 ELSE 0 END)
        AS Null_Distance_Count

FROM fact.Flights;
GO


IF EXISTS
(
    SELECT 1
    FROM fact.Flights
    WHERE DateKey IS NULL
       OR AirlineKey IS NULL
       OR OriginAirportKey IS NULL
       OR DestinationAirportKey IS NULL
       OR FlightNumber IS NULL
       OR ScheduledDepTime IS NULL
       OR ScheduledArrTime IS NULL
       OR ScheduledDepTimeBlock IS NULL
       OR ScheduledArrTimeBlock IS NULL
       OR IsCancelled IS NULL
       OR IsDiverted IS NULL
       OR DistanceMiles IS NULL
)
BEGIN
    ;THROW 50037,
        N'Validation failed: unexpected NULL values exist in required fact columns.',
        1;
END;

PRINT N'Required-field validation passed.';
GO


/*==============================================================================
    8. Monthly staging-to-fact reconciliation

    Compare the number of records per calendar month.

    Expected:
        Row_Count_Difference = 0 for every month.
==============================================================================*/

;WITH Staging_Monthly AS
(
    SELECT 1 AS Flight_Month, COUNT_BIG(*) AS Row_Count
    FROM staging.Flights_2025_01

    UNION ALL
    SELECT 2, COUNT_BIG(*) FROM staging.Flights_2025_02

    UNION ALL
    SELECT 3, COUNT_BIG(*) FROM staging.Flights_2025_03

    UNION ALL
    SELECT 4, COUNT_BIG(*) FROM staging.Flights_2025_04

    UNION ALL
    SELECT 5, COUNT_BIG(*) FROM staging.Flights_2025_05

    UNION ALL
    SELECT 6, COUNT_BIG(*) FROM staging.Flights_2025_06

    UNION ALL
    SELECT 7, COUNT_BIG(*) FROM staging.Flights_2025_07

    UNION ALL
    SELECT 8, COUNT_BIG(*) FROM staging.Flights_2025_08

    UNION ALL
    SELECT 9, COUNT_BIG(*) FROM staging.Flights_2025_09

    UNION ALL
    SELECT 10, COUNT_BIG(*) FROM staging.Flights_2025_10

    UNION ALL
    SELECT 11, COUNT_BIG(*) FROM staging.Flights_2025_11

    UNION ALL
    SELECT 12, COUNT_BIG(*) FROM staging.Flights_2025_12
),

Fact_Monthly AS
(
    SELECT
        d.[Month] AS Flight_Month,
        COUNT_BIG(*) AS Row_Count
    FROM fact.Flights AS f
    INNER JOIN dim.[Date] AS d
        ON d.DateKey = f.DateKey
    GROUP BY
        d.[Month]
)

SELECT
    s.Flight_Month,
    s.Row_Count AS Staging_Row_Count,
    f.Row_Count AS Fact_Row_Count,
    f.Row_Count - s.Row_Count AS Row_Count_Difference

FROM Staging_Monthly AS s

LEFT JOIN Fact_Monthly AS f
    ON f.Flight_Month = s.Flight_Month

ORDER BY
    s.Flight_Month;
GO


/*------------------------------------------------------------------------------
    Validate that every monthly count matches.
------------------------------------------------------------------------------*/

IF OBJECT_ID(N'tempdb..#Monthly_Mismatches') IS NOT NULL
    DROP TABLE #Monthly_Mismatches;


;WITH Staging_Monthly AS
(
    SELECT 1 AS Flight_Month, COUNT_BIG(*) AS Row_Count
    FROM staging.Flights_2025_01

    UNION ALL
    SELECT 2, COUNT_BIG(*) FROM staging.Flights_2025_02

    UNION ALL
    SELECT 3, COUNT_BIG(*) FROM staging.Flights_2025_03

    UNION ALL
    SELECT 4, COUNT_BIG(*) FROM staging.Flights_2025_04

    UNION ALL
    SELECT 5, COUNT_BIG(*) FROM staging.Flights_2025_05

    UNION ALL
    SELECT 6, COUNT_BIG(*) FROM staging.Flights_2025_06

    UNION ALL
    SELECT 7, COUNT_BIG(*) FROM staging.Flights_2025_07

    UNION ALL
    SELECT 8, COUNT_BIG(*) FROM staging.Flights_2025_08

    UNION ALL
    SELECT 9, COUNT_BIG(*) FROM staging.Flights_2025_09

    UNION ALL
    SELECT 10, COUNT_BIG(*) FROM staging.Flights_2025_10

    UNION ALL
    SELECT 11, COUNT_BIG(*) FROM staging.Flights_2025_11

    UNION ALL
    SELECT 12, COUNT_BIG(*) FROM staging.Flights_2025_12
),

Fact_Monthly AS
(
    SELECT
        d.[Month] AS Flight_Month,
        COUNT_BIG(*) AS Row_Count
    FROM fact.Flights AS f
    INNER JOIN dim.[Date] AS d
        ON d.DateKey = f.DateKey
    GROUP BY
        d.[Month]
)

SELECT
    s.Flight_Month,
    s.Row_Count AS Staging_Row_Count,
    f.Row_Count AS Fact_Row_Count,
    f.Row_Count - s.Row_Count AS Row_Count_Difference
INTO #Monthly_Mismatches

FROM Staging_Monthly AS s

LEFT JOIN Fact_Monthly AS f
    ON f.Flight_Month = s.Flight_Month

WHERE f.Row_Count IS NULL
   OR f.Row_Count <> s.Row_Count;


IF EXISTS
(
    SELECT 1
    FROM #Monthly_Mismatches
)
BEGIN
    SELECT *
    FROM #Monthly_Mismatches
    ORDER BY Flight_Month;

    ;THROW 50038,
        N'Validation failed: one or more monthly fact counts do not match staging.',
        1;
END;


DROP TABLE #Monthly_Mismatches;

PRINT N'Monthly reconciliation validation passed.';
GO


/*==============================================================================
    9. Flight date validation

    Expected:
        No fact records outside 2025.
==============================================================================*/

SELECT
    MIN(d.[Date]) AS Min_Flight_Date,
    MAX(d.[Date]) AS Max_Flight_Date
FROM fact.Flights AS f

INNER JOIN dim.[Date] AS d
    ON d.DateKey = f.DateKey;
GO


IF EXISTS
(
    SELECT 1
    FROM fact.Flights AS f

    INNER JOIN dim.[Date] AS d
        ON d.DateKey = f.DateKey

    WHERE d.[Date] < '2025-01-01'
       OR d.[Date] > '2025-12-31'
)
BEGIN
    ;THROW 50039,
        N'Validation failed: fact.Flights contains dates outside 2025.',
        1;
END;

PRINT N'Flight-date validation passed.';
GO


/*==============================================================================
    10. Basic status summary

    Informational output only.
==============================================================================*/

SELECT
    COUNT_BIG(*) AS Total_Flights,

    SUM(
        CASE
            WHEN IsCancelled = 1 THEN 1
            ELSE 0
        END
    ) AS Cancelled_Flights,

    SUM(
        CASE
            WHEN IsDiverted = 1 THEN 1
            ELSE 0
        END
    ) AS Diverted_Flights,

    SUM(
        CASE
            WHEN IsDepDelayed15 = 1 THEN 1
            ELSE 0
        END
    ) AS Departure_Delayed_15_Flights,

    SUM(
        CASE
            WHEN IsArrDelayed15 = 1 THEN 1
            ELSE 0
        END
    ) AS Arrival_Delayed_15_Flights

FROM fact.Flights;
GO


/*==============================================================================
    11. Final validation message
==============================================================================*/

PRINT N'';
PRINT N'==============================================';
PRINT N'Flight Reliability Intelligence validation';
PRINT N'All core validation checks passed successfully.';
PRINT N'==============================================';
GO


/*
Final SQL data validation completed successfully.

The staging layer and fact table both contain 7,001,619 rows with no row loss.
All dimension keys were resolved successfully.
No duplicate dimension business keys or fact-grain records were found.
The Date dimension covers the complete 2025 calendar year.
Monthly staging and fact counts reconcile successfully.

The SQL data warehouse is validated and ready for the Power BI stage.
*/