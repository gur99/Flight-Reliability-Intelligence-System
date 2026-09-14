"""Flight Reliability Intelligence - Python ETL script.

This script is the executable version of the approved ETL process
developed in Notebooks 01 and 02.

It reads the 12 original monthly BTS CSV files for 2025, applies the
approved data type conversions, validates the result, and exports 12
processed monthly CSV files.

The notebooks remain the place for investigation and decision-making.
This script only repeats transformations that were already approved.
"""

from pathlib import Path
import gc

import pandas as pd


CLOCK_TIME_COLUMNS = [
    "CRS_DEP_TIME",
    "DEP_TIME",
    "WHEELS_OFF",
    "WHEELS_ON",
    "CRS_ARR_TIME",
    "ARR_TIME",
]


INTEGER_COLUMNS = [
    "YEAR",
    "QUARTER",
    "MONTH",
    "DAY_OF_MONTH",
    "DAY_OF_WEEK",
    "OP_CARRIER_AIRLINE_ID",
    "OP_CARRIER_FL_NUM",
    "ORIGIN_AIRPORT_ID",
    "ORIGIN_AIRPORT_SEQ_ID",
    "ORIGIN_CITY_MARKET_ID",
    "ORIGIN_WAC",
    "DEST_AIRPORT_ID",
    "DEST_AIRPORT_SEQ_ID",
    "DEST_CITY_MARKET_ID",
    "DEST_WAC",
    "DEP_DELAY",
    "DEP_DELAY_NEW",
    "DEP_DEL15",
    "TAXI_OUT",
    "TAXI_IN",
    "ARR_DELAY",
    "ARR_DELAY_NEW",
    "ARR_DEL15",
    "CANCELLED",
    "DIVERTED",
    "CRS_ELAPSED_TIME",
    "ACTUAL_ELAPSED_TIME",
    "AIR_TIME",
    "DISTANCE",
    "CARRIER_DELAY",
    "WEATHER_DELAY",
    "NAS_DELAY",
    "SECURITY_DELAY",
    "LATE_AIRCRAFT_DELAY",
    "DIV_AIRPORT_LANDINGS",
    "DIV_REACHED_DEST",
    "DIV_ACTUAL_ELAPSED_TIME",
    "DIV_ARR_DELAY",
    "DIV_DISTANCE",
    "DIV1_AIRPORT_ID",
]


FL_DATE_FORMAT = "%m/%d/%Y %I:%M:%S %p"


def get_project_root():
    """Return the project root folder.

    This script lives in python/, so the project root is one folder up.
    """
    return Path(__file__).resolve().parent.parent


def locate_monthly_files(raw_data_dir):
    """Find the 12 expected monthly BTS CSV files for 2025."""
    expected_file_names = [
        f"2025_{month:02d}.csv"
        for month in range(1, 13)
    ]

    csv_files = sorted(raw_data_dir.glob("2025_*.csv"))

    found_file_names = [
        file_path.name
        for file_path in csv_files
    ]

    missing_files = [
        name
        for name in expected_file_names
        if name not in found_file_names
    ]

    if missing_files:
        raise FileNotFoundError(
            "One or more expected monthly CSV files are missing: "
            + ", ".join(missing_files)
        )

    if len(csv_files) != 12:
        raise ValueError(
            f"Expected 12 monthly files, but found {len(csv_files)}."
        )

    return csv_files


def load_monthly_files(csv_files):
    """Load each monthly CSV file into its own DataFrame."""
    monthly_frames = []

    for file_path in csv_files:
        print(f"Loading {file_path.name}...")

        month_df = pd.read_csv(
            file_path,
            low_memory=False,
        )

        monthly_frames.append(month_df)

        print(
            f"  Rows: {len(month_df):,}  "
            f"Columns: {len(month_df.columns)}"
        )

    if len(monthly_frames) != 12:
        raise ValueError(
            f"Expected 12 monthly DataFrames, "
            f"but loaded {len(monthly_frames)}."
        )

    print("All 12 monthly files were loaded successfully.")

    return monthly_frames


def combine_monthly_files(monthly_frames):
    """Stack the 12 monthly DataFrames into one yearly DataFrame."""
    flights = pd.concat(
        monthly_frames,
        ignore_index=True,
    )

    print(
        "Combined yearly DataFrame shape:",
        flights.shape,
    )

    return flights


