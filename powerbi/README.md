# Power BI Documentation

## Flight Reliability Intelligence System

This document describes the Power BI layer of the **Flight Reliability Intelligence System** portfolio project.

It focuses only on the analytical model, DAX logic, report design, visualizations, interaction behavior, and Power BI-specific decisions. A separate project-level `README.md` is intended to document the complete end-to-end workflow, including data sourcing, Python ETL, SQL Server, validation, and Power BI.

---

## 1. Power BI Objective

The Power BI report was designed to turn the validated SQL Server analytical model into an interactive flight-reliability dashboard.

The reporting layer focuses on four business questions:

1. **How reliable was the U.S. flight network during 2025?**
2. **How did airline performance differ across carriers?**
3. **Which airports and routes carried the most traffic, and how reliable were they?**
4. **How did operational disruptions such as delays, cancellations, and diversions change over time?**

The final report contains four focused pages:

- **Flight Reliability Dashboard | 2025**
- **Airline Performance**
- **Airport & Route Analysis**
- **Operational Performance**

The design intentionally avoids a large number of report pages. Each page has a specific analytical purpose and complements the others.

---

## 2. Data Source and Reporting Architecture

Power BI consumes the analytical model prepared in SQL Server.

```text
Official BTS monthly flight files
        ↓
Python ETL
        ↓
Clean monthly CSV files
        ↓
SQL Server staging layer
        ↓
SQL Server dimensional model
        ↓
Power BI semantic model
        ↓
DAX measures
        ↓
Interactive report pages
```

The validated fact table contains:

```text
7,001,619 flight records
```

The report therefore works on a large analytical fact table rather than a small demonstration dataset.

---

## 3. Power BI Semantic Model

The Power BI model follows a star-schema approach.

### Fact table

```text
fact Flights
```

The fact table represents individual flight occurrences and contains the foreign keys and operational flight attributes required for reporting.

Its validated business grain is based on:

```text
Flight Date
+ Airline
+ Flight Number
+ Origin Airport
+ Destination Airport
+ Scheduled Departure Time
```

This grain was validated in SQL Server before the data was used in Power BI.

### Core dimensions

```text
dim Date
dim Airline
dim Origin Airport
dim Destination Airport
```

The main relationships are:

```text
dim Date[DateKey]
        1 → *
fact Flights[DateKey]

dim Airline[AirlineKey]
        1 → *
fact Flights[AirlineKey]

dim Origin Airport[AirportKey]
        1 → *
fact Flights[OriginAirportKey]

dim Destination Airport[AirportKey]
        1 → *
fact Flights[DestinationAirportKey]
```

All analytical relationships used by the report are active and use dimension-to-fact filtering.

---

## 4. Role-Playing Airport Dimension

A major modeling challenge was the airport dimension.

A flight contains two airport roles:

```text
Origin Airport
Destination Airport
```

Using one airport table for both roles created the standard role-playing-dimension problem because both relationships could not be used as active analytical paths without ambiguity.

To solve this cleanly, the airport dimension was referenced twice in Power Query and exposed as two logical reporting dimensions:

```text
dim Origin Airport
dim Destination Airport
```

This allowed both relationships to remain active:

```text
dim Origin Airport → fact Flights[OriginAirportKey]

dim Destination Airport → fact Flights[DestinationAirportKey]
```

This also made report slicers such as **Origin State** and **Destination State** intuitive and avoided repeatedly relying on inactive relationships or `USERELATIONSHIP()` in DAX.

---

## 5. Date Model

The report uses a dedicated calendar dimension:

```text
dim Date
```

It contains fields such as:

```text
Date
Year
Quarter
Month
MonthName
YearMonth
DayOfMonth
DayOfWeek
DayName
IsWeekend
```

The table was explicitly marked as the model's **Date Table** using the real date column.

`MonthName` was sorted by the numeric month field so that report visuals display months chronologically:

```text
January → February → ... → December
```

---

## 6. Measure Organization

Measures were kept separate from physical data columns using dedicated measure tables.

### Business measures

The main measures table stores analytical KPIs such as:

```text
Total Flights
On-Time Flights
On-Time Rate
Cancelled Flights
Cancellation Rate
Diverted Flights
Diversion Rate
Departure Delayed 15+ Flights
Arrival Delayed 15+ Flights
Departure Delay Rate
Arrival Delay Rate
Average Departure Delay
Average Arrival Delay
```

### Formatting measures

