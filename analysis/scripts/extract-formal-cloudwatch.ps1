param(
    [switch]$Resume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Region = "ap-south-1"

$RepoRoot = (
    Resolve-Path "."
).Path

$MatrixPath = Join-Path `
    $RepoRoot `
    "docs\methodology\formal-experiment-matrix.csv"

$MetadataDir = Join-Path `
    $RepoRoot `
    "data\raw\formal\metadata"

$CloudWatchRoot = Join-Path `
    $RepoRoot `
    "data\raw\formal\cloudwatch"

$Ec2RawDir = Join-Path `
    $CloudWatchRoot `
    "ec2"

$LambdaRawDir = Join-Path `
    $CloudWatchRoot `
    "lambda"

$ApiRawDir = Join-Path `
    $CloudWatchRoot `
    "apigateway"

$DiscoveryDir = Join-Path `
    $CloudWatchRoot `
    "discovery"

$ProcessedDir = Join-Path `
    $RepoRoot `
    "data\processed\formal"

$QueryLogPath = Join-Path `
    $ProcessedDir `
    "cloudwatch-query-log.csv"

$DatapointPath = Join-Path `
    $ProcessedDir `
    "cloudwatch-datapoints.csv"


foreach ($Dir in @(
    $CloudWatchRoot,
    $Ec2RawDir,
    $LambdaRawDir,
    $ApiRawDir,
    $DiscoveryDir,
    $ProcessedDir
)) {

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $Dir |
        Out-Null
}


# ============================================================
# HELPERS
# ============================================================

function Get-TerraformOutput {

    param(
        [string]$Directory,
        [string]$OutputName
    )

    $PreviousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {

        $TempError = Join-Path `
            $env:TEMP `
            ("tf-" + [guid]::NewGuid().ToString() + ".err")

        $Output = @(
            & terraform `
                "-chdir=$Directory" `
                output `
                -raw `
                $OutputName `
                2> $TempError
        )

        $ExitCode = $LASTEXITCODE

        $ErrorText = ""

        if (Test-Path $TempError) {

            $ErrorText = (
                Get-Content `
                    $TempError `
                    -Raw `
                    -ErrorAction SilentlyContinue
            )

            Remove-Item `
                $TempError `
                -Force `
                -ErrorAction SilentlyContinue
        }

        if ($ExitCode -ne 0) {

            throw (
                "Terraform output failed: " +
                "$Directory / $OutputName : $ErrorText"
            )
        }

        return (
            ($Output -join "`n").Trim()
        )
    }
    finally {

        $ErrorActionPreference =
            $PreviousPreference
    }
}


function Invoke-AwsJson {

    param(
        [string[]]$Arguments,
        [string]$OutputPath,
        [switch]$AllowExisting
    )

    if (Test-Path $OutputPath) {

        if (-not $AllowExisting) {

            throw (
                "NO-OVERWRITE PROTECTION: " +
                "$OutputPath already exists."
            )
        }

        $ExistingText = Get-Content `
            $OutputPath `
            -Raw

        return (
            $ExistingText |
            ConvertFrom-Json
        )
    }


    $TempError = Join-Path `
        $env:TEMP `
        ("aws-" + [guid]::NewGuid().ToString() + ".err")

    $PreviousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {

        $Output = @(
            & aws `
                @Arguments `
                --no-cli-pager `
                --output json `
                2> $TempError
        )

        $ExitCode = $LASTEXITCODE
    }
    finally {

        $ErrorActionPreference =
            $PreviousPreference
    }


    $ErrorText = ""

    if (Test-Path $TempError) {

        $ErrorText = (
            Get-Content `
                $TempError `
                -Raw `
                -ErrorAction SilentlyContinue
        )

        Remove-Item `
            $TempError `
            -Force `
            -ErrorAction SilentlyContinue
    }


    if ($ExitCode -ne 0) {

        throw (
            "AWS CLI command failed. Exit=$ExitCode. " +
            $ErrorText
        )
    }


    $JsonText = (
        $Output -join "`n"
    ).Trim()

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw "AWS CLI returned empty JSON."
    }


    # Validate JSON before saving.
    $Object = $JsonText |
        ConvertFrom-Json


    $TempPath = "$OutputPath.tmp"

    $JsonText |
        Set-Content `
            -Path $TempPath `
            -Encoding UTF8

    Move-Item `
        -Path $TempPath `
        -Destination $OutputPath

    return $Object
}


