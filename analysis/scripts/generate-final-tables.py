from __future__ import annotations

import hashlib
from pathlib import Path

import pandas as pd


# ============================================================
# PATHS
# ============================================================

ROOT = Path(__file__).resolve().parents[2]

FINAL_DATA = (
    ROOT
    / "data"
    / "final"
    / "experiments.csv"
)

SUMMARY_DATA = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "formal-summary-by-workload-architecture.csv"
)

COMPARISON_DATA = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "formal-architecture-comparison.csv"
)

WORKLOAD_DATA = (
    ROOT
    / "load-testing"
    / "scenarios"
    / "formal-workloads.csv"
)

PRICING_DATA = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "aws-pricing-snapshot.csv"
)

TABLE_DATA_DIR = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "tables"
)

TABLE_DOC_DIR = (
    ROOT
    / "docs"
    / "tables"
)

TABLE_DATA_DIR.mkdir(
    parents=True,
    exist_ok=True,
)

TABLE_DOC_DIR.mkdir(
    parents=True,
    exist_ok=True,
)

AUDIT_PATH = (
    TABLE_DATA_DIR
    / "task28-table-audit.csv"
)

MANIFEST_PATH = (
    TABLE_DATA_DIR
    / "task28-table-manifest.csv"
)

COMBINED_MD_PATH = (
    TABLE_DOC_DIR
    / "final_result_tables.md"
)


# ============================================================
# CONSTANTS
# ============================================================

WORKLOAD_ORDER = [
    "W01",
    "W02",
    "W03",
    "W04",
    "W05",
    "W06",
]

ARCH_ORDER = [
    "EC2",
    "SVL",
]


# ============================================================
# HELPERS
# ============================================================