A second logical table was created for presentation-oriented measures:

```text
Formatting Measures
```

This table contains helper measures for:

```text
Conditional colors
Trend colors
Dynamic labels
Visual formatting logic
```

This keeps business calculations separate from formatting logic and makes the model easier to maintain.

---

## 7. Core KPI Definitions

### Total Flights

```DAX
Total Flights =
COUNTROWS('fact Flights')
```

### On-Time Flights

For this project, a flight is treated as on time when it:

- was not cancelled,
- was not diverted,
- and did not arrive 15 minutes or more late.

```DAX
On-Time Flights =
CALCULATE(
    [Total Flights],
    'fact Flights'[IsArrDelayed15] = FALSE(),
    'fact Flights'[IsCancelled] = FALSE(),
    'fact Flights'[IsDiverted] = FALSE()
)
```

### On-Time Rate

```DAX
On-Time Rate =
DIVIDE(
    [On-Time Flights],
    [Total Flights]
)
```

### Cancellation Rate

```DAX
Cancellation Rate =
DIVIDE(
    [Cancelled Flights],
    [Total Flights]
)
```

### Diversion Rate

```DAX
Diversion Rate =
DIVIDE(
    [Diverted Flights],
    [Total Flights]
)
```

Because these are measures, all KPIs recalculate dynamically under the current report filter context.

---

## 8. Filter Context and Interactivity

The report relies heavily on Power BI filter context.

Common slicers include:

```text
Month
Airline
Origin State
Destination State
```

The slicers dynamically affect KPIs, charts, matrices, and route-level analysis.

For example, selecting:

```text
Airline = Delta Air Lines
Month = July
Origin State = California
```

causes measures such as:

```text
On-Time Rate
Cancellation Rate
Average Arrival Delay
Total Flights
```

to recalculate automatically for that filtered subset.

---

## 9. 2025 vs 2024 Benchmark Logic

The Overview page includes a prior-year comparison for the main On-Time KPI.

A key design decision was to display the comparison only when the dashboard is in its unfiltered overall state.

The comparison is hidden when the user filters by:

```text
Month
Airline
Origin State
Destination State
```

This prevents an overall 2024 benchmark from being interpreted as a like-for-like comparison against a filtered 2025 subset.

The logic uses `ISFILTERED()` and returns `BLANK()` when a relevant slicer is active.

```DAX
VAR HasFilters =
    ISFILTERED('dim Date'[MonthName]) ||
    ISFILTERED('dim Airline'[CarrierCode]) ||
    ISFILTERED('dim Origin Airport'[StateName]) ||
    ISFILTERED('dim Destination Airport'[StateName])

RETURN
    IF(
        HasFilters,
        BLANK(),
        <2025 vs 2024 comparison text>
    )
```

A separate formatting measure controls the trend color, keeping displayed text and presentation logic independent.

---

## 10. Conditional Formatting

Conditional formatting was used selectively rather than applying color to every value.

### On-Time Rate

```text
Highest value → Green
Lowest value  → Red
```

### Cancellation Rate

```text
Lowest value  → Green
Highest value → Red
```

### Average Arrival Delay

```text
Lowest value  → Green
Highest value → Red
```

The min/max formatting logic uses `ALLSELECTED()` so that the comparison is made across the currently visible selection while still respecting slicers.

Example:

```DAX
On-Time Rate Color =
VAR CurrentRate =
    [On-Time Rate]

VAR MaxRate =
    MAXX(
        ALLSELECTED('dim Airline'),
        CALCULATE([On-Time Rate])
    )

VAR MinRate =
    MINX(
        ALLSELECTED('dim Airline'),
        CALCULATE([On-Time Rate])
    )

RETURN
    SWITCH(
        TRUE(),
        CurrentRate = MaxRate, "#2E7D32",
        CurrentRate = MinRate, "#C62828",
        BLANK()
    )
```

`Total Flights` is treated differently because volume is not inherently good or bad. Neutral encodings such as data bars are preferred.

---

## 11. Route Analysis

The source model contains separate origin and destination airport roles.

For report-level route analysis, a route label was created in the flight table:

```text
LAX → SFO
JFK → LAX
HNL → OGG
```

```DAX
Route =
RELATED('dim Origin Airport'[AirportCode])
    & " → "
    & RELATED('dim Destination Airport'[AirportCode])
```

This field makes route-level filtering and visualization much easier.

### Handling small route samples