function Test-ExactDimensionSeries {

    param(
        [object]$DiscoveryObject,
        [string]$DimensionName,
        [string]$DimensionValue
    )

    foreach ($Metric in @($DiscoveryObject.Metrics)) {

        $Dimensions = @(
            $Metric.Dimensions
        )

        if ($Dimensions.Count -ne 1) {
            continue
        }

        if (
            ($Dimensions[0].Name -eq $DimensionName) -and
            ($Dimensions[0].Value -eq $DimensionValue)
        ) {
            return $true
        }
    }

    return $false
}


function Get-ExpectedUnit {

    param(
        [string]$Service,
        [string]$Metric
    )

    if ($Service -eq "EC2") {

        if ($Metric -eq "CPUUtilization") {
            return "Percent"
        }

        if (
            ($Metric -eq "NetworkIn") -or
            ($Metric -eq "NetworkOut")
        ) {
            return "Bytes"
        }

        return "Count"
    }


    if ($Service -eq "Lambda") {

        if ($Metric -eq "Duration") {
            return "Milliseconds"
        }

        return "Count"
    }


    if ($Service -eq "APIGateway") {

        if (
            ($Metric -eq "Latency") -or
            ($Metric -eq "IntegrationLatency")
        ) {
            return "Milliseconds"
        }

        return "Count"
    }


    return "None"
}


# ============================================================
# TASK 22 PRECONDITION
# ============================================================

$Matrix = @(
    Import-Csv $MatrixPath
)

$Completed = @(
    $Matrix |
    Where-Object { $_.status -eq "COMPLETED" }
).Count

$Pending = @(
    $Matrix |
    Where-Object { $_.status -eq "PENDING" }
).Count

$Errors = @(
    $Matrix |
    Where-Object { $_.status -eq "ERROR" }
).Count


if (
    ($Matrix.Count -ne 36) -or
    ($Completed -ne 36) -or
    ($Pending -ne 0) -or
    ($Errors -ne 0)
) {

    throw (
        "Task 22 prerequisite failed. " +
        "Rows=$($Matrix.Count), " +
        "Completed=$Completed, " +
        "Pending=$Pending, " +
        "Errors=$Errors"
    )
}


# ============================================================
# RESOLVE AWS RESOURCE IDENTIFIERS
# ============================================================

$InstanceId = Get-TerraformOutput `
    -Directory "terraform/ec2" `
    -OutputName "instance_id"

$LambdaName = Get-TerraformOutput `
    -Directory "terraform/serverless" `
    -OutputName "lambda_function_name"

$ServerlessComputeUrl = Get-TerraformOutput `
    -Directory "terraform/serverless" `
    -OutputName "compute_url"


if (
    $ServerlessComputeUrl -notmatch
    '^https://([^.]+)\.execute-api\.'
) {

    throw (
        "Unable to derive API Gateway API ID from: " +
        $ServerlessComputeUrl
    )
}

$ApiId = $Matches[1]


Write-Host ""
Write-Host "AWS resources resolved:" -ForegroundColor Cyan
Write-Host "EC2 Instance ID : $InstanceId"
Write-Host "Lambda function : $LambdaName"
Write-Host "API Gateway ID  : $ApiId"
Write-Host "Region          : $Region"


# ============================================================
# DISCOVER EXACT CLOUDWATCH DIMENSIONS
# ============================================================

$Ec2DiscoveryPath = Join-Path `
    $DiscoveryDir `
    "ec2_cpu_metric_dimensions.json"

$LambdaDiscoveryPath = Join-Path `
    $DiscoveryDir `
    "lambda_invocations_metric_dimensions.json"

$ApiDiscoveryPath = Join-Path `
    $DiscoveryDir `
    "apigateway_count_metric_dimensions.json"


$Ec2Discovery = Invoke-AwsJson `
    -Arguments @(
        "cloudwatch",
        "list-metrics",
        "--namespace","AWS/EC2",
        "--metric-name","CPUUtilization",
        "--dimensions",
        "Name=InstanceId,Value=$InstanceId",
        "--region",$Region
    ) `
    -OutputPath $Ec2DiscoveryPath `
    -AllowExisting:$Resume


$LambdaDiscovery = Invoke-AwsJson `
    -Arguments @(
        "cloudwatch",
        "list-metrics",
        "--namespace","AWS/Lambda",
        "--metric-name","Invocations",
        "--dimensions",
        "Name=FunctionName,Value=$LambdaName",
        "--region",$Region
    ) `
    -OutputPath $LambdaDiscoveryPath `
    -AllowExisting:$Resume


