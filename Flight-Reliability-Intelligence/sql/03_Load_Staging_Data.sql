/*
    Flight Reliability Intelligence System
    Script: 03_Load_Staging_Data.sql

    Purpose:
        Load the 12 cleaned monthly CSV files produced by Python into the
        matching monthly staging tables.

    Data source:
        Python already cleaned and validated the 2025 flight data.
        SQL Server reads the processed files directly from data/:

            data/2025_01_clean.csv  ->  staging.Flights_2025_01
            data/2025_02_clean.csv  ->  staging.Flights_2025_02
            ...
            data/2025_12_clean.csv  ->  staging.Flights_2025_12

        Do not load the original raw BTS files from data/raw/bts/.

    Expected execution order:
        01_Create_Database_And_Schemas.sql
                ↓
        02_Create_Staging_Layer.sql
                ↓
        03_Load_Staging_Data.sql          <-- this script
                ↓
        dimension loading (future script)
                ↓
        fact loading (future script)
                ↓
        analytics layer (future script)

    Loading approach:
        - One configurable base directory at the top of this script
        - Full refresh per month: TRUNCATE, then BULK INSERT
        - If one monthly file fails, the script stops immediately
        - After all 12 files load, basic month-level validation runs
*/

USE FlightReliabilityIntelligence;
GO

SET NOCOUNT ON;
GO

/*------------------------------------------------------------------------------
    File path configuration

    Python writes cleaned files under the project data/ folder:

        <project>/data/2025_01_clean.csv
        ...
        <project>/data/2025_12_clean.csv

    Update @DataBasePath below to the SQL Server-accessible project path.
    The path must end with a trailing backslash on Windows.
------------------------------------------------------------------------------*/

DECLARE @DataBasePath NVARCHAR(500) =
    N'C:\Users\guryi\OneDrive\Desktop\Flight-Reliability-Intelligence\data\';

DECLARE @Month INT = 1;
DECLARE @MonthText NVARCHAR(2);
DECLARE @FileName NVARCHAR(50);
DECLARE @FilePath NVARCHAR(1000);
DECLARE @TableName SYSNAME;
DECLARE @Sql NVARCHAR(MAX);
DECLARE @LoadErrorMessage NVARCHAR(4000);

/*------------------------------------------------------------------------------
    Load each monthly file into its matching staging table.
------------------------------------------------------------------------------*/

WHILE @Month <= 12
BEGIN
    SET @MonthText = RIGHT(N'0' + CAST(@Month AS NVARCHAR(2)), 2);
    SET @FileName = N'2025_' + @MonthText + N'_clean.csv';
    SET @FilePath = @DataBasePath + @FileName;
    SET @TableName = N'staging.Flights_2025_' + @MonthText;

    PRINT N'Loading ' + @FileName + N' into ' + @TableName;

    BEGIN TRY
        SET @Sql = N'TRUNCATE TABLE ' + QUOTENAME(N'staging') + N'.' + QUOTENAME(N'Flights_2025_' + @MonthText) + N';';
        EXEC sys.sp_executesql @Sql;

      SET @Sql = N'
    BULK INSERT '
    + QUOTENAME(N'staging')
    + N'.'
    + QUOTENAME(N'Flights_2025_' + @MonthText)
    + N'
    FROM '''
    + REPLACE(@FilePath, '''', '''''')
    + N'''
    WITH
        (
            FORMAT = ''CSV'',
            FIRSTROW = 2,
            FIELDQUOTE = ''"'',
            FIELDTERMINATOR = '','',
            ROWTERMINATOR = ''0x0a'',
            CODEPAGE = ''65001'',
            KEEPNULLS,
            TABLOCK
        );
        ';
    PRINT @Sql;
        EXEC sys.sp_executesql @Sql;
    END TRY
    BEGIN CATCH
        SET @LoadErrorMessage =
            N'Failed to load processed file: '
            + @FilePath
            + N' into '
            + @TableName
            + N'. '
            + ERROR_MESSAGE();

        THROW 50001, @LoadErrorMessage, 1;
    END CATCH;

    SET @Month = @Month + 1;
END;
GO

/*------------------------------------------------------------------------------
    Load validation

    For each monthly staging table, show:
        - Row count
        - Minimum FL_DATE
        - Maximum FL_DATE

    Then validate:
        - Every monthly table contains data
        - Every monthly table contains only its expected month in 2025
        - All 12 months are represented
        - Total row count across all 12 tables
------------------------------------------------------------------------------*/

PRINT N'';
PRINT N'Load validation results';
PRINT N'-----------------------';

DECLARE @Month INT = 1;
DECLARE @MonthText NVARCHAR(2);
DECLARE @TableName SYSNAME;
DECLARE @Sql NVARCHAR(MAX);
DECLARE @ValidationErrorMessage NVARCHAR(4000);

