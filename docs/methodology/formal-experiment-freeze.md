# Formal Experiment Freeze

Date: 2026-08-16

Status: FROZEN BEFORE FORMAL DATA COLLECTION

## Pilot Validity Review

- Both architectures completed the Low workload: PASS
- Both architectures completed the High workload: PASS
- No application-code or infrastructure-misconfiguration failures were identified: PASS
- Lambda quota-related HTTP 503 responses were identified and documented as an environmental constraint.
- Locust completed the pilot runs: PASS
- Local load-generator CPU validation: PASS
- Average load-generator CPU: 15.79 %
- Maximum load-generator CPU: 37.67 %
- CloudWatch metrics were verified: PASS
- EC2 and Serverless computation equivalence was verified: PASS
- Pilot workloads produced meaningful latency and throughput variation: PASS

## One-Time Formal Workload Adjustment

The initially proposed 100-user and 200-user workload levels were rejected before formal data collection.

Reason:

The experimental AWS account has a regional Lambda concurrency quota of 10 concurrent executions.

The original 50-user sudden-burst pilot generated 405 HTTP 503 failures and reached the account concurrency ceiling.

Using 100 or 200 concurrent users would therefore primarily measure the account-specific quota rather than provide a useful comparison of the two architectural approaches.

The pilot-calibrated workload levels were retained instead.

## Frozen Formal Workloads

| ID | Workload | Users | Spawn Rate | Duration | Idle Before |
|---|---|---:|---:|---:|---:|
| W01 | Low | 5 | 1/s | 60 s | 0 |
| W02 | Moderate | 15 | 3/s | 60 s | 0 |
| W03 | High | 30 | 5/s | 60 s | 0 |
| W04 | Sudden Burst | 30 | 30/s | 60 s | 0 |
| W05 | Idle-to-Burst | 30 | 30/s | 60 s | 300 s |
| W06 | Sustained | 20 | 4/s | 300 s | 0 |

These workload parameters must not be changed after formal data collection begins.

Each architecture will execute three formal trials for each of the six workloads.

Total formal experiments:

2 architectures x 6 workloads x 3 trials = 36 trials.
