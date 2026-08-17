Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# TASK 32 — FINAL REPRODUCIBILITY PACKAGE
# Windows PowerShell 5.1 compatible
# ============================================================

$Root = "E:\GKS Research\aws-ec2-vs-serverless-research"

if (-not (Test-Path $Root -PathType Container)) {
    throw "Repository root not found: $Root"
}

Set-Location $Root

$OutputDir   = ".\docs\reproducibility"
$OutputFile  = "$OutputDir\REPRODUCIBILITY.md"
$AuditFile   = ".\data\processed\formal\task32-reproducibility-audit.csv"
$ManifestFile = ".\data\processed\formal\task32-reproducibility-manifest.csv"

New-Item -ItemType Directory -Force $OutputDir | Out-Null
New-Item -ItemType Directory -Force ".\paper" | Out-Null

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $Absolute = [System.IO.Path]::GetFullPath(
        (Join-Path (Get-Location).Path $Path)
    )

    [System.IO.File]::WriteAllText(
        $Absolute,
        $Text,
        $Utf8NoBom
    )
}

function Add-AuditRow {
    param(
        [Parameter(Mandatory = $true)][string]$Check,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Actual
    )

    $Status = "FAIL"

    if ($Expected -eq $Actual) {
        $Status = "PASS"
    }

    [PSCustomObject]@{
        check    = $Check
        expected = $Expected
        actual   = $Actual
        status   = $Status
    }
}

# ============================================================
# 1. REQUIRED REPOSITORY STRUCTURE
# ============================================================

$RequiredFolders = @(
    "application",
    "terraform",
    "load-testing",
    "data",
    "analysis",
    "docs",
    "paper"
)

$Audit = @()

foreach ($Folder in $RequiredFolders) {
    $Exists = Test-Path ".\$Folder" -PathType Container

    $Actual = "MISSING"
    if ($Exists) {
        $Actual = "PRESENT"
    }

    $Audit += Add-AuditRow `
        -Check "directory_$Folder" `
        -Expected "PRESENT" `
        -Actual $Actual
}

# ============================================================
# 2. REQUIRED RESEARCH FILES
# ============================================================

$FormalData      = ".\data\final\experiments.csv"
$WorkloadFile    = ".\load-testing\scenarios\formal-workloads.csv"
$MatrixFile      = ".\docs\methodology\formal-experiment-matrix.csv"
$CalibrationFile = ".\docs\methodology\workload-calibration.md"
$SummaryFile     = ".\data\processed\formal\formal-summary-by-workload-architecture.csv"
$ComparisonFile  = ".\data\processed\formal\formal-architecture-comparison.csv"
$PricingFile     = ".\data\processed\formal\aws-pricing-snapshot.csv"

$RequiredFiles = @(
    $FormalData,
    $WorkloadFile,
    $MatrixFile,
    $CalibrationFile,
    $SummaryFile,
    $ComparisonFile,
    $PricingFile
)

foreach ($File in $RequiredFiles) {
    $Exists = Test-Path $File -PathType Leaf

    $Actual = "MISSING"
    if ($Exists) {
        $Actual = "PRESENT"
    }

    $Audit += Add-AuditRow `
        -Check ("file_" + ($File -replace '[\\./]', '_')) `
        -Expected "PRESENT" `
        -Actual $Actual
}

$MissingRequired = @(
    $RequiredFiles |
    Where-Object {
        -not (Test-Path $_ -PathType Leaf)
    }
)

if ($MissingRequired.Count -gt 0) {
    Write-Host ""
    Write-Host "TASK 32 STOPPED - REQUIRED FILES MISSING" -ForegroundColor Red
    $MissingRequired | ForEach-Object {
        Write-Host $_ -ForegroundColor Red
    }
    exit 1
}

# ============================================================
# 3. LOAD FORMAL SOURCES
# ============================================================

$Formal     = @(Import-Csv $FormalData)
$Workloads  = @(Import-Csv $WorkloadFile)
$Matrix     = @(Import-Csv $MatrixFile)
$Summary    = @(Import-Csv $SummaryFile)
$Comparison = @(Import-Csv $ComparisonFile)

