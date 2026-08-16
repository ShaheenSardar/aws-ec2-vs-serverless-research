# Formal Runner Correction Record

Date: 2026-08-16

## Affected Experiment

EC2-W01-T01

## Status

The first attempted execution of EC2-W01-T01 was not accepted as a
formal experimental observation.

## Cause

The formal runner used PowerShell ErrorActionPreference=Stop while
capturing Locust native stderr with 2>&1.

Locust writes normal informational logging to stderr. PowerShell
therefore treated the initial Locust informational message as a
terminating runner error before the runner could complete its normal
validation sequence.

## Scientific Treatment

The attempt was classified as an instrumentation/runner failure, not as
an EC2 performance result.

No values from this invalid attempt are included in the final formal
dataset.

Any files created by the invalid attempt were preserved under:

data/raw/formal/invalid-attempts/EC2-W01-T01_runner-stderr-error/

The experiment matrix was restored from ERROR to PENDING only after the
failed attempt had been archived and documented.

## Runner Correction

The Locust native-command invocation now temporarily prevents normal
native stderr output from becoming a terminating PowerShell error.

Formal validity continues to be determined from:

- Locust process exit code
- presence of required CSV evidence
- Locust exception records
- generated request count
- infrastructure health

HTTP/request failures remain experimental data and are not hidden.

## Workload Integrity

No workload parameter, application computation, EC2 configuration,
Lambda configuration, or experimental condition was changed as part of
this correction.