$ApiDiscovery = Invoke-AwsJson `
    -Arguments @(
        "cloudwatch",
        "list-metrics",
        "--namespace","AWS/ApiGateway",
        "--metric-name","Count",
        "--dimensions",
        "Name=ApiId,Value=$ApiId",
        "--region",$Region
    ) `
    -OutputPath $ApiDiscoveryPath `
    -AllowExisting:$Resume


$Ec2DimensionOK = Test-ExactDimensionSeries `
    -DiscoveryObject $Ec2Discovery `
    -DimensionName "InstanceId" `
    -DimensionValue $InstanceId

$LambdaDimensionOK = Test-ExactDimensionSeries `
    -DiscoveryObject $LambdaDiscovery `
    -DimensionName "FunctionName" `
    -DimensionValue $LambdaName

$ApiDimensionOK = Test-ExactDimensionSeries `
    -DiscoveryObject $ApiDiscovery `
    -DimensionName "ApiId" `
    -DimensionValue $ApiId


if (-not $Ec2DimensionOK) {
    throw "Exact AWS/EC2 InstanceId metric series not found."
}

if (-not $LambdaDimensionOK) {
    throw "Exact AWS/Lambda FunctionName metric series not found."
}

if (-not $ApiDimensionOK) {
    throw "Exact AWS/ApiGateway ApiId metric series not found."
}


Write-Host ""
Write-Host "CloudWatch dimension discovery: PASS" -ForegroundColor Green


# ============================================================
# METRIC DEFINITIONS
# ============================================================

$Ec2Definitions = @(
    [PSCustomObject]@{
        Metric    = "CPUUtilization"
        Statistic = "Average"
    },
    [PSCustomObject]@{
        Metric    = "CPUUtilization"
        Statistic = "Maximum"
    },
    [PSCustomObject]@{
        Metric    = "NetworkIn"
        Statistic = "Sum"
    },
    [PSCustomObject]@{
        Metric    = "NetworkOut"
        Statistic = "Sum"
    },
    [PSCustomObject]@{
        Metric    = "StatusCheckFailed"
        Statistic = "Maximum"
    }
)


$LambdaDefinitions = @(
    [PSCustomObject]@{
        Metric    = "Invocations"
        Statistic = "Sum"
    },
    [PSCustomObject]@{
        Metric    = "Duration"
        Statistic = "Average"
    },
    [PSCustomObject]@{
        Metric    = "Errors"
        Statistic = "Sum"
    },
    [PSCustomObject]@{
        Metric    = "Throttles"
        Statistic = "Sum"
    },
    [PSCustomObject]@{
        Metric    = "ConcurrentExecutions"
        Statistic = "Maximum"
    }
)


$ApiDefinitions = @(
    [PSCustomObject]@{
        Metric    = "Count"
        Statistic = "Sum"
    },
    [PSCustomObject]@{
        Metric    = "4xx"
        Statistic = "Sum"
    },
    [PSCustomObject]@{
        Metric    = "5xx"
        Statistic = "Sum"
    },
    [PSCustomObject]@{
        Metric    = "Latency"
        Statistic = "Average"
    },
    [PSCustomObject]@{
        Metric    = "IntegrationLatency"
        Statistic = "Average"
    }
)


# ============================================================
# EXTRACTION STATE
# ============================================================

$QueryLog = @()
$Datapoints = @()

$ExpectedQueries = 270
$AwsQueryFailures = 0
$AnchorMissing = @()
$MetadataProblems = @()