$FormalCount     = $Formal.Count
$WorkloadCount   = $Workloads.Count
$MatrixCount     = $Matrix.Count
$SummaryCount    = $Summary.Count
$ComparisonCount = $Comparison.Count

$UniqueExperimentIds = @(
    $Formal.experiment_id |
    Sort-Object -Unique
).Count

$PilotRows = @(
    $Formal |
    Where-Object {
        $_.experiment_id -like "P-*"
    }
).Count

$Regions = @(
    $Formal.aws_region |
    Where-Object { $_ -ne $null -and $_ -ne "" } |
    Sort-Object -Unique
)

$IterationValues = @(
    $Formal.compute_iterations |
    Where-Object { $_ -ne $null -and $_ -ne "" } |
    Sort-Object -Unique
)

if ($Regions.Count -ne 1) {
    throw "Expected exactly one AWS region in formal data; found $($Regions.Count)."
}

if ($IterationValues.Count -ne 1) {
    throw "Expected exactly one compute-iteration value; found $($IterationValues.Count)."
}

$Region = [string]$Regions[0]
$ComputeIterations = [string]$IterationValues[0]

$Groups = @(
    $Formal |
    Group-Object -Property workload_id, architecture
)

$ThreeTrialGroups = @(
    $Groups |
    Where-Object {
        $_.Count -eq 3
    }
).Count

$BadGroups = @(
    $Groups |
    Where-Object {
        $_.Count -ne 3
    }
).Count

# ============================================================
# 4. DISCOVER REAL APPLICATION / COMPUTE FILES
# ============================================================

$ApplicationFiles = @(
    Get-ChildItem ".\application" `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue
)

$ComputeFiles = @(
    Get-ChildItem "." `
        -Recurse `
        -File `
        -Filter "compute_logic.py" `
        -ErrorAction SilentlyContinue
)

$ComputeLines = @()

foreach ($File in $ComputeFiles) {
    $Relative = $File.FullName.Substring($Root.Length).TrimStart("\")
    $Hash = (
        Get-FileHash $File.FullName -Algorithm SHA256
    ).Hash.ToLower()

    $ComputeLines += "- $Relative — SHA256: $Hash"
}

if ($ComputeLines.Count -eq 0) {
    $ComputeLines += "- No compute_logic.py file was discovered automatically."
}

# ============================================================
# 5. DISCOVER ANALYSIS SCRIPTS
# ============================================================

$AnalysisScripts = @(
    Get-ChildItem ".\analysis\scripts" `
        -File `
        -ErrorAction SilentlyContinue |
    Sort-Object Name
)

$AnalysisLines = @()

foreach ($Script in $AnalysisScripts) {
    $Relative = $Script.FullName.Substring($Root.Length).TrimStart("\")
    $AnalysisLines += "- $Relative"
}

if ($AnalysisLines.Count -eq 0) {
    $AnalysisLines += "- No analysis scripts discovered."
}

# ============================================================
# 6. WORKLOAD TABLE
# ============================================================

$WorkloadLines = @(
    "| ID | Workload | Users | Spawn rate (users/s) | Duration (s) | Idle before (s) |",
    "|---|---|---:|---:|---:|---:|"
)

foreach ($Row in $Workloads) {
    $WorkloadLines += (
        "| {0} | {1} | {2} | {3} | {4} | {5} |" -f `
            $Row.workload_id,
            $Row.workload_name,
            $Row.users,
            $Row.spawn_rate,
            $Row.duration_seconds,
            $Row.idle_before_seconds
    )
}

$ExperimentIds = @(
    $Formal.experiment_id |
    Sort-Object
)

# ============================================================
# 7. BUILD REPRODUCIBILITY DOCUMENT
# ============================================================

$Doc = @()

