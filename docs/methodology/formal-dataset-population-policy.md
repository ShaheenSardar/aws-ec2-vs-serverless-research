# Formal Dataset Population Policy

Date: 2026-08-16

## Scope

This policy governs population of:

`data/final/experiments.csv`

Only accepted formal experiment evidence is used.

Pilot results and archived invalid attempts are excluded.

## Locust Measurements

For each experiment, the `/compute` row from the corresponding
`*_stats.csv` file is used.

Fields populated directly from Locust:

- total requests
- failed requests
- average latency
- median latency
- p95 latency
- p99 latency
- minimum latency
- maximum latency
- requests per second

Successful requests are calculated as:

`total_requests - failed_requests`

Failure rate is calculated as:

`failed_requests / total_requests * 100`

## UTC Timing

`run_start_utc` and `run_end_utc` are copied directly from the accepted
formal metadata file for the experiment.

## EC2 CloudWatch Aggregation

For EC2 trials:

- CPUUtilization Average:
  arithmetic mean of returned one-minute Average datapoints

- CPUUtilization Maximum:
  maximum of returned one-minute Maximum datapoints

- NetworkIn:
  sum of returned one-minute Sum datapoints

- NetworkOut:
  sum of returned one-minute Sum datapoints

- StatusCheckFailed:
  maximum of returned one-minute Maximum datapoints

## Lambda CloudWatch Aggregation

For Serverless trials:

- Invocations:
  sum

- Duration:
  invocation-weighted mean of returned one-minute Average datapoints

- Errors:
  sum

- Throttles:
  sum

- ConcurrentExecutions:
  maximum

## API Gateway CloudWatch Aggregation

For Serverless trials:

- Count:
  sum

- 4xx:
  sum

- 5xx:
  sum

- Latency:
  request-count-weighted mean

- IntegrationLatency:
  request-count-weighted mean

CloudWatch metrics are based on the one-minute datapoints returned for
the formal run's requested UTC query window.

## Architecture-Specific Fields

For EC2 rows, Lambda and API Gateway fields are:

`NOT_APPLICABLE`

For Serverless rows, EC2-specific fields are:

`NOT_APPLICABLE`

A numeric zero is used only when it was actually returned or derived
from measured evidence.

## Cost Fields

The following fields remain `TO_BE_MEASURED` until the cost-analysis
task is completed:

- actual_cost_usd
- estimated_cost_usd
- cost_per_1000_successful_requests_usd

## Reproducibility

Application and Terraform commit hashes are copied from each accepted
formal metadata record.

No experimental value is manually entered into the final dataset.
