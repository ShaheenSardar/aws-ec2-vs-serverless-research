# Formal Results Interpretation

## Interpretation scope

The following interpretation uses only the 36 accepted formal trials.
Each workload/architecture condition contains three repetitions (n=3).
The comparisons are therefore descriptive and are interpreted together
with the observed variability. No statistical-significance claim is
made from these three-trial groups.

Performance, reliability, resource behavior, and estimated cost are
treated as separate dimensions. An architecture is not declared
universally superior simply because it performs better on one metric.

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

## W01 — Low

Across the three formal repetitions, EC2 recorded a mean average latency of 123.19 ms, compared with 126.04 ms for Serverless. Serverless was 2.3% higher than EC2 for average latency. Mean P95 latency was 196.67 ms for EC2 and 163.33 ms for Serverless; Serverless was 16.9% lower than EC2 for P95 latency. Mean P99 latency was 390.00 ms for EC2 and 363.33 ms for Serverless.

EC2 achieved 10.10 requests/s and Serverless achieved 10.05 requests/s. Achieved throughput was effectively similar (0.4% difference). The mean failure rates were 0.000% for EC2 and 0.000% for Serverless, a Serverless-minus-EC2 difference of +0.000 percentage points.

Estimated cost per 1,000 successful requests was $0.000804 for EC2 and $0.001485 for Serverless. Serverless cost per 1,000 successful requests was 84.5% higher than EC2 (1.85x). The performance result was mixed: neither architecture dominated the measured speed metrics. Reliability was equivalent in the measured trials, while EC2 retained the lower estimated cost.

Resource/quota context: Peak ConcurrentExecutions remained below the experimental account quota (10). Any observed failures in this condition should not be attributed to reaching that quota.

## W02 — Moderate

Across the three formal repetitions, EC2 recorded a mean average latency of 200.09 ms, compared with 174.43 ms for Serverless. Serverless was 12.8% lower than EC2 for average latency. Mean P95 latency was 730.00 ms for EC2 and 426.67 ms for Serverless; Serverless was 41.6% lower than EC2 for P95 latency. Mean P99 latency was 1326.67 ms for EC2 and 733.33 ms for Serverless.

EC2 achieved 26.70 requests/s and Serverless achieved 27.59 requests/s. Serverless achieved 3.3% higher throughput than EC2. The mean failure rates were 0.000% for EC2 and 0.115% for Serverless, a Serverless-minus-EC2 difference of +0.115 percentage points.

Estimated cost per 1,000 successful requests was $0.000311 for EC2 and $0.001291 for Serverless. Serverless cost per 1,000 successful requests was 315.9% higher than EC2 (4.16x). The observed performance profile favored Serverless on most speed-related metrics. Serverless therefore provided a performance advantage under this workload, but that advantage was accompanied by higher failure rate and higher estimated cost per successful request.

Resource/quota context: ConcurrentExecutions reached the experimental account quota (10) and CloudWatch recorded 5 throttles. The observed throttling is therefore consistent with the account-specific concurrency constraint.

## W03 — High

Across the three formal repetitions, EC2 recorded a mean average latency of 341.52 ms, compared with 325.82 ms for Serverless. Serverless was 4.6% lower than EC2 for average latency. Mean P95 latency was 720.00 ms for EC2 and 570.00 ms for Serverless; Serverless was 20.8% lower than EC2 for P95 latency. Mean P99 latency was 1380.00 ms for EC2 and 1276.67 ms for Serverless.

EC2 achieved 43.72 requests/s and Serverless achieved 40.00 requests/s. Serverless achieved 8.5% lower throughput than EC2. The mean failure rates were 0.000% for EC2 and 4.086% for Serverless, a Serverless-minus-EC2 difference of +4.086 percentage points.

Estimated cost per 1,000 successful requests was $0.000194 for EC2 and $0.001786 for Serverless. Serverless cost per 1,000 successful requests was 820.5% higher than EC2 (9.21x). The observed performance profile favored Serverless on most speed-related metrics. Serverless therefore provided a performance advantage under this workload, but that advantage was accompanied by higher failure rate and higher estimated cost per successful request.

