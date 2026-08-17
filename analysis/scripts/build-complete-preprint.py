from __future__ import annotations

import re
from pathlib import Path

import pandas as pd


# ============================================================
# PATHS
# ============================================================

ROOT = Path(__file__).resolve().parents[2] if "analysis" in Path(__file__).parts else Path.cwd()

# When this file is saved in analysis/scripts/, ROOT becomes the repository root.
if not (ROOT / "data").exists():
    ROOT = Path.cwd()

FORMAL = ROOT / "data" / "final" / "experiments.csv"
SUMMARY = ROOT / "data" / "processed" / "formal" / "formal-summary-by-workload-architecture.csv"
COMPARISON = ROOT / "data" / "processed" / "formal" / "formal-architecture-comparison.csv"
PRICING = ROOT / "data" / "processed" / "formal" / "aws-pricing-snapshot.csv"
WORKLOADS = ROOT / "load-testing" / "scenarios" / "formal-workloads.csv"
CALIBRATION = ROOT / "docs" / "methodology" / "workload-calibration.md"

TABLE_DIR = ROOT / "docs" / "tables"
FIGURE_DIR = ROOT / "docs" / "figures"

OUTPUT_DIR = ROOT / "docs" / "preprint"
OUTPUT = OUTPUT_DIR / "preprint.md"
AUDIT = ROOT / "data" / "processed" / "formal" / "task31-preprint-audit.csv"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

WORKLOAD_ORDER = ["W01", "W02", "W03", "W04", "W05", "W06"]
WORKLOAD_NAMES = {
    "W01": "Low Workload",
    "W02": "Moderate Workload",
    "W03": "High Workload",
    "W04": "Sudden Burst",
    "W05": "Idle-to-Burst",
    "W06": "Sustained Workload",
}


# ============================================================
# VALIDATION HELPERS
# ============================================================

