# Workload Calibration Record

Date: 2026-08-16

## Purpose

Pilot trials were performed before formal data collection to verify the load generator, identify environmental limits, and calibrate workload intensity.

Pilot results are excluded from the formal experimental dataset.

## Shared Workload Generator

Both EC2 and Serverless architectures use the same:

- Locust configuration
- `/compute` endpoint
- workload implementation
- workload generator machine
- request behavior

Only the target host differs.

## Pilot Workloads

### P-W01 — Low

- Users: 5
- Spawn rate: 1 user/second
- Duration: 60 seconds

Accepted.

### P-W02 — Moderate

- Users: 15
- Spawn rate: 3 users/second
- Duration: 60 seconds

Accepted.

### P-W03 — High

- Users: 30
- Spawn rate: 5 users/second
- Duration: 60 seconds

Accepted.

### Original P-W04 — Sudden Burst

Original candidate:

- Users: 50
- Spawn rate: 50 users/second
- Duration: 60 seconds

Observed Serverless result:

- Requests: 6143
- HTTP failures: 405
- Failure type: HTTP 503
- Lambda execution errors: 0
- Lambda throttles observed: 413
- Maximum Lambda ConcurrentExecutions: 10

AWS account settings showed:

- Regional ConcurrentExecutions quota: 10
- UnreservedConcurrentExecutions: 10
- Function reserved concurrency: not configured

The original P-W04 was therefore retained as pilot evidence but excluded from formal testing.

### P-W04R1 — Calibrated Sudden Burst

Revised once during pilot calibration:

- Users: 30
- Spawn rate: 30 users/second
- Duration: 60 seconds

Observed Serverless pilot result:

- Requests: 3216
- Failures: 19
- Failure percentage: approximately 0.59%

This workload was accepted as the formal sudden-burst condition.

The remaining transient failures are retained as observed behavior and are not removed from the dataset.

### P-W05 — Idle-to-Burst

- Controlled idle interval: 300 seconds
- Users after idle: 30
- Spawn rate: 30 users/second
- Duration: 60 seconds

The scenario is described as idle-to-burst and does not assume or claim a guaranteed Lambda cold start.

### P-W06 — Sustained

- Users: 20
- Spawn rate: 4 users/second
- Duration: 300 seconds

## Final Formal Workloads

Formal workload definitions are stored in:

`load-testing/scenarios/formal-workloads.csv`

The workload parameters are frozen before formal experimental data collection begins.

## Important Environmental Limitation

The experimental AWS account had a regional Lambda concurrency quota of 10 concurrent executions during pilot testing.

Therefore, Lambda throttling observed during burst scenarios must be interpreted in the context of this account-specific quota. The study must not generalize this quota as the normal scalability limit of AWS Lambda.

## Data Separation

Pilot data:

`data/raw/pilot/`

Processed pilot summaries:

`data/processed/pilot/`

Formal results will be stored separately under:

`data/raw/formal/`

Pilot measurements must not be mixed with formal experimental measurements.
