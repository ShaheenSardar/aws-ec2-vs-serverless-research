# Reproducibility and Data Availability

## Study

**Title:** Experimental Evaluation of EC2-Based and Serverless Architectures for Bursty Web Application Workloads on AWS: Performance, Scalability, and Cost Trade-offs

This document records the configuration, experimental design, analysis procedure, limitations, and data-availability boundaries for the study.

---

## 1. Repository Structure

- application/ — application source and deterministic compute implementation.
- terraform/ — Infrastructure-as-Code for the EC2 and serverless environments.
- load-testing/ — Locust workload implementation, frozen workload definitions, and formal runner.
- data/ — raw, processed, and final experiment data.
- analysis/ — analysis, tables, figures, interpretation, and paper-generation scripts.
- docs/ — methodology, evidence, figures, tables, literature, results, and reproducibility documentation.
- paper/ — final publication-oriented artifacts.

---

## 2. Exact AWS Region

**AWS Region:** ap-south-1

All 36 formal dataset rows contain the same AWS region.

---

## 3. AWS Resources

### EC2 architecture

- Amazon EC2 t3.small
- Ubuntu 24.04
- Flask application
- Python virtual environment
- Gunicorn with 3 workers
- systemd service
- Nginx reverse proxy
- 8 GB encrypted gp3 EBS root storage
- Public IPv4 HTTP endpoint
- Amazon CloudWatch monitoring

The EC2 application was installed directly into a Python virtual environment and run by Gunicorn under systemd behind Nginx. The formal EC2 deployment is therefore not described as Dockerized.

### Serverless architecture

- Amazon API Gateway HTTP API
- AWS Lambda
- Python 3.12
- x86_64
- 1024 MB memory
- Amazon CloudWatch monitoring

The experimental AWS account exposed a concurrency quota of 10. This is an account-specific study constraint and is not presented as a general AWS Lambda scalability limit.

---

## 4. Identical Compute Implementation

Both architectures used the same deterministic CPU-bound /compute operation.

**Workload version:** sha256-v1

**Configured compute iterations:** 25000 chained SHA-256 iterations per request.

Detected compute implementation files:

- application\ec2\compute_logic.py — SHA256: a9d1927df4b13a1e3b107247ce7cc01ee55d4bc6128094e104c1799db9441483
- application\lambda\compute_logic.py — SHA256: a9d1927df4b13a1e3b107247ce7cc01ee55d4bc6128094e104c1799db9441483

The study previously verified matching workload version, iteration count, and deterministic output across EC2 and Lambda before formal measurement.

---

## 5. Frozen Workload Definitions

| ID | Workload | Users | Spawn rate (users/s) | Duration (s) | Idle before (s) |
|---|---|---:|---:|---:|---:|
| W01 | Low | 5 | 1 | 60 | 0 |
| W02 | Moderate | 15 | 3 | 60 | 0 |
| W03 | High | 30 | 5 | 60 | 0 |
| W04 | Sudden-Burst | 30 | 30 | 60 | 0 |
| W05 | Idle-to-Burst | 30 | 30 | 60 | 300 |
| W06 | Sustained | 20 | 4 | 300 | 0 |

The same Locust request behavior was used for both architectures; only the target host changed.

The generator used a closed-loop virtual-user model. Requests per second are therefore interpreted as achieved throughput under the frozen virtual-user workload rather than a separately fixed offered request rate.

---

## 6. Repetitions and Formal Experiment IDs

- Architectures: 2
- Workloads: 6
- Repetitions per architecture/workload condition: 3
- Formal workload/architecture groups: 12
- Groups with exactly three trials: 12
- Total formal trials: 36
- Unique formal experiment IDs: 36

Formal experiment IDs:

- EC2-W01-T01
- EC2-W01-T02
- EC2-W01-T03
- EC2-W02-T01
- EC2-W02-T02
- EC2-W02-T03
- EC2-W03-T01
- EC2-W03-T02
- EC2-W03-T03
- EC2-W04-T01
- EC2-W04-T02
- EC2-W04-T03
- EC2-W05-T01
- EC2-W05-T02
- EC2-W05-T03
- EC2-W06-T01
- EC2-W06-T02
- EC2-W06-T03
- SVL-W01-T01
- SVL-W01-T02
- SVL-W01-T03
- SVL-W02-T01
- SVL-W02-T02
- SVL-W02-T03
- SVL-W03-T01
- SVL-W03-T02
- SVL-W03-T03
- SVL-W04-T01
- SVL-W04-T02
- SVL-W04-T03
- SVL-W05-T01
- SVL-W05-T02
- SVL-W05-T03
- SVL-W06-T01
- SVL-W06-T02
- SVL-W06-T03

