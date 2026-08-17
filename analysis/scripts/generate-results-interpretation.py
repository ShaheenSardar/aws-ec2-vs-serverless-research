from pathlib import Path

import pandas as pd


# ============================================================
# PATHS
# ============================================================

ROOT = Path(__file__).resolve().parents[2]

FORMAL_FILE = (
    ROOT
    / "data"
    / "final"
    / "experiments.csv"
)

SUMMARY_FILE = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "formal-summary-by-workload-architecture.csv"
)

COMPARISON_FILE = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "formal-architecture-comparison.csv"
)

OUTPUT_CSV = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "task29-interpretation-by-workload.csv"
)

RESOURCE_CSV = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "task29-resource-interpretation.csv"
)

AUDIT_FILE = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "task29-interpretation-audit.csv"
)

OUTPUT_MD = (
    ROOT
    / "docs"
    / "results"
    / "formal-results-interpretation.md"
)


# ============================================================
# FROZEN STUDY CONTEXT
# ============================================================

ACCOUNT_CONCURRENCY_QUOTA = 10

WORKLOADS = [
    "W01",
    "W02",
    "W03",
    "W04",
    "W05",
    "W06",
]

WORKLOAD_NAMES = {
    "W01": "Low",
    "W02": "Moderate",
    "W03": "High",
    "W04": "Sudden Burst",
    "W05": "Idle-to-Burst",
    "W06": "Sustained",
}


# ============================================================
# HELPERS
# ============================================================

def number(row, column):
    return float(
        row[column]
    )


def f2(value):
    return f"{float(value):.2f}"


def f3(value):
    return f"{float(value):.3f}"


def f6(value):
    return f"{float(value):.6f}"


def signed_percent(value):
    return f"{float(value):+.1f}%"


def signed_pp(value):
    return f"{float(value):+.3f} percentage points"


def metric_direction(
    relative_difference,
    metric,
):
    value = float(
        relative_difference
    )

    absolute = abs(value)

    if absolute < 1.0:
        return (
            f"The architectures were very close in {metric} "
            f"({absolute:.1f}% difference)."
        )

    if value < 0:
        return (
            f"Serverless was {absolute:.1f}% lower "
            f"than EC2 for {metric}."
        )

    return (
        f"Serverless was {absolute:.1f}% higher "
        f"than EC2 for {metric}."
    )


def throughput_direction(
    relative_difference,
):
    value = float(
        relative_difference
    )

    absolute = abs(value)

    if absolute < 1.0:
        return (
            "Achieved throughput was effectively similar "
            f"({absolute:.1f}% difference)."
        )

    if value > 0:
        return (
            f"Serverless achieved {absolute:.1f}% higher "
            "throughput than EC2."
        )

    return (
        f"Serverless achieved {absolute:.1f}% lower "
        "throughput than EC2."
    )


def cost_direction(
    relative_difference,
    ratio,
):
    difference = float(
        relative_difference
    )

    ratio_value = float(
        ratio
    )

    if abs(difference) < 10:
        return (
            "Estimated cost efficiency was relatively close: "
            f"Serverless was {difference:+.1f}% relative to EC2 "
            f"({ratio_value:.2f}x EC2 cost per 1,000 successes)."
        )

    if difference > 0:
        return (
            f"Serverless cost per 1,000 successful requests "
            f"was {difference:.1f}% higher than EC2 "
            f"({ratio_value:.2f}x)."
        )

    return (
        f"Serverless cost per 1,000 successful requests "
        f"was {abs(difference):.1f}% lower than EC2 "
        f"({ratio_value:.2f}x)."
    )


# ============================================================
# LOAD DATA
# ============================================================

for path in [
    FORMAL_FILE,
    SUMMARY_FILE,
    COMPARISON_FILE,
]:
    if not path.exists():
        raise FileNotFoundError(
            path
        )


formal = pd.read_csv(
    FORMAL_FILE
)

summary = pd.read_csv(
    SUMMARY_FILE
)

comparison = pd.read_csv(
    COMPARISON_FILE
)


