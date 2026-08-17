Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path ".").Path

$InputPath =
    Join-Path `
        $RepoRoot `
        "data\final\experiments.csv"

$SummaryPath =
    Join-Path `
        $RepoRoot `
        "data\processed\formal\formal-summary-by-workload-architecture.csv"

$ComparisonPath =
    Join-Path `
        $RepoRoot `
        "data\processed\formal\formal-architecture-comparison.csv"

$TrialPath =
    Join-Path `
        $RepoRoot `
        "data\processed\formal\formal-trial-analysis-input.csv"

$AuditPath =
    Join-Path `
        $RepoRoot `
        "data\processed\formal\task26-statistical-audit.csv"

$Invariant =
    [Globalization.CultureInfo]::InvariantCulture


# ============================================================
# NUMERIC HELPERS
# ============================================================

function Parse-Number {

    param(
        [string]$Value,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing value: $Label"
    }

    if (
        $Value -eq "NOT_APPLICABLE" -or
        $Value -eq "TO_BE_MEASURED" -or
        $Value -eq "NOT_DIRECTLY_ATTRIBUTABLE"
    ) {
        throw "Non-numeric value for $Label : $Value"
    }

    return [double]::Parse(
        $Value,
        [Globalization.NumberStyles]::Float,
        $Invariant
    )
}


function Format-Number {

    param(
        [double]$Value,
        [int]$Decimals = 6
    )

    $Pattern = "0"

    if ($Decimals -gt 0) {

        $Pattern =
            "0." +
            ("0" * $Decimals)
    }

    return $Value.ToString(
        $Pattern,
        $Invariant
    )
}


function Get-Mean {

    param(
        [double[]]$Values
    )

    if ($Values.Count -eq 0) {
        throw "Cannot calculate mean of empty set."
    }

    $Sum = 0.0

    foreach ($Value in $Values) {
        $Sum += $Value
    }

    return ($Sum / $Values.Count)
}


function Get-Median {

    param(
        [double[]]$Values
    )

    if ($Values.Count -eq 0) {
        throw "Cannot calculate median of empty set."
    }

    $Sorted =
        @(
            $Values |
            Sort-Object
        )

    $Count =
        $Sorted.Count

    if (($Count % 2) -eq 1) {

        return [double]$Sorted[
            [int][Math]::Floor($Count / 2)
        ]
    }

    $Upper =
        [int]($Count / 2)

    $Lower =
        $Upper - 1

    return (
        ([double]$Sorted[$Lower] +
        [double]$Sorted[$Upper]) /
        2.0
    )
}


function Get-SampleSd {

    param(
        [double[]]$Values
    )

    if ($Values.Count -lt 2) {
        return 0.0
    }

    $Mean =
        Get-Mean $Values

    $SquaredSum =
        0.0

    foreach ($Value in $Values) {

        $Difference =
            $Value - $Mean

        $SquaredSum +=
            ($Difference * $Difference)
    }

    return [Math]::Sqrt(
        $SquaredSum /
        ($Values.Count - 1)
    )
}


function Get-Minimum {

    param(
        [double[]]$Values
    )

    return [double](
        $Values |
        Measure-Object -Minimum
    ).Minimum
}


function Get-Maximum {

    param(
        [double[]]$Values
    )

    return [double](
        $Values |
        Measure-Object -Maximum
    ).Maximum
}


function Get-CvPercent {

    param(
        [double[]]$Values
    )

    $Mean =
        Get-Mean $Values

    if ([Math]::Abs($Mean) -lt 0.000000000001) {
        return $null
    }

    $Sd =
        Get-SampleSd $Values

    return (
        $Sd /
        [Math]::Abs($Mean) *
        100.0
    )
}


function Get-RelativeDifference {

    param(
        [double]$Ec2,
        [double]$Serverless
    )

    if ([Math]::Abs($Ec2) -lt 0.000000000001) {
        return $null
    }

    return (
        ($Serverless - $Ec2) /
        $Ec2 *
        100.0
    )
}


