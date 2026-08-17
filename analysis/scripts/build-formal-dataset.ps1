Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path ".").Path

$FinalPath = Join-Path $RepoRoot "data\final\experiments.csv"
$BackupPath = Join-Path $RepoRoot "data\processed\formal\experiments-template-before-task24.csv"
$AuditPath = Join-Path $RepoRoot "data\processed\formal\task24-population-audit.csv"
$CloudWatchPath = Join-Path $RepoRoot "data\processed\formal\cloudwatch-datapoints.csv"
$QueryLogPath = Join-Path $RepoRoot "data\processed\formal\cloudwatch-query-log.csv"
$MatrixPath = Join-Path $RepoRoot "docs\methodology\formal-experiment-matrix.csv"
$MetadataDir = Join-Path $RepoRoot "data\raw\formal\metadata"
$Ec2Dir = Join-Path $RepoRoot "data\raw\formal\ec2"
$SvlDir = Join-Path $RepoRoot "data\raw\formal\serverless"

$Culture = [Globalization.CultureInfo]::InvariantCulture

function Parse-Number {
    param(
        [string]$Value,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing numeric value: $Label"
    }

    return [double]::Parse(
        $Value,
        [Globalization.NumberStyles]::Float,
        $Culture
    )
}

function Format-Number {
    param([double]$Value)

    return $Value.ToString(
        "0.######",
        $Culture
    )
}

function Get-CWRows {
    param(
        [string]$ExperimentId,
        [string]$Service,
        [string]$Metric,
        [string]$Statistic
    )

    $Rows = @(
        $script:CloudWatch |
        Where-Object {
            $_.experiment_id -eq $ExperimentId -and
            $_.service -eq $Service -and
            $_.metric_name -eq $Metric -and
            $_.statistic -eq $Statistic -and
            $_.datapoint_status -eq "RETURNED"
        }
    )

    if ($Rows.Count -eq 0) {
        throw "No CloudWatch datapoints: $ExperimentId / $Service / $Metric / $Statistic"
    }

    return $Rows
}

function Get-SumValue {
    param(
        [object[]]$Rows,
        [string]$Label
    )

    $Total = 0.0

    foreach ($Row in $Rows) {
        $Total += Parse-Number $Row.value $Label
    }

    return $Total
}

function Get-MaxValue {
    param(
        [object[]]$Rows,
        [string]$Label
    )

    $Values = @()

    foreach ($Row in $Rows) {
        $Values += Parse-Number $Row.value $Label
    }

    return ($Values | Measure-Object -Maximum).Maximum
}

function Get-AverageValue {
    param(
        [object[]]$Rows,
        [string]$Label
    )

    $Values = @()

    foreach ($Row in $Rows) {
        $Values += Parse-Number $Row.value $Label
    }

    return ($Values | Measure-Object -Average).Average
}

function Get-WeightedAverage {
    param(
        [object[]]$AverageRows,
        [object[]]$CountRows,
        [string]$Label
    )

    $Weights = @{}

    foreach ($Row in $CountRows) {
        $Weights[$Row.datapoint_utc] =
            Parse-Number $Row.value "$Label weight"
    }

    $WeightedTotal = 0.0
    $TotalWeight = 0.0

    foreach ($Row in $AverageRows) {

        if (-not $Weights.ContainsKey($Row.datapoint_utc)) {
            throw "Missing matching count datapoint for $Label at $($Row.datapoint_utc)"
        }

        $Value = Parse-Number $Row.value $Label
        $Weight = $Weights[$Row.datapoint_utc]

        $WeightedTotal += ($Value * $Weight)
        $TotalWeight += $Weight
    }

    if ($TotalWeight -le 0) {
        throw "Zero total weight for $Label"
    }

    return ($WeightedTotal / $TotalWeight)
}

function Get-LocustComputeRow {
    param(
        [string]$Path,
        [string]$ExperimentId
    )

    if (-not (Test-Path $Path)) {
        throw "Missing Locust stats file: $Path"
    }

    $Rows = @(
        Import-Csv $Path |
        Where-Object { $_.Name -eq "/compute" }
    )

    if ($Rows.Count -ne 1) {
        throw "$ExperimentId expected one /compute row; found $($Rows.Count)"
    }

    return $Rows[0]
}


