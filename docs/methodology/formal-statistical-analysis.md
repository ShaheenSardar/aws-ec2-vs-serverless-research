# Formal Statistical Analysis Policy

Date: 2026-08-17

## Scope

This analysis uses only the 36 accepted formal experiment rows from:

`data/final/experiments.csv`

Pilot experiments and archived invalid attempts are excluded.

The formal design contains:

- 6 workloads: W01-W06
- 2 architectures: EC2 and Serverless
- 3 independent formal repetitions per workload/architecture
- 12 workload/architecture groups
- 36 total trials

## Statistical Approach

Because each workload/architecture condition contains only three
repetitions (n = 3), the analysis emphasizes descriptive statistics and
observed variability.

No p-values, statistical-significance claims, or large-sample inference
are produced by this task.

## Per-Group Metrics

For each workload and architecture, calculate:

- mean average latency
- mean of trial median latency
- median of trial median latency
- mean p95 latency
- mean p99 latency
- mean throughput
- mean failure rate
- mean estimated cost
- mean cost per 1,000 successful requests

Sample standard deviation (n - 1 denominator) is calculated for:

- average latency
- p95 latency
- p99 latency
- throughput
- failure rate
- cost per 1,000 successful requests

Minimum and maximum values across the three trials are retained for the
same principal metrics.

Coefficient of variation is reported where meaningful as:

`sample standard deviation / mean * 100`

## Cross-Architecture Comparison

For each workload, Serverless is compared with EC2 using:

Relative difference:

`(Serverless - EC2) / EC2 * 100`

Architecture ratio:

`Serverless / EC2`

For latency and cost:

- ratio below 1 favors Serverless
- ratio above 1 favors EC2

For throughput:

- ratio above 1 favors Serverless
- ratio below 1 favors EC2

Failure rate is primarily compared using percentage-point difference.
A ratio is reported only when the EC2 denominator is non-zero.

## Interpretation

Relative differences and ratios are descriptive comparisons only.

With n = 3 repetitions, small differences must not be interpreted as
proof of general superiority without considering trial variability,
workload characteristics, platform limits, and experimental threats to
validity.