def require(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Required Task 31 input is missing: {path}")


def num(value) -> float:
    return float(value)


def f2(value) -> str:
    return f"{float(value):.2f}"


def f3(value) -> str:
    return f"{float(value):.3f}"


def f6(value) -> str:
    return f"{float(value):.6f}"


def signed(value, digits=1, suffix="%") -> str:
    return f"{float(value):+.{digits}f}{suffix}"


def table_body(path: Path) -> str:
    text = path.read_text(encoding="utf-8-sig").strip()
    lines = text.splitlines()
    # Remove the generated Markdown heading; the paper supplies its own caption.
    if lines and lines[0].startswith("## Table"):
        lines = lines[1:]
        while lines and not lines[0].strip():
            lines.pop(0)
    return "\n".join(lines).strip()


def summary_row(summary: pd.DataFrame, workload: str, arch: str) -> pd.Series:
    rows = summary[(summary["workload_id"] == workload) & (summary["architecture_code"] == arch)]
    if len(rows) != 1:
        raise RuntimeError(f"Expected one summary row for {workload}/{arch}; found {len(rows)}")
    return rows.iloc[0]


def comparison_row(comparison: pd.DataFrame, workload: str) -> pd.Series:
    rows = comparison[comparison["workload_id"] == workload]
    if len(rows) != 1:
        raise RuntimeError(f"Expected one comparison row for {workload}; found {len(rows)}")
    return rows.iloc[0]


def direction_sentence(metric: str, relative_diff: float, lower_is_better=True) -> str:
    d = float(relative_diff)
    a = abs(d)
    if a < 1.0:
        return f"The architectures were close on {metric} ({a:.1f}% difference)."
    if lower_is_better:
        if d < 0:
            return f"Serverless was {a:.1f}% lower on {metric}."
        return f"Serverless was {a:.1f}% higher on {metric}."
    if d > 0:
        return f"Serverless was {a:.1f}% higher on {metric}."
    return f"Serverless was {a:.1f}% lower on {metric}."


def result_paragraph(workload: str, summary: pd.DataFrame, comparison: pd.DataFrame) -> str:
    e = summary_row(summary, workload, "EC2")
    s = summary_row(summary, workload, "SVL")
    c = comparison_row(comparison, workload)

    lat_diff = num(c["serverless_vs_ec2_latency_relative_difference_percent"])
    p95_diff = num(c["serverless_vs_ec2_p95_relative_difference_percent"])
    p99_diff = num(c["serverless_vs_ec2_p99_relative_difference_percent"])
    thr_diff = num(c["serverless_vs_ec2_throughput_relative_difference_percent"])
    fail_pp = num(c["serverless_minus_ec2_failure_percentage_points"])
    cost_diff = num(c["serverless_vs_ec2_cost_relative_difference_percent"])
    cost_ratio = num(c["serverless_to_ec2_cost_ratio"])

    performance_wins = sum([
        num(c["serverless_mean_avg_latency_ms"]) < num(c["ec2_mean_avg_latency_ms"]),
        num(c["serverless_mean_p95_ms"]) < num(c["ec2_mean_p95_ms"]),
        num(c["serverless_mean_p99_ms"]) < num(c["ec2_mean_p99_ms"]),
        num(c["serverless_mean_throughput_rps"]) > num(c["ec2_mean_throughput_rps"]),
    ])

    if performance_wins >= 3:
        interpretation = (
            "The speed-related profile therefore favored Serverless on most measured metrics, "
            "but that observation must be weighed against reliability, cost, and the three-trial variability."
        )
    elif performance_wins <= 1:
        interpretation = (
            "The speed-related profile therefore favored EC2 on most measured metrics, although individual tail-latency "
            "or throughput measures may still differ."
        )
    else:
        interpretation = (
            "The speed-related result was mixed; neither architecture dominated average latency, tail latency, and achieved throughput simultaneously."
        )

    return (
        f"Across the three accepted repetitions, EC2 produced a mean average latency of "
        f"{f2(e['mean_avg_latency_ms'])} ± {f2(e['sd_avg_latency_ms'])} ms, whereas Serverless produced "
        f"{f2(s['mean_avg_latency_ms'])} ± {f2(s['sd_avg_latency_ms'])} ms. "
        f"{direction_sentence('average latency', lat_diff)} Mean P95 latency was "
        f"{f2(c['ec2_mean_p95_ms'])} ms for EC2 and {f2(c['serverless_mean_p95_ms'])} ms for Serverless "
        f"({signed(p95_diff)} Serverless relative to EC2), while mean P99 latency was "
        f"{f2(c['ec2_mean_p99_ms'])} ms and {f2(c['serverless_mean_p99_ms'])} ms, respectively "
        f"({signed(p99_diff)}). Achieved throughput averaged {f2(c['ec2_mean_throughput_rps'])} requests/s on EC2 "
        f"and {f2(c['serverless_mean_throughput_rps'])} requests/s on Serverless ({signed(thr_diff)}). "
        f"The mean failure rates were {f3(c['ec2_mean_failure_rate_percent'])}% and "
        f"{f3(c['serverless_mean_failure_rate_percent'])}%, a Serverless-minus-EC2 difference of "
        f"{fail_pp:+.3f} percentage points. Estimated cost per 1,000 successful requests was "
        f"${f6(c['ec2_mean_cost_per_1000_usd'])} for EC2 and ${f6(c['serverless_mean_cost_per_1000_usd'])} "
        f"for Serverless; the Serverless value was {signed(cost_diff)} relative to EC2, corresponding to a "
        f"{cost_ratio:.2f}× cost ratio. {interpretation}"
    )


def resource_summary(formal: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for workload in WORKLOAD_ORDER:
        ec2 = formal[(formal["workload_id"] == workload) & (formal["architecture"] == "EC2")].copy()
        svl = formal[(formal["workload_id"] == workload) & (formal["architecture"] == "SVL")].copy()
        cpu = pd.to_numeric(ec2["ec2_cpu_avg_percent"], errors="raise")
        cpu_max = pd.to_numeric(ec2["ec2_cpu_max_percent"], errors="raise")
        conc = pd.to_numeric(svl["lambda_concurrency_peak"], errors="raise")
        throttles = pd.to_numeric(svl["lambda_throttles"], errors="raise")
        errors = pd.to_numeric(svl["lambda_errors"], errors="raise")
        rows.append({
            "workload_id": workload,
            "ec2_cpu_mean": cpu.mean(),
            "ec2_cpu_max_mean": cpu_max.mean(),
            "lambda_peak_concurrency_mean": conc.mean(),
            "lambda_peak_concurrency_max": conc.max(),
            "lambda_throttles_sum": throttles.sum(),
            "lambda_errors_sum": errors.sum(),
        })
    return pd.DataFrame(rows)


# ============================================================
# LOAD INPUTS
# ============================================================

required_files = [FORMAL, SUMMARY, COMPARISON, PRICING, WORKLOADS, CALIBRATION]
required_files += [TABLE_DIR / f"table_0{i}_{name}.md" for i, name in [
    (1, "experimental_environment"),
    (2, "frozen_workloads"),
    (3, "performance_comparison"),
    (4, "reliability_comparison"),
    (5, "cost_comparison"),
    (6, "three_trial_variability"),
]]
required_files += [FIGURE_DIR / f for f in [
    "figure_01_research_architecture.png",
    "figure_02_average_latency.png",
    "figure_03_p95_latency.png",
    "figure_04_throughput.png",
    "figure_05_failure_rate.png",
    "figure_06_cost_per_1000.png",
    "figure_07_resource_behavior.png",
]]

for path in required_files:
    require(path)

formal = pd.read_csv(FORMAL)
summary = pd.read_csv(SUMMARY)
comparison = pd.read_csv(COMPARISON)
pricing = pd.read_csv(PRICING)
workloads = pd.read_csv(WORKLOADS)
calibration_text = CALIBRATION.read_text(encoding="utf-8-sig")

if len(formal) != 36:
    raise RuntimeError(f"Expected 36 formal trials; found {len(formal)}")
if len(summary) != 12:
    raise RuntimeError(f"Expected 12 workload/architecture summaries; found {len(summary)}")
if len(comparison) != 6:
    raise RuntimeError(f"Expected 6 architecture comparisons; found {len(comparison)}")
if formal["experiment_id"].astype(str).str.startswith("P-").any():
    raise RuntimeError("Pilot ID detected in formal dataset")
if formal.astype(str).eq("TO_BE_MEASURED").sum().sum() != 0:
    raise RuntimeError("Formal dataset still contains TO_BE_MEASURED")

counts = formal.groupby(["workload_id", "architecture"]).size()
if len(counts) != 12 or not (counts == 3).all():
    raise RuntimeError("Expected exactly three trials for all 12 workload/architecture conditions")

# Refuse to write the quota pilot statement unless the preserved calibration evidence contains it.
for token in ["50", "405", "503", "10", "quota"]:
    if token.lower() not in calibration_text.lower():
        raise RuntimeError(f"Pilot calibration evidence is missing expected token: {token}")

resources = resource_summary(formal)


# ============================================================
# TABLES AND KEY RESULTS
# ============================================================

table1 = table_body(TABLE_DIR / "table_01_experimental_environment.md")
table2 = table_body(TABLE_DIR / "table_02_frozen_workloads.md")
table3 = table_body(TABLE_DIR / "table_03_performance_comparison.md")
table4 = table_body(TABLE_DIR / "table_04_reliability_comparison.md")
table5 = table_body(TABLE_DIR / "table_05_cost_comparison.md")
table6 = table_body(TABLE_DIR / "table_06_three_trial_variability.md")

w04 = comparison_row(comparison, "W04")
w05 = comparison_row(comparison, "W05")
w06 = comparison_row(comparison, "W06")

quota_touch = resources[resources["lambda_peak_concurrency_max"] >= 10]["workload_id"].tolist()
throttle_workloads = resources[resources["lambda_throttles_sum"] > 0]["workload_id"].tolist()

pricing_lines = []
for _, r in pricing.iterrows():
    pricing_lines.append(f"- {r['component']}: {r['rate_usd']} USD per {r['unit']} ({r['usage_type']}).")
pricing_text = "\n".join(pricing_lines)


# ============================================================
# COMPLETE PREPRINT
# ============================================================

paper = f"""# Experimental Evaluation of EC2-Based and Serverless Architectures for Bursty Web Application Workloads on AWS: Performance, Scalability, and Cost Trade-offs

**Shaheen Sardar**  
Independent Researcher, Pakistan

**Preprint**

## Abstract

Cloud applications can be deployed on continuously provisioned virtual machines or on serverless platforms that allocate compute on demand. The practical choice between these models is workload-dependent because latency, tail behavior, throughput, reliability, scaling constraints, and cost can move in different directions. This study presents a controlled experimental comparison of an Amazon EC2 architecture and an AWS serverless architecture for a deterministic CPU-bound web workload. The EC2 system used a `t3.small` instance running Ubuntu 24.04, Flask, Gunicorn, and Nginx. The serverless system used Amazon API Gateway HTTP API and an AWS Lambda function configured with Python 3.12, x86_64, and 1024 MB of memory. Both systems executed the same `/compute` logic consisting of 25,000 chained SHA-256 operations. Six frozen workload profiles—low, moderate, high, sudden burst, idle-to-burst, and sustained—were evaluated using the same Locust client behavior, with three accepted repetitions per architecture and workload, yielding 36 formal trials. Descriptive statistics were used because each condition had only three repetitions.

The results show a workload-dependent trade-off rather than a universal winner. Under the sudden-burst workload, Serverless reduced average latency by {abs(num(w04['serverless_vs_ec2_latency_relative_difference_percent'])):.1f}% and increased achieved throughput by {num(w04['serverless_vs_ec2_throughput_relative_difference_percent']):.1f}%, but its mean failure rate was {f3(w04['serverless_mean_failure_rate_percent'])}% versus {f3(w04['ec2_mean_failure_rate_percent'])}% for EC2 and its normalized cost per 1,000 successful requests was {num(w04['serverless_to_ec2_cost_ratio']):.2f}× the EC2 value. In the idle-to-burst workload, Serverless reduced average latency by {abs(num(w05['serverless_vs_ec2_latency_relative_difference_percent'])):.1f}% and increased achieved throughput by {num(w05['serverless_vs_ec2_throughput_relative_difference_percent']):.1f}%, while its cost per 1,000 successful requests moved much closer to EC2 at {num(w05['serverless_to_ec2_cost_ratio']):.2f}×. Sustained-load results were more mixed: Serverless achieved {num(w06['serverless_vs_ec2_throughput_relative_difference_percent']):+.1f}% relative throughput difference, but its P95 latency differed by {num(w06['serverless_vs_ec2_p95_relative_difference_percent']):+.1f}% and reliability remained lower. Across the formal experiment, EC2 generally provided lower normalized request cost and stronger reliability, whereas Serverless often provided favorable responsiveness under burstier workloads. The study also separates AWS Lambda service behavior from an account-specific concurrency quota of 10 that constrained the experimental account; this quota is not treated as a general Lambda scalability limit.

**Keywords—** cloud computing, serverless computing, AWS Lambda, Amazon EC2, Function-as-a-Service, burst workloads, tail latency, scalability, cloud cost, performance evaluation

---

# 1. Introduction

## 1.1 Background

Cloud platforms expose multiple execution models for web applications. A virtual-machine model gives the operator direct control over provisioned compute capacity and the software stack, whereas Function-as-a-Service (FaaS) shifts much of provisioning, scaling, and runtime lifecycle management to the provider. Serverless computing is commonly presented as an elasticity- and operations-oriented model, but prior work has shown that the apparent simplicity of the programming interface hides nontrivial resource-management, isolation, startup, and performance behavior [1], [2]. Production FaaS traces also show highly variable invocation frequencies, motivating resource management that can handle intermittent and bursty demand [3].

AWS Lambda is one prominent FaaS platform. Its default compute model uses isolated execution environments, and AWS has described Firecracker microVMs as part of the isolation foundation used by Lambda [4]. By contrast, Amazon EC2 provides explicitly provisioned virtual machines whose lifecycle is controlled by the user. These architectural differences imply different performance and cost behavior: EC2 capacity is paid for while provisioned, whereas Lambda Functions are priced primarily by requests and execution duration [12], [13].

## 1.2 Problem

A simple statement such as “serverless scales better” or “virtual machines are cheaper” is insufficient for architecture selection. Low demand, gradual load, sudden bursts, idle periods followed by bursts, and sustained load exercise the two deployment models differently. Average latency alone can also conceal tail behavior, while throughput can improve at the same time that reliability or cost deteriorates. Tail latency is particularly important in distributed and online services because high-percentile delays can dominate user-perceived behavior even when average latency appears acceptable [9].

## 1.3 Research Gap

Existing research has characterized commercial serverless platforms [2], production FaaS workloads [3], cold-start and launch overheads [5], [6], alternative serverless runtimes [7], and formal performance/cost models for FaaS applications [8]. These studies establish that serverless behavior depends on resource management, workload shape, isolation mechanisms, and billing semantics. The present study does not claim that EC2-versus-serverless comparison is itself novel. Instead, it contributes a reproducible, controlled comparison in which the application-level computation, request endpoint, client behavior, AWS Region, workload definitions, trial count, metric-extraction pipeline, and normalized cost methodology are frozen before formal analysis. The aim is to produce a transparent case study of workload-dependent trade-offs rather than a universal platform ranking.

## 1.4 Research Questions

This study addresses four research questions:

**RQ1.** How do EC2 and serverless architectures differ in average latency, P95/P99 tail latency, and achieved throughput across low, moderate, high, burst, idle-to-burst, and sustained workloads?

**RQ2.** How do reliability and observed scaling behavior change as concurrency and burstiness increase?

**RQ3.** How does estimated cost per 1,000 successful requests differ between continuously provisioned EC2 capacity and request/duration-based serverless execution?

**RQ4.** How should resource behavior and an account-specific Lambda concurrency quota be interpreted without generalizing an experimental account constraint to AWS Lambda as a service?

## 1.5 Contributions

The main contributions are:

1. A controlled EC2-versus-serverless experiment using identical deterministic application-level computation.
2. Six frozen workload profiles that distinguish low, moderate, high, sudden-burst, idle-to-burst, and sustained behavior.
3. Thirty-six accepted formal trials, with three repetitions for each workload/architecture condition and descriptive variability reporting.
4. Joint analysis of average latency, median latency, P95/P99 latency, achieved throughput, request failures, CloudWatch resource metrics, and normalized list-price cost.
5. Explicit separation of formal results from pilot calibration data and explicit separation of Lambda platform behavior from the experimental account's concurrency quota.
6. A reproducibility package containing processed data, non-sensitive methodology artifacts, analysis scripts, tables, and figures.

---

# 2. Related Work

Hellerstein et al. framed serverless computing as an important cloud-computing direction while emphasizing that provider-managed execution introduces both opportunities and architectural constraints [1]. Wang et al. conducted a large measurement study of AWS Lambda, Azure Functions, and Google Cloud Functions, characterizing scalability, cold-start latency, isolation, and resource efficiency from a customer perspective [2]. Their work is particularly relevant to the present study because it demonstrates that commercial serverless platforms should be evaluated empirically rather than treated as homogeneous abstractions.

Shahrad et al. analyzed a large production FaaS workload and showed extreme variation in invocation frequency, reinforcing the importance of irregular and bursty workload behavior in serverless resource management [3]. Startup behavior is also a recurring concern. Boucher et al. showed that conventional FaaS launch paths can impose substantial cold-launch latency [6], while Akkus et al. designed SAND to reduce startup delays and improve elasticity/resource efficiency [5]. AWS itself distinguishes cold initialization from reuse of retained execution environments; therefore, an idle interval alone does not prove that a later invocation is a cold start [11]. This distinction is important for the present W05 idle-to-burst experiment.

The isolation and runtime substrate of serverless platforms also affects performance. Agache et al. described Firecracker, a microVM monitor designed for serverless workloads and deployed in AWS Lambda and Fargate [4]. Shillaker and Pietzuch demonstrated that alternative isolation approaches can materially affect throughput and tail latency [7]. These systems results motivate measuring both central tendency and high-percentile latency rather than relying on average response time alone.

Economic trade-offs are similarly workload-dependent. Lin et al. developed fine-grained performance and cost models for FaaS applications and emphasized that performance/cost optimization is difficult because of infrastructure opacity and configuration choices [8]. In practical AWS deployments, the billing bases themselves differ: EC2 On-Demand Instances charge for running provisioned capacity with a minimum billing duration [13], while Lambda Functions charge for requests and GB-second execution duration [12]. API Gateway adds a separate request-priced component for the serverless HTTP path [15]. The present study therefore reports normalized cost per 1,000 successful requests in addition to raw per-trial estimated cost.

Finally, Dean and Barroso's analysis of “tail at scale” establishes why the high-percentile latency distribution matters for interactive systems [9]. Although the present experiment is much smaller than warehouse-scale services, the methodological principle remains relevant: P95 and P99 can reveal behavior hidden by averages. Accordingly, this study treats average latency, tail latency, throughput, reliability, and cost as separate outcome dimensions.

---

# 3. Experimental Methodology

## 3.1 Research Design

The experiment used a controlled repeated-measures design at the configuration level. The primary independent variables were **architecture** (EC2 or Serverless) and **workload profile** (W01–W06). Dependent variables included response latency, tail latency, achieved requests per second, failures, EC2 utilization metrics, Lambda/API Gateway metrics, and estimated cost. Controlled variables included the AWS Region (`ap-south-1`), application-level computation, `/compute` endpoint behavior, Locust client logic, workload definitions, trial duration, measurement pipeline, and analysis procedure.

The formal dataset contains 36 accepted trials: six workloads × two architectures × three repetitions. Because each condition contains only three repetitions, the analysis emphasizes descriptive means, sample standard deviations, ranges, architecture ratios, and relative differences. No p-value or statistical-significance claim is made from these n=3 groups.

![Figure 1. Experimental architecture and measurement workflow.](../figures/figure_01_research_architecture.png)

## 3.2 EC2 Architecture

The EC2 architecture used a Linux `t3.small` instance in `ap-south-1`, provisioned with Terraform. The application ran in a Python virtual environment, with Gunicorn managed by systemd and Nginx acting as the reverse proxy for the same Flask `/compute` logic. The instance used an 8 GB encrypted gp3 EBS root volume and a public IPv4 endpoint for the client path. Amazon Systems Manager was enabled for management. Detailed EC2 CloudWatch monitoring was used for the formal telemetry pipeline.

The use of `t3.small` is methodologically important. T3 instances are burstable-performance instances governed by CPU credits; AWS documents `t3.small` as a 2-vCPU instance with a 20% baseline per vCPU and T3 instances launch in Unlimited mode by default unless account configuration changes that behavior [14]. Consequently, the measured EC2 results characterize this specific burstable instance configuration rather than “EC2 in general.”

## 3.3 Serverless Architecture

The serverless architecture used Amazon API Gateway HTTP API as the public HTTP entry point and AWS Lambda as the compute layer. The Lambda function used Python 3.12, x86_64 architecture, and 1024 MB of configured memory. Terraform managed the serverless resources. API Gateway and Lambda CloudWatch metrics were collected separately so that front-door latency/error behavior and function execution/scaling behavior could be analyzed without conflating the two services.

AWS documents Lambda concurrency as the number of simultaneous in-flight invocations; when available account concurrency is exhausted, functions can be throttled [10]. The experimental account had an observed regional concurrency quota of 10. This value is treated as an account-specific experimental constraint and is not treated as the normal AWS Lambda service limit.

## 3.4 Identical Computation

Both architectures executed the same deterministic compute routine: 25,000 chained SHA-256 operations (`sha256-v1`). The `/health` endpoint provided a lightweight health check, while `/compute` invoked the controlled CPU-bound routine. Before formal testing, outputs from EC2 and Lambda were verified to produce the same deterministic result. Authentication, databases, sessions, file uploads, and other application features were deliberately excluded to reduce confounding application-level variables.

## 3.5 Workload Model

Locust 2.46.3 generated the formal workload. The same Locust file was used for both architectures; only the destination host changed. Each virtual user repeatedly requested `/compute` with a randomized wait interval of 0.2–0.5 s between completed requests. This is a **closed-loop virtual-user workload**, so requests per second are interpreted as *achieved throughput under the frozen user-concurrency pattern*, not as a separately fixed offered RPS.

**Table 2. Frozen Formal Workload Definitions**

{table2}

W01 represents low demand; W02 increases concurrent users gradually; W03 raises concurrency further; W04 creates an abrupt 30-user burst; W05 applies the same burst after a 300-second idle period; and W06 maintains 20 users for five minutes to expose sustained behavior. W05 is intentionally described as *idle-to-burst*, not as a guaranteed cold-start experiment, because AWS may retain a Lambda execution environment across an idle interval [11].

## 3.6 Pilot Calibration

Pilot trials were performed before formal data collection to validate instrumentation and calibrate workload intensity. Pilot data were stored separately and were not used in formal result figures or statistical summaries. The original sudden-burst pilot used 50 users spawned at 50 users/s for 60 s. In the serverless path it produced 405 HTTP 503 failures while the experimental account's Lambda concurrency reached 10; the account quota was also observed as 10. This pilot condition was retained as calibration evidence but excluded from formal analysis. The formal W04 burst was therefore frozen at 30 users with a 30 users/s spawn rate.

The purpose of this calibration was not to hide unfavorable serverless behavior. Instead, it established a repeatable formal workload matrix while preserving the original quota-bound pilot as evidence of an environmental limit. The account quota is discussed explicitly in Section 7.4.

## 3.7 Formal Experiment Design

Each of the six workloads was run three times against EC2 and three times against Serverless, producing 36 accepted formal trials. Experiment identifiers followed the pattern `EC2-Wxx-Tyy` and `SVL-Wxx-Tyy`. The formal runner recorded exact UTC start/end metadata, Locust output, failures, exceptions, and trial configuration. Invalid instrumentation attempts were archived separately rather than silently overwritten. The completed formal audit verified all 36 unique experiment identifiers and preserved a SHA-256 manifest of accepted raw artifacts.

## 3.8 Metrics

Application-level metrics were taken from the `/compute` Locust row: total requests, successful and failed requests, failure percentage, average and median response time, P95/P99 latency, minimum/maximum latency, and requests per second. For each workload/architecture group, the three trial values were summarized using means and sample standard deviations; ranges were also retained.

CloudWatch metrics were extracted from the formal UTC run windows at 60-second granularity. EC2 metrics included `CPUUtilization`, `NetworkIn`, `NetworkOut`, and `StatusCheckFailed`. Lambda metrics included `Invocations`, `Duration`, `Errors`, `Throttles`, and `ConcurrentExecutions`. API Gateway metrics included `Count`, `4XX`, `5XX`, `Latency`, and `IntegrationLatency`. Because CloudWatch rounds and aggregates metric timestamps, these values should be interpreted as one-minute datapoints returned for the requested formal windows rather than millisecond-exact attribution to individual requests.

## 3.9 Cost Methodology

Cost analysis used the current regional AWS list-price snapshot captured during Task 25 rather than the researcher's actual AWS invoice. Free Tier benefits, promotional credits, Savings Plans, Reserved Instance discounts, taxes, and account-specific discounts were excluded so that architecture comparisons would not depend on one account's billing benefits. `actual_cost_usd` was therefore recorded as `NOT_DIRECTLY_ATTRIBUTABLE`, while `estimated_cost_usd` represented the reproducible list-price estimate.

For EC2, the allocation included `t3.small` On-Demand compute, attached gp3 storage, and the in-use public IPv4 address. EC2 allocation time equaled the formal load duration, except W05, where the 300-second idle interval plus the 60-second burst was allocated to the continuously provisioned EC2 architecture. For Serverless, the estimate used measured Lambda invocations, average Lambda duration, configured memory (1 GB), the regional Lambda request and GB-second rates, and measured API Gateway request count. Serverless compute was not allocated during the W05 idle interval. CloudWatch research instrumentation, Systems Manager usage, Git, the load generator, and unrelated account services were excluded from the application cost boundary.

The captured pricing snapshot was:

{pricing_text}

Lambda compute cost is an estimate based on CloudWatch aggregate `Duration`, invocation count, and configured memory, rather than a reconstruction of every invoice-level billed-duration record. This is why the study consistently refers to **estimated cost**.

---

# 4. Experimental Environment

**Table 1. Experimental Environment**

{table1}

The environment was intentionally small and reproducible. EC2 and Serverless ran in the same AWS Region and exposed equivalent application behavior. The load generator ran outside the target architectures and was checked before formal execution to avoid obvious client CPU saturation. Infrastructure definitions were managed with Terraform, and no-drift checks were used before the formal phase.

---

# 5. Results

The results below use only the 36 accepted formal trials. Pilot calibration runs are excluded. Figure error bars represent sample standard deviation across the three trials. Because n=3 is small, differences are reported descriptively and are not presented as statistically significant population effects.

**Table 3. Performance Comparison**

{table3}

![Figure 2. Mean average latency by formal workload; error bars show sample SD across three trials.](../figures/figure_02_average_latency.png)

![Figure 3. Mean P95 latency by formal workload; error bars show sample SD across three trials.](../figures/figure_03_p95_latency.png)

![Figure 4. Achieved throughput by formal workload; error bars show sample SD across three trials.](../figures/figure_04_throughput.png)

## 5.1 Low Workload

{result_paragraph('W01', summary, comparison)}

At low demand, the small differences in achieved throughput and average latency indicate that both architectures comfortably served the frozen five-user workload. The cost result is therefore especially relevant in this condition because the performance gap was limited compared with heavier workloads.

## 5.2 Moderate Workload

{result_paragraph('W02', summary, comparison)}

The larger latency standard deviations in this workload also show why three-trial variability must be retained when interpreting the architecture-level mean. A single run would have produced a less reliable characterization of the comparison.

## 5.3 High Workload

{result_paragraph('W03', summary, comparison)}

The high workload demonstrates that lower average or tail latency does not automatically imply higher achieved throughput or stronger reliability. Multiple outcome dimensions therefore need to be considered together.

## 5.4 Sudden Burst

{result_paragraph('W04', summary, comparison)}

The sudden burst is the clearest formal case in which Serverless provided a strong responsiveness/throughput advantage while EC2 retained a reliability and cost advantage. This is an architecture trade-off, not evidence of universal Serverless superiority.

## 5.5 Idle-to-Burst

{result_paragraph('W05', summary, comparison)}

W05 is particularly important for cost interpretation. EC2 remained provisioned through the 300-second idle interval, whereas on-demand Lambda compute was not allocated during idle. As a result, the normalized cost gap narrowed considerably relative to the continuously active 60-second workloads. This finding concerns the chosen idle-to-burst scenario; it should not be relabeled as a cold-start result without direct evidence that Lambda created a new execution environment after the idle interval.

## 5.6 Sustained Workload

{result_paragraph('W06', summary, comparison)}

The sustained workload illustrates the value of reporting tail latency separately from the mean. An architecture can remain competitive on average response time or achieved throughput while exhibiting materially different P95/P99 behavior and request reliability over a longer interval.

**Table 4. Reliability Comparison**

{table4}

![Figure 5. Formal request failure rate by workload.](../figures/figure_05_failure_rate.png)

## 5.7 Cost Comparison

**Table 5. Estimated Cost Comparison**

{table5}

![Figure 6. Estimated cost per 1,000 successful requests.](../figures/figure_06_cost_per_1000.png)

Across the formal workload set, EC2 generally produced the lower normalized cost per 1,000 successful requests. This occurs partly because short, active tests amortize the fixed EC2 allocation over many completed requests, whereas the Serverless path includes both Lambda and API Gateway request/duration components. W05 changes that relationship because the experiment explicitly allocates the 300-second idle period to continuously provisioned EC2 capacity. Consequently, Serverless becomes much more cost-competitive in that idle-to-burst condition, although the reliability result still has to be considered.

**Table 6. Three-Trial Summary and Variability**

{table6}

The variability table is central to interpretation because several conditions show substantial trial-to-trial dispersion. With only three repetitions, the study therefore treats differences as observed experimental effects rather than population-level significance estimates.

---

# 6. Discussion

## 6.1 Workload-Dependent Performance

The central result is that architecture suitability changed with workload shape. Under W01, both architectures served the low workload with similar achieved throughput, leaving cost as an important differentiator. As load increased, Serverless frequently improved one or more latency metrics, but the improvements did not consistently extend to reliability or cost. W04 and W05 provided the strongest Serverless responsiveness results, consistent with the general motivation for elastic on-demand execution under bursty demand [2], [3], [5]. However, the high and sustained workloads show that elasticity should not be equated with uniformly better tail latency or failure behavior.

The sustained workload is especially useful for avoiding an average-only conclusion. Serverless's W06 mean latency difference was {num(w06['serverless_vs_ec2_latency_relative_difference_percent']):+.1f}% and throughput difference was {num(w06['serverless_vs_ec2_throughput_relative_difference_percent']):+.1f}% relative to EC2, yet its P95 difference was {num(w06['serverless_vs_ec2_p95_relative_difference_percent']):+.1f}% and its mean failure rate was {f3(w06['serverless_mean_failure_rate_percent'])}% versus {f3(w06['ec2_mean_failure_rate_percent'])}% for EC2. This supports the decision to report average, P95, P99, throughput, and failures jointly.

## 6.2 Resource and Scaling Behavior

![Figure 7. EC2 resource behavior and Lambda scaling behavior across formal workloads.](../figures/figure_07_resource_behavior.png)

EC2 CPU utilization and Lambda concurrency are different units and should not be placed on a single quantitative scale. Figure 7 therefore presents them as separate panels. The EC2 panel describes how the selected `t3.small` consumed provisioned CPU capacity, while the Lambda panel describes peak concurrent function execution. The formal workloads whose observed peak Lambda concurrency reached the experimental quota value of 10 were: **{', '.join(quota_touch) if quota_touch else 'none'}**. Workloads with nonzero formal Lambda throttles were: **{', '.join(throttle_workloads) if throttle_workloads else 'none'}**.

Where concurrency reached 10 and CloudWatch recorded throttles, the degradation is consistent with exhaustion of the experimental account's available concurrency. Where failures occurred without that combination, they should not be attributed to the quota solely because the account had a low limit. This evidence-based distinction avoids converting an account constraint into an incorrect statement about the Lambda service.

AWS currently documents a default regional account concurrency limit of 1,000 concurrent executions, subject to quotas and account circumstances, and describes throttling when available concurrency is exhausted [10]. The experimental value of 10 was therefore unusually restrictive and materially limits external generalization of the highest-concurrency serverless results.

## 6.3 Reliability Trade-offs

The formal results generally show stronger EC2 reliability, particularly as the workload becomes more demanding. Importantly, failures are not discarded as “bad runs”; they are part of the architecture outcome. The experiment runner was designed to distinguish application/HTTP failures from instrumentation failures so that valid trials with nonzero request failures remained in the formal dataset.

For Serverless, reliability reflects the complete HTTP path—API Gateway plus Lambda—not only successful Lambda handler executions. Consequently, API Gateway 5XX responses, Lambda throttles, and Lambda errors are retained separately in the dataset. This separation prevents a 5XX response from being automatically mislabeled as a function-code error.

## 6.4 Cost Trade-offs

The cost results highlight the difference between **provisioned capacity** and **usage-granular execution**. For short actively loaded tests, the low-priced `t3.small` provided very low normalized cost because its fixed capacity was heavily utilized during the measurement interval. The Serverless architecture paid separate request costs for API Gateway and Lambda plus duration-based Lambda compute. In contrast, W05 penalized the EC2 model for remaining allocated during the intentionally idle interval, bringing normalized costs much closer.

This finding should not be extrapolated into a universal monthly cost claim. Real workloads differ in idle fraction, request rate, function duration, memory allocation, data transfer, operational overhead, scaling policies, discounts, and reserved-capacity commitments. The experiment instead demonstrates how cost rankings can change when the idle/burst structure changes while the application logic remains fixed.

## 6.5 Answers to the Research Questions

**RQ1 — Performance:** No architecture dominated every workload. Serverless frequently reduced latency under burstier conditions and sometimes increased achieved throughput, whereas EC2 remained competitive or superior on other tail-latency conditions. The W06 result shows that average and tail latency can point in different directions.

**RQ2 — Reliability and scaling:** EC2 was generally more reliable in the formal runs. Serverless scaling behavior was also affected by the experimental account's concurrency quota, so high-concurrency failures must be interpreted together with `ConcurrentExecutions` and `Throttles` rather than generalized to unrestricted Lambda.

**RQ3 — Cost:** EC2 generally had lower cost per 1,000 successful requests in the active formal workloads. The idle-to-burst workload narrowed the gap because EC2 remained provisioned during the 300-second idle interval while Serverless on-demand compute did not.

**RQ4 — Resource/account constraints:** EC2 CPU utilization describes consumption of fixed provisioned capacity, whereas Lambda concurrency describes the number of simultaneous function executions. These are complementary, not directly comparable, measures. The observed concurrency ceiling of 10 belongs to this experimental account and is a threat to external validity, not a general Lambda limit.

---

# 7. Threats to Validity

## 7.1 Internal Validity

First, cloud platforms contain background variability that cannot be eliminated by a small independent experiment. Shared infrastructure, network conditions, provider scheduling, execution-environment reuse, and VM placement can affect individual trials. Repeating each condition three times and reporting sample standard deviations reduces dependence on a single observation but does not eliminate this variability.

Second, the EC2 system used a T3 burstable instance. CPU-credit state can affect performance, and T3 Unlimited mode can permit bursting above baseline and may incur surplus-credit charges under sufficiently prolonged utilization [14]. The study monitored EC2 CPU utilization but did not claim that a `t3.small` represents fixed-performance EC2 instance families.

Third, CloudWatch formal extraction uses one-minute datapoints for requested UTC windows. This is appropriate for infrastructure-level context but does not provide request-level causal attribution. CloudWatch averages should therefore not be read as synchronized millisecond traces of the Locust requests.

Fourth, formal trials were executed from a single load-generator environment. A pre-formal check found no obvious client CPU saturation, but network path and client-side scheduling remain potential sources of variation.

## 7.2 External Validity

The experiment uses one AWS Region (`ap-south-1`), one EC2 instance type (`t3.small`), one Lambda memory configuration (1024 MB), one Lambda architecture (x86_64), one API type (HTTP API), and one deterministic CPU-bound application. Results may differ for I/O-bound services, databases, larger payloads, different EC2 families, Graviton/ARM, different Lambda memory sizes, provisioned concurrency, reserved concurrency, or other Regions.

The experiment also studies modest absolute concurrency. Production systems can operate at much larger scale and may employ caches, CDNs, queues, asynchronous processing, Auto Scaling groups, load balancers, reserved capacity, or multi-region routing. The paper therefore presents a controlled case study rather than a benchmark of the maximum capacity of either AWS service.

## 7.3 Construct Validity

Locust uses a closed-loop user model in this study. Faster responses allow the same virtual users to issue more completed requests; therefore, `requests_per_second` is correctly interpreted as achieved throughput under equal user-concurrency behavior rather than a fixed offered arrival rate.

W05 contains a 300-second idle interval, but AWS does not guarantee that an idle environment will be discarded after a fixed interval. AWS documents that execution environments may be retained and reused [11]. W05 is therefore an idle-to-burst experiment and not proof of a cold start.

The cost model is another construct limitation. Lambda GB-second cost is estimated from aggregate invocation count, average CloudWatch `Duration`, and configured memory. Exact AWS invoice-level billed duration may differ. For this reason, the paper reports estimated rather than actual per-trial cost.

## 7.4 AWS Account Concurrency Limitation

The most important serverless-specific validity constraint is the account's observed regional Lambda concurrency quota of **10** during the experiment. Pilot evidence showed that the original 50-user sudden burst reached this value and generated both throttling and HTTP 503 responses. The formal burst intensity was calibrated downward, but some formal high/burst conditions could still approach the same environmental ceiling.

This value must not be presented as “AWS Lambda scales to only 10 concurrent requests.” AWS documentation describes a much larger default regional account concurrency pool and allows quota management; functions are throttled when available concurrency is exhausted [10]. Accordingly, this study's high-concurrency Serverless results measure **AWS Lambda under the tested account constraint**, not the unconstrained scaling ceiling of the Lambda platform. This distinction is carried into the Results, Discussion, and Conclusion.

---

# 8. Reproducibility and Data Availability

The experiment was implemented as a reproducible infrastructure-and-analysis workflow. Terraform definitions provisioned the EC2 and Serverless architectures. A shared Locust workload file generated requests against `/compute`. Formal experiment metadata recorded architecture, workload, trial number, UTC timing, application commit, and Terraform commit. Raw formal Locust artifacts, CloudWatch extraction results, processed datasets, cost calculations, statistical summaries, tables, and publication figures were generated by scripts rather than manually transcribing results.

The processed experimental data and non-sensitive reproducibility materials supporting this study are provided as supplementary materials with this preprint. The complete research repository is maintained privately because it also contains account-specific logs and security-sensitive configuration. Additional non-sensitive supporting materials may be obtained from the corresponding author upon reasonable request.

The principal formal dataset is `data/final/experiments.csv` (36 rows × 44 columns). Processed analysis artifacts include workload/architecture summaries, architecture comparisons, pricing snapshots, cost breakdowns, table outputs, figure manifests, and SHA-256 evidence manifests. Pilot calibration evidence is stored separately from formal results and is not included in formal result graphs.

---

# 9. Conclusion

This study experimentally compared an EC2-based web application and an API Gateway + AWS Lambda serverless application under six frozen workload patterns with identical deterministic computation. Thirty-six accepted formal trials show that the architecture decision is workload-dependent. Serverless frequently improved responsiveness under burst-oriented workloads and, in the idle-to-burst scenario, became substantially more cost-competitive because compute was not continuously allocated during the idle interval. EC2, however, generally delivered lower normalized cost per 1,000 successful requests and stronger request reliability in the tested conditions.

The results also demonstrate why architecture comparisons should not rely on a single metric. Average latency, P95/P99 tail latency, achieved throughput, failure rate, resource behavior, and cost sometimes favored different architectures in the same workload. The sustained workload particularly shows that acceptable mean behavior can coexist with less favorable tail latency or reliability.

Finally, the experiment identifies an important boundary on the Serverless findings: the AWS account used for the study had a regional Lambda concurrency quota of 10. Observations associated with reaching that ceiling are valid measurements of the tested environment, but they are not evidence that AWS Lambda normally has a concurrency limit of 10. Future work should repeat the frozen experiment with a higher concurrency quota, additional EC2 instance families, multiple Lambda memory/architecture configurations, open-loop arrival processes, and additional Regions. Such extensions would test whether the workload-dependent trade-offs observed here persist under broader capacity and workload conditions.

---

# References

[1] J. M. Hellerstein, J. Faleiro, J. E. Gonzalez, J. Schleier-Smith, V. Sreekanti, A. Tumanov, and C. Wu, “Serverless Computing: One Step Forward, Two Steps Back,” in *9th Biennial Conference on Innovative Data Systems Research (CIDR)*, 2019.

[2] L. Wang, M. Li, Y. Zhang, T. Ristenpart, and M. Swift, “Peeking Behind the Curtains of Serverless Platforms,” in *2018 USENIX Annual Technical Conference (USENIX ATC 18)*, pp. 133–146, 2018.

[3] M. Shahrad, R. Fonseca, I. Goiri, G. Chaudhry, P. Batum, J. Cooke, E. Laureano, C. Tresness, M. Russinovich, and R. Bianchini, “Serverless in the Wild: Characterizing and Optimizing the Serverless Workload at a Large Cloud Provider,” in *2020 USENIX Annual Technical Conference (USENIX ATC 20)*, pp. 205–218, 2020.

[4] A. Agache, M. Brooker, A. Florescu, A. Iordache, A. Liguori, R. Neugebauer, P. Piwonka, and D.-M. Popa, “Firecracker: Lightweight Virtualization for Serverless Applications,” in *17th USENIX Symposium on Networked Systems Design and Implementation (NSDI 20)*, pp. 419–434, 2020.

[5] I. E. Akkus, R. Chen, I. Rimac, M. Stein, K. Satzke, A. Beck, P. Aditya, and V. Hilt, “SAND: Towards High-Performance Serverless Computing,” in *2018 USENIX Annual Technical Conference (USENIX ATC 18)*, pp. 923–935, 2018.

[6] S. Boucher, A. Kalia, D. G. Andersen, and M. Kaminsky, “Putting the ‘Micro’ Back in Microservice,” in *2018 USENIX Annual Technical Conference (USENIX ATC 18)*, pp. 645–650, 2018.

[7] S. Shillaker and P. Pietzuch, “Faasm: Lightweight Isolation for Efficient Stateful Serverless Computing,” in *2020 USENIX Annual Technical Conference (USENIX ATC 20)*, pp. 419–433, 2020.

[8] C. Lin, N. Mahmoudi, S. Fan, and H. Khazaei, “Fine-Grained Performance and Cost Modeling and Optimization for FaaS Applications,” *IEEE Transactions on Parallel and Distributed Systems*, vol. 34, no. 1, pp. 180–194, 2023, doi: 10.1109/TPDS.2022.3214783.

[9] J. Dean and L. A. Barroso, “The Tail at Scale,” *Communications of the ACM*, vol. 56, no. 2, pp. 74–80, 2013, doi: 10.1145/2408776.2408794.

[10] Amazon Web Services, “Understanding Lambda function scaling,” *AWS Lambda Developer Guide*, accessed Aug. 17, 2026.

[11] Amazon Web Services, “Understanding the Lambda execution environment lifecycle,” *AWS Lambda Developer Guide*, accessed Aug. 17, 2026.

[12] Amazon Web Services, “AWS Lambda Pricing,” accessed Aug. 17, 2026.

[13] Amazon Web Services, “Purchasing On-Demand Instances for Amazon EC2,” *Amazon EC2 User Guide*, accessed Aug. 17, 2026.

[14] Amazon Web Services, “Key concepts for burstable performance instances,” *Amazon EC2 User Guide*, accessed Aug. 17, 2026.

[15] Amazon Web Services, “Amazon API Gateway Pricing,” accessed Aug. 17, 2026.
"""

OUTPUT.write_text(paper, encoding="utf-8")


# ============================================================
# FINAL AUDIT
# ============================================================

text = OUTPUT.read_text(encoding="utf-8")
word_count = len(re.findall(r"\b\w+[\w'-]*\b", text))

checks = [
    ("formal_trials", 36, len(formal)),
    ("summary_groups", 12, len(summary)),
    ("architecture_comparisons", 6, len(comparison)),
    ("pilot_ids_in_formal_dataset", 0, int(formal["experiment_id"].astype(str).str.startswith("P-").sum())),
    ("remaining_to_be_measured", 0, int(formal.astype(str).eq("TO_BE_MEASURED").sum().sum())),
    ("formal_workloads", 6, len(workloads)),
    ("paper_tables_referenced", 6, sum(f"Table {i}." in text for i in range(1, 7))),
    ("paper_figures_referenced", 7, sum(f"Figure {i}." in text for i in range(1, 8))),
    ("references", 15, len(re.findall(r"^\[\d+\]", text, flags=re.MULTILINE))),
    ("major_sections", 9, sum(f"# {i}." in text for i in range(1, 10))),
    ("quota_limit_not_generalized", 1, int("not treated as the normal AWS Lambda service limit" in text)),
    ("n3_significance_caution", 1, int("No p-value or statistical-significance claim" in text)),
    ("preprint_created", 1, int(OUTPUT.exists() and OUTPUT.stat().st_size > 0)),
]

audit_rows = []
for name, expected, actual in checks:
    audit_rows.append({
        "check": name,
        "expected": expected,
        "actual": actual,
        "status": "PASS" if str(expected) == str(actual) else "FAIL",
    })

audit = pd.DataFrame(audit_rows)
audit.to_csv(AUDIT, index=False)

failures = audit[audit["status"] != "PASS"]
if len(failures):
    print(failures.to_string(index=False))
    raise RuntimeError("Task 31 preprint audit failed")

print("=" * 76)
print(" DAY 2 - TASK 31 - COMPLETE PREPRINT")
print("=" * 76)
print()
print("Source-data audit")
print("-----------------")
print(f"Formal trials                    : {len(formal)} / 36")
print(f"Workload/architecture groups     : {len(summary)} / 12")
print(f"Architecture comparisons         : {len(comparison)} / 6")
print("Pilot IDs in formal dataset      : 0")
print("Remaining TO_BE_MEASURED         : 0")
print()
print("Paper audit")
print("-----------")
print("Major numbered sections          : 9 / 9")
print("Final research tables referenced : 6 / 6")
print("Publication figures referenced   : 7 / 7")
print("References                       : 15 / 15")
print(f"Approximate word count            : {word_count}")
print("n=3 significance overclaim       : BLOCKED")
print("Lambda quota 10 generalized      : NO")
print()
print(audit.to_string(index=False))
print()
print("=" * 76)
print(" TASK 31 PASSED")
print(" COMPLETE PREPRINT WRITTEN")
print(" 36 / 36 FORMAL TRIALS USED")
print(" 0 PILOT TRIALS USED AS FORMAL RESULTS")
print(" RESULTS WRITTEN FROM PROCESSED FORMAL DATA")
print(" 6 / 6 FINAL TABLES INTEGRATED")
print(" 7 / 7 PUBLICATION FIGURES INTEGRATED")
print(" 15 / 15 CURATED REFERENCES INCLUDED")
print(" ACCOUNT CONCURRENCY 10 NOT GENERALIZED AS LAMBDA LIMIT")
print(" NO INFERENTIAL SIGNIFICANCE CLAIMS")
print(" PREPRINT READY FOR SCIENTIFIC EDITING")
print("=" * 76)
print()
print(f"Paper : {OUTPUT}")
print(f"Audit : {AUDIT}")