# ============================================================
# INPUT VALIDATION
# ============================================================

foreach ($Required in @(
    $FinalPath,
    $CloudWatchPath,
    $QueryLogPath,
    $MatrixPath
)) {
    if (-not (Test-Path $Required)) {
        throw "Required input missing: $Required"
    }
}

$Matrix = @(Import-Csv $MatrixPath)
$CloudWatch = @(Import-Csv $CloudWatchPath)
$QueryLog = @(Import-Csv $QueryLogPath)

if ($Matrix.Count -ne 36) {
    throw "Formal matrix must contain 36 rows."
}

$Completed = @(
    $Matrix |
    Where-Object { $_.status -eq "COMPLETED" }
).Count

if ($Completed -ne 36) {
    throw "Expected 36 COMPLETED formal experiments."
}

if ($QueryLog.Count -ne 270) {
    throw "Expected 270 CloudWatch queries."
}

$BadQueries = @(
    $QueryLog |
    Where-Object { $_.query_status -ne "OK" }
)

if ($BadQueries.Count -ne 0) {
    throw "CloudWatch query log contains non-OK queries."
}


# ============================================================
# BACK UP ORIGINAL 36 x 44 TEMPLATE
# ============================================================

if (-not (Test-Path $BackupPath)) {

    Copy-Item `
        $FinalPath `
        $BackupPath

    Write-Host "Original experiments.csv template backed up." -ForegroundColor Green
}

$Dataset = @(Import-Csv $BackupPath)

if ($Dataset.Count -ne 36) {
    throw "Dataset template rows=$($Dataset.Count), expected 36."
}

$ColumnCount = (
    $Dataset[0].PSObject.Properties |
    Measure-Object
).Count

if ($ColumnCount -ne 44) {
    throw "Dataset template columns=$ColumnCount, expected 44."
}

$IdDifference = @(
    Compare-Object `
        ($Dataset.experiment_id | Sort-Object) `
        ($Matrix.experiment_id | Sort-Object)
)

if ($IdDifference.Count -ne 0) {
    throw "Dataset IDs do not match formal matrix."
}


# ============================================================
# POPULATE EACH ACCEPTED FORMAL EXPERIMENT
# ============================================================

$Trace = @()