function Invoke-MetricExtraction {

    param(
        [string]$ExperimentId,
        [string]$Architecture,
        [string]$Service,
        [string]$Namespace,
        [string]$Metric,
        [string]$Statistic,
        [string]$DimensionName,
        [string]$DimensionValue,
        [string]$StartUtc,
        [string]$EndUtc,
        [string]$OutputDirectory,
        [bool]$AnchorMetric
    )


    $SafeMetric = $Metric `
        -replace '[^A-Za-z0-9_-]', '_'

    $FileName = (
        "{0}_{1}_{2}.json" -f
        $ExperimentId,
        $SafeMetric,
        $Statistic
    )

    $OutputPath = Join-Path `
        $OutputDirectory `
        $FileName


    try {

        $Response = Invoke-AwsJson `
            -Arguments @(
                "cloudwatch",
                "get-metric-statistics",
                "--namespace",$Namespace,
                "--metric-name",$Metric,
                "--dimensions",
                "Name=$DimensionName,Value=$DimensionValue",
                "--start-time",$StartUtc,
                "--end-time",$EndUtc,
                "--period","60",
                "--statistics",$Statistic,
                "--region",$Region
            ) `
            -OutputPath $OutputPath `
            -AllowExisting:$Resume
    }
    catch {

        $script:AwsQueryFailures++

        $script:QueryLog += [PSCustomObject]@{
            experiment_id  = $ExperimentId
            architecture   = $Architecture
            service        = $Service
            namespace      = $Namespace
            metric_name    = $Metric
            statistic      = $Statistic
            run_start_utc  = $StartUtc
            run_end_utc    = $EndUtc
            period_seconds = 60
            dimension_name = $DimensionName
            dimension_value= $DimensionValue
            datapoint_count= 0
            query_status   = "AWS_QUERY_ERROR"
            raw_json_file  = $OutputPath
        }

        throw
    }


    $Points = @(
        $Response.Datapoints
    )

    $QueryStatus = "OK"

    if ($Points.Count -eq 0) {
        $QueryStatus = "NO_DATAPOINT"
    }


    if (
        $AnchorMetric -and
        ($Points.Count -eq 0)
    ) {

        $script:AnchorMissing += (
            "$ExperimentId/$Service/$Metric/$Statistic"
        )
    }


    $script:QueryLog += [PSCustomObject]@{
        experiment_id   = $ExperimentId
        architecture    = $Architecture
        service         = $Service
        namespace       = $Namespace
        metric_name     = $Metric
        statistic       = $Statistic
        run_start_utc   = $StartUtc
        run_end_utc     = $EndUtc
        period_seconds  = 60
        dimension_name  = $DimensionName
        dimension_value = $DimensionValue
        datapoint_count = $Points.Count
        query_status    = $QueryStatus
        raw_json_file   = $OutputPath
    }


    if ($Points.Count -eq 0) {

        $script:Datapoints += [PSCustomObject]@{
            experiment_id      = $ExperimentId
            architecture       = $Architecture
            service            = $Service
            metric_name        = $Metric
            statistic          = $Statistic
            run_start_utc      = $StartUtc
            run_end_utc        = $EndUtc
            datapoint_utc      = ""
            value              = ""
            unit               = Get-ExpectedUnit `
                                     -Service $Service `
                                     -Metric $Metric
            datapoint_status   = "NO_DATAPOINT"
            raw_json_file      = $OutputPath
        }

        return
    }


    foreach (
        $Point in (
            $Points |
            Sort-Object Timestamp
        )
    ) {

        $Value = $Point.$Statistic

        $TimestampUtc = (
            [DateTimeOffset]::Parse(
                $Point.Timestamp.ToString()
            )
        ).UtcDateTime.ToString(
            "yyyy-MM-ddTHH:mm:ss.fffZ"
        )

        $Unit = ""

        if ($Point.Unit) {
            $Unit = $Point.Unit
        }

        if ([string]::IsNullOrWhiteSpace($Unit)) {

            $Unit = Get-ExpectedUnit `
                -Service $Service `
                -Metric $Metric
        }


        $script:Datapoints += [PSCustomObject]@{
            experiment_id      = $ExperimentId
            architecture       = $Architecture
            service            = $Service
            metric_name        = $Metric
            statistic          = $Statistic
            run_start_utc      = $StartUtc
            run_end_utc        = $EndUtc
            datapoint_utc      = $TimestampUtc
            value              = $Value
            unit               = $Unit
            datapoint_status   = "RETURNED"
            raw_json_file      = $OutputPath
        }
    }
}


# ============================================================
# EXTRACT ALL 36 TRIALS
# ============================================================

$Counter = 0