Resource/quota context: ConcurrentExecutions reached the experimental account quota (10) and CloudWatch recorded 240 throttles. The observed throttling is therefore consistent with the account-specific concurrency constraint.

## W04 — Sudden Burst

Across the three formal repetitions, EC2 recorded a mean average latency of 225.00 ms, compared with 152.77 ms for Serverless. Serverless was 32.1% lower than EC2 for average latency. Mean P95 latency was 400.00 ms for EC2 and 300.00 ms for Serverless; Serverless was 25.0% lower than EC2 for P95 latency. Mean P99 latency was 563.33 ms for EC2 and 513.33 ms for Serverless.

EC2 achieved 51.78 requests/s and Serverless achieved 59.26 requests/s. Serverless achieved 14.5% higher throughput than EC2. The mean failure rates were 0.000% for EC2 and 0.434% for Serverless, a Serverless-minus-EC2 difference of +0.434 percentage points.

Estimated cost per 1,000 successful requests was $0.000154 for EC2 and $0.001463 for Serverless. Serverless cost per 1,000 successful requests was 849.8% higher than EC2 (9.50x). The observed performance profile favored Serverless on most speed-related metrics. Serverless therefore provided a performance advantage under this workload, but that advantage was accompanied by higher failure rate and higher estimated cost per successful request.

Resource/quota context: ConcurrentExecutions reached the experimental account quota (10) and CloudWatch recorded 46 throttles. The observed throttling is therefore consistent with the account-specific concurrency constraint.

## W05 — Idle-to-Burst

Across the three formal repetitions, EC2 recorded a mean average latency of 290.49 ms, compared with 168.64 ms for Serverless. Serverless was 41.9% lower than EC2 for average latency. Mean P95 latency was 396.67 ms for EC2 and 340.00 ms for Serverless; Serverless was 14.3% lower than EC2 for P95 latency. Mean P99 latency was 723.33 ms for EC2 and 676.67 ms for Serverless.

EC2 achieved 44.04 requests/s and Serverless achieved 57.39 requests/s. Serverless achieved 30.3% higher throughput than EC2. The mean failure rates were 0.000% for EC2 and 0.916% for Serverless, a Serverless-minus-EC2 difference of +0.916 percentage points.

Estimated cost per 1,000 successful requests was $0.001222 for EC2 and $0.001297 for Serverless. Estimated cost efficiency was relatively close: Serverless was +6.1% relative to EC2 (1.06x EC2 cost per 1,000 successes). The observed performance profile favored Serverless on most speed-related metrics. Serverless therefore provided a performance advantage under this workload, but that advantage was accompanied by higher failure rate and higher estimated cost per successful request.

Resource/quota context: ConcurrentExecutions reached the experimental account quota (10) and CloudWatch recorded 90 throttles. The observed throttling is therefore consistent with the account-specific concurrency constraint.

## W06 — Sustained

Across the three formal repetitions, EC2 recorded a mean average latency of 572.17 ms, compared with 544.83 ms for Serverless. Serverless was 4.8% lower than EC2 for average latency. Mean P95 latency was 996.67 ms for EC2 and 1566.67 ms for Serverless; Serverless was 57.2% higher than EC2 for P95 latency. Mean P99 latency was 2373.33 ms for EC2 and 4233.33 ms for Serverless.

EC2 achieved 20.64 requests/s and Serverless achieved 21.84 requests/s. Serverless achieved 5.8% higher throughput than EC2. The mean failure rates were 0.110% for EC2 and 1.354% for Serverless, a Serverless-minus-EC2 difference of +1.243 percentage points.

Estimated cost per 1,000 successful requests was $0.000461 for EC2 and $0.001692 for Serverless. Serverless cost per 1,000 successful requests was 266.8% higher than EC2 (3.67x). The performance result was mixed: neither architecture dominated the measured speed metrics. The workload demonstrates a multi-metric trade-off, so an overall winner should not be inferred from a single performance or cost measure.

Resource/quota context: ConcurrentExecutions reached the experimental account quota (10) and CloudWatch recorded 263 throttles. The observed throttling is therefore consistent with the account-specific concurrency constraint.

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