foreach ($Row in $Dataset) {

    $Id = $Row.experiment_id

    Write-Host "Populating $Id..." -ForegroundColor Cyan

    $MetaPath = Join-Path `
        $MetadataDir `
        "${Id}_metadata.csv"

    if (-not (Test-Path $MetaPath)) {
        throw "$Id metadata missing."
    }

    $MetaRows = @(Import-Csv $MetaPath)

    if ($MetaRows.Count -ne 1) {
        throw "$Id metadata row count=$($MetaRows.Count)"
    }

    $Meta = $MetaRows[0]

    if ($Meta.status -ne "COMPLETED") {
        throw "$Id metadata status is not COMPLETED."
    }


    # --------------------------------------------------------
    # LOCUST
    # --------------------------------------------------------

    $StatsPath = ""

    if ($Row.architecture -eq "EC2") {
        $StatsPath = Join-Path $Ec2Dir "${Id}_stats.csv"
    }

    if ($Row.architecture -eq "SVL") {
        $StatsPath = Join-Path $SvlDir "${Id}_stats.csv"
    }

    if ([string]::IsNullOrWhiteSpace($StatsPath)) {
        throw "$Id has unknown architecture: $($Row.architecture)"
    }

    $Stats = Get-LocustComputeRow `
        -Path $StatsPath `
        -ExperimentId $Id

    $TotalRequests = [long](
        Parse-Number $Stats.'Request Count' "$Id total requests"
    )

    $FailedRequests = [long](
        Parse-Number $Stats.'Failure Count' "$Id failed requests"
    )

    $SuccessfulRequests =
        $TotalRequests - $FailedRequests

    if ($TotalRequests -le 0) {
        throw "$Id produced zero requests."
    }

    $FailureRate =
        ($FailedRequests / $TotalRequests) * 100.0


    # Cross-check against runner metadata.
    if ([long]$Meta.total_requests -ne $TotalRequests) {
        throw "$Id total request mismatch between metadata and Locust."
    }

    if ([long]$Meta.failed_requests -ne $FailedRequests) {
        throw "$Id failure mismatch between metadata and Locust."
    }

    if ([long]$Meta.successful_requests -ne $SuccessfulRequests) {
        throw "$Id successful-request mismatch."
    }


    # --------------------------------------------------------
    # COMMON FIELDS
    # --------------------------------------------------------

    $Row.run_start_utc = $Meta.run_start_utc
    $Row.run_end_utc = $Meta.run_end_utc

    $Row.total_requests = "$TotalRequests"
    $Row.successful_requests = "$SuccessfulRequests"
    $Row.failed_requests = "$FailedRequests"

    $Row.failure_rate_percent =
        Format-Number $FailureRate

    $Row.avg_latency_ms =
        Format-Number (
            Parse-Number `
                $Stats.'Average Response Time' `
                "$Id average latency"
        )

    $Row.median_latency_ms =
        Format-Number (
            Parse-Number `
                $Stats.'Median Response Time' `
                "$Id median latency"
        )

    $Row.p95_latency_ms =
        Format-Number (
            Parse-Number `
                $Stats.'95%' `
                "$Id p95 latency"
        )

    $Row.p99_latency_ms =
        Format-Number (
            Parse-Number `
                $Stats.'99%' `
                "$Id p99 latency"
        )

    $Row.min_latency_ms =
        Format-Number (
            Parse-Number `
                $Stats.'Min Response Time' `
                "$Id min latency"
        )

    $Row.max_latency_ms =
        Format-Number (
            Parse-Number `
                $Stats.'Max Response Time' `
                "$Id max latency"
        )

    $Row.requests_per_second =
        Format-Number (
            Parse-Number `
                $Stats.'Requests/s' `
                "$Id RPS"
        )

    $Row.application_commit = $Meta.application_commit
    $Row.terraform_commit = $Meta.terraform_commit


    # --------------------------------------------------------
    # EC2 CLOUDWATCH
    # --------------------------------------------------------

    $CloudWatchMetricCount = 0

    if ($Row.architecture -eq "EC2") {

        $CpuAvg = Get-CWRows `
            $Id "EC2" "CPUUtilization" "Average"

        $CpuMax = Get-CWRows `
            $Id "EC2" "CPUUtilization" "Maximum"

        $NetIn = Get-CWRows `
            $Id "EC2" "NetworkIn" "Sum"

        $NetOut = Get-CWRows `
            $Id "EC2" "NetworkOut" "Sum"

        $StatusCheck = Get-CWRows `
            $Id "EC2" "StatusCheckFailed" "Maximum"

        $Row.ec2_cpu_avg_percent =
            Format-Number (
                Get-AverageValue $CpuAvg "$Id EC2 CPU average"
            )

        $Row.ec2_cpu_max_percent =
            Format-Number (
                Get-MaxValue $CpuMax "$Id EC2 CPU max"
            )

        $Row.ec2_network_in_bytes =
            Format-Number (
                Get-SumValue $NetIn "$Id EC2 NetworkIn"
            )

        $Row.ec2_network_out_bytes =
            Format-Number (
                Get-SumValue $NetOut "$Id EC2 NetworkOut"
            )

        $Row.ec2_status_check_failed =
            Format-Number (
                Get-MaxValue $StatusCheck "$Id EC2 status"
            )

        $Row.lambda_invocations = "NOT_APPLICABLE"
        $Row.lambda_duration_avg_ms = "NOT_APPLICABLE"
        $Row.lambda_errors = "NOT_APPLICABLE"
        $Row.lambda_throttles = "NOT_APPLICABLE"
        $Row.lambda_concurrency_peak = "NOT_APPLICABLE"

        $Row.api_gateway_count = "NOT_APPLICABLE"
        $Row.api_gateway_4xx = "NOT_APPLICABLE"
        $Row.api_gateway_5xx = "NOT_APPLICABLE"
        $Row.api_gateway_latency_avg_ms = "NOT_APPLICABLE"
        $Row.api_gateway_integration_latency_avg_ms = "NOT_APPLICABLE"

        $CloudWatchMetricCount = 5
    }


    # --------------------------------------------------------
    # SERVERLESS CLOUDWATCH
    # --------------------------------------------------------

    if ($Row.architecture -eq "SVL") {

        $Invocations = Get-CWRows `
            $Id "Lambda" "Invocations" "Sum"

        $Duration = Get-CWRows `
            $Id "Lambda" "Duration" "Average"

        $LambdaErrors = Get-CWRows `
            $Id "Lambda" "Errors" "Sum"

        $Throttles = Get-CWRows `
            $Id "Lambda" "Throttles" "Sum"

        $Concurrency = Get-CWRows `
            $Id "Lambda" "ConcurrentExecutions" "Maximum"


        $ApiCount = Get-CWRows `
            $Id "APIGateway" "Count" "Sum"

        $Api4xx = Get-CWRows `
            $Id "APIGateway" "4xx" "Sum"

        $Api5xx = Get-CWRows `
            $Id "APIGateway" "5xx" "Sum"

        $ApiLatency = Get-CWRows `
            $Id "APIGateway" "Latency" "Average"

        $ApiIntegration = Get-CWRows `
            $Id "APIGateway" "IntegrationLatency" "Average"


        $Row.lambda_invocations =
            Format-Number (
                Get-SumValue `
                    $Invocations `
                    "$Id Lambda invocations"
            )

        $Row.lambda_duration_avg_ms =
            Format-Number (
                Get-WeightedAverage `
                    $Duration `
                    $Invocations `
                    "$Id Lambda duration"
            )

        $Row.lambda_errors =
            Format-Number (
                Get-SumValue `
                    $LambdaErrors `
                    "$Id Lambda errors"
            )

        $Row.lambda_throttles =
            Format-Number (
                Get-SumValue `
                    $Throttles `
                    "$Id Lambda throttles"
            )

        $Row.lambda_concurrency_peak =
            Format-Number (
                Get-MaxValue `
                    $Concurrency `
                    "$Id Lambda concurrency"
            )

        $Row.api_gateway_count =
            Format-Number (
                Get-SumValue `
                    $ApiCount `
                    "$Id API count"
            )

        $Row.api_gateway_4xx =
            Format-Number (
                Get-SumValue `
                    $Api4xx `
                    "$Id API 4xx"
            )

        $Row.api_gateway_5xx =
            Format-Number (
                Get-SumValue `
                    $Api5xx `
                    "$Id API 5xx"
            )

        $Row.api_gateway_latency_avg_ms =
            Format-Number (
                Get-WeightedAverage `
                    $ApiLatency `
                    $ApiCount `
                    "$Id API latency"
            )

        $Row.api_gateway_integration_latency_avg_ms =
            Format-Number (
                Get-WeightedAverage `
                    $ApiIntegration `
                    $ApiCount `
                    "$Id API integration latency"
            )

        $Row.ec2_cpu_avg_percent = "NOT_APPLICABLE"
        $Row.ec2_cpu_max_percent = "NOT_APPLICABLE"
        $Row.ec2_network_in_bytes = "NOT_APPLICABLE"
        $Row.ec2_network_out_bytes = "NOT_APPLICABLE"
        $Row.ec2_status_check_failed = "NOT_APPLICABLE"

        $CloudWatchMetricCount = 10
    }


    # --------------------------------------------------------
    # COST NOT CALCULATED YET
    # --------------------------------------------------------

    $Row.actual_cost_usd = "TO_BE_MEASURED"
    $Row.estimated_cost_usd = "TO_BE_MEASURED"
    $Row.cost_per_1000_successful_requests_usd = "TO_BE_MEASURED"

    $Row.notes = (
        "Formal measured trial; Locust and CloudWatch populated; " +
        "architecture-inapplicable metrics marked NOT_APPLICABLE; " +
        "cost pending Task 25."
    )


    $Trace += [PSCustomObject]@{
        experiment_id           = $Id
        architecture            = $Row.architecture
        locust_source           = $StatsPath
        metadata_source         = $MetaPath
        cloudwatch_metrics_used = $CloudWatchMetricCount
        total_requests          = $TotalRequests
        failed_requests         = $FailedRequests
        application_commit      = $Meta.application_commit
        terraform_commit        = $Meta.terraform_commit
        population_status       = "PASS"
    }
}