foreach ($Experiment in $Matrix) {

    $Id = $Experiment.experiment_id

    $MetadataPath = Join-Path `
        $MetadataDir `
        "${Id}_metadata.csv"


    if (-not (Test-Path $MetadataPath)) {

        $MetadataProblems += (
            "$Id metadata missing"
        )

        continue
    }


    $MetaRows = @(
        Import-Csv $MetadataPath
    )

    if ($MetaRows.Count -ne 1) {

        $MetadataProblems += (
            "$Id metadata row count=" +
            "$($MetaRows.Count)"
        )

        continue
    }


    $Meta = $MetaRows[0]

    $StartUtc = $Meta.run_start_utc
    $EndUtc = $Meta.run_end_utc


    if (
        [string]::IsNullOrWhiteSpace($StartUtc) -or
        [string]::IsNullOrWhiteSpace($EndUtc)
    ) {

        $MetadataProblems += (
            "$Id missing UTC window"
        )

        continue
    }


    Write-Host ""
    Write-Host (
        "[$Id] extracting CloudWatch metrics..."
    ) -ForegroundColor Cyan


    if ($Experiment.architecture -eq "EC2") {

        foreach ($Definition in $Ec2Definitions) {

            $Counter++

            Invoke-MetricExtraction `
                -ExperimentId $Id `
                -Architecture "EC2" `
                -Service "EC2" `
                -Namespace "AWS/EC2" `
                -Metric $Definition.Metric `
                -Statistic $Definition.Statistic `
                -DimensionName "InstanceId" `
                -DimensionValue $InstanceId `
                -StartUtc $StartUtc `
                -EndUtc $EndUtc `
                -OutputDirectory $Ec2RawDir `
                -AnchorMetric $true
        }
    }


    if ($Experiment.architecture -eq "SVL") {

        foreach ($Definition in $LambdaDefinitions) {

            $Counter++

            $Anchor = $false

            if (
                ($Definition.Metric -eq "Invocations") -or
                ($Definition.Metric -eq "Duration") -or
                ($Definition.Metric -eq "ConcurrentExecutions")
            ) {
                $Anchor = $true
            }

            Invoke-MetricExtraction `
                -ExperimentId $Id `
                -Architecture "SVL" `
                -Service "Lambda" `
                -Namespace "AWS/Lambda" `
                -Metric $Definition.Metric `
                -Statistic $Definition.Statistic `
                -DimensionName "FunctionName" `
                -DimensionValue $LambdaName `
                -StartUtc $StartUtc `
                -EndUtc $EndUtc `
                -OutputDirectory $LambdaRawDir `
                -AnchorMetric $Anchor
        }


        foreach ($Definition in $ApiDefinitions) {

            $Counter++

            $Anchor = $false

            if (
                ($Definition.Metric -eq "Count") -or
                ($Definition.Metric -eq "Latency") -or
                ($Definition.Metric -eq "IntegrationLatency")
            ) {
                $Anchor = $true
            }

            Invoke-MetricExtraction `
                -ExperimentId $Id `
                -Architecture "SVL" `
                -Service "APIGateway" `
                -Namespace "AWS/ApiGateway" `
                -Metric $Definition.Metric `
                -Statistic $Definition.Statistic `
                -DimensionName "ApiId" `
                -DimensionValue $ApiId `
                -StartUtc $StartUtc `
                -EndUtc $EndUtc `
                -OutputDirectory $ApiRawDir `
                -AnchorMetric $Anchor
        }
    }
}


# ============================================================
# SAVE NORMALIZED EXTRACTION RECORDS
# ============================================================

$QueryLog |
    Export-Csv `
        -Path $QueryLogPath `
        -NoTypeInformation `
        -Encoding UTF8

$Datapoints |
    Export-Csv `
        -Path $DatapointPath `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# FINAL AUDIT
# ============================================================

$Ec2JsonFiles = @(
    Get-ChildItem `
        $Ec2RawDir `
        -File `
        -Filter "*.json"
).Count

$LambdaJsonFiles = @(
    Get-ChildItem `
        $LambdaRawDir `
        -File `
        -Filter "*.json"
).Count

$ApiJsonFiles = @(
    Get-ChildItem `
        $ApiRawDir `
        -File `
        -Filter "*.json"
).Count