An analytical issue appeared when routes were ranked directly by On-Time Rate.

Small routes can easily produce:

```text
100% On-Time Rate
```

from only a handful of flights.

A route with 10 flights and 10 on-time arrivals is mathematically 100%, but it is not necessarily more informative than a high-volume route with a slightly lower rate.

The final design therefore focuses on the busiest routes first and then evaluates their On-Time Rate.

This answers:

> How reliable are the routes that carry the most traffic?

instead of:

> Which small routes happen to have the highest percentage?

---

## 12. Top-N and Tie Handling

Power BI's built-in `Top N` filter can return more than N categories when multiple categories share the same boundary value.

This became visible when many routes shared a `100%` On-Time Rate.

The report design therefore avoids relying on tied percentage rankings without considering volume.

Where exact ranking is needed, DAX ranking logic can use a secondary tie-breaker such as `Total Flights`.

This is an important reporting lesson: Top-N visual filtering should be supported by analytical context, not used mechanically.

---

# 13. Final Report Pages

## Page 1: Flight Reliability Dashboard | 2025

Purpose:

Provide an executive-level overview of flight reliability across the complete dataset.

### Slicers

```text
Month
Airline
Origin State
Destination State
```

### KPI cards

```text
Total Flights
On-Time Rate
Cancellation Rate
Departure Delay Rate
Arrival Delay Rate
Average Arrival Delay
```

The full-year overview currently summarizes:

```text
7,001,619 Total Flights
76.34% On-Time Rate
1.47% Cancellation Rate
21.45% Departure Delay Rate
21.92% Arrival Delay Rate
8.50 min Average Arrival Delay
```

### Visuals

- **Monthly On-Time Performance**
- **Airline On-Time Performance**
- **Top 10 Origin Airports by Flight Volume**

This page acts as the report's executive entry point.

---

## Page 2: Airline Performance

Purpose:

Compare airlines across reliability, delay, cancellation, and operating scale.

### Slicers

```text
Airline
Month
```

### Visuals

- **Airline On-Time Performance**
- **Average Arrival Delay by Airline**
- **Monthly On-Time Rate**
- **On-Time Rate vs Cancellation Rate**
- **Airline Performance Matrix**

The scatter plot combines several analytical dimensions:

```text
X-axis   → On-Time Rate
Y-axis   → Cancellation Rate
Bubble   → Total Flights
Category → Airline
```

The matrix combines:

```text
Airline
Total Flights
On-Time Rate
Cancellation Rate
Average Arrival Delay
```

and uses conditional formatting to highlight performance extremes.

---

## Page 3: Airport & Route Analysis

Purpose:

Analyze traffic concentration and reliability at airport and route level.

### Slicers

```text
Airline
Month
Origin State
Destination State
```

### Visuals

- **Top 10 Origin Airports by Flight Volume**
- **Top 10 Origin Airports by Average Arrival Delay**
- **On-Time Rate of Top 10 Busiest Routes**
- **Top 25 Origin Airports by Flight Volume Matrix**

The airport matrix combines:

```text
Origin Airport
Total Flights
On-Time Rate
Cancellation Rate
Average Arrival Delay
```

The route visual deliberately focuses on high-volume routes to reduce the misleading effect of tiny samples with extreme percentages.

---

## Page 4: Operational Performance

Purpose:

Monitor operational disruptions and how they change throughout the year.

### Slicers

```text
Airline
Month
Origin State
Destination State
```

### KPI cards

```text
Diversion Rate
Average Arrival Delay
Cancellation Rate
Departure Delay Rate
```

### Visuals

- **Monthly Diversion Rate**
- **Diverted Flights by Airline**
- **Monthly Delay Trend**
- **Monthly Cancellation Rate**

The Monthly Delay Trend compares:

```text
Arrival Delay Rate
Departure Delay Rate
```

on the same timeline.

The project did not include delay-cause columns in the final reporting model, so this page intentionally focuses on metrics fully supported by the available data rather than introducing an unsupported causal breakdown.

---

## 14. Visual Design

The final report uses a consistent card-based design across all four pages.

Design principles include:

- Clear visual hierarchy
- Limited number of report pages
- Consistent slicer placement
- Rounded visual containers
- Page-specific accent colors
- White or light visual surfaces
- Compact KPI cards
- Horizontal bars for ranked categories
- Line charts for time trends
- Scatter plots only where multivariate comparison adds value
- Matrices for detailed inspection