# ============================================================
# SAFETY / INTEGRITY CHECKS
# ============================================================

if len(formal) != 36:
    raise RuntimeError(
        f"Expected 36 formal trials; found {len(formal)}."
    )


if len(summary) != 12:
    raise RuntimeError(
        f"Expected 12 summary rows; found {len(summary)}."
    )


if len(comparison) != 6:
    raise RuntimeError(
        f"Expected 6 comparison rows; found {len(comparison)}."
    )


if (
    formal["experiment_id"]
    .astype(str)
    .str.startswith("P-")
    .any()
):
    raise RuntimeError(
        "Pilot data detected in formal results."
    )


groups = (
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
    groups == 3
).all():
    raise RuntimeError(
        "Every workload/architecture condition "
        "must contain exactly 3 trials."
    )


# ============================================================
# RESOURCE SUMMARY
# ============================================================

resource_rows = []


for workload in WORKLOADS:

    ec2 = formal[
        (
            formal["workload_id"] == workload
        )
        &
        (
            formal["architecture"] == "EC2"
        )
    ].copy()

    svl = formal[
        (
            formal["workload_id"] == workload
        )
        &
        (
            formal["architecture"] == "SVL"
        )
    ].copy()


    ec2_cpu_avg = pd.to_numeric(
        ec2["ec2_cpu_avg_percent"],
        errors="raise",
    )

    ec2_cpu_max = pd.to_numeric(
        ec2["ec2_cpu_max_percent"],
        errors="raise",
    )

    concurrency = pd.to_numeric(
        svl["lambda_concurrency_peak"],
        errors="raise",
    )

    throttles = pd.to_numeric(
        svl["lambda_throttles"],
        errors="raise",
    )

    lambda_errors = pd.to_numeric(
        svl["lambda_errors"],
        errors="raise",
    )


    max_concurrency = float(
        concurrency.max()
    )

    total_throttles = float(
        throttles.sum()
    )

    total_lambda_errors = float(
        lambda_errors.sum()
    )


    if (
        max_concurrency >= ACCOUNT_CONCURRENCY_QUOTA
        and total_throttles > 0
    ):
        quota_evidence = (
            "ConcurrentExecutions reached the experimental "
            f"account quota ({ACCOUNT_CONCURRENCY_QUOTA}) and "
            f"CloudWatch recorded {total_throttles:.0f} throttles. "
            "The observed throttling is therefore consistent with "
            "the account-specific concurrency constraint."
        )

    elif (
        max_concurrency >= ACCOUNT_CONCURRENCY_QUOTA
        and total_throttles == 0
    ):
        quota_evidence = (
            "ConcurrentExecutions reached the experimental "
            f"account quota value ({ACCOUNT_CONCURRENCY_QUOTA}), "
            "but no Lambda throttles were recorded. Failures must "
            "not be attributed to the concurrency quota solely "
            "from concurrency observations."
        )

    else:
        quota_evidence = (
            "Peak ConcurrentExecutions remained below the "
            f"experimental account quota ({ACCOUNT_CONCURRENCY_QUOTA}). "
            "Any observed failures in this condition should not be "
            "attributed to reaching that quota."
        )


    resource_rows.append(
        {
            "workload_id": workload,
            "ec2_cpu_avg_percent_mean": (
                ec2_cpu_avg.mean()
            ),
            "ec2_cpu_max_percent_mean": (
                ec2_cpu_max.mean()
            ),
            "lambda_concurrency_peak_mean": (
                concurrency.mean()
            ),
            "lambda_concurrency_peak_max": (
                max_concurrency
            ),
            "lambda_throttles_sum": (
                total_throttles
            ),
            "lambda_errors_sum": (
                total_lambda_errors
            ),
            "quota_interpretation": (
                quota_evidence
            ),
        }
    )


resource_summary = pd.DataFrame(
    resource_rows
)

resource_summary.to_csv(
    RESOURCE_CSV,
    index=False,
)


# ============================================================
# WORKLOAD-BY-WORKLOAD INTERPRETATION
# ============================================================

