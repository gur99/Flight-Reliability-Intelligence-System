/*
    Flight Reliability Intelligence System
    Script: 04_Create_Dimensional_Model.sql

    Purpose:
        Create the star schema tables, keys, and relationships.

    Current model:
        dim.Date
        dim.Airline
        dim.Airport
        fact.Flights

    Design notes:
        dim.Airport is a role-playing dimension, referenced by fact.Flights as
        Origin Airport and Destination Airport.

        A separate Route dimension is not required. A route is represented by
        OriginAirportKey + DestinationAirportKey.

        fact.Flights grain:
            One scheduled flight occurrence on a specific date, operated by a
            specific airline, between a specific origin and destination airport,
            at a specific scheduled departure time.

        Logical uniqueness:
            FlightDate + DOTAirlineID + FlightNumber + OriginAirportID
            + DestinationAirportID + ScheduledDepTime

        fact.Flights uses FlightKey as a surrogate primary key.
        dim.Airline and dim.Airport use IDENTITY surrogate keys.
        dim.Date uses a YYYYMMDD DateKey, the standard warehouse date key.

        Descriptive attributes stay in dimensions.
        Measurable flight-level fields stay on the fact table.

    Execution order:
        Run after 03_Load_Staging_Data.sql.
        Run before 05_Load_Dimensions.sql.

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

    Responsibilities:
        - Create dim.Date
        - Create dim.Airline
        - Create dim.Airport
        - Create fact.Flights
        - Create primary keys, foreign keys, uniqueness constraints, and indexes
*/



USE FlightReliabilityIntelligence;
GO

/*------------------------------------------------------------------------------
    Drop in dependency order so the script can be re-run during development.
------------------------------------------------------------------------------*/

IF OBJECT_ID(N'fact.Flights', N'U') IS NOT NULL
    DROP TABLE fact.Flights;
GO

IF OBJECT_ID(N'dim.Airport', N'U') IS NOT NULL
    DROP TABLE dim.Airport;
GO

IF OBJECT_ID(N'dim.Airline', N'U') IS NOT NULL
    DROP TABLE dim.Airline;
GO

IF OBJECT_ID(N'dim.Date', N'U') IS NOT NULL
    DROP TABLE dim.[Date];
GO

/*------------------------------------------------------------------------------
    dim.Date

    One row per calendar date. DateKey is YYYYMMDD so the fact table can store
    a readable, joinable date key without an IDENTITY lookup.
------------------------------------------------------------------------------*/

CREATE TABLE dim.[Date]
(
    DateKey         INT          NOT NULL,
    [Date]          DATE         NOT NULL,
    [Year]          SMALLINT     NOT NULL,
    [Quarter]       TINYINT      NOT NULL,
    QuarterName     CHAR(2)      NOT NULL,
    [Month]         TINYINT      NOT NULL,
    MonthName       VARCHAR(9)   NOT NULL,
    YearMonth       INT          NOT NULL,
    DayOfMonth      TINYINT      NOT NULL,
    DayOfWeek       TINYINT      NOT NULL,  -- BTS convention: 1 = Monday ... 7 = Sunday
    DayName         VARCHAR(9)   NOT NULL,
    IsWeekend       BIT          NOT NULL,
    CONSTRAINT PK_Date PRIMARY KEY CLUSTERED (DateKey),
    CONSTRAINT UQ_Date_Date UNIQUE ([Date])
);
GO

/*------------------------------------------------------------------------------
    dim.Airline

    One row per DOT-certified operating carrier.
    DOTAirlineID is the durable business key from BTS.
------------------------------------------------------------------------------*/

CREATE TABLE dim.Airline
(
    AirlineKey          INT          NOT NULL IDENTITY(1, 1),
    DOTAirlineID        INT          NOT NULL,
    UniqueCarrierCode   VARCHAR(10)  NOT NULL,
    CarrierCode         VARCHAR(10)  NOT NULL,
    CONSTRAINT PK_Airline PRIMARY KEY CLUSTERED (AirlineKey),
    CONSTRAINT UQ_Airline_DOTAirlineID UNIQUE (DOTAirlineID)
);
GO

/*------------------------------------------------------------------------------
    dim.Airport

    One row per DOT airport. AirportID is the durable business key and should
    be used for analysis across years, because airport codes can change or
    be reused.

    This dimension is role-playing: fact.Flights references it twice.
------------------------------------------------------------------------------*/

CREATE TABLE dim.Airport
(
    AirportKey          INT          NOT NULL IDENTITY(1, 1),
    AirportID           INT          NOT NULL,
    AirportSeqID        INT          NULL,
    AirportCode         VARCHAR(3)   NOT NULL,
    CityName            VARCHAR(100) NOT NULL,
    CityMarketID        INT          NULL,
    StateCode           VARCHAR(2)   NOT NULL,
    StateName           VARCHAR(100) NOT NULL,
    WorldAreaCode       SMALLINT     NULL,
    CONSTRAINT PK_Airport PRIMARY KEY CLUSTERED (AirportKey),
    CONSTRAINT UQ_Airport_AirportID UNIQUE (AirportID)
);
GO

/*------------------------------------------------------------------------------
    fact.Flights

    Grain: one scheduled flight occurrence.

    Foreign keys:
        DateKey               -> dim.Date
        AirlineKey            -> dim.Airline
        OriginAirportKey      -> dim.Airport
        DestinationAirportKey -> dim.Airport
------------------------------------------------------------------------------*/

