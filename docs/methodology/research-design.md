# Frozen Experimental Research Design

## Research Title

Experimental Evaluation of EC2-Based and Serverless Architectures for Bursty Web Application Workloads on AWS: Performance, Scalability, and Cost Trade-offs

## Main Research Question

How do fixed-capacity EC2-based and on-demand serverless AWS architectures differ in performance, scalability behavior, reliability, and cost when serving the same lightweight web application under normal and bursty workloads?

## Architectures

### EC2

Fixed-capacity EC2

Nginx

Gunicorn

Python/Flask

No Auto Scaling

No Load Balancer

### Serverless

API Gateway HTTP API

AWS Lambda

Python 3.12

No Provisioned Concurrency

## AWS Region

ap-south-1

## Independent Variables

- Architecture
- Workload

## Dependent Variables

- Average latency
- Median latency
- p95 latency
- p99 latency
- Throughput
- Failure rate
- EC2 utilization
- Lambda duration
- Lambda concurrency
- Lambda throttles
- API Gateway errors
- Cost

## Formal Workloads

W01 - Low

W02 - Moderate

W03 - High

W04 - Burst

W05 - Idle-to-Burst

W06 - Sustained

## Trial Count

3 trials per workload per architecture.

Total formal trials = 36.

## Formal Experiment Naming

EC2-WXX-TXX

SVL-WXX-TXX

## Pilot Naming

P-EC2-WXX-XX

P-SVL-WXX-XX

## Data Integrity Rule

Pilot results will not be mixed with formal experimental results.

Raw experimental files will never be manually modified.

Formal workloads will be frozen after pilot calibration.

---

Design status: PRE-FORMAL FREEZE

Date: 2026-08-16