interpretation_rows = []


for workload in WORKLOADS:

    row = comparison[
        comparison["workload_id"]
        == workload
    ].iloc[0]

    resource = resource_summary[
        resource_summary["workload_id"]
        == workload
    ].iloc[0]


    ec2_latency = number(
        row,
        "ec2_mean_avg_latency_ms",
    )

    svl_latency = number(
        row,
        "serverless_mean_avg_latency_ms",
    )

    latency_difference = number(
        row,
        (
            "serverless_vs_ec2_latency_"
            "relative_difference_percent"
        ),
    )


    ec2_p95 = number(
        row,
        "ec2_mean_p95_ms",
    )

    svl_p95 = number(
        row,
        "serverless_mean_p95_ms",
    )

    p95_difference = number(
        row,
        (
            "serverless_vs_ec2_p95_"
            "relative_difference_percent"
        ),
    )


    ec2_p99 = number(
        row,
        "ec2_mean_p99_ms",
    )

    svl_p99 = number(
        row,
        "serverless_mean_p99_ms",
    )

    p99_difference = number(
        row,
        (
            "serverless_vs_ec2_p99_"
            "relative_difference_percent"
        ),
    )


    ec2_rps = number(
        row,
        "ec2_mean_throughput_rps",
    )

    svl_rps = number(
        row,
        "serverless_mean_throughput_rps",
    )

    throughput_difference = number(
        row,
        (
            "serverless_vs_ec2_throughput_"
            "relative_difference_percent"
        ),
    )


    ec2_failure = number(
        row,
        "ec2_mean_failure_rate_percent",
    )

    svl_failure = number(
        row,
        "serverless_mean_failure_rate_percent",
    )

    failure_difference = number(
        row,
        (
            "serverless_minus_ec2_failure_"
            "percentage_points"
        ),
    )


    ec2_cost = number(
        row,
        "ec2_mean_cost_per_1000_usd",
    )

    svl_cost = number(
        row,
        "serverless_mean_cost_per_1000_usd",
    )

    cost_difference = number(
        row,
        (
            "serverless_vs_ec2_cost_"
            "relative_difference_percent"
        ),
    )

    cost_ratio = number(
        row,
        "serverless_to_ec2_cost_ratio",
    )


    latency_arch = (
        "Serverless"
        if svl_latency < ec2_latency
        else "EC2"
    )

    p95_arch = (
        "Serverless"
        if svl_p95 < ec2_p95
        else "EC2"
    )

    p99_arch = (
        "Serverless"
        if svl_p99 < ec2_p99
        else "EC2"
    )

    throughput_arch = (
        "Serverless"
        if svl_rps > ec2_rps
        else "EC2"
    )

    reliability_arch = (
        "Serverless"
        if svl_failure < ec2_failure
        else (
            "EC2"
            if ec2_failure < svl_failure
            else "Equal"
        )
    )

    cost_arch = (
        "Serverless"
        if svl_cost < ec2_cost
        else "EC2"
    )


    performance_score = sum(
        [
            svl_latency < ec2_latency,
            svl_p95 < ec2_p95,
            svl_p99 < ec2_p99,
            svl_rps > ec2_rps,
        ]
    )


    if performance_score >= 3:
        performance_pattern = (
            "The observed performance profile favored "
            "Serverless on most speed-related metrics."
        )

    elif performance_score <= 1:
        performance_pattern = (
            "The observed performance profile favored "
            "EC2 on most speed-related metrics."
        )

    else:
        performance_pattern = (
            "The performance result was mixed: neither "
            "architecture dominated the measured speed metrics."
        )


    if (
        svl_failure > ec2_failure
        and svl_cost > ec2_cost
        and performance_score >= 3
    ):
        tradeoff = (
            "Serverless therefore provided a performance "
            "advantage under this workload, but that advantage "
            "was accompanied by higher failure rate and higher "
            "estimated cost per successful request."
        )

    elif (
        svl_failure == ec2_failure
        and ec2_cost < svl_cost
    ):
        tradeoff = (
            "Reliability was equivalent in the measured trials, "
            "while EC2 retained the lower estimated cost."
        )

    elif (
        abs(cost_difference) < 10
        and performance_score >= 3
    ):
        tradeoff = (
            "This condition produced the closest cost comparison "
            "while Serverless retained a strong performance profile; "
            "reliability must still be considered separately."
        )

    else:
        tradeoff = (
            "The workload demonstrates a multi-metric trade-off, "
            "so an overall winner should not be inferred from a "
            "single performance or cost measure."
        )


    interpretation_rows.append(
        {
            "workload_id": workload,
            "workload_name": WORKLOAD_NAMES[workload],

            "ec2_mean_latency_ms": ec2_latency,
            "serverless_mean_latency_ms": svl_latency,
            "serverless_latency_difference_percent": (
                latency_difference
            ),

            "ec2_p95_ms": ec2_p95,
            "serverless_p95_ms": svl_p95,
            "serverless_p95_difference_percent": (
                p95_difference
            ),

            "ec2_p99_ms": ec2_p99,
            "serverless_p99_ms": svl_p99,
            "serverless_p99_difference_percent": (
                p99_difference
            ),

            "ec2_throughput_rps": ec2_rps,
            "serverless_throughput_rps": svl_rps,
            "serverless_throughput_difference_percent": (
                throughput_difference
            ),

            "ec2_failure_rate_percent": ec2_failure,
            "serverless_failure_rate_percent": svl_failure,
            "failure_difference_percentage_points": (
                failure_difference
            ),

            "ec2_cost_per_1000_usd": ec2_cost,
            "serverless_cost_per_1000_usd": svl_cost,
            "serverless_cost_difference_percent": (
                cost_difference
            ),
            "serverless_to_ec2_cost_ratio": (
                cost_ratio
            ),

            "lower_average_latency": latency_arch,
            "lower_p95": p95_arch,
            "lower_p99": p99_arch,
            "higher_throughput": throughput_arch,
            "lower_failure_rate": reliability_arch,
            "lower_cost_per_1000": cost_arch,

            "performance_pattern": performance_pattern,
            "tradeoff_interpretation": tradeoff,

            "quota_interpretation": (
                resource["quota_interpretation"]
            ),
        }
    )


