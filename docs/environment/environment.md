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