# ============================================================
# ATOMIC DATASET WRITE
# ============================================================

$TempFinal = "$FinalPath.tmp"

$Dataset |
    Export-Csv `
        $TempFinal `
        -NoTypeInformation `
        -Encoding UTF8

Move-Item `
    $TempFinal `
    $FinalPath `
    -Force

$Trace |
    Export-Csv `
        $AuditPath `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# FINAL AUDIT
# ============================================================

$Final = @(Import-Csv $FinalPath)

$FinalColumnCount = (
    $Final[0].PSObject.Properties |
    Measure-Object
).Count

$UniqueIds = @(
    $Final.experiment_id |
    Sort-Object -Unique
).Count

$DuplicateIds = @(
    $Final |
    Group-Object experiment_id |
    Where-Object { $_.Count -gt 1 }
).Count


$CommonMeasuredFields = @(
    "run_start_utc",
    "run_end_utc",
    "total_requests",
    "successful_requests",
    "failed_requests",
    "failure_rate_percent",
    "avg_latency_ms",
    "median_latency_ms",
    "p95_latency_ms",
    "p99_latency_ms",
    "min_latency_ms",
    "max_latency_ms",
    "requests_per_second",
    "application_commit",
    "terraform_commit"
)

$Ec2Fields = @(
    "ec2_cpu_avg_percent",
    "ec2_cpu_max_percent",
    "ec2_network_in_bytes",
    "ec2_network_out_bytes",
    "ec2_status_check_failed"
)