function Get-Ratio {

    param(
        [double]$Ec2,
        [double]$Serverless
    )

    if ([Math]::Abs($Ec2) -lt 0.000000000001) {
        return $null
    }

    return (
        $Serverless /
        $Ec2
    )
}


function Format-Nullable {

    param(
        $Value,
        [int]$Decimals = 6
    )

    if ($null -eq $Value) {
        return "NOT_DEFINED"
    }

    return (
        Format-Number `
            ([double]$Value) `
            $Decimals
    )
}


# ============================================================
# INPUT AUDIT
# ============================================================

if (-not (Test-Path $InputPath)) {
    throw "Final formal dataset missing."
}

$Data =
    @(Import-Csv $InputPath)

if ($Data.Count -ne 36) {
    throw "Expected 36 formal trials; found $($Data.Count)."
}

$ColumnCount =
    (
        $Data[0].
            PSObject.Properties |
        Measure-Object
    ).Count

if ($ColumnCount -ne 44) {
    throw "Expected 44 columns; found $ColumnCount."
}


$ExpectedWorkloads =
    @(
        "W01",
        "W02",
        "W03",
        "W04",
        "W05",
        "W06"
    )


$ExpectedArchitectures =
    @(
        "EC2",
        "SVL"
    )


foreach ($Workload in $ExpectedWorkloads) {

    foreach ($Architecture in $ExpectedArchitectures) {

        $Count =
            @(
                $Data |
                Where-Object {

                    $_.workload_id -eq
                    $Workload -and

                    $_.architecture -eq
                    $Architecture
                }
            ).Count

        if ($Count -ne 3) {

            throw (
                "$Workload / $Architecture expected " +
                "3 trials; found $Count."
            )
        }
    }
}


$RemainingTBM =
    0

foreach ($Row in $Data) {

    foreach (
        $Property in
        $Row.PSObject.Properties
    ) {

        if (
            $Property.Value -eq
            "TO_BE_MEASURED"
        ) {
            $RemainingTBM++
        }
    }
}

if ($RemainingTBM -ne 0) {
    throw "Dataset still contains TO_BE_MEASURED values."
}


# ============================================================
# CREATE ANALYSIS INPUT SNAPSHOT
# ============================================================

$TrialInput =
    @()


foreach ($Row in $Data) {

    $ArchitectureLabel =
        $Row.architecture

    if ($Row.architecture -eq "SVL") {
        $ArchitectureLabel = "Serverless"
    }


    $TrialInput +=
        [PSCustomObject]@{

            experiment_id =
                $Row.experiment_id

            workload_id =
                $Row.workload_id

            workload_type =
                $Row.workload_type

            architecture_code =
                $Row.architecture

            architecture =
                $ArchitectureLabel

            trial_number =
                $Row.trial_number

            avg_latency_ms =
                $Row.avg_latency_ms

            median_latency_ms =
                $Row.median_latency_ms

            p95_latency_ms =
                $Row.p95_latency_ms

            p99_latency_ms =
                $Row.p99_latency_ms

            requests_per_second =
                $Row.requests_per_second

            failure_rate_percent =
                $Row.failure_rate_percent

            successful_requests =
                $Row.successful_requests

            failed_requests =
                $Row.failed_requests

            estimated_cost_usd =
                $Row.estimated_cost_usd

            cost_per_1000_successful_requests_usd =
                $Row.cost_per_1000_successful_requests_usd
        }
}


$TrialInput |
    Export-Csv `
        $TrialPath `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# GROUP ANALYSIS
#
# 6 workloads x 2 architectures = 12 groups
# ============================================================

$Summary =
    @()