def convert_bts_hhmm(hhmm_value):
    """Convert one BTS HHMM value to a HH:MM text time.

    Examples:
        530  -> 05:30
        1435 -> 14:35
        2400 -> 00:00
    """
    if pd.isna(hhmm_value):
        return pd.NA

    hhmm_value = int(hhmm_value)

    # BTS uses 2400 for midnight at the end of the operating day.
    if hhmm_value == 2400:
        return "00:00"

    hours = hhmm_value // 100
    minutes = hhmm_value % 100

    if hhmm_value < 0 or hours > 23 or minutes > 59:
        return "INVALID"

    return f"{hours:02d}:{minutes:02d}"


def convert_clock_times(flights):
    """Apply the approved HHMM to HH:MM conversion for clock-time fields."""
    original_missing_counts = {
        column_name: flights[column_name].isna().sum()
        for column_name in CLOCK_TIME_COLUMNS
    }

    for column_name in CLOCK_TIME_COLUMNS:
        print(f"Converting {column_name}...")

        flights[column_name] = flights[column_name].map(
            convert_bts_hhmm
        )

        invalid_count = (
            flights[column_name] == "INVALID"
        ).sum()

        if invalid_count > 0:
            raise ValueError(
                f"{column_name} contains {invalid_count} values "
                "that cannot be converted to a valid clock time."
            )

        new_missing = flights[column_name].isna().sum()

        if new_missing != original_missing_counts[column_name]:
            raise ValueError(
                f"{column_name} conversion changed the "
                "missing-value count from "
                f"{original_missing_counts[column_name]} "
                f"to {new_missing}."
            )

    print("Clock-time conversion complete.")

    return flights


def convert_flight_date(flights):
    """Convert FL_DATE from BTS text timestamps to pandas datetime."""
    original_missing = flights["FL_DATE"].isna().sum()

    parsed_dates = pd.to_datetime(
        flights["FL_DATE"],
        format=FL_DATE_FORMAT,
        errors="coerce",
    )

    failed_count = (
        flights["FL_DATE"].notna()
        & parsed_dates.isna()
    ).sum()

    if failed_count > 0:
        raise ValueError(
            f"{failed_count} FL_DATE values cannot be parsed "
            f"with format {FL_DATE_FORMAT}."
        )

    flights["FL_DATE"] = parsed_dates

    if flights["FL_DATE"].isna().sum() != original_missing:
        raise ValueError(
            "FL_DATE conversion created unexpected missing values."
        )

    print("FL_DATE conversion complete.")
    print(
        "FL_DATE data type:",
        flights["FL_DATE"].dtype,
    )
    print(
        "Minimum date:",
        flights["FL_DATE"].min(),
    )
    print(
        "Maximum date:",
        flights["FL_DATE"].max(),
    )

    return flights


def convert_integer_columns(flights):
    """Convert integer-like numeric fields to nullable pandas integers."""
    for column_name in INTEGER_COLUMNS:
        print(f"Converting {column_name} to integer...")

        original_missing = (
            flights[column_name].isna().sum()
        )

        numeric_values = pd.to_numeric(
            flights[column_name],
            errors="coerce",
        )

        conversion_failures = (
            flights[column_name].notna()
            & numeric_values.isna()
        ).sum()

        if conversion_failures > 0:
            raise ValueError(
                f"{column_name} contains "
                f"{conversion_failures} values that cannot "
                "be converted to numeric."
            )

        non_integer_count = (
            numeric_values.dropna() % 1 != 0
        ).sum()

        if non_integer_count > 0:
            raise ValueError(
                f"{column_name} contains "
                f"{non_integer_count} non-integer numeric values."
            )

        flights[column_name] = (
            numeric_values.astype("Int64")
        )

        new_missing = (
            flights[column_name].isna().sum()
        )

        if new_missing != original_missing:
            raise ValueError(
                f"{column_name} integer conversion changed "
                f"the missing-value count from "
                f"{original_missing} to {new_missing}."
            )

    print("Integer conversion complete.")

    return flights


def validate_processed_data(flights):
    """Run the validation checks required before splitting and export."""
    if flights["FL_DATE"].isna().sum() != 0:
        raise ValueError(
            "FL_DATE contains missing values after conversion."
        )

    years = sorted(
        flights["FL_DATE"]
        .dt.year
        .unique()
        .tolist()
    )

    if years != [2025]:
        raise ValueError(
            f"Expected only year 2025 in FL_DATE, "
            f"but found {years}."
        )

    months = sorted(
        flights["FL_DATE"]
        .dt.month
        .unique()
        .tolist()
    )

    if months != list(range(1, 13)):
        raise ValueError(
            f"Expected months 1 through 12, "
            f"but found {months}."
        )

    print("Processed data validation passed.")
    print(
        "Rows:",
        f"{len(flights):,}",
    )
    print(
        "Columns:",
        len(flights.columns),
    )

    return True