$ServerlessFields = @(
    "lambda_invocations",
    "lambda_duration_avg_ms",
    "lambda_errors",
    "lambda_throttles",
    "lambda_concurrency_peak",
    "api_gateway_count",
    "api_gateway_4xx",
    "api_gateway_5xx",
    "api_gateway_latency_avg_ms",
    "api_gateway_integration_latency_avg_ms"
)

$ApplicableMissing = @()
$PolicyProblems = @()

foreach ($Row in $Final) {

    foreach ($Field in $CommonMeasuredFields) {

        if (
            [string]::IsNullOrWhiteSpace($Row.$Field) -or
            $Row.$Field -eq "TO_BE_MEASURED" -or
            $Row.$Field -eq "NOT_APPLICABLE"
        ) {
            $ApplicableMissing += "$($Row.experiment_id):$Field"
        }
    }

    if ($Row.architecture -eq "EC2") {

        foreach ($Field in $Ec2Fields) {

            if (
                [string]::IsNullOrWhiteSpace($Row.$Field) -or
                $Row.$Field -eq "TO_BE_MEASURED" -or
                $Row.$Field -eq "NOT_APPLICABLE"
            ) {
                $ApplicableMissing += "$($Row.experiment_id):$Field"
            }
        }

        foreach ($Field in $ServerlessFields) {

            if ($Row.$Field -ne "NOT_APPLICABLE") {
                $PolicyProblems += "$($Row.experiment_id):$Field"
            }
        }
    }

    if ($Row.architecture -eq "SVL") {

        foreach ($Field in $ServerlessFields) {

            if (
                [string]::IsNullOrWhiteSpace($Row.$Field) -or
                $Row.$Field -eq "TO_BE_MEASURED" -or
                $Row.$Field -eq "NOT_APPLICABLE"
            ) {
                $ApplicableMissing += "$($Row.experiment_id):$Field"
            }
        }

        foreach ($Field in $Ec2Fields) {

            if ($Row.$Field -ne "NOT_APPLICABLE") {
                $PolicyProblems += "$($Row.experiment_id):$Field"
            }
        }
    }

    if ($Row.actual_cost_usd -ne "TO_BE_MEASURED") {
        $PolicyProblems += "$($Row.experiment_id):actual_cost_usd"
    }

    if ($Row.estimated_cost_usd -ne "TO_BE_MEASURED") {
        $PolicyProblems += "$($Row.experiment_id):estimated_cost_usd"
    }

    if (
        $Row.cost_per_1000_successful_requests_usd -ne
        "TO_BE_MEASURED"
    ) {
        $PolicyProblems += "$($Row.experiment_id):cost_per_1000"
    }
}


