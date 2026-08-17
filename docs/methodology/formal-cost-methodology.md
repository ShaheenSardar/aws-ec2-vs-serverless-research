# Formal Cost Analysis Methodology

Date: 2026-08-16
Region: ap-south-1 (Asia Pacific - Mumbai)

## Pricing Basis

Cost estimates use current AWS public On-Demand/list prices.

AWS Free Tier, promotional credits, Savings Plans, Reserved Instances,
organization-specific discounts, taxes, and account credits are excluded
from the comparative estimate.

Pricing evidence is retrieved using the AWS Price List API and preserved
with the research artifacts.

## EC2 Cost

For EC2 trials the allocated cost contains:

1. t3.small Linux On-Demand compute
2. Attached gp3 EBS storage
3. One in-use public IPv4 address when the experiment instance actually
   has a public IPv4 address

For W01-W04:
allocated interval = 60 seconds

For W05 Idle-to-Burst:
allocated interval = 300-second controlled idle + 60-second measurement
                   = 360 seconds

The EC2 resource remains allocated during the controlled idle interval,
so this time is included.

For W06:
allocated interval = 300 seconds

The calculation allocates the continuously running infrastructure price
proportionally to each controlled experiment interval. Costs between
formal experiment intervals are not assigned to any individual trial.

gp3 baseline IOPS and throughput are included in the storage price.
The cost script stops if the attached gp3 configuration exceeds baseline
performance instead of silently omitting additional IOPS/throughput cost.

## Serverless Cost

For Serverless trials the estimate contains:

1. AWS Lambda billed requests
2. AWS Lambda compute GB-seconds
3. Amazon API Gateway HTTP API requests

Lambda billed requests use the measured Lambda Invocations value.

Lambda compute is estimated as:

Invocations
x average Lambda Duration
x allocated memory in GB
x current Lambda x86 GB-second rate

API Gateway request cost uses the measured API Gateway Count value.

There is no serverless compute allocation charge during W05's 300-second
idle period.

The single pre-idle /health control request used by W05 is treated as
experimental instrumentation and excluded from comparative workload cost.

## Explicit Exclusions

The following are not included in per-trial comparative cost:

- AWS Free Tier and credits
- taxes
- CloudWatch research instrumentation/monitoring
- Systems Manager research tooling
- Git/GitHub costs
- client/load-generator cost
- Internet data-transfer charges
- protocol health-check instrumentation
- T3 surplus CPU-credit charges unless separately attributable

These exclusions must be stated as limitations.

## actual_cost_usd

AWS billing data does not reliably attribute an exact invoice amount to
each individual 60-second or 300-second formal experiment across EC2,
Lambda, and API Gateway.

Therefore:

actual_cost_usd = NOT_DIRECTLY_ATTRIBUTABLE

No actual dollar amount is fabricated.

## estimated_cost_usd

This field contains the reproducible list-price estimate calculated from
the experiment's measured usage and allocated infrastructure interval.

## cost_per_1000_successful_requests_usd

Calculated as:

estimated_cost_usd
/ successful_requests
x 1000

## Interpretation

Cost values are architecture-comparison estimates, not reconstructed AWS
invoice line items.