def split_by_month(flights):
    """Count and validate monthly splits without copying all 12 months at once."""
    yearly_row_count = len(flights)

    month_numbers = flights["FL_DATE"].dt.month

    monthly_counts = (
        month_numbers
        .value_counts()
        .sort_index()
    )

    unassigned_count = int(
        (~month_numbers.between(1, 12)).sum()
    )

    months_present = [
        int(month)
        for month in monthly_counts.index.tolist()
    ]

    total_monthly_rows = int(
        monthly_counts.sum()
    )

    for month in range(1, 13):
        row_count = int(
            monthly_counts.get(month, 0)
        )

        print(
            f"Month {month:02d}: "
            f"{row_count:,} rows"
        )

    if months_present != list(range(1, 13)):
        raise ValueError(
            "The split does not contain all 12 months."
        )

    if unassigned_count != 0:
        raise ValueError(
            "Some records were not assigned to a month."
        )

    if total_monthly_rows != yearly_row_count:
        raise ValueError(
            "The monthly row counts do not match "
            "the yearly DataFrame."
        )

    print(
        "Split validation passed. "
        "No records were lost."
    )

    return monthly_counts


def export_monthly_files(flights, processed_dir):
    """Export one month at a time so only one extra slice is in memory."""
    processed_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    exported_files = []
    total_rows_exported = 0

    for month in range(1, 13):
        file_name = (
            f"2025_{month:02d}_clean.csv"
        )

        output_file = (
            processed_dir / file_name
        )

        month_df = flights.loc[
            flights["FL_DATE"].dt.month == month
        ]

        row_count = len(month_df)

        month_df.to_csv(
            output_file,
            index=False,
            date_format="%Y-%m-%d",
            na_rep="",
            lineterminator="\n",
        )

        exported_files.append(
            file_name
        )

        total_rows_exported += (
            row_count
        )

        print(
            f"Exported {file_name}: "
            f"{row_count:,} rows"
        )

        del month_df
        gc.collect()

    return (
        exported_files,
        total_rows_exported,
    )


def main():
    project_root = get_project_root()

    raw_data_dir = (
        project_root
        / "data"
        / "raw"
        / "bts"
        / "2025"
    )

    processed_dir = (
        project_root
        / "data"
        / "processed"
    )

    print(
        "Flight Reliability Intelligence ETL"
    )
    print(
        "Project root:",
        project_root,
    )
    print()

    # Locate and verify the 12 original monthly source files.
    print(
        "Step 1: Locate monthly source files"
    )

    csv_files = locate_monthly_files(
        raw_data_dir
    )

    print(
        "Found 12 monthly files in",
        raw_data_dir.relative_to(
            project_root
        ),
    )
    print()

    # Load each monthly file separately, then combine them for transformation.
    print(
        "Step 2: Load and combine monthly files"
    )

    monthly_frames = load_monthly_files(
        csv_files
    )

    flights = combine_monthly_files(
        monthly_frames
    )

    del monthly_frames
    gc.collect()

    print()

    # Apply only the approved data type conversions.
    print(
        "Step 3: Apply approved data type conversions"
    )

    flights = convert_clock_times(
        flights
    )

    flights = convert_flight_date(
        flights
    )

    flights = convert_integer_columns(
        flights
    )

    print()

    # Confirm the processed yearly dataset is ready to split.
    print(
        "Step 4: Validate processed data"
    )

    validate_processed_data(
        flights
    )

    print()

    # Count rows by month without copying all 12 months into memory at once.
    print(
        "Step 5: Split by month"
    )

    split_by_month(
        flights
    )

    print()

    # Export one month at a time, then release that slice before the next month.
    print(
        "Step 6: Export processed monthly files"
    )

    exported_files, total_rows_exported = (
        export_monthly_files(
            flights,
            processed_dir,
        )
    )

    print()

    print("ETL complete.")

    print(
        "Number of files exported:",
        len(exported_files),
    )

    print(
        "Total rows exported:",
        f"{total_rows_exported:,}",
    )

    print(
        "Output directory:",
        processed_dir.relative_to(
            project_root
        ),
    )


if __name__ == "__main__":
    main()