$TracePass = @(
    $Trace |
    Where-Object { $_.population_status -eq "PASS" }
).Count


Clear-Host

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " DAY 2 - TASK 24 - FINAL DATASET AUDIT" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Dataset"
Write-Host "-------"
Write-Host "Rows                         : $($Final.Count) / 36"
Write-Host "Columns                      : $FinalColumnCount / 44"
Write-Host "Unique experiment IDs        : $UniqueIds / 36"
Write-Host "Duplicate experiment IDs     : $DuplicateIds"

Write-Host ""
Write-Host "Traceability"
Write-Host "------------"
Write-Host "Source-traced experiments    : $TracePass / 36"
Write-Host "Applicable TBM/missing fields: $($ApplicableMissing.Count)"
Write-Host "Unsupported/fabricated flags : $($PolicyProblems.Count)"

Write-Host ""
Write-Host "Architecture-specific policy"
Write-Host "----------------------------"
Write-Host "EC2 rows                      : $(@($Final | Where-Object {$_.architecture -eq 'EC2'}).Count)"
Write-Host "Serverless rows               : $(@($Final | Where-Object {$_.architecture -eq 'SVL'}).Count)"
Write-Host "Inapplicable fields           : NOT_APPLICABLE"
Write-Host "Cost fields                   : TO_BE_MEASURED (Task 25)"


$Pass = $true

if ($Final.Count -ne 36) {
    $Pass = $false
}

if ($FinalColumnCount -ne 44) {
    $Pass = $false
}

if ($UniqueIds -ne 36) {
    $Pass = $false
}

if ($DuplicateIds -ne 0) {
    $Pass = $false
}

if ($TracePass -ne 36) {
    $Pass = $false
}

if ($ApplicableMissing.Count -ne 0) {
    $Pass = $false
}

if ($PolicyProblems.Count -ne 0) {
    $Pass = $false
}


if ($Pass) {

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host " TASK 24 PASSED" -ForegroundColor Green
    Write-Host " 36 / 36 FORMAL DATASET ROWS POPULATED" -ForegroundColor Green
    Write-Host " 44 / 44 DATASET COLUMNS PRESERVED" -ForegroundColor Green
    Write-Host " ALL COLLECTED PERFORMANCE METRICS POPULATED" -ForegroundColor Green
    Write-Host " ALL COLLECTED CLOUDWATCH METRICS POPULATED" -ForegroundColor Green
    Write-Host " GIT COMMITS RECORDED" -ForegroundColor Green
    Write-Host " 0 APPLICABLE TO_BE_MEASURED VALUES REMAIN" -ForegroundColor Green
    Write-Host " 0 UNSUPPORTED/FABRICATED VALUE FLAGS" -ForegroundColor Green
    Write-Host " COST FIELDS RESERVED FOR TASK 25" -ForegroundColor Green
    Write-Host " FINAL FORMAL DATASET READY" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
}

if (-not $Pass) {

    Write-Host ""
    Write-Host "TASK 24 FAILED - DO NOT CONTINUE" -ForegroundColor Red

    if ($ApplicableMissing.Count -gt 0) {
        Write-Host "`nMissing applicable values:" -ForegroundColor Yellow
        $ApplicableMissing
    }

    if ($PolicyProblems.Count -gt 0) {
        Write-Host "`nPolicy/fabrication problems:" -ForegroundColor Yellow
        $PolicyProblems
    }
}
