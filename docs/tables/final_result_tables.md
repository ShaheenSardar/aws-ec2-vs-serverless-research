# Final Research Tables



All result tables below are generated from accepted formal data only. Pilot experiments and archived invalid attempts are excluded.



## Table 1. Experimental Environment

| Category | Parameter | Value |
| --- | --- | --- |
| Cloud region | AWS Region | ap-south-1 |
| Experimental design | Formal trials | 36 accepted trials |
| Experimental design | Conditions | 6 workloads × 2 architectures × 3 repetitions |
| Workload | Compute operation | Chained SHA-256 CPU-bound computation |
| Workload | Compute iterations | 25,000 |
| Load generation | Tool | Locust 2.46.3 |
| EC2 | Instance | t3.small |
| EC2 | Application stack | Ubuntu 24.04, Flask, Gunicorn, Nginx |
| EC2 | Storage / access | 8 GB gp3 EBS; public IPv4 endpoint |
| Serverless | Lambda configuration | Python 3.12, x86_64, 1024 MB |
| Serverless | API | Amazon API Gateway HTTP API |
| Monitoring | AWS telemetry | Amazon CloudWatch; 60-second formal metric extraction |
| Cost | Cost methodology | Regional AWS list-price estimate |
| Cost | Account-specific benefits | Free Tier, credits and discounts excluded |

*Note: The formal analysis uses the frozen experimental configuration.*



## Table 2. Frozen Formal Workload Definitions

| Workload | Definition | Concurrent users | Spawn rate (users/s) | Load duration (s) | Pre-load idle (s) |
| --- | --- | --- | --- | --- | --- |
| W01 | Low | 5 | 1 | 60 | 0 |
| W02 | Moderate | 15 | 3 | 60 | 0 |
| W03 | High | 30 | 5 | 60 | 0 |
| W04 | Sudden-Burst | 30 | 30 | 60 | 0 |
| W05 | Idle-to-Burst | 30 | 30 | 60 | 300 |
| W06 | Sustained | 20 | 4 | 300 | 0 |

*Note: W05 includes a 300-second idle period before the 60-second burst.*



## Table 3. Performance Comparison

| Workload | EC2 mean latency (ms) | Serverless mean latency (ms) | Latency Δ | EC2 P95 (ms) | Serverless P95 (ms) | EC2 P99 (ms) | Serverless P99 (ms) | EC2 throughput (req/s) | Serverless throughput (req/s) | Throughput Δ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| W01 | 123.19 | 126.04 | +2.3% | 196.67 | 163.33 | 390.00 | 363.33 | 10.10 | 10.05 | -0.4% |
| W02 | 200.09 | 174.43 | -12.8% | 730.00 | 426.67 | 1326.67 | 733.33 | 26.70 | 27.59 | +3.3% |
| W03 | 341.52 | 325.82 | -4.6% | 720.00 | 570.00 | 1380.00 | 1276.67 | 43.72 | 40.00 | -8.5% |
| W04 | 225.00 | 152.77 | -32.1% | 400.00 | 300.00 | 563.33 | 513.33 | 51.78 | 59.26 | +14.5% |
| W05 | 290.49 | 168.64 | -41.9% | 396.67 | 340.00 | 723.33 | 676.67 | 44.04 | 57.39 | +30.3% |
| W06 | 572.17 | 544.83 | -4.8% | 996.67 | 1566.67 | 2373.33 | 4233.33 | 20.64 | 21.84 | +5.8% |

*Note: Values are descriptive means across three accepted formal repetitions. Δ is Serverless relative to EC2.*



## Table 4. Reliability Comparison

| Workload | EC2 failure rate (%) | Serverless failure rate (%) | Difference (percentage points) | EC2 failed requests | Serverless failed requests | EC2 successful requests | Serverless successful requests |
| --- | --- | --- | --- | --- | --- | --- | --- |
| W01 | 0.000 | 0.000 | +0.000 pp | 0 | 0 | 1766 | 1771 |
| W02 | 0.000 | 0.115 | +0.115 pp | 0 | 5 | 4679 | 4902 |
| W03 | 0.000 | 4.086 | +4.086 pp | 0 | 278 | 7744 | 7034 |
| W04 | 0.000 | 0.434 | +0.434 pp | 0 | 46 | 9226 | 10517 |
| W05 | 0.000 | 0.916 | +0.916 pp | 0 | 90 | 7845 | 9970 |
| W06 | 0.110 | 1.354 | +1.243 pp | 16 | 275 | 19598 | 21315 |

*Note: Failure-rate difference is expressed in percentage points.*



## Table 5. Estimated Cost Comparison