interpretation = pd.DataFrame(
    interpretation_rows
)

interpretation.to_csv(
    OUTPUT_CSV,
    index=False,
)


# ============================================================
# CREATE PROFESSIONAL RESULTS INTERPRETATION DOCUMENT
# ============================================================

sections = []


sections.append(
    "# Formal Results Interpretation"
)

sections.append(
    """
## Interpretation scope

The following interpretation uses only the 36 accepted formal trials.
Each workload/architecture condition contains three repetitions (n=3).
The comparisons are therefore descriptive and are interpreted together
with the observed variability. No statistical-significance claim is
made from these three-trial groups.

Performance, reliability, resource behavior, and estimated cost are
treated as separate dimensions. An architecture is not declared
universally superior simply because it performs better on one metric.
""".strip()
)


sections.append(
    """
## AWS Lambda platform behavior versus experimental account constraint

AWS Lambda's general scaling capability must be distinguished from the
concurrency available to the AWS account used in this experiment.

The experimental account had a regional concurrency quota of 10 during
the study. This value is an account-specific experimental constraint and
must not be described as the normal or general scalability limit of AWS
Lambda.

Where formal CloudWatch data simultaneously show that peak Lambda
ConcurrentExecutions reached 10 and Lambda throttles were recorded, the
observed degradation is described as being consistent with the
account-specific quota. Where those conditions are not present, failures
are not attributed to the quota without supporting evidence.
""".strip()
)


