/*

    Flight Reliability Intelligence System

    Script: 01_Create_Database_And_Schemas.sql



    Purpose:

        Create the SQL Server database and the schemas used after the

        Python ETL step.



    Why the raw schema was removed:

        Earlier versions of this project treated SQL Server as the ETL

        engine. Raw BTS files were loaded into a raw schema and cleaned

        inside SQL Server.



        That design duplicated work. Python (python/etl_flights.py) now

        performs extraction, cleaning, validation, and data type conversion

        on the original BTS CSV files before SQL Server sees the data.



        SQL Server therefore starts from already-processed files, not from

        the original BTS extracts. A raw landing zone is no longer needed.



    Current architecture:

        Original BTS CSV files

                ↓

        Python ETL

                ↓

        12 cleaned monthly CSV files

                data/2025_01_clean.csv

                ...

                data/2025_12_clean.csv

                ↓

        SQL Server

                ↓

        12 monthly staging tables

                ↓

        Star Schema (dim + fact)

                ↓

        analytics views

                ↓

        Power BI



    Responsibility split:

        Python:

            - Extract original CSV files

            - Clean and validate the data

            - Convert dates, clock times, and numeric fields

            - Export 12 cleaned monthly CSV files



        SQL Server:

            - Create the database and schemas

            - Store the processed monthly data

            - Build the dimensional model

            - Create dimension tables, the fact table, and analytical views



        Power BI:

            - Data model, DAX, dashboards, and analysis



    This script creates only the database and schemas.

    Table creation belongs in later SQL scripts.



    Schemas created:

        staging    Landing zone for cleaned Python ETL output

        dim        Analytical dimension tables

        fact       Analytical fact tables

        analytics  Reporting views and reusable SQL logic

*/



USE master;

GO



-- Create the project database if it does not already exist.

IF DB_ID(N'FlightReliabilityIntelligence') IS NULL

BEGIN

    CREATE DATABASE FlightReliabilityIntelligence;

END;

GO



USE FlightReliabilityIntelligence;

GO



-- Staging: one monthly table per cleaned Python CSV file.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'staging')

    EXEC(N'CREATE SCHEMA staging');

GO



-- Dim: descriptive tables used by the Star Schema (date, airline, airport).

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'dim')

    EXEC(N'CREATE SCHEMA dim');

GO



-- Fact: flight-level measures used for delay, cancellation, and reliability analysis.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'fact')

    EXEC(N'CREATE SCHEMA fact');

GO



-- Analytics: reporting views that sit between the Star Schema and Power BI.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'analytics')

    EXEC(N'CREATE SCHEMA analytics');

GO

