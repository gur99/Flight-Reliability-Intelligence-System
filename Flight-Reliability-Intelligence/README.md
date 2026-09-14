# Flight Reliability Intelligence System

End-to-end Data Analytics portfolio project for U.S. flight reliability, built with SQL Server and Power BI.

The system analyzes airlines, airports, routes, dates, and flight schedules to identify patterns in delays, on-time performance, cancellations, diversions, delay causes, and airline / airport / route reliability.

## Objective

Build a professional analytics workflow using official flight-level data from the U.S. Bureau of Transportation Statistics (BTS), not a pre-built Kaggle dataset.

The work follows a realistic Business Intelligence development process: source files are loaded into SQL Server, cleaned in staging, modeled as a star schema, exposed through analytical SQL, and consumed in Power BI.

## Architecture

```text
Official Data Sources
        ↓
Raw Data Files
        ↓
SQL Server
        ↓
Raw Layer
        ↓
Staging Layer
        ↓
Data Cleaning & Transformation
        ↓
Dimensional Model
        ↓
Fact & Dimension Tables
        ↓
Analytical SQL Views
        ↓
Power BI
        ↓
DAX Measures / KPIs
        ↓
Interactive Dashboards
        ↓
Business Insights
```

SQL Server is organized by schema:

| Schema | Responsibility |
| --- | --- |
| `raw` | Source data as close as possible to the original BTS files |
| `staging` | Cleaned, standardized, and correctly typed data |
| `dim` | Analytical dimension tables |
| `fact` | Analytical fact tables |
| `analytics` | Reporting views and reusable SQL logic |

## Dimensional Model

The project uses a star schema:

- `dim.Date`
- `dim.Airline`
- `dim.Airport`
- `fact.Flights`

`dim.Airport` is a role-playing dimension. `fact.Flights` references it as both Origin Airport and Destination Airport. A separate Route dimension is not required; a route is the combination of `OriginAirportKey` and `DestinationAirportKey`.

### Fact grain

One row in `fact.Flights` represents one scheduled flight occurrence on a specific date, operated by a specific airline, between a specific origin and destination airport, at a specific scheduled departure time.

Logical uniqueness is defined as:

```text
FlightDate
+ DOTAirlineID
+ FlightNumber
+ OriginAirportID
+ DestinationAirportID
+ ScheduledDepTime
```

`fact.Flights` uses `FlightKey` as a surrogate primary key.

## Repository Structure

```text
Flight-Reliability-Intelligence/
├── data/raw/bts/
│   ├── description/          BTS field documentation
│   └── 2025/                 Monthly On-Time Performance extracts
├── sql/
│   ├── 01_Create_Database_And_Schemas.sql
│   ├── 02_Create_Staging_Layer.sql
│   ├── 03_Load_Raw_Data.sql
│   ├── 04_Create_Dimensional_Model.sql
│   ├── 05_Load_Dimensions.sql
│   ├── 06_Load_FactFlights.sql
│   ├── 07_Data_Validation.sql
│   └── analytics/            Analytical views and reporting SQL
├── notebooks/                Exploratory and validation notebooks
├── powerbi/                  Power BI reports and semantic models
├── docs/                     Architecture notes, findings, and supporting documents
├── README.md
└── .gitignore
```

SQL scripts are maintained in this repository and executed against a real SQL Server database.

## Data Source

Primary source: U.S. Bureau of Transportation Statistics, Airline On-Time Performance data.

Monthly files are stored locally as:

```text
data/raw/bts/2025/2025_01.csv
...
data/raw/bts/2025/2025_12.csv
```

These extracts are large and are not committed to git. Official BTS field documentation is stored in `data/raw/bts/description/`.

FAA airport data and NOAA historical weather data may be added later.

## SQL Script Order

```text
01_Create_Database_And_Schemas.sql
        ↓
02_Create_Staging_Layer.sql
        ↓
03_Load_Raw_Data.sql
        ↓
04_Create_Dimensional_Model.sql
        ↓
05_Load_Dimensions.sql
        ↓
06_Load_FactFlights.sql
        ↓
07_Data_Validation.sql
```

1. `01_Create_Database_And_Schemas.sql` — create the database and the `raw`, `staging`, `dim`, `fact`, and `analytics` schemas
2. `02_Create_Staging_Layer.sql` — create `raw.OnTimePerformance`, `staging.Flights`, `staging.ConvertHhmmToTime`, and `staging.LoadFlightsFromRaw`; do not load CSV files
3. `03_Load_Raw_Data.sql` — truncate and load the 12 monthly 2025 BTS CSV files, execute `staging.LoadFlightsFromRaw`, and validate raw and staging row counts
4. `04_Create_Dimensional_Model.sql` — create `dim.Date`, `dim.Airline`, `dim.Airport`, and `fact.Flights` with keys, constraints, and indexes
5. `05_Load_Dimensions.sql` — populate `dim.Date`, `dim.Airline`, and `dim.Airport`, preserving surrogate keys across reloads
6. `06_Load_FactFlights.sql` — populate `fact.Flights` from staging and resolve dimension keys
7. `07_Data_Validation.sql` — validate the dimensional model and fact table after load

## Data Flow

```text
BTS CSV files
        ↓
raw.OnTimePerformance
        ↓
staging.LoadFlightsFromRaw
        ↓
staging.Flights
        ↓
dim.Date / dim.Airline / dim.Airport
        ↓
fact.Flights
        ↓
Data Validation
```

## Long-Term Analytical Goal

Power BI should support analysis by airline, origin airport, destination airport, route, date, month, day of week, departure time, delay type, cancellation status, and diversion status.

A later iteration may add a custom Flight Reliability Score using on-time rate, average delay, severe delay rate, cancellation rate, and delay variability.