| Workload | EC2 estimated cost / trial (USD) | Serverless estimated cost / trial (USD) | EC2 cost / 1,000 success (USD) | Serverless cost / 1,000 success (USD) | Serverless vs EC2 cost Δ | Serverless / EC2 cost ratio |
| --- | --- | --- | --- | --- | --- | --- |
| W01 | 0.00047356 | 0.00087629 | 0.00080447 | 0.00148451 | +84.5% | 1.845 |
| W02 | 0.00047356 | 0.00205757 | 0.00031057 | 0.00129150 | +315.9% | 4.159 |
| W03 | 0.00047356 | 0.00352736 | 0.00019401 | 0.00178594 | +820.5% | 9.205 |
| W04 | 0.00047356 | 0.00512335 | 0.00015402 | 0.00146294 | +849.8% | 9.498 |
| W05 | 0.00284133 | 0.00427440 | 0.00122208 | 0.00129720 | +6.1% | 1.061 |
| W06 | 0.00236778 | 0.01199757 | 0.00046144 | 0.00169234 | +266.8% | 3.668 |

*Note: Costs use the frozen Task 25 AWS list-price methodology; Free Tier, credits and discounts are excluded.*



## Table 6. Three-Trial Summary and Variability

| Workload | Architecture | n | Latency mean ± SD (ms) | Latency min-max (ms) | P95 mean ± SD (ms) | Throughput mean ± SD (req/s) | Throughput min-max (req/s) | Failure rate mean ± SD (%) | Cost/1K mean ± SD (USD) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| W01 | EC2 | 3 | 123.19 ± 2.99 | 119.79–125.37 | 196.67 ± 25.17 | 10.10 ± 0.06 | 10.06–10.17 | 0.000 ± 0.000 | 0.00080447 ± 0.00000393 |
| W01 | Serverless | 3 | 126.04 ± 3.18 | 123.73–129.67 | 163.33 ± 25.17 | 10.05 ± 0.05 | 10.01–10.11 | 0.000 ± 0.000 | 0.00148451 ± 0.00003518 |
| W02 | EC2 | 3 | 200.09 ± 109.50 | 134.25–326.49 | 730.00 ± 840.77 | 26.70 ± 4.65 | 21.33–29.51 | 0.000 ± 0.000 | 0.00031057 ± 0.00005993 |
| W02 | Serverless | 3 | 174.43 ± 53.99 | 138.62–236.53 | 426.67 ± 297.71 | 27.59 ± 2.70 | 24.50–29.54 | 0.115 ± 0.199 | 0.00129150 ± 0.00053157 |
| W03 | EC2 | 3 | 341.52 ± 220.69 | 208.22–596.26 | 720.00 ± 675.80 | 43.72 ± 11.76 | 30.15–51.03 | 0.000 ± 0.000 | 0.00019401 ± 0.00006020 |
| W03 | Serverless | 3 | 325.82 ± 181.16 | 135.96–496.80 | 570.00 ± 547.45 | 40.00 ± 18.55 | 20.98–58.04 | 4.086 ± 4.286 | 0.00178594 ± 0.00123867 |
| W04 | EC2 | 3 | 225.00 ± 10.43 | 214.38–235.24 | 400.00 ± 55.68 | 51.78 ± 0.97 | 50.88–52.81 | 0.000 ± 0.000 | 0.00015402 ± 0.00000282 |
| W04 | Serverless | 3 | 152.77 ± 20.63 | 134.47–175.13 | 300.00 ± 147.31 | 59.26 ± 2.58 | 56.57–61.70 | 0.434 ± 0.118 | 0.00146294 ± 0.00007451 |
| W05 | EC2 | 3 | 290.49 ± 142.04 | 205.96–454.48 | 396.67 ± 210.79 | 44.04 ± 15.98 | 25.58–53.58 | 0.000 ± 0.000 | 0.00122208 ± 0.00056053 |
| W05 | Serverless | 3 | 168.64 ± 22.10 | 155.74–194.15 | 340.00 ± 121.24 | 57.39 ± 2.33 | 54.70–58.82 | 0.916 ± 0.782 | 0.00129720 ± 0.00034680 |
| W06 | EC2 | 3 | 572.17 ± 449.46 | 236.72–1082.85 | 996.67 ± 782.33 | 20.64 ± 13.59 | 6.24–33.24 | 0.110 ± 0.096 | 0.00046144 ± 0.00029170 |
| W06 | Serverless | 3 | 544.83 ± 250.63 | 307.47–806.90 | 1566.67 ± 503.32 | 21.84 ± 8.49 | 12.97–29.89 | 1.354 ± 1.024 | 0.00169234 ± 0.00005061 |

*Note: SD is sample standard deviation across n=3 trials. These descriptive statistics are not significance tests.*
