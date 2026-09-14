# Flight Reliability Intelligence System

End-to-end Data Analytics portfolio project for U.S. flight reliability, built with Python, SQL Server, and Power BI.

The system analyzes airlines, airports, routes, dates, and flight schedules to identify patterns in delays, on-time performance, cancellations, diversions, delay causes, and airline / airport / route reliability.

## Objective

Build a professional analytics workflow using official flight-level data from the U.S. Bureau of Transportation Statistics (BTS), rather than a pre-built Kaggle dataset.

The project follows a realistic Business Intelligence workflow:

1. Extract official monthly BTS flight data.
2. Clean, validate, and standardize the data with Python.
3. Load the processed monthly files into SQL Server staging tables.
4. Build a dimensional Star Schema.
5. Validate the final Data Warehouse.
6. Connect the analytical model to Power BI.
7. Build DAX measures, KPIs, dashboards, and business insights.

## Architecture

```text
U.S. Bureau of Transportation Statistics
        ↓
12 Monthly Raw BTS CSV Files
        ↓
Python ETL
        ↓
Cleaning / Validation / Type Conversion
        ↓
12 Processed Monthly CSV Files
        ↓
SQL Server
        ↓
12 Monthly Staging Tables
        ↓
Dimensional Model
        ↓
Dimension Tables + Fact Table
        ↓
Data Validation
        ↓
Power BI
        ↓
DAX Measures / KPIs
        ↓
Interactive Dashboards
        ↓
Business Insights
```

## Technology Stack

- Python
- Pandas
- SQL Server
- T-SQL
- Power BI
- DAX
- Git / GitHub

## Responsibility Split

### Python

Python is responsible for the ETL process before the data reaches SQL Server:

- Read the 12 original monthly BTS CSV files.
- Combine the monthly data for transformation and validation.
- Convert flight dates.
- Convert BTS HHMM clock-time fields into valid time values.
- Convert integer-like numerical fields into SQL-compatible integer values.
- Validate the processed dataset.
- Split the processed data back into monthly datasets.
- Export 12 cleaned monthly CSV files.

### SQL Server

SQL Server is responsible for:

- Creating the project database.
- Creating the staging, dimension, fact, and analytics schemas.
- Loading the 12 processed monthly CSV files.
- Creating the dimensional model.
- Generating surrogate keys.
- Populating dimensions.
- Populating the flight fact table.
- Enforcing keys, relationships, and uniqueness constraints.
- Running final Data Warehouse validation.

### Power BI

Power BI is responsible for:

- Semantic modeling.
- DAX measures.
- KPIs.
- Interactive reporting.
- Reliability analysis.
- Business insights.

## SQL Server Schemas

| Schema | Responsibility |
| --- | --- |
| `staging` | Landing layer for the cleaned Python ETL output |
| `dim` | Analytical dimension tables |
| `fact` | Flight-level fact tables |
| `analytics` | Reusable analytical SQL views and reporting logic |

The project intentionally does not use a SQL Server `raw` schema.

The original BTS data is retained in the file system, while Python performs the extraction, cleaning, validation, and type-conversion steps before SQL Server receives the data.

## Data Source

Primary source:

**U.S. Bureau of Transportation Statistics (BTS) - Airline On-Time Performance Data**

The project uses the complete 2025 calendar year.

Original monthly source files:

```text
data/raw/bts/2025/2025_01.csv
data/raw/bts/2025/2025_02.csv
...
data/raw/bts/2025/2025_12.csv
```

The source files are large and are not committed to Git.

Official BTS field documentation is stored under:

```text
data/raw/bts/description/
```

## Python ETL

The executable ETL process is implemented in:

```text
python/etl_flights.py
```

The development notebooks are used for investigation, profiling, validation, and transformation decisions.

The Python ETL exports:

```text
2025_01_clean.csv
2025_02_clean.csv
...
2025_12_clean.csv
```

The processed files contain 62 selected flight-level fields and are prepared for direct loading into SQL Server.

### Important transformations

Examples of transformations performed before SQL Server loading include:

```text
FL_DATE
→ standardized flight date

CRS_DEP_TIME
DEP_TIME
WHEELS_OFF
WHEELS_ON
CRS_ARR_TIME
ARR_TIME
→ BTS HHMM values converted to HH:MM

Integer-like numerical fields
→ exported without unnecessary decimal values
```

The SQL Server staging layer therefore receives already-cleaned and correctly formatted data.

