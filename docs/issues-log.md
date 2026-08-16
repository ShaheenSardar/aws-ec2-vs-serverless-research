# Research Issues Log

Research Status: PRE-FORMAL EXPERIMENT PREPARATION

Created: 2026-08-16

## Purpose

This document records infrastructure, configuration, and experimental issues encountered during the research.

Issues are documented rather than silently corrected.

## Issue Summary

| Issue ID | Date | Component | Problem | Resolution | Experimental Impact |
|----------|------|-----------|---------|------------|---------------------|
| INF-001 | 2026-08-16 | Terraform Provider | AWS provider download was interrupted | Official archive was resumed, SHA-256 verified, and Terraform initialization completed | None; formal experiments had not started |
| INF-002 | 2026-08-16 | Terraform CLI | Terraform command was executed from the repository root | Commands were rerun from terraform/ec2 | None; no infrastructure changes occurred |
| INF-003 | 2026-08-16 | Terraform Saved Plan | Saved plan became stale | Old plan was removed and a fresh reconciliation plan was generated | None; no formal measurements were affected |

---

## INF-001 — Terraform Provider Download Interrupted

### Symptom

Terraform initialization repeatedly failed while downloading the HashiCorp AWS provider.

### Diagnosis

DNS and HTTPS connectivity were available, but the large provider archive download was interrupted before completion.

The incomplete archive failed SHA-256 integrity verification.

### Resolution

The official HashiCorp AWS provider archive was downloaded using resumable transfer.

Completed archive size:

    192547309 bytes

Expected SHA-256:

    CB349F8A43653BFC78867909D6342C56073F9805BDBD9DC32A8E1D18302257D4

Actual SHA-256:

    CB349F8A43653BFC78867909D6342C56073F9805BDBD9DC32A8E1D18302257D4

Integrity verification result:

    PASS

Terraform initialization subsequently completed successfully with AWS provider version 6.60.0.

### Experimental Impact

No formal experiments had begun.

No experimental data was affected.

---

## INF-002 — Terraform Command Executed From Wrong Directory

### Symptom

Terraform returned:

    Error: No configuration files

### Diagnosis

terraform plan was executed from the repository root instead of the EC2 Terraform root module.

Correct working directory:

    terraform/ec2

### Resolution

Terraform commands were rerun from the correct EC2 Terraform directory.

### Experimental Impact

No AWS resources were created, changed, or destroyed by the failed command.

No formal experimental data was affected.

---

## INF-003 — Terraform Saved Plan Became Stale

### Symptom

A previously generated Terraform saved plan was no longer current.

### Diagnosis

Saved Terraform plans represent configuration and state at the time they are generated.

### Resolution

The old saved plan was removed and Terraform was run again against the current configuration and state.

Final reconciliation result:

    No changes. Your infrastructure matches the configuration.

### Experimental Impact

No infrastructure drift was introduced.

No formal experimental measurements were affected.

---

## Current EC2 Infrastructure Status

Terraform configuration validation:

    PASS

Terraform state reconciliation:

    No changes. Your infrastructure matches the configuration.

Application verification:

    /health  -> successful
    /compute -> successful

Formal workload measurements have not yet begun.
