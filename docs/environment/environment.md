# Experimental Environment

Date: 2026-08-16

AWS Region: ap-south-1

## Local Workload Generator

Operating System: Windows

AWS CLI: aws-cli/2.36.8 Python/3.14.6 Windows/11 exe/AMD64

Terraform: Terraform v1.15.8

Python: Python 3.12.10

Git: git version 2.52.0.windows.1

Pip: pip 25.0.1 from C:\Users\Eagle\AppData\Local\Programs\Python\Python312\Lib\site-packages\pip (python 3.12)

## AWS Authentication

AWS CLI authentication was verified successfully using AWS STS before infrastructure deployment.

AWS account identifiers and authentication details are intentionally excluded from this document for security and privacy.

## Planned AWS Experiment Configuration

EC2 operating system: Ubuntu 24.04 LTS

EC2 instance class: t3.small

Lambda runtime: Python 3.12

Lambda architecture: x86_64

Lambda memory: 1024 MB

## Reproducibility Notes

The AWS Region is fixed to ap-south-1 for the experiment.

The exact Terraform AWS provider version will be recorded in the committed .terraform.lock.hcl file after Terraform initialization.

Infrastructure-specific identifiers such as AWS account IDs, access credentials, resource ARNs containing account identifiers, and secret values must not be included in public research evidence.

Environment status: PRE-DEPLOYMENT VERIFIED

## Load Testing Environment

- Locust: locust 2.46.3 from E:\GKS Research\aws-ec2-vs-serverless-research\.venv\Lib\site-packages\locust (Python 3.12.10)
- Load generator: Local Windows workstation
- Shared workload script: load-testing/locustfile.py
- Target architectures: AWS EC2 and AWS Lambda/API Gateway

### Locust Smoke-Test Validation

Before pilot experiments, the shared Locust workload was tested against both architectures.

- EC2 smoke test: PASS
- Serverless smoke test: PASS
- Locust users: 5
- Spawn rate: 1 user/second
- Duration: 20 seconds
- Endpoint: /compute
- EC2 failures: 0
- Serverless failures: 0
- Purpose: tooling and endpoint validation only
- Status: NON-FORMAL TEST — excluded from experimental results

The same `load-testing/locustfile.py` is used for both architectures. Only the target host changes.

### Lambda Concurrency Constraint Discovered During Pilot Calibration

- Regional account concurrency quota: 10 concurrent executions
- Unreserved concurrency: 10
- Function reserved concurrency: not configured
- Original P-W04 candidate: 50 users, 50 users/second
- Original serverless P-W04 result: 405 HTTP 503 failures
- Lambda Errors: 0
- Lambda Throttles observed: 413
- Maximum ConcurrentExecutions observed: 10
- Interpretation: original burst workload reached the AWS account-level Lambda concurrency quota.
- Action: original P-W04 retained as pilot evidence only and excluded from formal results.
- Revised pilot candidate: P-W04R1, 30 users, 30 users/second, 60 seconds.