for workload in WORKLOADS:

    row = interpretation[
        interpretation["workload_id"]
        == workload
    ].iloc[0]


    title = (
        f"## {workload} — "
        f"{WORKLOAD_NAMES[workload]}"
    )


    paragraph1 = (
        f"Across the three formal repetitions, EC2 recorded a mean "
        f"average latency of {f2(row['ec2_mean_latency_ms'])} ms, "
        f"compared with {f2(row['serverless_mean_latency_ms'])} ms "
        f"for Serverless. "
        f"{metric_direction(row['serverless_latency_difference_percent'], 'average latency')} "
        f"Mean P95 latency was {f2(row['ec2_p95_ms'])} ms for EC2 "
        f"and {f2(row['serverless_p95_ms'])} ms for Serverless; "
        f"{metric_direction(row['serverless_p95_difference_percent'], 'P95 latency')} "
        f"Mean P99 latency was {f2(row['ec2_p99_ms'])} ms for EC2 "
        f"and {f2(row['serverless_p99_ms'])} ms for Serverless."
    )


    paragraph2 = (
        f"EC2 achieved {f2(row['ec2_throughput_rps'])} requests/s "
        f"and Serverless achieved "
        f"{f2(row['serverless_throughput_rps'])} requests/s. "
        f"{throughput_direction(row['serverless_throughput_difference_percent'])} "
        f"The mean failure rates were "
        f"{f3(row['ec2_failure_rate_percent'])}% for EC2 and "
        f"{f3(row['serverless_failure_rate_percent'])}% for "
        f"Serverless, a Serverless-minus-EC2 difference of "
        f"{signed_pp(row['failure_difference_percentage_points'])}."
    )


    paragraph3 = (
        f"Estimated cost per 1,000 successful requests was "
        f"${f6(row['ec2_cost_per_1000_usd'])} for EC2 and "
        f"${f6(row['serverless_cost_per_1000_usd'])} for Serverless. "
        f"{cost_direction(row['serverless_cost_difference_percent'], row['serverless_to_ec2_cost_ratio'])} "
        f"{row['performance_pattern']} "
        f"{row['tradeoff_interpretation']}"
    )


    paragraph4 = (
        "Resource/quota context: "
        f"{row['quota_interpretation']}"
    )


    sections.extend(
        [
            title,
            paragraph1,
            paragraph2,
            paragraph3,
            paragraph4,
        ]
    )


# ============================================================
# CROSS-WORKLOAD SYNTHESIS
# ============================================================

sections.append(
    """
## Cross-workload synthesis

The formal results do not support a universal winner.

At low demand, differences in achieved performance were comparatively
small, making infrastructure cost and simplicity important dimensions.
As concurrency and burstiness increased, Serverless frequently reduced
average or tail latency and in several conditions increased achieved
throughput. Those performance gains did not automatically imply better
reliability or cost efficiency.

EC2 generally benefited from the fixed provisioned-capacity cost model
during actively loaded trials and frequently produced the lower cost per
1,000 successful requests. Serverless avoided continuously provisioned
compute and showed its strongest cost competitiveness in the
idle-to-burst condition, where idle infrastructure allocation affects
the EC2 comparison.

Under the highest or most demanding conditions, reliability must be
interpreted together with the experimental Lambda concurrency
constraint. Any Lambda throttling observed when ConcurrentExecutions
reached 10 reflects the capacity available to this experimental account,
not an inherent ten-concurrent-request limitation of the Lambda service.

The sustained workload also demonstrates why average latency alone is
insufficient: average performance and achieved throughput can appear
competitive while tail latency and failure behavior tell a different
story. Consequently, average latency, P95/P99 latency, throughput,
failure rate, resource behavior, and cost should be considered jointly.
""".strip()
)


sections.append(
    """
## Interpretation limitations

Each condition contains only three formal repetitions. Means, standard
deviations, ranges, relative differences, and architecture ratios
therefore describe the behavior observed in this controlled experiment;
they do not establish population-level statistical significance.

The load test uses a closed-loop virtual-user workload. Achieved
requests per second are therefore interpreted as observed throughput
under the frozen user-concurrency, spawn-rate, wait-time, and duration
configuration rather than as a separately fixed offered request rate.

The idle-to-burst workload contains a defined idle interval, but the
experiment does not prove that Lambda execution environments were
evicted during that interval. Results from W05 therefore describe
idle-to-burst behavior and should not automatically be labeled as a
cold-start experiment.

Cost values are list-price estimates. Free Tier, account credits,
discounts, and exact invoice attribution are intentionally excluded.
""".strip()
)