Because n=3 per condition, the analysis is descriptive and does not make inferential statistical-significance claims.

---

## 7. Pilot / Formal Separation

Pilot calibration was completed before formal data collection and was used only to validate the generator, calibrate workload intensity, and identify experimental constraints.

**Pilot IDs present in final formal dataset:** 0

The original higher-intensity sudden-burst pilot that encountered the account-specific Lambda concurrency quota was preserved as pilot evidence and excluded from the 36 formal trials.

---

## 8. Analysis Procedure

The formal analysis procedure was:

1. Validate the final 36-trial dataset and experiment IDs.
2. Keep pilot and formal evidence separate.
3. Group observations by workload and architecture.
4. Compute equal-weight trial-level descriptive means.
5. Compute sample standard deviation using n-1.
6. Report trial-level P95/P99 summaries without claiming pooled request percentiles.
7. Compare achieved throughput, failure rate, and percentage-point reliability differences.
8. Extract CloudWatch metrics for the formal UTC query windows.
9. Model AWS list-price cost and normalize cost per 1,000 successful requests.
10. Generate publication tables and figures from formal data only.
11. Interpret workload-specific trade-offs without declaring a universal architecture winner.

Analysis scripts detected:

- analysis\scripts\.gitkeep
- analysis\scripts\analyze-formal-results.ps1
- analysis\scripts\build-complete-preprint.py
- analysis\scripts\build-formal-dataset.ps1
- analysis\scripts\build-reproducibility-package.ps1
- analysis\scripts\calculate-formal-costs.ps1
- analysis\scripts\extract-formal-cloudwatch.ps1
- analysis\scripts\generate-final-tables.py
- analysis\scripts\generate-publication-figures.py
- analysis\scripts\generate-results-interpretation.py
- analysis\scripts\task22-formal-completeness-audit.ps1

---

## 9. Key Limitations

- Only three formal repetitions were performed per condition.
- The EC2 baseline is specifically t3.small and should not be generalized to all EC2 configurations.
- The study used one AWS region.
- The application is a controlled deterministic CPU-bound web workload rather than a full production application.
- Locust used a closed-loop virtual-user model.
- The experimental account concurrency quota was 10; this must not be generalized as Lambda's normal scalability limit.
- W05 contains a 300-second idle interval but does not prove Lambda execution-environment eviction; it is an idle-to-burst workload, not a guaranteed cold-start experiment.
- CloudWatch values represent minute-level datapoints associated with requested formal UTC windows, not request-level telemetry.
- Cost values are AWS list-price estimates rather than exact per-trial invoice charges.

---

## 10. Cost Reproducibility

The cost model excludes Free Tier, credits, discounts, taxes, Savings Plans, and Reserved Instance discounts.

The normalized comparison metric is estimated cost per 1,000 successful requests.

Per-trial actual billing is not fabricated where exact AWS invoice attribution is unavailable.

---

## 11. Data Availability and Private Repository Statement

The processed experimental data and non-sensitive reproducibility materials supporting this study are provided as supplementary materials with the preprint.

The complete research repository is maintained privately because it also contains account-specific logs and security-sensitive configuration.

Raw or internal materials containing account identifiers, operational logs, credentials, or security-sensitive configuration are not intended for unrestricted public release.

Additional non-sensitive supporting materials may be obtained from the corresponding author upon reasonable request.

---

## 12. Reproduction Boundaries

A reproduction should preserve or explicitly document changes to: AWS region, architecture configuration, application logic, compute iteration count, workload definitions, concurrency, spawn rates, durations, W05 idle interval, repetitions, measurement method, analysis procedure, and pricing assumptions.

---

## 13. Integrity Summary

- Formal trials: 36
- Unique experiment IDs: 36
- Frozen workload definitions: 6
- Formal experiment matrix rows: 36
- Workload/architecture summary groups: 12
- Architecture comparisons: 6
- Groups with exactly three trials: 12
- Pilot rows in final formal dataset: 0
- AWS region: ap-south-1
- Compute iterations: 25000

This documentation was generated from repository artifacts rather than by manually re-entering result values.