$Doc += "# Reproducibility and Data Availability"
$Doc += ""
$Doc += "## Study"
$Doc += ""
$Doc += "**Title:** Experimental Evaluation of EC2-Based and Serverless Architectures for Bursty Web Application Workloads on AWS: Performance, Scalability, and Cost Trade-offs"
$Doc += ""
$Doc += "This document records the configuration, experimental design, analysis procedure, limitations, and data-availability boundaries for the study."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 1. Repository Structure"
$Doc += ""
$Doc += "- application/ — application source and deterministic compute implementation."
$Doc += "- terraform/ — Infrastructure-as-Code for the EC2 and serverless environments."
$Doc += "- load-testing/ — Locust workload implementation, frozen workload definitions, and formal runner."
$Doc += "- data/ — raw, processed, and final experiment data."
$Doc += "- analysis/ — analysis, tables, figures, interpretation, and paper-generation scripts."
$Doc += "- docs/ — methodology, evidence, figures, tables, literature, results, and reproducibility documentation."
$Doc += "- paper/ — final publication-oriented artifacts."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 2. Exact AWS Region"
$Doc += ""
$Doc += "**AWS Region:** $Region"
$Doc += ""
$Doc += "All 36 formal dataset rows contain the same AWS region."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 3. AWS Resources"
$Doc += ""
$Doc += "### EC2 architecture"
$Doc += ""
$Doc += "- Amazon EC2 t3.small"
$Doc += "- Ubuntu 24.04"
$Doc += "- Flask application"
$Doc += "- Python virtual environment"
$Doc += "- Gunicorn with 3 workers"
$Doc += "- systemd service"
$Doc += "- Nginx reverse proxy"
$Doc += "- 8 GB encrypted gp3 EBS root storage"
$Doc += "- Public IPv4 HTTP endpoint"
$Doc += "- Amazon CloudWatch monitoring"
$Doc += ""
$Doc += "The EC2 application was installed directly into a Python virtual environment and run by Gunicorn under systemd behind Nginx. The formal EC2 deployment is therefore not described as Dockerized."
$Doc += ""
$Doc += "### Serverless architecture"
$Doc += ""
$Doc += "- Amazon API Gateway HTTP API"
$Doc += "- AWS Lambda"
$Doc += "- Python 3.12"
$Doc += "- x86_64"
$Doc += "- 1024 MB memory"
$Doc += "- Amazon CloudWatch monitoring"
$Doc += ""
$Doc += "The experimental AWS account exposed a concurrency quota of 10. This is an account-specific study constraint and is not presented as a general AWS Lambda scalability limit."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 4. Identical Compute Implementation"
$Doc += ""
$Doc += "Both architectures used the same deterministic CPU-bound /compute operation."
$Doc += ""
$Doc += "**Workload version:** sha256-v1"
$Doc += ""
$Doc += "**Configured compute iterations:** $ComputeIterations chained SHA-256 iterations per request."
$Doc += ""
$Doc += "Detected compute implementation files:"
$Doc += ""
$Doc += $ComputeLines
$Doc += ""
$Doc += "The study previously verified matching workload version, iteration count, and deterministic output across EC2 and Lambda before formal measurement."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 5. Frozen Workload Definitions"
$Doc += ""
$Doc += $WorkloadLines
$Doc += ""
$Doc += "The same Locust request behavior was used for both architectures; only the target host changed."
$Doc += ""
$Doc += "The generator used a closed-loop virtual-user model. Requests per second are therefore interpreted as achieved throughput under the frozen virtual-user workload rather than a separately fixed offered request rate."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 6. Repetitions and Formal Experiment IDs"
$Doc += ""
$Doc += "- Architectures: 2"
$Doc += "- Workloads: 6"
$Doc += "- Repetitions per architecture/workload condition: 3"
$Doc += "- Formal workload/architecture groups: $($Groups.Count)"
$Doc += "- Groups with exactly three trials: $ThreeTrialGroups"
$Doc += "- Total formal trials: $FormalCount"
$Doc += "- Unique formal experiment IDs: $UniqueExperimentIds"
$Doc += ""
$Doc += "Formal experiment IDs:"
$Doc += ""
foreach ($Id in $ExperimentIds) {
    $Doc += "- $Id"
}
$Doc += ""
$Doc += "Because n=3 per condition, the analysis is descriptive and does not make inferential statistical-significance claims."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 7. Pilot / Formal Separation"
$Doc += ""
$Doc += "Pilot calibration was completed before formal data collection and was used only to validate the generator, calibrate workload intensity, and identify experimental constraints."
$Doc += ""
$Doc += "**Pilot IDs present in final formal dataset:** $PilotRows"
$Doc += ""
$Doc += "The original higher-intensity sudden-burst pilot that encountered the account-specific Lambda concurrency quota was preserved as pilot evidence and excluded from the 36 formal trials."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 8. Analysis Procedure"
$Doc += ""
$Doc += "The formal analysis procedure was:"
$Doc += ""
$Doc += "1. Validate the final 36-trial dataset and experiment IDs."
$Doc += "2. Keep pilot and formal evidence separate."
$Doc += "3. Group observations by workload and architecture."
$Doc += "4. Compute equal-weight trial-level descriptive means."
$Doc += "5. Compute sample standard deviation using n-1."
$Doc += "6. Report trial-level P95/P99 summaries without claiming pooled request percentiles."
$Doc += "7. Compare achieved throughput, failure rate, and percentage-point reliability differences."
$Doc += "8. Extract CloudWatch metrics for the formal UTC query windows."
$Doc += "9. Model AWS list-price cost and normalize cost per 1,000 successful requests."
$Doc += "10. Generate publication tables and figures from formal data only."
$Doc += "11. Interpret workload-specific trade-offs without declaring a universal architecture winner."
$Doc += ""
$Doc += "Analysis scripts detected:"
$Doc += ""
$Doc += $AnalysisLines
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 9. Key Limitations"
$Doc += ""
$Doc += "- Only three formal repetitions were performed per condition."
$Doc += "- The EC2 baseline is specifically t3.small and should not be generalized to all EC2 configurations."
$Doc += "- The study used one AWS region."
$Doc += "- The application is a controlled deterministic CPU-bound web workload rather than a full production application."
$Doc += "- Locust used a closed-loop virtual-user model."
$Doc += "- The experimental account concurrency quota was 10; this must not be generalized as Lambda's normal scalability limit."
$Doc += "- W05 contains a 300-second idle interval but does not prove Lambda execution-environment eviction; it is an idle-to-burst workload, not a guaranteed cold-start experiment."
$Doc += "- CloudWatch values represent minute-level datapoints associated with requested formal UTC windows, not request-level telemetry."
$Doc += "- Cost values are AWS list-price estimates rather than exact per-trial invoice charges."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 10. Cost Reproducibility"
$Doc += ""
$Doc += "The cost model excludes Free Tier, credits, discounts, taxes, Savings Plans, and Reserved Instance discounts."
$Doc += ""
$Doc += "The normalized comparison metric is estimated cost per 1,000 successful requests."
$Doc += ""
$Doc += "Per-trial actual billing is not fabricated where exact AWS invoice attribution is unavailable."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 11. Data Availability and Private Repository Statement"
$Doc += ""
$Doc += "The processed experimental data and non-sensitive reproducibility materials supporting this study are provided as supplementary materials with the preprint."
$Doc += ""
$Doc += "The complete research repository is maintained privately because it also contains account-specific logs and security-sensitive configuration."
$Doc += ""
$Doc += "Raw or internal materials containing account identifiers, operational logs, credentials, or security-sensitive configuration are not intended for unrestricted public release."
$Doc += ""
$Doc += "Additional non-sensitive supporting materials may be obtained from the corresponding author upon reasonable request."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 12. Reproduction Boundaries"
$Doc += ""
$Doc += "A reproduction should preserve or explicitly document changes to: AWS region, architecture configuration, application logic, compute iteration count, workload definitions, concurrency, spawn rates, durations, W05 idle interval, repetitions, measurement method, analysis procedure, and pricing assumptions."
$Doc += ""
$Doc += "---"
$Doc += ""
$Doc += "## 13. Integrity Summary"
$Doc += ""
$Doc += "- Formal trials: $FormalCount"
$Doc += "- Unique experiment IDs: $UniqueExperimentIds"
$Doc += "- Frozen workload definitions: $WorkloadCount"
$Doc += "- Formal experiment matrix rows: $MatrixCount"
$Doc += "- Workload/architecture summary groups: $SummaryCount"
$Doc += "- Architecture comparisons: $ComparisonCount"
$Doc += "- Groups with exactly three trials: $ThreeTrialGroups"
$Doc += "- Pilot rows in final formal dataset: $PilotRows"
$Doc += "- AWS region: $Region"
$Doc += "- Compute iterations: $ComputeIterations"
$Doc += ""
$Doc += "This documentation was generated from repository artifacts rather than by manually re-entering result values."

