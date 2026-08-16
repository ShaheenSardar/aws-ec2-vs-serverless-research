# Formal Experiment Runner Protocol

Date: 2026-08-16

## Purpose

The formal experiment runner executes one frozen experiment ID at a time.

Runner:

`load-testing/run-formal-experiment.ps1`

## Input Sources

The runner reads:

- `docs/methodology/formal-experiment-matrix.csv`
- `load-testing/scenarios/formal-workloads.csv`
- `load-testing/locustfile.py`

It does not define new workload parameters.

## Experiment Identification

Formal experiment identifiers follow:

`ARCH-WXX-TXX`

Examples:

- `EC2-W01-T01`
- `SVL-W04-T03`

## Raw Data Separation

EC2:

`data/raw/formal/ec2/`

Serverless:

`data/raw/formal/serverless/`

Metadata:

`data/raw/formal/metadata/`

## No-Overwrite Rule

The runner refuses to execute an experiment if any formal output for that experiment ID already exists.

Formal raw evidence must never be overwritten.

## Status Transitions

Normal:

`PENDING -> RUNNING -> COMPLETED`

Infrastructure or runner problem:

`PENDING -> RUNNING -> ERROR`

HTTP/request failures recorded by Locust are experimental measurements and do not by themselves cause the experiment to be classified as a runner failure.

## UTC Timing

Each run records exact UTC start and end timestamps.

W05 additionally records:

- idle activity UTC
- idle start UTC
- idle end UTC

The formal workload start timestamp occurs after the controlled idle interval.

## W05 Idle-to-Burst Protocol

For W05 only:

1. Perform one `/health` activity.
2. Record idle start.
3. Wait exactly the frozen idle interval of 300 seconds.
4. Record idle end.
5. Begin the formal Locust workload.

This is an idle-to-burst experiment and does not assert that a Lambda cold start must occur.

## Reproducibility

Each metadata record stores:

- repository commit
- application commit
- Terraform commit
- formal runner commit
- Locust exit code
- workload parameters
- exact UTC timing

## Experimental Integrity

The runner stops for conditions such as:

- missing frozen input files
- duplicate experiment IDs
- missing workload definition
- existing formal output
- changed critical application/infrastructure/load-test code
- changed Lambda concurrency quota
- Locust/Python exceptions
- missing statistics files
- zero generated requests
- unexpected Locust process failure

Observed HTTP failures remain in the raw experimental dataset.