CREATE TABLE fact.Flights
(
    FlightKey                   BIGINT       NOT NULL IDENTITY(1, 1),

    DateKey                     INT          NOT NULL,
    AirlineKey                  INT          NOT NULL,
    OriginAirportKey            INT          NOT NULL,
    DestinationAirportKey       INT          NOT NULL,

    -- Degenerate identifiers that belong to the flight occurrence
    FlightNumber                INT          NOT NULL,
    TailNumber                  VARCHAR(10)  NULL,
    ScheduledDepTime            TIME(0)      NOT NULL,
    ScheduledArrTime            TIME(0)      NOT NULL,
    ScheduledDepTimeBlock       VARCHAR(9)   NOT NULL,
    ScheduledArrTimeBlock       VARCHAR(9)   NOT NULL,
    CancellationCode            VARCHAR(1)   NULL,

    -- Status flags
    IsCancelled                 BIT          NOT NULL,
    IsDiverted                  BIT          NOT NULL,
    IsDepDelayed15              BIT          NULL,
    IsArrDelayed15              BIT          NULL,

    -- Actual times
    ActualDepTime               TIME(0)      NULL,
    ActualArrTime               TIME(0)      NULL,
    WheelsOffTime               TIME(0)      NULL,
    WheelsOnTime                TIME(0)      NULL,

    -- Delay, duration, and distance measures
    DepDelayMinutes             SMALLINT     NULL,
    DepDelayNonNegative         SMALLINT     NULL,
    ArrDelayMinutes             SMALLINT     NULL,
    ArrDelayNonNegative         SMALLINT     NULL,
    TaxiOutMinutes              SMALLINT     NULL,
    TaxiInMinutes               SMALLINT     NULL,
    ScheduledElapsedMinutes     SMALLINT     NULL,
    ActualElapsedMinutes        SMALLINT     NULL,
    AirTimeMinutes              SMALLINT     NULL,
    DistanceMiles               SMALLINT     NOT NULL,

    -- Delay-cause minutes (NULL when the flight is not a 15+ minute arrival delay)
    CarrierDelayMinutes         SMALLINT     NULL,
    WeatherDelayMinutes         SMALLINT     NULL,
    NasDelayMinutes             SMALLINT     NULL,
    SecurityDelayMinutes        SMALLINT     NULL,
    LateAircraftDelayMinutes    SMALLINT     NULL,

    -- Diversion measures (no additional airport role is modeled)
    DivertedAirportLandings     TINYINT      NULL,
    DivertedReachedDestination  BIT          NULL,
    DivertedElapsedMinutes      SMALLINT     NULL,
    DivertedArrDelayMinutes     SMALLINT     NULL,
    DivertedDistanceMiles       SMALLINT     NULL,
    DivertedAirportID1          INT          NULL,
    DivertedAirportCode1        VARCHAR(3)   NULL,

    CONSTRAINT PK_Flights PRIMARY KEY CLUSTERED (FlightKey),

    CONSTRAINT UQ_Flights_Grain UNIQUE
    (
        DateKey,
        AirlineKey,
        FlightNumber,
        OriginAirportKey,
        DestinationAirportKey,
        ScheduledDepTime
    ),

    CONSTRAINT FK_Flights_Date
        FOREIGN KEY (DateKey)
        REFERENCES dim.[Date] (DateKey),

    CONSTRAINT FK_Flights_Airline
        FOREIGN KEY (AirlineKey)
        REFERENCES dim.Airline (AirlineKey),

    CONSTRAINT FK_Flights_OriginAirport
        FOREIGN KEY (OriginAirportKey)
        REFERENCES dim.Airport (AirportKey),

    CONSTRAINT FK_Flights_DestinationAirport
        FOREIGN KEY (DestinationAirportKey)
        REFERENCES dim.Airport (AirportKey)
);
GO

-- Support common slice-and-dice joins from Power BI and analytical SQL.
CREATE NONCLUSTERED INDEX IX_Flights_DateKey
    ON fact.Flights (DateKey);
GO

CREATE NONCLUSTERED INDEX IX_Flights_AirlineKey
    ON fact.Flights (AirlineKey);
GO

CREATE NONCLUSTERED INDEX IX_Flights_OriginAirportKey
    ON fact.Flights (OriginAirportKey);
GO

CREATE NONCLUSTERED INDEX IX_Flights_DestinationAirportKey
    ON fact.Flights (DestinationAirportKey);
GO


--CHECK #1 -- Proof that the grain is valid
--USE FlightReliabilityIntelligence;
--GO

--WITH AllFlights AS
--(
--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_01

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_02

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_03

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_04

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_05

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_06

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_07

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_08

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_09

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_10

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_11

--    UNION ALL

--    SELECT
--        FL_DATE,
--        OP_CARRIER_AIRLINE_ID,
--        OP_CARRIER_FL_NUM,
--        ORIGIN_AIRPORT_ID,
--        DEST_AIRPORT_ID,
--        CRS_DEP_TIME
--    FROM staging.Flights_2025_12
--)

--SELECT
--    FL_DATE,
--    OP_CARRIER_AIRLINE_ID,
--    OP_CARRIER_FL_NUM,
--    ORIGIN_AIRPORT_ID,
--    DEST_AIRPORT_ID,
--    CRS_DEP_TIME,
--    COUNT(*) AS DuplicateCount
--FROM AllFlights
--GROUP BY
--    FL_DATE,
--    OP_CARRIER_AIRLINE_ID,
--    OP_CARRIER_FL_NUM,
--    ORIGIN_AIRPORT_ID,
--    DEST_AIRPORT_ID,
--    CRS_DEP_TIME
--HAVING COUNT(*) > 1
--ORDER BY DuplicateCount DESC;
--GO
-- END CHECK #1
