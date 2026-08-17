# Task 34 — Professional Preprint Editorial Report

- Objective editorial checks passed: **20 / 20**
- Failed checks: **0**
- Safe editorial replacements applied: **11**
- Numerical tokens preserved: **True**

## Safe editorial changes

- `1×` — `The experiment used a controlled repeated-measures design at the configuration level.` → `The experiment used a controlled factorial design with repeated trials.`
- `1×` — `front-door latency/error behavior` → `API-layer latency and error behavior`
- `6×` — `mean average latency` → `mean trial-level average latency`
- `1×` — `The sustained workload is especially useful for avoiding an average-only conclusion.` → `The sustained workload illustrates why an average-only conclusion would be incomplete.`
- `1×` — `The most important serverless-specific validity constraint` → `A key serverless-specific validity constraint`
- `1×` — `AWS currently documents` → `AWS documentation states`

## Objective audit

| Check | Status | Note |
|---|---|---|
| 01_major_sections | PASS |  |
| 02_figure_numbering | PASS |  |
| 03_table_numbering | PASS |  |
| 04_reference_numbering | PASS |  |
| 05_citations_valid | PASS |  |
| 06_all_references_cited | PASS | uncited=[] |
| 07_faas_defined_before_use | PASS |  |
| 08_units_consistent | PASS | problems=[] |
| 09_percentage_point_terminology | PASS | bad=[] |
| 10_no_generation_placeholders | PASS | hits=[] |
| 11_no_ec2_docker_contradiction | PASS |  |
| 12_lambda_quota_wording | PASS |  |
| 13_closed_loop_terminology | PASS |  |
| 14_cost_terminology | PASS |  |
| 15_n3_statistical_caution | PASS |  |
| 16_w05_cold_start_caution | PASS |  |
| 17_abstract_result_consistency | PASS | missing=[] |
| 18_conclusion_consistency | PASS | missing=[] |
| 19_numerical_tokens_preserved | PASS |  |
| 20_title_keywords_consistency | PASS |  |

## Optional human-review observations

- Sentences longer than 50 words: **6**
- Non-table lines containing repeated spaces: **0**

### Long sentences to inspect

- Frozen Formal Workload Definitions** | Workload | Definition | Concurrent users | Spawn rate (users/s) | Load duration (s) | Pre-load idle (s) | | --- | --- | --- | --- | --- | --- | | W01 | Low | 5 | 1 | 60 | 0 | | W02 | Moderate | 15 | 3 | 60 | 0 | | W03 | High | 30 | 5 | 60 | 0 | | W04 | Sudden-Burst | 30 | 30 | 60 | 0 | | W05 | Idle-to-Burst | 30 | 30 | 60 | 300 | | W06 | Sustained | 20 | 4 | 
- Experimental Environment** | Category | Parameter | Value | | --- | --- | --- | | Cloud region | AWS Region | ap-south-1 | | Experimental design | Formal trials | 36 accepted trials | | Experimental design | Conditions | 6 workloads × 2 architectures × 3 repetitions | | Workload | Compute operation | Chained SHA-256 CPU-bound computation | | Workload | Compute iterations | 25,000 | | Load generati
- Performance Comparison** | Workload | EC2 mean latency (ms) | Serverless mean latency (ms) | Latency Δ | EC2 P95 (ms) | Serverless P95 (ms) | EC2 P99 (ms) | Serverless P99 (ms) | EC2 throughput (req/s) | Serverless throughput (req/s) | Throughput Δ | | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | | W01 | 123.19 | 126.04 | +2.3% | 196.67 | 163.33 | 390.00 | 363.33 | 10.10 | 10.
- Reliability Comparison** | Workload | EC2 failure rate (%) | Serverless failure rate (%) | Difference (percentage points) | EC2 failed requests | Serverless failed requests | EC2 successful requests | Serverless successful requests | | --- | --- | --- | --- | --- | --- | --- | --- | | W01 | 0.000 | 0.000 | +0.000 pp | 0 | 0 | 1766 | 1771 | | W02 | 0.000 | 0.115 | +0.115 pp | 0 | 5 | 4679 | 4902 | 
- Estimated Cost Comparison** | Workload | EC2 estimated cost / trial (USD) | Serverless estimated cost / trial (USD) | EC2 cost / 1,000 success (USD) | Serverless cost / 1,000 success (USD) | Serverless vs EC2 cost Δ | Serverless / EC2 cost ratio | | --- | --- | --- | --- | --- | --- | --- | | W01 | 0.00047356 | 0.00087629 | 0.00080447 | 0.00148451 | +84.5% | 1.845 | | W02 | 0.00047356 | 0.00205757
- Three-Trial Summary and Variability** | Workload | Architecture | n | Latency mean ± SD (ms) | Latency min-max (ms) | P95 mean ± SD (ms) | Throughput mean ± SD (req/s) | Throughput min-max (req/s) | Failure rate mean ± SD (%) | Cost/1K mean ± SD (USD) | | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | | W01 | EC2 | 3 | 123.19 ± 2.99 | 119.79–125.37 | 196.67 ± 25.17 | 10.10 ± 0.06 | 10