## Staging Layer

SQL Server contains one staging table for each month:

```text
staging.Flights_2025_01
staging.Flights_2025_02
...
staging.Flights_2025_12
```

All 12 tables share the same 62-column structure.

The staging layer represents the validated output of the Python ETL process and serves as the source for the dimensional model.

## Dimensional Model

The analytical model uses a Star Schema.

### Dimensions

```text
dim.Date
dim.Airline
dim.Airport
```

### Fact table

```text
fact.Flights
```

Conceptually:

```text
                    dim.Date
                       │
                       │
                       ▼
dim.Airline ─────► fact.Flights ◄───── dim.Airport
                                      ▲           ▲
                                      │           │
                                   Origin    Destination
```

## Dimension Tables

### `dim.Date`

Contains one row per calendar date.

For the current 2025 dataset:

```text
365 rows
2025-01-01 → 2025-12-31
```

Attributes include:

- Year
- Quarter
- Quarter Name
- Month
- Month Name
- Year-Month
- Day of Month
- Day of Week
- Day Name
- Weekend flag

`DateKey` uses the `YYYYMMDD` warehouse key format.

Example:

```text
2025-01-01 → 20250101
```

### `dim.Airline`

Contains one row per DOT airline.

Current dimension size:

```text
14 airlines
```

Business key:

```text
DOTAirlineID
```

Surrogate key:

```text
AirlineKey
```

### `dim.Airport`

Contains one row per airport.

Current dimension size:

```text
352 airports
```

Business key:

```text
AirportID
```

Surrogate key:

```text
AirportKey
```

`dim.Airport` is a role-playing dimension.

`fact.Flights` references the same airport dimension twice:

```text
OriginAirportKey
DestinationAirportKey
```

A separate Route dimension is not required.

A route is represented by:

```text
OriginAirportKey + DestinationAirportKey
```

## Fact Table

The central analytical table is:

```text
fact.Flights
```

The current fact table contains:

```text
7,001,619 flight records
```

### Fact Grain

One row represents one scheduled flight occurrence:

```text
Flight Date
+ Airline
+ Flight Number
+ Origin Airport
+ Destination Airport
+ Scheduled Departure Time
```

The original business-key definition is:

```text
FL_DATE
+ OP_CARRIER_AIRLINE_ID
+ OP_CARRIER_FL_NUM
+ ORIGIN_AIRPORT_ID
+ DEST_AIRPORT_ID
+ CRS_DEP_TIME
```

The warehouse uniqueness constraint is implemented using:

```text
DateKey
+ AirlineKey
+ FlightNumber
+ OriginAirportKey
+ DestinationAirportKey
+ ScheduledDepTime
```

This grain was validated across the complete 2025 dataset and no duplicate grain combinations were found.

### Surrogate Key

Each fact row receives:

```text
FlightKey
```

as a `BIGINT IDENTITY` surrogate primary key.

### Fact Measures

The fact table includes measures such as:

- Departure delay minutes
- Arrival delay minutes
- Non-negative departure delay
- Non-negative arrival delay
- Taxi-out time
- Taxi-in time
- Scheduled elapsed time
- Actual elapsed time
- Air time
- Flight distance
- Carrier delay
- Weather delay
- NAS delay
- Security delay
- Late aircraft delay
- Diversion measures

It also contains flight-level status flags including:

- Cancellation
- Diversion
- Departure delay of 15+ minutes
- Arrival delay of 15+ minutes

## Repository Structure

```text
Flight-Reliability-Intelligence/
│
├── data/
│   ├── raw/
│   │   └── bts/
│   │       ├── description/
│   │       └── 2025/
│   │           ├── 2025_01.csv
│   │           ├── ...
│   │           └── 2025_12.csv
│   │
│   └── processed/
│       ├── 2025_01_clean.csv
│       ├── ...
│       └── 2025_12_clean.csv
│
├── python/
│   └── etl_flights.py
│
├── notebooks/
│
├── sql/
│   ├── 01_Create_Database_And_Schemas.sql
│   ├── 02_Create_Staging_Layer.sql
│   ├── 03_Load_Staging_Data.sql
│   ├── 04_Create_Dimensional_Model.sql
│   ├── 05_Load_Dimensions.sql
│   ├── 06_Load_FactFlights.sql
│   ├── 07_Data_Validation.sql
│   └── analytics/
│
├── powerbi/
│
├── docs/
│
├── README.md
└── .gitignore
```