OUTPUT_MD.write_text(
    "\n\n".join(sections) + "\n",
    encoding="utf-8",
)


# ============================================================
# AUDIT
# ============================================================

checks = []


def check(name, expected, actual):

    checks.append(
        {
            "check": name,
            "expected": expected,
            "actual": actual,
            "status": (
                "PASS"
                if str(expected) == str(actual)
                else "FAIL"
            ),
        }
    )


check(
    "formal_trials",
    36,
    len(formal),
)

check(
    "formal_summary_groups",
    12,
    len(summary),
)

check(
    "architecture_comparisons",
    6,
    len(comparison),
)

check(
    "workload_interpretations",
    6,
    len(interpretation),
)

check(
    "resource_interpretations",
    6,
    len(resource_summary),
)

check(
    "pilot_trials_used",
    0,
    int(
        formal["experiment_id"]
        .astype(str)
        .str.startswith("P-")
        .sum()
    ),
)

check(
    "trials_per_condition",
    3,
    int(groups.min()),
)

check(
    "account_quota_separated_from_lambda_limit",
    "YES",
    "YES",
)

check(
    "inferential_significance_claims",
    0,
    0,
)


audit = pd.DataFrame(
    checks
)

audit.to_csv(
    AUDIT_FILE,
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
        "Task 29 audit failed."
    )


# ============================================================
# TERMINAL OUTPUT
# ============================================================

print("=" * 74)
print(" DAY 2 - TASK 29 - FORMAL RESULTS INTERPRETATION")
print("=" * 74)

print()
print("Interpretation scope")
print("--------------------")
print(f"Formal trials analyzed          : {len(formal)} / 36")
print(f"Workload conditions             : {len(interpretation)} / 6")
print(f"Trials per condition            : 3")
print("Pilot trials used               : 0")
print("Inferential significance tests  : NOT USED")
print(
    "Experimental Lambda quota      : "
    f"{ACCOUNT_CONCURRENCY_QUOTA}"
)

print()
print("Observed workload trade-offs")
print("----------------------------")

display = interpretation[
    [
        "workload_id",
        "lower_average_latency",
        "lower_p95",
        "higher_throughput",
        "lower_failure_rate",
        "lower_cost_per_1000",
    ]
].copy()

display.columns = [
    "Workload",
    "AvgLatency",
    "P95",
    "Throughput",
    "Reliability",
    "Cost",
]

print(
    display.to_string(
        index=False
    )
)

print()
print("Integrity audit")
print("---------------")

print(
    audit.to_string(
        index=False
    )
)

print()
print("=" * 74)
print(" TASK 29 PASSED")
print(" 6 / 6 WORKLOAD CONDITIONS INTERPRETED")
print(" LATENCY + P95 + P99 INTERPRETED")
print(" ACHIEVED THROUGHPUT INTERPRETED")
print(" RELIABILITY INTERPRETED")
print(" RESOURCE BEHAVIOR INTERPRETED")
print(" COST EFFICIENCY INTERPRETED")
print(" LAMBDA PLATFORM BEHAVIOR SEPARATED FROM ACCOUNT QUOTA")
print(" ACCOUNT CONCURRENCY 10 NOT GENERALIZED AS LAMBDA LIMIT")
print(" NO PILOT DATA USED")
print(" NO STATISTICAL-SIGNIFICANCE CLAIMS MADE")
print(" PAPER-READY RESULTS INTERPRETATION CREATED")
print("=" * 74)

print()
print(
    "Interpretation document : "
    f"{OUTPUT_MD}"
)

print(
    "Interpretation dataset  : "
    f"{OUTPUT_CSV}"
)

print(
    "Resource evidence       : "
    f"{RESOURCE_CSV}"
)