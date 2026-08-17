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
