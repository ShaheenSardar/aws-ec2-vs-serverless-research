# Related Work Writing Plan

## 1. Serverless Computing and FaaS

Introduce serverless/FaaS as a cloud execution model in which
infrastructure provisioning and scaling responsibilities are shifted
toward the cloud provider.

Primary citations:
- Hellerstein et al. (2019)
- Wang et al. (2018)
- Adzic and Chatley (2017)

Do not claim that serverless means that servers do not exist.

---

## 2. Serverless Platform Architecture and Resource Management

Discuss the use of lightweight isolation, dynamic execution
environments, automatic provisioning, and platform-managed scaling.

Primary citations:
- Wang et al. (2018)
- Agache et al. (2020)
- Akkus et al. (2018)

AWS-specific implementation facts:
- AWS Lambda scaling documentation
- AWS Lambda execution-environment documentation

---

## 3. Cold Starts and Latency Variability

Discuss initialization overhead and the distinction between cold and
warm execution environments.

Primary citations:
- Wang et al. (2018)
- Boucher et al. (2018)
- Shahrad et al. (2020)

AWS-specific definition:
- AWS Lambda execution-environment lifecycle documentation

Important:
The present study's W05 idle-to-burst workload must not automatically
be described as a cold-start experiment because an idle interval does
not prove that Lambda discarded the previous execution environment.

---

## 4. Scalability and Bursty Workloads

Explain why serverless architectures are attractive for irregular,
elastic, and bursty request patterns, while also noting that scaling
behavior can be affected by platform and account constraints.

Primary citations:
- Wang et al. (2018)
- Shahrad et al. (2020)
- SAND (Akkus et al., 2018)

AWS-specific scaling:
- AWS Lambda scaling documentation

Important:
The concurrency quota of 10 observed in this experiment is an
account-specific experimental constraint. It is not a general AWS
Lambda scalability limit.

---

## 5. Performance, Throughput, and Tail Latency

Explain why average latency alone is insufficient and why tail metrics
such as P95 and P99 are important.

Primary citations:
- Dean and Barroso (2013)
- Wang et al. (2018)
- Shillaker and Pietzuch (2020)
- Kotni et al. (2021)

The present study reports:
- mean latency
- median latency
- P95
- P99
- achieved throughput
- failure rate

---

## 6. Serverless versus Serverful Performance

Previous research shows that serverless suitability is workload
dependent rather than universally superior.

Primary citations:
- Savi et al. (2022)
- Wang et al. (2018)
- Jackson and Clynch (2018)

The present experiment differs by executing the same CPU-bound web
application logic under a frozen workload matrix across EC2 and an
AWS API Gateway + Lambda architecture.

Avoid claiming novelty solely from this distinction unless a more
systematic literature review confirms that no equivalent study exists.

---

## 7. Cost Modeling and Economic Trade-offs

Contrast continuously provisioned VM capacity with usage-granular
serverless billing.

Primary citations:
- Adzic and Chatley (2017)
- Lin et al. (2023)
- Jackson and Clynch (2018)

Official AWS cost definitions:
- AWS Lambda Pricing
- EC2 On-Demand documentation
- API Gateway Pricing

The current study uses list-price estimates and excludes Free Tier,
credits, discounts, and account-specific benefits.

---

## 8. EC2 Burstable Instance Context

The experimental EC2 architecture uses t3.small, which belongs to the
T3 burstable-performance family.

Primary platform citation:
- AWS EC2 burstable-performance documentation

This should be acknowledged in methodology and threats to validity
because CPU-credit behavior is a property of the chosen EC2 instance
class.

---

## 9. Related-Work Gap

The selected literature demonstrates substantial research on:

- FaaS architectures
- cold starts
- serverless scaling
- production FaaS workloads
- serverless resource management
- tail latency
- serverless cost modeling
- workload-dependent serverless/serverful trade-offs

The present study contributes a controlled empirical comparison using
identical application-level computation across EC2 and AWS Serverless,
six frozen workload profiles, three formal repetitions per condition,
performance metrics, reliability metrics, CloudWatch resource metrics,
and a reproducible list-price cost model.

This wording describes the study's positioning without making an
unsupported claim that no previous study has ever used a similar
experimental design.