def require_file(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(
            f"Required Task 28 source missing: {path}"
        )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()

    with path.open("rb") as handle:
        for chunk in iter(
            lambda: handle.read(1024 * 1024),
            b"",
        ):
            digest.update(chunk)

    return digest.hexdigest()


def require_columns(
    df: pd.DataFrame,
    columns: list[str],
    label: str,
) -> None:

    missing = [
        column
        for column in columns
        if column not in df.columns
    ]

    if missing:
        raise RuntimeError(
            f"{label} missing columns: {missing}"
        )


def format_number(
    value,
    decimals: int = 2,
) -> str:

    if pd.isna(value):
        return "N/A"

    return f"{float(value):.{decimals}f}"


def format_signed(
    value,
    decimals: int = 1,
    suffix: str = "%",
) -> str:

    if pd.isna(value):
        return "N/A"

    number = float(value)

    return (
        f"{number:+.{decimals}f}{suffix}"
    )


def escape_markdown(value) -> str:
    text = str(value)

    return (
        text
        .replace("|", "\\|")
        .replace("\n", " ")
    )


def dataframe_to_markdown(
    df: pd.DataFrame,
) -> str:

    headers = [
        escape_markdown(column)
        for column in df.columns
    ]

    lines = [
        "| " + " | ".join(headers) + " |",
        "| "
        + " | ".join(
            ["---"] * len(headers)
        )
        + " |",
    ]

    for _, row in df.iterrows():

        values = [
            escape_markdown(value)
            for value in row.tolist()
        ]

        lines.append(
            "| "
            + " | ".join(values)
            + " |"
        )

    return "\n".join(lines)


def write_markdown_table(
    path: Path,
    number: int,
    title: str,
    dataframe: pd.DataFrame,
    note: str | None = None,
) -> None:

    parts = [
        f"## Table {number}. {title}",
        "",
        dataframe_to_markdown(
            dataframe
        ),
    ]

    if note:
        parts.extend(
            [
                "",
                f"*Note: {note}*",
            ]
        )

    path.write_text(
        "\n".join(parts) + "\n",
        encoding="utf-8",
    )


def architecture_name(code: str) -> str:
    if code == "SVL":
        return "Serverless"

    return code


# ============================================================
# LOAD AND VALIDATE INPUTS
# ============================================================

for source in [
    FINAL_DATA,
    SUMMARY_DATA,
    COMPARISON_DATA,
    WORKLOAD_DATA,
    PRICING_DATA,
]:
    require_file(source)


formal = pd.read_csv(
    FINAL_DATA
)

summary = pd.read_csv(
    SUMMARY_DATA
)

comparison = pd.read_csv(
    COMPARISON_DATA
)

workloads = pd.read_csv(
    WORKLOAD_DATA
)

pricing = pd.read_csv(
    PRICING_DATA
)


if len(formal) != 36:
    raise RuntimeError(
        f"Expected 36 formal trials; found {len(formal)}."
    )


if len(summary) != 12:
    raise RuntimeError(
        f"Expected 12 summary groups; found {len(summary)}."
    )


if len(comparison) != 6:
    raise RuntimeError(
        f"Expected 6 architecture comparisons; "
        f"found {len(comparison)}."
    )


if len(workloads) != 6:
    raise RuntimeError(
        f"Expected 6 frozen workloads; found {len(workloads)}."
    )


if (
    formal["experiment_id"]
    .astype(str)
    .str.startswith("P-")
    .any()
):
    raise RuntimeError(
        "Pilot experiment detected in formal dataset."
    )


if set(
    formal["workload_id"]
) != set(WORKLOAD_ORDER):

    raise RuntimeError(
        "Formal workload IDs do not equal W01-W06."
    )


if set(
    formal["architecture"]
) != {"EC2", "SVL"}:

    raise RuntimeError(
        "Unexpected architecture values."
    )


group_counts = (
    formal
    .groupby(
        [
            "workload_id",
            "architecture",
        ]
    )
    .size()
)


if not (
    group_counts == 3
).all():

    raise RuntimeError(
        "Every workload/architecture group "
        "must contain exactly three trials."
    )


tbm_count = (
    formal
    .astype(str)
    .eq("TO_BE_MEASURED")
    .sum()
    .sum()
)


if tbm_count != 0:
    raise RuntimeError(
        f"Dataset contains {tbm_count} TO_BE_MEASURED values."
    )


# ============================================================
# DETERMINE UNIQUE FORMAL CONFIG VALUES
# ============================================================

regions = formal[
    "aws_region"
].dropna().unique()


if len(regions) != 1:
    raise RuntimeError(
        "Expected exactly one AWS region."
    )


aws_region = str(
    regions[0]
)


iteration_values = formal[
    "compute_iterations"
].dropna().unique()


if len(iteration_values) != 1:
    raise RuntimeError(
        "Expected exactly one compute iteration count."
    )


compute_iterations = int(
    float(iteration_values[0])
)


# ============================================================
# TABLE 1 — EXPERIMENTAL ENVIRONMENT
# ============================================================

table1 = pd.DataFrame(
    [
        {
            "Category": "Cloud region",
            "Parameter": "AWS Region",
            "Value": aws_region,
        },
        {
            "Category": "Experimental design",
            "Parameter": "Formal trials",
            "Value": "36 accepted trials",
        },
        {
            "Category": "Experimental design",
            "Parameter": "Conditions",
            "Value": (
                "6 workloads × 2 architectures × "
                "3 repetitions"
            ),
        },
        {
            "Category": "Workload",
            "Parameter": "Compute operation",
            "Value": (
                "Chained SHA-256 CPU-bound computation"
            ),
        },
        {
            "Category": "Workload",
            "Parameter": "Compute iterations",
            "Value": f"{compute_iterations:,}",
        },
        {
            "Category": "Load generation",
            "Parameter": "Tool",
            "Value": "Locust 2.46.3",
        },
        {
            "Category": "EC2",
            "Parameter": "Instance",
            "Value": "t3.small",
        },
        {
            "Category": "EC2",
            "Parameter": "Application stack",
            "Value": (
                "Ubuntu 24.04, Flask, "
                "Gunicorn, Nginx"
            ),
        },
        {
            "Category": "EC2",
            "Parameter": "Storage / access",
            "Value": (
                "8 GB gp3 EBS; public IPv4 endpoint"
            ),
        },
        {
            "Category": "Serverless",
            "Parameter": "Lambda configuration",
            "Value": (
                "Python 3.12, x86_64, 1024 MB"
            ),
        },
        {
            "Category": "Serverless",
            "Parameter": "API",
            "Value": "Amazon API Gateway HTTP API",
        },
        {
            "Category": "Monitoring",
            "Parameter": "AWS telemetry",
            "Value": (
                "Amazon CloudWatch; 60-second "
                "formal metric extraction"
            ),
        },
        {
            "Category": "Cost",
            "Parameter": "Cost methodology",
            "Value": (
                "Regional AWS list-price estimate"
            ),
        },
        {
            "Category": "Cost",
            "Parameter": "Account-specific benefits",
            "Value": (
                "Free Tier, credits and discounts excluded"
            ),
        },
    ]
)


# ============================================================
# TABLE 2 — FROZEN WORKLOAD DEFINITIONS
# ============================================================

require_columns(
    workloads,
    [
        "workload_id",
        "workload_name",
        "users",
        "spawn_rate",
        "duration_seconds",
        "idle_before_seconds",
    ],
    "Frozen workload file",
)


workload_lookup = (
    workloads
    .set_index("workload_id")
    .loc[WORKLOAD_ORDER]
    .reset_index()
)


table2 = workload_lookup[
    [
        "workload_id",
        "workload_name",
        "users",
        "spawn_rate",
        "duration_seconds",
        "idle_before_seconds",
    ]
].copy()


table2.columns = [
    "Workload",
    "Definition",
    "Concurrent users",
    "Spawn rate (users/s)",
    "Load duration (s)",
    "Pre-load idle (s)",
]


# ============================================================
# TABLE 3 — PERFORMANCE COMPARISON
# ============================================================

require_columns(
    comparison,
    [
        "workload_id",
        "workload_type",
        "ec2_mean_avg_latency_ms",
        "serverless_mean_avg_latency_ms",
        (
            "serverless_vs_ec2_latency_"
            "relative_difference_percent"
        ),
        "ec2_mean_p95_ms",
        "serverless_mean_p95_ms",
        "ec2_mean_p99_ms",
        "serverless_mean_p99_ms",
        "ec2_mean_throughput_rps",
        "serverless_mean_throughput_rps",
        (
            "serverless_vs_ec2_throughput_"
            "relative_difference_percent"
        ),
    ],
    "Architecture comparison",
)


comparison_ordered = (
    comparison
    .set_index("workload_id")
    .loc[WORKLOAD_ORDER]
    .reset_index()
)


table3_rows = []


for _, row in comparison_ordered.iterrows():

    table3_rows.append(
        {
            "Workload": row["workload_id"],
            "EC2 mean latency (ms)": format_number(
                row["ec2_mean_avg_latency_ms"],
                2,
            ),
            "Serverless mean latency (ms)": format_number(
                row["serverless_mean_avg_latency_ms"],
                2,
            ),
            "Latency Δ": format_signed(
                row[
                    "serverless_vs_ec2_latency_"
                    "relative_difference_percent"
                ],
                1,
            ),
            "EC2 P95 (ms)": format_number(
                row["ec2_mean_p95_ms"],
                2,
            ),
            "Serverless P95 (ms)": format_number(
                row["serverless_mean_p95_ms"],
                2,
            ),
            "EC2 P99 (ms)": format_number(
                row["ec2_mean_p99_ms"],
                2,
            ),
            "Serverless P99 (ms)": format_number(
                row["serverless_mean_p99_ms"],
                2,
            ),
            "EC2 throughput (req/s)": format_number(
                row["ec2_mean_throughput_rps"],
                2,
            ),
            "Serverless throughput (req/s)": format_number(
                row["serverless_mean_throughput_rps"],
                2,
            ),
            "Throughput Δ": format_signed(
                row[
                    "serverless_vs_ec2_throughput_"
                    "relative_difference_percent"
                ],
                1,
            ),
        }
    )


table3 = pd.DataFrame(
    table3_rows
)


# ============================================================
# TABLE 4 — RELIABILITY COMPARISON
# ============================================================

require_columns(
    comparison,
    [
        "workload_id",
        "ec2_mean_failure_rate_percent",
        "serverless_mean_failure_rate_percent",
        (
            "serverless_minus_ec2_failure_"
            "percentage_points"
        ),
    ],
    "Reliability comparison",
)


require_columns(
    summary,
    [
        "workload_id",
        "architecture_code",
        "total_successful_requests",
        "total_failed_requests",
    ],
    "Summary data",
)


reliability_rows = []


for workload in WORKLOAD_ORDER:

    comp = comparison[
        comparison["workload_id"]
        == workload
    ].iloc[0]

    ec2 = summary[
        (
            summary["workload_id"]
            == workload
        )
        &
        (
            summary["architecture_code"]
            == "EC2"
        )
    ].iloc[0]

    svl = summary[
        (
            summary["workload_id"]
            == workload
        )
        &
        (
            summary["architecture_code"]
            == "SVL"
        )
    ].iloc[0]

    reliability_rows.append(
        {
            "Workload": workload,
            "EC2 failure rate (%)": format_number(
                comp[
                    "ec2_mean_failure_rate_percent"
                ],
                3,
            ),
            "Serverless failure rate (%)": format_number(
                comp[
                    "serverless_mean_failure_rate_percent"
                ],
                3,
            ),
            "Difference (percentage points)": format_signed(
                comp[
                    "serverless_minus_ec2_failure_"
                    "percentage_points"
                ],
                3,
                " pp",
            ),
            "EC2 failed requests": int(
                float(
                    ec2[
                        "total_failed_requests"
                    ]
                )
            ),
            "Serverless failed requests": int(
                float(
                    svl[
                        "total_failed_requests"
                    ]
                )
            ),
            "EC2 successful requests": int(
                float(
                    ec2[
                        "total_successful_requests"
                    ]
                )
            ),
            "Serverless successful requests": int(
                float(
                    svl[
                        "total_successful_requests"
                    ]
                )
            ),
        }
    )


table4 = pd.DataFrame(
    reliability_rows
)


# ============================================================
# TABLE 5 — COST COMPARISON
# ============================================================

require_columns(
    comparison,
    [
        "workload_id",
        "ec2_mean_cost_per_1000_usd",
        "serverless_mean_cost_per_1000_usd",
        (
            "serverless_vs_ec2_cost_"
            "relative_difference_percent"
        ),
        "serverless_to_ec2_cost_ratio",
    ],
    "Cost comparison",
)


cost_rows = []


for workload in WORKLOAD_ORDER:

    comp = comparison[
        comparison["workload_id"]
        == workload
    ].iloc[0]

    ec2 = summary[
        (
            summary["workload_id"]
            == workload
        )
        &
        (
            summary["architecture_code"]
            == "EC2"
        )
    ].iloc[0]

    svl = summary[
        (
            summary["workload_id"]
            == workload
        )
        &
        (
            summary["architecture_code"]
            == "SVL"
        )
    ].iloc[0]

    cost_rows.append(
        {
            "Workload": workload,
            "EC2 estimated cost / trial (USD)": format_number(
                ec2[
                    "mean_estimated_cost_usd"
                ],
                8,
            ),
            (
                "Serverless estimated cost / "
                "trial (USD)"
            ): format_number(
                svl[
                    "mean_estimated_cost_usd"
                ],
                8,
            ),
            "EC2 cost / 1,000 success (USD)": format_number(
                comp[
                    "ec2_mean_cost_per_1000_usd"
                ],
                8,
            ),
            (
                "Serverless cost / 1,000 "
                "success (USD)"
            ): format_number(
                comp[
                    "serverless_mean_cost_per_1000_usd"
                ],
                8,
            ),
            "Serverless vs EC2 cost Δ": format_signed(
                comp[
                    "serverless_vs_ec2_cost_"
                    "relative_difference_percent"
                ],
                1,
            ),
            "Serverless / EC2 cost ratio": format_number(
                comp[
                    "serverless_to_ec2_cost_ratio"
                ],
                3,
            ),
        }
    )


table5 = pd.DataFrame(
    cost_rows
)


# ============================================================
# TABLE 6 — THREE-TRIAL SUMMARY / VARIABILITY
# ============================================================

require_columns(
    summary,
    [
        "workload_id",
        "architecture_code",
        "n_trials",
        "mean_avg_latency_ms",
        "sd_avg_latency_ms",
        "min_avg_latency_ms",
        "max_avg_latency_ms",
        "mean_p95_latency_ms",
        "sd_p95_latency_ms",
        "mean_throughput_rps",
        "sd_throughput_rps",
        "min_throughput_rps",
        "max_throughput_rps",
        "mean_failure_rate_percent",
        "sd_failure_rate_percent",
        (
            "mean_cost_per_1000_"
            "successful_requests_usd"
        ),
        "sd_cost_per_1000_usd",
    ],
    "Three-trial summary",
)


variability_rows = []


for workload in WORKLOAD_ORDER:

    for architecture in ARCH_ORDER:

        row = summary[
            (
                summary["workload_id"]
                == workload
            )
            &
            (
                summary["architecture_code"]
                == architecture
            )
        ].iloc[0]

        variability_rows.append(
            {
                "Workload": workload,
                "Architecture": architecture_name(
                    architecture
                ),
                "n": int(
                    row["n_trials"]
                ),
                "Latency mean ± SD (ms)": (
                    f"{format_number(row['mean_avg_latency_ms'], 2)} "
                    f"± {format_number(row['sd_avg_latency_ms'], 2)}"
                ),
                "Latency min-max (ms)": (
                    f"{format_number(row['min_avg_latency_ms'], 2)}"
                    f"–"
                    f"{format_number(row['max_avg_latency_ms'], 2)}"
                ),
                "P95 mean ± SD (ms)": (
                    f"{format_number(row['mean_p95_latency_ms'], 2)} "
                    f"± {format_number(row['sd_p95_latency_ms'], 2)}"
                ),
                "Throughput mean ± SD (req/s)": (
                    f"{format_number(row['mean_throughput_rps'], 2)} "
                    f"± {format_number(row['sd_throughput_rps'], 2)}"
                ),
                "Throughput min-max (req/s)": (
                    f"{format_number(row['min_throughput_rps'], 2)}"
                    f"–"
                    f"{format_number(row['max_throughput_rps'], 2)}"
                ),
                "Failure rate mean ± SD (%)": (
                    f"{format_number(row['mean_failure_rate_percent'], 3)} "
                    f"± {format_number(row['sd_failure_rate_percent'], 3)}"
                ),
                "Cost/1K mean ± SD (USD)": (
                    f"{format_number(row['mean_cost_per_1000_successful_requests_usd'], 8)} "
                    f"± {format_number(row['sd_cost_per_1000_usd'], 8)}"
                ),
            }
        )


table6 = pd.DataFrame(
    variability_rows
)


# ============================================================
# SAVE CSV TABLES
# ============================================================

csv_outputs = {
    "table_01_experimental_environment.csv": table1,
    "table_02_frozen_workloads.csv": table2,
    "table_03_performance_comparison.csv": table3,
    "table_04_reliability_comparison.csv": table4,
    "table_05_cost_comparison.csv": table5,
    "table_06_three_trial_variability.csv": table6,
}


for filename, dataframe in csv_outputs.items():

    dataframe.to_csv(
        TABLE_DATA_DIR / filename,
        index=False,
    )


# ============================================================
# SAVE PAPER-READY MARKDOWN TABLES
# ============================================================

markdown_outputs = [
    (
        "table_01_experimental_environment.md",
        1,
        "Experimental Environment",
        table1,
        (
            "The formal analysis uses the frozen "
            "experimental configuration."
        ),
    ),
    (
        "table_02_frozen_workloads.md",
        2,
        "Frozen Formal Workload Definitions",
        table2,
        (
            "W05 includes a 300-second idle period "
            "before the 60-second burst."
        ),
    ),
    (
        "table_03_performance_comparison.md",
        3,
        "Performance Comparison",
        table3,
        (
            "Values are descriptive means across "
            "three accepted formal repetitions. "
            "Δ is Serverless relative to EC2."
        ),
    ),
    (
        "table_04_reliability_comparison.md",
        4,
        "Reliability Comparison",
        table4,
        (
            "Failure-rate difference is expressed "
            "in percentage points."
        ),
    ),
    (
        "table_05_cost_comparison.md",
        5,
        "Estimated Cost Comparison",
        table5,
        (
            "Costs use the frozen Task 25 AWS "
            "list-price methodology; Free Tier, "
            "credits and discounts are excluded."
        ),
    ),
    (
        "table_06_three_trial_variability.md",
        6,
        "Three-Trial Summary and Variability",
        table6,
        (
            "SD is sample standard deviation "
            "across n=3 trials. These descriptive "
            "statistics are not significance tests."
        ),
    ),
]


for (
    filename,
    number,
    title,
    dataframe,
    note,
) in markdown_outputs:

    write_markdown_table(
        TABLE_DOC_DIR / filename,
        number,
        title,
        dataframe,
        note,
    )


# ============================================================
# CREATE COMBINED PAPER TABLE DOCUMENT
# ============================================================

combined_sections = [
    "# Final Research Tables",
    "",
    (
        "All result tables below are generated from "
        "accepted formal data only. Pilot experiments "
        "and archived invalid attempts are excluded."
    ),
    "",
]


for (
    filename,
    _,
    _,
    _,
    _,
) in markdown_outputs:

    content = (
        TABLE_DOC_DIR
        / filename
    ).read_text(
        encoding="utf-8"
    )

    combined_sections.append(
        content.strip()
    )

    combined_sections.append("")


COMBINED_MD_PATH.write_text(
    "\n\n".join(
        combined_sections
    ).strip()
    + "\n",
    encoding="utf-8",
)


# ============================================================
# FINAL AUDIT
# ============================================================

checks = []


def add_check(
    check: str,
    expected,
    actual,
) -> None:

    status = (
        "PASS"
        if str(expected) == str(actual)
        else "FAIL"
    )

    checks.append(
        {
            "check": check,
            "expected": expected,
            "actual": actual,
            "status": status,
        }
    )


add_check(
    "formal_trials",
    36,
    len(formal),
)

add_check(
    "pilot_trials_used",
    0,
    int(
        formal[
            "experiment_id"
        ]
        .astype(str)
        .str.startswith("P-")
        .sum()
    ),
)

add_check(
    "table_1_rows",
    14,
    len(table1),
)

add_check(
    "table_2_workloads",
    6,
    len(table2),
)

add_check(
    "table_3_performance_rows",
    6,
    len(table3),
)

add_check(
    "table_4_reliability_rows",
    6,
    len(table4),
)

add_check(
    "table_5_cost_rows",
    6,
    len(table5),
)

add_check(
    "table_6_variability_rows",
    12,
    len(table6),
)

add_check(
    "workload_architecture_groups",
    12,
    len(summary),
)

add_check(
    "architecture_comparisons",
    6,
    len(comparison),
)

add_check(
    "remaining_to_be_measured",
    0,
    int(tbm_count),
)


audit = pd.DataFrame(
    checks
)

audit.to_csv(
    AUDIT_PATH,
    index=False,
)


failures = audit[
    audit["status"] != "PASS"
]


if len(failures) != 0:

    print(
        failures.to_string(
            index=False
        )
    )

    raise RuntimeError(
        "Task 28 table audit failed."
    )


# ============================================================
# MANIFEST
# ============================================================

manifest_rows = []


source_files = [
    FINAL_DATA,
    SUMMARY_DATA,
    COMPARISON_DATA,
    WORKLOAD_DATA,
    PRICING_DATA,
]


for source in source_files:

    manifest_rows.append(
        {
            "artifact_type": "SOURCE_DATA",
            "path": str(
                source.relative_to(ROOT)
            ),
            "sha256": sha256_file(source),
        }
    )


generated_files = []


for filename in csv_outputs:

    generated_files.append(
        TABLE_DATA_DIR / filename
    )


for (
    filename,
    _,
    _,
    _,
    _,
) in markdown_outputs:

    generated_files.append(
        TABLE_DOC_DIR / filename
    )


generated_files.append(
    COMBINED_MD_PATH
)

generated_files.append(
    AUDIT_PATH
)


for output in generated_files:

    if not output.exists():
        raise RuntimeError(
            f"Missing Task 28 output: {output}"
        )

    if output.stat().st_size == 0:
        raise RuntimeError(
            f"Zero-byte Task 28 output: {output}"
        )

    manifest_rows.append(
        {
            "artifact_type": "GENERATED_TABLE",
            "path": str(
                output.relative_to(ROOT)
            ),
            "sha256": sha256_file(output),
        }
    )


manifest = pd.DataFrame(
    manifest_rows
)

manifest.to_csv(
    MANIFEST_PATH,
    index=False,
)


# ============================================================
# TERMINAL SUMMARY
# ============================================================

print("=" * 72)
print(" DAY 2 - TASK 28 - FINAL RESEARCH TABLES")
print("=" * 72)

print()
print("Input validation")
print("----------------")
print(f"Formal trials                     : {len(formal)} / 36")
print(f"Workload/architecture groups      : {len(summary)} / 12")
print(f"Architecture comparisons          : {len(comparison)} / 6")
print(f"Frozen workload definitions       : {len(workloads)} / 6")
print("Pilot trials used                 : 0")
print(f"Remaining TO_BE_MEASURED          : {tbm_count}")

print()
print("Generated tables")
print("----------------")
print(f"Table 1 Experimental environment  : {len(table1)} rows")
print(f"Table 2 Frozen workloads          : {len(table2)} rows")
print(f"Table 3 Performance comparison    : {len(table3)} rows")
print(f"Table 4 Reliability comparison    : {len(table4)} rows")
print(f"Table 5 Cost comparison           : {len(table5)} rows")
print(f"Table 6 Three-trial variability   : {len(table6)} rows")

print()
print("Integrity audit")
print("---------------")
print(
    audit.to_string(
        index=False
    )
)

print()
print("=" * 72)
print(" TASK 28 PASSED")
print(" 6 / 6 FINAL RESEARCH TABLES GENERATED")
print(" 36 / 36 FORMAL TRIALS REPRESENTED")
print(" 0 PILOT TRIALS USED")
print(" PERFORMANCE TABLE COMPLETE")
print(" RELIABILITY TABLE COMPLETE")
print(" COST TABLE COMPLETE")
print(" THREE-TRIAL VARIABILITY TABLE COMPLETE")
print(" CSV + PAPER-READY MARKDOWN GENERATED")
print(" TABLE MANIFEST AND SHA256 EVIDENCE CREATED")
print(" FINAL TABLES READY FOR PREPRINT")
print("=" * 72)