foreach ($Workload in $ExpectedWorkloads) {

    foreach ($Architecture in $ExpectedArchitectures) {

        $Rows =
            @(
                $Data |
                Where-Object {

                    $_.workload_id -eq
                    $Workload -and

                    $_.architecture -eq
                    $Architecture
                } |
                Sort-Object trial_number
            )


        if ($Rows.Count -ne 3) {

            throw (
                "$Workload / $Architecture " +
                "does not contain 3 trials."
            )
        }


        $AvgLatency =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.avg_latency_ms `
                        "$($_.experiment_id) avg latency"
                }
            )


        $MedianLatency =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.median_latency_ms `
                        "$($_.experiment_id) median latency"
                }
            )


        $P95 =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.p95_latency_ms `
                        "$($_.experiment_id) p95"
                }
            )


        $P99 =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.p99_latency_ms `
                        "$($_.experiment_id) p99"
                }
            )


        $Throughput =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.requests_per_second `
                        "$($_.experiment_id) throughput"
                }
            )


        $FailureRate =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.failure_rate_percent `
                        "$($_.experiment_id) failure rate"
                }
            )


        $EstimatedCost =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.estimated_cost_usd `
                        "$($_.experiment_id) estimated cost"
                }
            )


        $CostPer1000 =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.cost_per_1000_successful_requests_usd `
                        "$($_.experiment_id) cost per 1000"
                }
            )


        $SuccessfulRequests =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.successful_requests `
                        "$($_.experiment_id) successful requests"
                }
            )


        $FailedRequests =
            @(
                $Rows |
                ForEach-Object {

                    Parse-Number `
                        $_.failed_requests `
                        "$($_.experiment_id) failed requests"
                }
            )


        $ArchitectureLabel =
            $Architecture

        if ($Architecture -eq "SVL") {
            $ArchitectureLabel = "Serverless"
        }


        $Summary +=
            [PSCustomObject]@{

                workload_id =
                    $Workload

                workload_type =
                    $Rows[0].workload_type

                architecture_code =
                    $Architecture

                architecture =
                    $ArchitectureLabel

                n_trials =
                    $Rows.Count


                # ----------------------------
                # Central tendency
                # ----------------------------

                mean_avg_latency_ms =
                    Format-Number `
                        (Get-Mean $AvgLatency) `
                        6

                mean_trial_median_latency_ms =
                    Format-Number `
                        (Get-Mean $MedianLatency) `
                        6

                median_trial_median_latency_ms =
                    Format-Number `
                        (Get-Median $MedianLatency) `
                        6

                mean_p95_latency_ms =
                    Format-Number `
                        (Get-Mean $P95) `
                        6

                mean_p99_latency_ms =
                    Format-Number `
                        (Get-Mean $P99) `
                        6

                mean_throughput_rps =
                    Format-Number `
                        (Get-Mean $Throughput) `
                        6

                mean_failure_rate_percent =
                    Format-Number `
                        (Get-Mean $FailureRate) `
                        6

                mean_estimated_cost_usd =
                    Format-Number `
                        (Get-Mean $EstimatedCost) `
                        12

                mean_cost_per_1000_successful_requests_usd =
                    Format-Number `
                        (Get-Mean $CostPer1000) `
                        12


                # ----------------------------
                # Sample standard deviation
                # ----------------------------

                sd_avg_latency_ms =
                    Format-Number `
                        (Get-SampleSd $AvgLatency) `
                        6

                sd_p95_latency_ms =
                    Format-Number `
                        (Get-SampleSd $P95) `
                        6

                sd_p99_latency_ms =
                    Format-Number `
                        (Get-SampleSd $P99) `
                        6

                sd_throughput_rps =
                    Format-Number `
                        (Get-SampleSd $Throughput) `
                        6

                sd_failure_rate_percent =
                    Format-Number `
                        (Get-SampleSd $FailureRate) `
                        6

                sd_cost_per_1000_usd =
                    Format-Number `
                        (Get-SampleSd $CostPer1000) `
                        12


                # ----------------------------
                # Range across trials
                # ----------------------------

                min_avg_latency_ms =
                    Format-Number `
                        (Get-Minimum $AvgLatency) `
                        6

                max_avg_latency_ms =
                    Format-Number `
                        (Get-Maximum $AvgLatency) `
                        6

                min_p95_latency_ms =
                    Format-Number `
                        (Get-Minimum $P95) `
                        6

                max_p95_latency_ms =
                    Format-Number `
                        (Get-Maximum $P95) `
                        6

                min_p99_latency_ms =
                    Format-Number `
                        (Get-Minimum $P99) `
                        6

                max_p99_latency_ms =
                    Format-Number `
                        (Get-Maximum $P99) `
                        6

                min_throughput_rps =
                    Format-Number `
                        (Get-Minimum $Throughput) `
                        6

                max_throughput_rps =
                    Format-Number `
                        (Get-Maximum $Throughput) `
                        6

                min_failure_rate_percent =
                    Format-Number `
                        (Get-Minimum $FailureRate) `
                        6

                max_failure_rate_percent =
                    Format-Number `
                        (Get-Maximum $FailureRate) `
                        6

                min_cost_per_1000_usd =
                    Format-Number `
                        (Get-Minimum $CostPer1000) `
                        12

                max_cost_per_1000_usd =
                    Format-Number `
                        (Get-Maximum $CostPer1000) `
                        12


                # ----------------------------
                # Relative variability
                # ----------------------------

                cv_avg_latency_percent =
                    Format-Nullable `
                        (Get-CvPercent $AvgLatency) `
                        6

                cv_throughput_percent =
                    Format-Nullable `
                        (Get-CvPercent $Throughput) `
                        6

                cv_cost_per_1000_percent =
                    Format-Nullable `
                        (Get-CvPercent $CostPer1000) `
                        6


                # ----------------------------
                # Aggregated request counts
                # ----------------------------

                total_successful_requests =
                    Format-Number `
                        (
                            ($SuccessfulRequests |
                            Measure-Object -Sum).Sum
                        ) `
                        0

                total_failed_requests =
                    Format-Number `
                        (
                            ($FailedRequests |
                            Measure-Object -Sum).Sum
                        ) `
                        0
            }
    }
}


if ($Summary.Count -ne 12) {
    throw "Expected 12 statistical summary rows."
}


$Summary |
    Export-Csv `
        $SummaryPath `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# EC2 VS SERVERLESS COMPARISON
#
# One row per workload = 6 rows
# ============================================================

$Comparison =
    @()


foreach ($Workload in $ExpectedWorkloads) {

    $Ec2Rows =
        @(
            $Summary |
            Where-Object {

                $_.workload_id -eq
                $Workload -and

                $_.architecture_code -eq
                "EC2"
            }
        )


    $SvlRows =
        @(
            $Summary |
            Where-Object {

                $_.workload_id -eq
                $Workload -and

                $_.architecture_code -eq
                "SVL"
            }
        )


    if (
        $Ec2Rows.Count -ne 1 -or
        $SvlRows.Count -ne 1
    ) {

        throw (
            "$Workload architecture summary " +
            "pair is incomplete."
        )
    }


    $Ec2 =
        $Ec2Rows[0]

    $Svl =
        $SvlRows[0]


    $Ec2AvgLatency =
        Parse-Number `
            $Ec2.mean_avg_latency_ms `
            "$Workload EC2 latency"


    $SvlAvgLatency =
        Parse-Number `
            $Svl.mean_avg_latency_ms `
            "$Workload Serverless latency"


    $Ec2P95 =
        Parse-Number `
            $Ec2.mean_p95_latency_ms `
            "$Workload EC2 p95"


    $SvlP95 =
        Parse-Number `
            $Svl.mean_p95_latency_ms `
            "$Workload Serverless p95"


    $Ec2P99 =
        Parse-Number `
            $Ec2.mean_p99_latency_ms `
            "$Workload EC2 p99"


    $SvlP99 =
        Parse-Number `
            $Svl.mean_p99_latency_ms `
            "$Workload Serverless p99"


    $Ec2Throughput =
        Parse-Number `
            $Ec2.mean_throughput_rps `
            "$Workload EC2 throughput"


    $SvlThroughput =
        Parse-Number `
            $Svl.mean_throughput_rps `
            "$Workload Serverless throughput"


    $Ec2Failure =
        Parse-Number `
            $Ec2.mean_failure_rate_percent `
            "$Workload EC2 failure"


    $SvlFailure =
        Parse-Number `
            $Svl.mean_failure_rate_percent `
            "$Workload Serverless failure"


    $Ec2Cost =
        Parse-Number `
            $Ec2.mean_cost_per_1000_successful_requests_usd `
            "$Workload EC2 cost per 1000"


    $SvlCost =
        Parse-Number `
            $Svl.mean_cost_per_1000_successful_requests_usd `
            "$Workload Serverless cost per 1000"


    $Comparison +=
        [PSCustomObject]@{

            workload_id =
                $Workload

            workload_type =
                $Ec2.workload_type


            # ----------------------------
            # Latency
            # ----------------------------

            ec2_mean_avg_latency_ms =
                $Ec2.mean_avg_latency_ms

            serverless_mean_avg_latency_ms =
                $Svl.mean_avg_latency_ms

            serverless_vs_ec2_latency_relative_difference_percent =
                Format-Nullable `
                    (
                        Get-RelativeDifference `
                            $Ec2AvgLatency `
                            $SvlAvgLatency
                    ) `
                    6

            serverless_to_ec2_latency_ratio =
                Format-Nullable `
                    (
                        Get-Ratio `
                            $Ec2AvgLatency `
                            $SvlAvgLatency
                    ) `
                    6


            # ----------------------------
            # P95
            # ----------------------------

            ec2_mean_p95_ms =
                $Ec2.mean_p95_latency_ms

            serverless_mean_p95_ms =
                $Svl.mean_p95_latency_ms

            serverless_vs_ec2_p95_relative_difference_percent =
                Format-Nullable `
                    (
                        Get-RelativeDifference `
                            $Ec2P95 `
                            $SvlP95
                    ) `
                    6

            serverless_to_ec2_p95_ratio =
                Format-Nullable `
                    (
                        Get-Ratio `
                            $Ec2P95 `
                            $SvlP95
                    ) `
                    6


            # ----------------------------
            # P99
            # ----------------------------

            ec2_mean_p99_ms =
                $Ec2.mean_p99_latency_ms

            serverless_mean_p99_ms =
                $Svl.mean_p99_latency_ms

            serverless_vs_ec2_p99_relative_difference_percent =
                Format-Nullable `
                    (
                        Get-RelativeDifference `
                            $Ec2P99 `
                            $SvlP99
                    ) `
                    6

            serverless_to_ec2_p99_ratio =
                Format-Nullable `
                    (
                        Get-Ratio `
                            $Ec2P99 `
                            $SvlP99
                    ) `
                    6


            # ----------------------------
            # Throughput
            # ----------------------------

            ec2_mean_throughput_rps =
                $Ec2.mean_throughput_rps

            serverless_mean_throughput_rps =
                $Svl.mean_throughput_rps

            serverless_vs_ec2_throughput_relative_difference_percent =
                Format-Nullable `
                    (
                        Get-RelativeDifference `
                            $Ec2Throughput `
                            $SvlThroughput
                    ) `
                    6

            serverless_to_ec2_throughput_ratio =
                Format-Nullable `
                    (
                        Get-Ratio `
                            $Ec2Throughput `
                            $SvlThroughput
                    ) `
                    6


            # ----------------------------
            # Failure rate
            # ----------------------------

            ec2_mean_failure_rate_percent =
                $Ec2.mean_failure_rate_percent

            serverless_mean_failure_rate_percent =
                $Svl.mean_failure_rate_percent

            serverless_minus_ec2_failure_percentage_points =
                Format-Number `
                    (
                        $SvlFailure -
                        $Ec2Failure
                    ) `
                    6

            serverless_to_ec2_failure_ratio =
                Format-Nullable `
                    (
                        Get-Ratio `
                            $Ec2Failure `
                            $SvlFailure
                    ) `
                    6


            # ----------------------------
            # Cost efficiency
            # ----------------------------

            ec2_mean_cost_per_1000_usd =
                $Ec2.mean_cost_per_1000_successful_requests_usd

            serverless_mean_cost_per_1000_usd =
                $Svl.mean_cost_per_1000_successful_requests_usd

            serverless_vs_ec2_cost_relative_difference_percent =
                Format-Nullable `
                    (
                        Get-RelativeDifference `
                            $Ec2Cost `
                            $SvlCost
                    ) `
                    6

            serverless_to_ec2_cost_ratio =
                Format-Nullable `
                    (
                        Get-Ratio `
                            $Ec2Cost `
                            $SvlCost
                    ) `
                    6


            # ----------------------------
            # Variability context
            # ----------------------------

            ec2_latency_sd_ms =
                $Ec2.sd_avg_latency_ms

            serverless_latency_sd_ms =
                $Svl.sd_avg_latency_ms

            ec2_throughput_sd_rps =
                $Ec2.sd_throughput_rps

            serverless_throughput_sd_rps =
                $Svl.sd_throughput_rps

            ec2_cost_sd_per_1000_usd =
                $Ec2.sd_cost_per_1000_usd

            serverless_cost_sd_per_1000_usd =
                $Svl.sd_cost_per_1000_usd
        }
}


if ($Comparison.Count -ne 6) {
    throw "Expected 6 architecture comparison rows."
}


$Comparison |
    Export-Csv `
        $ComparisonPath `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# INDEPENDENT FINAL AUDIT
# ============================================================

$SummaryCheck =
    @(Import-Csv $SummaryPath)


$ComparisonCheck =
    @(Import-Csv $ComparisonPath)


$TrialCheck =
    @(Import-Csv $TrialPath)


$GroupsWithThreeTrials =
    @(
        $SummaryCheck |
        Where-Object {

            [int]$_.n_trials -eq 3
        }
    ).Count


$SummaryMissing =
    0


foreach ($Row in $SummaryCheck) {

    foreach (
        $Property in
        $Row.PSObject.Properties
    ) {

        if (
            [string]::IsNullOrWhiteSpace(
                [string]$Property.Value
            )
        ) {

            $SummaryMissing++
        }
    }
}


$ComparisonMissing =
    0


foreach ($Row in $ComparisonCheck) {

    foreach (
        $Property in
        $Row.PSObject.Properties
    ) {

        if (
            [string]::IsNullOrWhiteSpace(
                [string]$Property.Value
            )
        ) {

            $ComparisonMissing++
        }
    }
}


$Audit =
    @(
        [PSCustomObject]@{
            check="formal_trial_rows"
            expected=36
            actual=$TrialCheck.Count
            status=if ($TrialCheck.Count -eq 36) {"PASS"} else {"FAIL"}
        },

        [PSCustomObject]@{
            check="workload_architecture_groups"
            expected=12
            actual=$SummaryCheck.Count
            status=if ($SummaryCheck.Count -eq 12) {"PASS"} else {"FAIL"}
        },

        [PSCustomObject]@{
            check="groups_with_three_trials"
            expected=12
            actual=$GroupsWithThreeTrials
            status=if ($GroupsWithThreeTrials -eq 12) {"PASS"} else {"FAIL"}
        },

        [PSCustomObject]@{
            check="architecture_comparisons"
            expected=6
            actual=$ComparisonCheck.Count
            status=if ($ComparisonCheck.Count -eq 6) {"PASS"} else {"FAIL"}
        },

        [PSCustomObject]@{
            check="summary_missing_values"
            expected=0
            actual=$SummaryMissing
            status=if ($SummaryMissing -eq 0) {"PASS"} else {"FAIL"}
        },

        [PSCustomObject]@{
            check="comparison_missing_values"
            expected=0
            actual=$ComparisonMissing
            status=if ($ComparisonMissing -eq 0) {"PASS"} else {"FAIL"}
        }
    )


$Audit |
    Export-Csv `
        $AuditPath `
        -NoTypeInformation `
        -Encoding UTF8