The goal was to create a polished portfolio report without sacrificing analytical readability.

---

## 15. Visualization Decisions

Several visualization ideas were tested and intentionally rejected or replaced.

### Maps

A geographic map was considered for airport analysis.

It was ultimately removed because it was less clear for performance comparison than ranked charts and matrices.

The decision favored readability over decoration.

### Scatter plots

Scatter plots were retained only where they added meaningful multivariate analysis.

The Airline Performance page uses:

```text
On-Time Rate vs Cancellation Rate
```

with bubble size representing flight volume.

A similar airport scatter became too dense because many airports clustered at low flight volume, so it was replaced with clearer ranked visuals.

### Avoiding repetitive chart types

The report was iteratively refined to avoid pages composed entirely of similar bar charts.

Trend lines, matrices, bubble/scatter analysis, KPI cards, and conditional formatting were used to create variety while keeping the report consistent.

---

## 16. Power BI Challenges and Solutions

### Challenge: One airport dimension, two flight roles

**Problem:** Origin and destination both reference airports.

**Solution:** Create two role-playing reporting dimensions:

```text
dim Origin Airport
dim Destination Airport
```

This allows both relationships to remain active.

---

### Challenge: Slicers did not initially affect visuals as expected

The relationships and visual interactions were reviewed so slicers filter the intended report elements.

The final semantic model relies on active one-to-many relationships from dimensions to the fact table.

---

### Challenge: Month names sorted alphabetically

**Solution:** Sort `MonthName` by the numeric month field.

---

### Challenge: KPI comparison became misleading under filters

The overall 2024 benchmark should not be displayed next to a filtered 2025 subset.

**Solution:** Detect relevant slicer filters using `ISFILTERED()` and return `BLANK()` when a comparison is no longer like-for-like.

---

### Challenge: Conditional formatting colored every row

The initial min/max logic was being evaluated inside each row's filter context.

**Solution:** Use:

```DAX
ALLSELECTED(...)
```

together with `CALCULATE()` inside `MAXX()` and `MINX()` so min/max is evaluated across the visible population.

---

### Challenge: Route rankings were dominated by tiny samples

Some routes achieved `100%` On-Time Rate with very few flights.

**Solution:** Treat flight volume as part of the interpretation and focus final route comparisons on the busiest routes.

---

### Challenge: Top N produced more than N categories

Ties at the Top-N boundary can cause Power BI to display additional categories.

**Solution:** Avoid percentage-only ranking where ties are common and use volume or DAX ranking logic as a secondary discriminator when required.

---

## 17. Analytical Design Philosophy

The Power BI layer was built around a few principles.

### Measures over hard-coded calculations

Reusable DAX measures ensure that KPIs respond consistently to all filters.

### Meaningful rankings over visually impressive rankings

A 100% rate from a tiny sample is not automatically more meaningful than a slightly lower rate from a major operation.

### Separate overview and diagnostic analysis

The Overview page answers:

> What is happening?

The detailed pages answer:

> Where is it happening?

and:

> Which airline, airport, route, or operational period contributes to it?

### Avoid unsupported analysis

When the model does not contain a reliable field, such as delay-cause detail, the report does not invent or approximate the analysis.

---

## 18. Skills Demonstrated

The Power BI implementation demonstrates practical use of:

```text
Power BI Desktop
Dimensional modeling
Star schema design
Role-playing dimensions
Power Query references
Active relationships
DAX measures
Filter context
CALCULATE
DIVIDE
ISFILTERED
ALLSELECTED
MAXX / MINX
RANKX concepts
Dynamic KPI text
Conditional formatting
Top-N filtering
Tooltips
Matrices
Scatter charts
Time-series visualizations
Interactive slicers
Dashboard UX design
Analytical storytelling
```

---

## 19. Final Outcome

The final Power BI report converts more than seven million validated flight records into a compact four-page analytical experience.

```text
Executive Overview
        ↓
Airline Performance
        ↓
Airport & Route Analysis
        ↓
Operational Performance
```

The Power BI work went beyond creating charts.

It required:

- building a reliable semantic model,
- handling role-playing dimensions,
- defining reusable business measures,
- managing filter context,
- designing safe benchmark comparisons,
- solving ranking and sample-size issues,
- creating reusable formatting logic,
- and refining the visual design around clear analytical questions.

The result is a Power BI reporting layer designed not only to present flight data, but to make reliability patterns understandable, comparable, and explorable.