DECLARE @RowCount BIGINT;
DECLARE @MinFlightDate DATE;
DECLARE @MaxFlightDate DATE;
DECLARE @DistinctMonthCount INT;
DECLARE @DistinctYearCount INT;
DECLARE @MonthsFound TABLE (flight_month TINYINT NOT NULL PRIMARY KEY);
DECLARE @TotalRowCount BIGINT = 0;

WHILE @Month <= 12
BEGIN
    SET @MonthText = RIGHT(N'0' + CAST(@Month AS NVARCHAR(2)), 2);
    SET @TableName = N'staging.Flights_2025_' + @MonthText;

    SET @Sql = N'
        SELECT
            @RowCountOut = COUNT(*),
            @MinFlightDateOut = MIN(FL_DATE),
            @MaxFlightDateOut = MAX(FL_DATE),
            @DistinctMonthCountOut = COUNT(DISTINCT MONTH(FL_DATE)),
            @DistinctYearCountOut = COUNT(DISTINCT YEAR(FL_DATE))
        FROM ' + QUOTENAME(N'staging') + N'.' + QUOTENAME(N'Flights_2025_' + @MonthText) + N';';

    EXEC sys.sp_executesql
        @Sql,
        N'@RowCountOut BIGINT OUTPUT,
          @MinFlightDateOut DATE OUTPUT,
          @MaxFlightDateOut DATE OUTPUT,
          @DistinctMonthCountOut INT OUTPUT,
          @DistinctYearCountOut INT OUTPUT',
        @RowCountOut = @RowCount OUTPUT,
        @MinFlightDateOut = @MinFlightDate OUTPUT,
        @MaxFlightDateOut = @MaxFlightDate OUTPUT,
        @DistinctMonthCountOut = @DistinctMonthCount OUTPUT,
        @DistinctYearCountOut = @DistinctYearCount OUTPUT;

    PRINT N'Table: ' + @TableName;
    PRINT N'  Row count: ' + CAST(@RowCount AS NVARCHAR(20));
    PRINT N'  Min FL_DATE: ' + CONVERT(NVARCHAR(10), @MinFlightDate, 23);
    PRINT N'  Max FL_DATE: ' + CONVERT(NVARCHAR(10), @MaxFlightDate, 23);

    IF @RowCount = 0
    BEGIN
        SET @ValidationErrorMessage = N'Table ' + @TableName + N' is empty after the load.';
        THROW 50002, @ValidationErrorMessage, 1;
    END;

    IF @DistinctYearCount <> 1 OR YEAR(@MinFlightDate) <> 2025 OR YEAR(@MaxFlightDate) <> 2025
    BEGIN
        SET @ValidationErrorMessage =
            N'Table ' + @TableName + N' contains records outside calendar year 2025.';
        THROW 50003, @ValidationErrorMessage, 1;
    END;

    IF @DistinctMonthCount <> 1 OR MONTH(@MinFlightDate) <> @Month OR MONTH(@MaxFlightDate) <> @Month
    BEGIN
        SET @ValidationErrorMessage =
            N'Table ' + @TableName
            + N' does not contain only month '
            + CAST(@Month AS NVARCHAR(2))
            + N' records. Found FL_DATE range '
            + CONVERT(NVARCHAR(10), @MinFlightDate, 23)
            + N' to '
            + CONVERT(NVARCHAR(10), @MaxFlightDate, 23)
            + N'.';
        THROW 50004, @ValidationErrorMessage, 1;
    END;

    IF NOT EXISTS (SELECT 1 FROM @MonthsFound WHERE flight_month = @Month)
    BEGIN
        INSERT INTO @MonthsFound (flight_month) VALUES (@Month);
    END;

    SET @TotalRowCount = @TotalRowCount + @RowCount;
    SET @Month = @Month + 1;
END;

IF (SELECT COUNT(*) FROM @MonthsFound) <> 12
BEGIN
    ;THROW 50005, N'Load is incomplete: fewer than 12 monthly staging tables contain data.', 1;
END;

PRINT N'';
PRINT N'Total row count across all 12 staging tables: ' + CAST(@TotalRowCount AS NVARCHAR(20));
PRINT N'Load validation passed.';
GO



--DEBUGGING
USE FlightReliabilityIntelligence;
GO

DROP TABLE IF EXISTS staging.Flights_2025_01_TextTest;
GO

DECLARE @Sql NVARCHAR(MAX);

SELECT @Sql =
    N'CREATE TABLE staging.Flights_2025_01_TextTest (' +
    STRING_AGG(
        CAST(
            QUOTENAME(COLUMN_NAME) + N' VARCHAR(500) NULL'
            AS NVARCHAR(MAX)
        ),
        N','
    ) WITHIN GROUP (ORDER BY ORDINAL_POSITION)
    + N');'
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'staging'
  AND TABLE_NAME = N'Flights_2025_01';

EXEC sys.sp_executesql @Sql;
GO



--CONTINUE