$Document = $Doc -join [Environment]::NewLine
Write-Utf8NoBom -Path $OutputFile -Text $Document

# ============================================================
# 8. FINAL AUDIT
# ============================================================

$Audit += Add-AuditRow -Check "formal_trials" -Expected "36" -Actual "$FormalCount"
$Audit += Add-AuditRow -Check "unique_experiment_ids" -Expected "36" -Actual "$UniqueExperimentIds"
$Audit += Add-AuditRow -Check "formal_workloads" -Expected "6" -Actual "$WorkloadCount"
$Audit += Add-AuditRow -Check "formal_matrix_rows" -Expected "36" -Actual "$MatrixCount"
$Audit += Add-AuditRow -Check "summary_groups" -Expected "12" -Actual "$SummaryCount"
$Audit += Add-AuditRow -Check "architecture_comparisons" -Expected "6" -Actual "$ComparisonCount"
$Audit += Add-AuditRow -Check "formal_condition_groups" -Expected "12" -Actual "$($Groups.Count)"
$Audit += Add-AuditRow -Check "groups_with_three_trials" -Expected "12" -Actual "$ThreeTrialGroups"
$Audit += Add-AuditRow -Check "groups_with_wrong_trial_count" -Expected "0" -Actual "$BadGroups"
$Audit += Add-AuditRow -Check "pilot_rows_in_formal_dataset" -Expected "0" -Actual "$PilotRows"
$Audit += Add-AuditRow -Check "single_aws_region" -Expected "1" -Actual "$($Regions.Count)"
$Audit += Add-AuditRow -Check "single_compute_iteration_value" -Expected "1" -Actual "$($IterationValues.Count)"