$Failures =
    @(
        $Audit |
        Where-Object {
            $_.status -ne "PASS"
        }
    ).Count


# ============================================================
# SCREEN OUTPUT
# ============================================================

Clear-Host

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " DAY 2 - TASK 26 - FORMAL STATISTICAL ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Analysis design"
Write-Host "---------------"
Write-Host "Formal trials                 : $($TrialCheck.Count) / 36"
Write-Host "Workloads                     : 6 / 6"
Write-Host "Architectures                 : 2 / 2"
Write-Host "Trials per condition          : 3"
Write-Host "Workload/architecture groups  : $($SummaryCheck.Count) / 12"
Write-Host "Architecture comparisons      : $($ComparisonCheck.Count) / 6"
Write-Host "Groups with n=3               : $GroupsWithThreeTrials / 12"
Write-Host "Inferential significance tests: NOT USED"

Write-Host ""
Write-Host "Primary descriptive summary"
Write-Host "---------------------------"

$DisplayRows =
    @()

foreach ($Row in $SummaryCheck) {

    $DisplayRows +=
        [PSCustomObject]@{

            Workload =
                $Row.workload_id

            Arch =
                $Row.architecture

            MeanLatencyMs =
                [Math]::Round(
                    [double]$Row.mean_avg_latency_ms,
                    2
                )

            SDLatency =
                [Math]::Round(
                    [double]$Row.sd_avg_latency_ms,
                    2
                )

            MeanP95Ms =
                [Math]::Round(
                    [double]$Row.mean_p95_latency_ms,
                    2
                )

            MeanRPS =
                [Math]::Round(
                    [double]$Row.mean_throughput_rps,
                    2
                )

            FailurePct =
                [Math]::Round(
                    [double]$Row.mean_failure_rate_percent,
                    3
                )

            CostPer1K =
                [Math]::Round(
                    [double]$Row.mean_cost_per_1000_successful_requests_usd,
                    6
                )
        }
}


