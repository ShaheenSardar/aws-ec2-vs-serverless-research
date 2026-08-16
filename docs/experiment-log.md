# Experimental Activity Log

Research Title:
Experimental Evaluation of EC2-Based and Serverless Architectures for Bursty Web Application Workloads on AWS: Performance, Scalability, and Cost Trade-offs

Research Status: PRE-FORMAL EXPERIMENT PREPARATION

AWS Region: ap-south-1

Created: 2026-08-16

---

## Purpose

This log records significant experimental activities performed during the research project.

Pilot calibration activities and formal experimental trials must be clearly distinguished.

Formal measurements must not be entered retrospectively without documentation.

---

## Activity Log

| Date | Phase | Activity | Result | Evidence |
|------|-------|----------|--------|----------|


---

## Day 1 - Serverless Architecture Deployment Verification

Date: 2026-08-16

Architecture: AWS API Gateway HTTP API + AWS Lambda

Region: ap-south-1

Lambda runtime: Python 3.12

Lambda architecture: x86_64

Lambda memory: 1024 MB

Provisioned concurrency: disabled

### Verification Results

- Serverless /health endpoint returned healthy.
- Serverless /compute endpoint executed successfully.
- Workload version: sha256-v1.
- Computation iterations: 25000.
- EC2 and Serverless workload versions matched.
- EC2 and Serverless iteration counts matched.
- EC2 and Serverless deterministic computation results matched.
- Final Terraform plan reported no infrastructure drift.

### Equivalence Result

SameWorkloadVersion: True

SameIterations: True

SameResult: True

Formal workload measurements have not yet begun.