$AppStatus = "EMPTY"
if ($ApplicationFiles.Count -gt 0) {
    $AppStatus = "PRESENT"
}
$Audit += Add-AuditRow -Check "application_files" -Expected "PRESENT" -Actual $AppStatus

$ComputeStatus = "MISSING"
if ($ComputeFiles.Count -gt 0) {
    $ComputeStatus = "PRESENT"
}
$Audit += Add-AuditRow -Check "compute_implementation_files" -Expected "PRESENT" -Actual $ComputeStatus

$DocumentStatus = "MISSING"
if (Test-Path $OutputFile -PathType Leaf) {
    $DocumentStatus = "PRESENT"
}
$Audit += Add-AuditRow -Check "reproducibility_document" -Expected "PRESENT" -Actual $DocumentStatus

$Audit |
    Export-Csv `
        $AuditFile `
        -NoTypeInformation `
        -Encoding UTF8

# ============================================================
# 9. SHA256 MANIFEST
# ============================================================

$ManifestPaths = @()
$ManifestPaths += $RequiredFiles
$ManifestPaths += $ComputeFiles.FullName
$ManifestPaths += $AnalysisScripts.FullName
$ManifestPaths += (
    Join-Path $Root "docs\reproducibility\REPRODUCIBILITY.md"
)

$PreprintPath = Join-Path $Root "docs\preprint\preprint.md"
if (Test-Path $PreprintPath -PathType Leaf) {
    $ManifestPaths += $PreprintPath
}

$ManifestPaths = @(
    $ManifestPaths |
    Sort-Object -Unique
)

$Manifest = @()

foreach ($PathValue in $ManifestPaths) {
    $AbsolutePath = $PathValue

    if (-not [System.IO.Path]::IsPathRooted($AbsolutePath)) {
        $AbsolutePath = Join-Path $Root $AbsolutePath
    }

    if (Test-Path $AbsolutePath -PathType Leaf) {
        $Relative = $AbsolutePath.Substring($Root.Length).TrimStart("\")
        $Hash = (
            Get-FileHash $AbsolutePath -Algorithm SHA256
        ).Hash.ToLower()

        $Manifest += [PSCustomObject]@{
            path   = $Relative
            sha256 = $Hash
        }
    }
}

$Manifest |
    Export-Csv `
        $ManifestFile `
        -NoTypeInformation `
        -Encoding UTF8