$DiscoveryFiles = @(
    Get-ChildItem `
        $DiscoveryDir `
        -File `
        -Filter "*.json"
).Count

$RawMetricJsonFiles =
    $Ec2JsonFiles +
    $LambdaJsonFiles +
    $ApiJsonFiles


$NoDatapointQueries = @(
    $QueryLog |
    Where-Object {
        $_.query_status -eq "NO_DATAPOINT"
    }
).Count


Clear-Host

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " DAY 2 - TASK 23 - CLOUDWATCH EXTRACTION AUDIT" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Resources"
Write-Host "---------"
Write-Host "Region                 : $Region"
Write-Host "EC2 Instance           : $InstanceId"
Write-Host "Lambda Function        : $LambdaName"
Write-Host "API Gateway ID         : $ApiId"

Write-Host ""
Write-Host "Dimension discovery"
Write-Host "-------------------"
Write-Host "EC2 InstanceId series  : $Ec2DimensionOK"
Write-Host "Lambda Function series : $LambdaDimensionOK"
Write-Host "API Gateway ApiId      : $ApiDimensionOK"

Write-Host ""
Write-Host "Extraction"
Write-Host "----------"
Write-Host "Formal experiments     : 36 / 36"
Write-Host "Exact UTC windows read : $(36 - $MetadataProblems.Count) / 36"
Write-Host "CloudWatch queries     : $Counter / $ExpectedQueries"
Write-Host "EC2 metric JSON files  : $Ec2JsonFiles / 90"
Write-Host "Lambda JSON files      : $LambdaJsonFiles / 90"
Write-Host "API Gateway JSON files : $ApiJsonFiles / 90"
Write-Host "Raw metric JSON total  : $RawMetricJsonFiles / 270"
Write-Host "Discovery JSON files   : $DiscoveryFiles / 3"
Write-Host "No-datapoint queries   : $NoDatapointQueries"
Write-Host "Anchor metrics missing : $($AnchorMissing.Count)"
Write-Host "AWS query failures     : $AwsQueryFailures"
Write-Host "Metadata problems      : $($MetadataProblems.Count)"

Write-Host ""
Write-Host "Processed indexes"
Write-Host "-----------------"
Write-Host "Query log rows          : $($QueryLog.Count)"
Write-Host "Datapoint rows          : $($Datapoints.Count)"


$Task23Passed = $true

if ($Counter -ne 270) {
    $Task23Passed = $false
}

if ($Ec2JsonFiles -ne 90) {
    $Task23Passed = $false
}

if ($LambdaJsonFiles -ne 90) {
    $Task23Passed = $false
}

if ($ApiJsonFiles -ne 90) {
    $Task23Passed = $false
}

if ($RawMetricJsonFiles -ne 270) {
    $Task23Passed = $false
}

if ($DiscoveryFiles -ne 3) {
    $Task23Passed = $false
}

if ($AnchorMissing.Count -ne 0) {
    $Task23Passed = $false
}

if ($AwsQueryFailures -ne 0) {
    $Task23Passed = $false
}

if ($MetadataProblems.Count -ne 0) {
    $Task23Passed = $false
}

if ($QueryLog.Count -ne 270) {
    $Task23Passed = $false
}


if ($Task23Passed) {

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host " TASK 23 PASSED" -ForegroundColor Green
    Write-Host " CLOUDWATCH DATA EXTRACTED FOR ALL 36 FORMAL RUNS" -ForegroundColor Green
    Write-Host " EXACT FORMAL UTC WINDOWS USED" -ForegroundColor Green
    Write-Host " 270 / 270 METRIC QUERIES PRESERVED" -ForegroundColor Green
    Write-Host " EC2 MONITORING DATA COMPLETE" -ForegroundColor Green
    Write-Host " LAMBDA MONITORING DATA COMPLETE" -ForegroundColor Green
    Write-Host " API GATEWAY MONITORING DATA COMPLETE" -ForegroundColor Green
    Write-Host " RAW CLOUDWATCH DATA KEPT SEPARATE" -ForegroundColor Green
    Write-Host " READY FOR FORMAL DATASET POPULATION" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
}


if (-not $Task23Passed) {

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Red
    Write-Host " TASK 23 NEEDS REVIEW" -ForegroundColor Red
    Write-Host " DO NOT POPULATE experiments.csv YET" -ForegroundColor Red
    Write-Host "========================================================" -ForegroundColor Red

    if ($AnchorMissing.Count -gt 0) {

        Write-Host ""
        Write-Host "Missing anchor metrics:" -ForegroundColor Yellow

        $AnchorMissing
    }

    if ($MetadataProblems.Count -gt 0) {

        Write-Host ""
        Write-Host "Metadata problems:" -ForegroundColor Yellow

        $MetadataProblems
    }
}