Large source and processed datasets are excluded from Git.

## SQL Script Order

SQL scripts are executed in the following order:

```text
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
```

### `01_Create_Database_And_Schemas.sql`

Creates:

```text
FlightReliabilityIntelligence
```

and the schemas:

```text
staging
dim
fact
analytics
```

### `02_Create_Staging_Layer.sql`

Creates the 12 monthly staging tables:

```text
staging.Flights_2025_01
...
staging.Flights_2025_12
```

All monthly tables use the same structure.

### `03_Load_Staging_Data.sql`

Loads the 12 cleaned CSV files produced by Python into their matching staging tables using SQL Server bulk loading.

The script also validates:

- Row counts
- Minimum flight date
- Maximum flight date
- Expected calendar month
- Expected calendar year

### `04_Create_Dimensional_Model.sql`

Creates:

```text
dim.Date
dim.Airline
dim.Airport
fact.Flights
```

including:

- Primary keys
- Surrogate keys
- Foreign keys
- Uniqueness constraints
- Analytical indexes

### `05_Load_Dimensions.sql`

Populates:

```text
dim.Date
dim.Airline
dim.Airport
```

Surrogate keys are generated for airlines and airports.

The airport dimension is populated from both origin and destination airport data.

### `06_Load_FactFlights.sql`

Loads all 12 monthly staging datasets into:

```text
fact.Flights
```

During the load, the script resolves:

```text
FL_DATE
→ DateKey

OP_CARRIER_AIRLINE_ID
→ AirlineKey

ORIGIN_AIRPORT_ID
→ OriginAirportKey

DEST_AIRPORT_ID
→ DestinationAirportKey
```

The script validates all dimension lookups before loading the fact table.

### `07_Data_Validation.sql`

Runs final Data Warehouse validation.

Checks include:

- Staging row count vs. fact row count
- Dimension business-key uniqueness
- Fact grain uniqueness
- Referential integrity
- Required field NULL validation
- Date coverage
- Monthly staging-to-fact reconciliation
- Flight date range validation

The script does not modify project data.

## Final SQL Validation Results

The complete 2025 dataset passed the final SQL validation process.

### Row reconciliation

```text
Staging rows: 7,001,619
Fact rows:    7,001,619
Difference:   0
```

### Dimension sizes

```text
dim.Date:     365
dim.Airline:   14
dim.Airport:  352
```

### Referential integrity

```text
Missing Date Keys:                0
Missing Airline Keys:             0
Missing Origin Airport Keys:      0
Missing Destination Airport Keys: 0
```

### Grain validation

```text
Duplicate fact-grain records: 0
```

### Date coverage

```text
Minimum Flight Date: 2025-01-01
Maximum Flight Date: 2025-12-31
```

### Flight status summary

```text
Total Flights:                 7,001,619
Cancelled Flights:               102,876
Diverted Flights:                 19,258
Departure Delayed 15+ Flights: 1,501,825
Arrival Delayed 15+ Flights:   1,534,638
```

The SQL Data Warehouse is therefore validated and ready for the Power BI stage.

## End-to-End Data Flow

```text
BTS Monthly CSV Files
        ↓
Python ETL
        ↓
12 Cleaned Monthly CSV Files
        ↓
12 SQL Server Staging Tables
        ↓
dim.Date
dim.Airline
dim.Airport
        ↓
fact.Flights
        ↓
SQL Data Validation
        ↓
Power BI
```

## Power BI Analytical Goal

Power BI will support analysis by:

- Airline
- Origin airport
- Destination airport
- Route
- Date
- Month
- Day of week
- Departure time
- Arrival time
- Delay status
- Delay cause
- Cancellation status
- Diversion status

Planned analytical measures include:

- Total flights
- On-time flights
- On-time rate
- Average departure delay
- Average arrival delay
- 15+ minute delay rate
- Cancellation rate
- Diversion rate
- Delay cause contribution
- Airline reliability
- Airport reliability
- Route reliability

A later iteration may introduce a custom **Flight Reliability Score** combining metrics such as:

- On-time rate
- Average delay
- Severe delay rate
- Cancellation rate
- Delay variability

## Current Project Status

```text
BTS Data Acquisition       ✓
Python ETL                 ✓
SQL Staging Layer          ✓
Dimensional Model          ✓
Dimension Loading          ✓
Fact Loading               ✓
SQL Data Validation        ✓
Power BI                   In Progress
```