# ============================================================
# 10. DISPLAY FINAL RESULT
# ============================================================

$Failures = @(
    $Audit |
    Where-Object {
        $_.status -eq "FAIL"
    }
)

Clear-Host

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " DAY 2 - TASK 32 - FINAL REPRODUCIBILITY AUDIT" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

$Audit |
    Format-Table `
        check,
        expected,
        actual,
        status `
        -AutoSize

Write-Host ""
Write-Host "Repository / experiment summary"
Write-Host "-------------------------------"
Write-Host "AWS region                  : $Region"
Write-Host "Compute iterations          : $ComputeIterations"
Write-Host "Formal trials               : $FormalCount / 36"
Write-Host "Unique experiment IDs       : $UniqueExperimentIds / 36"
Write-Host "Frozen workloads            : $WorkloadCount / 6"
Write-Host "Three-trial groups          : $ThreeTrialGroups / 12"
Write-Host "Pilot rows in formal data   : $PilotRows"
Write-Host "Application files detected  : $($ApplicationFiles.Count)"
Write-Host "Compute implementations     : $($ComputeFiles.Count)"
Write-Host "Analysis scripts documented : $($AnalysisScripts.Count)"
Write-Host "Manifest entries            : $($Manifest.Count)"

if ($Failures.Count -eq 0) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host " TASK 32 PASSED" -ForegroundColor Green
    Write-Host " REPOSITORY STRUCTURE VERIFIED" -ForegroundColor Green
    Write-Host " EXACT AWS REGION DOCUMENTED" -ForegroundColor Green
    Write-Host " AWS RESOURCES DOCUMENTED" -ForegroundColor Green
    Write-Host " WORKLOAD DEFINITIONS DOCUMENTED" -ForegroundColor Green
    Write-Host " IDENTICAL COMPUTE IMPLEMENTATION DOCUMENTED" -ForegroundColor Green
    Write-Host " 36 / 36 EXPERIMENT IDS DOCUMENTED" -ForegroundColor Green
    Write-Host " 3 REPETITIONS PER CONDITION VERIFIED" -ForegroundColor Green
    Write-Host " PILOT / FORMAL SEPARATION VERIFIED" -ForegroundColor Green
    Write-Host " ANALYSIS PROCEDURE DOCUMENTED" -ForegroundColor Green
    Write-Host " LIMITATIONS DOCUMENTED" -ForegroundColor Green
    Write-Host " DATA AVAILABILITY STATEMENT DOCUMENTED" -ForegroundColor Green
    Write-Host " PRIVATE-REPOSITORY STATEMENT DOCUMENTED" -ForegroundColor Green
    Write-Host " SHA256 REPRODUCIBILITY MANIFEST CREATED" -ForegroundColor Green
    Write-Host " REPRODUCIBILITY PACKAGE READY" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Red
Write-Host " TASK 32 FAILED" -ForegroundColor Red
Write-Host " $($Failures.Count) AUDIT CHECK(S) FAILED" -ForegroundColor Red
Write-Host " FIX FAILED ITEMS BEFORE FINALIZING" -ForegroundColor Red
Write-Host "========================================================================" -ForegroundColor Red

exit 1