$DisplayRows |
    Format-Table `
        -AutoSize


Write-Host ""
Write-Host "Integrity audit"
Write-Host "---------------"

$Audit |
    Format-Table `
        check,
        expected,
        actual,
        status `
        -AutoSize


if ($Failures -ne 0) {

    Write-Host ""
    Write-Host "TASK 26 FAILED - DO NOT INTERPRET RESULTS" -ForegroundColor Red

    exit 1
}


Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " TASK 26 PASSED" -ForegroundColor Green
Write-Host " 36 / 36 FORMAL TRIALS ANALYZED" -ForegroundColor Green
Write-Host " 12 / 12 WORKLOAD-ARCHITECTURE GROUPS SUMMARIZED" -ForegroundColor Green
Write-Host " 3 / 3 TRIALS INCLUDED PER CONDITION" -ForegroundColor Green
Write-Host " SAMPLE STANDARD DEVIATIONS CALCULATED" -ForegroundColor Green
Write-Host " MIN/MAX VARIABILITY CALCULATED" -ForegroundColor Green
Write-Host " 6 / 6 EC2-VS-SERVERLESS COMPARISONS CALCULATED" -ForegroundColor Green
Write-Host " RELATIVE DIFFERENCES AND RATIOS CALCULATED" -ForegroundColor Green
Write-Host " COST PER 1,000 REQUESTS INCLUDED" -ForegroundColor Green
Write-Host " NO INFERENTIAL SIGNIFICANCE CLAIMS USED" -ForegroundColor Green
Write-Host " FORMAL STATISTICAL RESULTS READY" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
