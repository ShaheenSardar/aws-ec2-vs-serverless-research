Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Region = "ap-south-1"
$PricingEndpointRegion = "us-east-1"
$Location = "Asia Pacific (Mumbai)"

$RepoRoot = (Resolve-Path ".").Path

$DatasetPath = Join-Path `
    $RepoRoot `
    "data\final\experiments.csv"

$BackupPath = Join-Path `
    $RepoRoot `
    "data\processed\formal\experiments-before-task25-v4.csv"

$BreakdownPath = Join-Path `
    $RepoRoot `
    "data\processed\formal\cost-breakdown.csv"

$SnapshotPath = Join-Path `
    $RepoRoot `
    "data\processed\formal\aws-pricing-snapshot.csv"

$PricingRawDir = Join-Path `
    $RepoRoot `
    "data\raw\formal\pricing-v4"

New-Item `
    -ItemType Directory `
    -Force `
    $PricingRawDir |
    Out-Null

$Invariant =
    [Globalization.CultureInfo]::InvariantCulture


# ============================================================
# NUMERIC HELPERS
# ============================================================

function To-Decimal {

    param(
        [string]$Value,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing numeric value: $Label"
    }

    return [decimal]::Parse(
        $Value,
        [Globalization.NumberStyles]::Float,
        $Invariant
    )
}


function Format-Cost {

    param(
        [decimal]$Value
    )

    return $Value.ToString(
        "0.000000000000",
        $Invariant
    )
}


function Get-Optional {

    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return ""
    }

    $Property =
        $Object.PSObject.Properties[$Name]

    if ($null -eq $Property) {
        return ""
    }

    if ($null -eq $Property.Value) {
        return ""
    }

    return [string]$Property.Value
}


# ============================================================
# NATIVE COMMAND HELPERS
# ============================================================

function Invoke-AwsJson {

    param(
        [string[]]$Arguments
    )

    $PreviousPreference =
        $ErrorActionPreference

    $ErrorActionPreference =
        "Continue"

    $ErrorFile = Join-Path `
        $env:TEMP `
        (
            "aws-" +
            [guid]::NewGuid().ToString() +
            ".err"
        )

    try {

        $Output = @(
            & aws `
                @Arguments `
                --no-cli-pager `
                --output json `
                2>$ErrorFile
        )

        $ExitCode =
            $LASTEXITCODE
    }
    finally {

        $ErrorActionPreference =
            $PreviousPreference
    }


    $ErrorText = ""

    if (Test-Path $ErrorFile) {

        $ErrorText =
            Get-Content `
                $ErrorFile `
                -Raw `
                -ErrorAction SilentlyContinue

        Remove-Item `
            $ErrorFile `
            -Force `
            -ErrorAction SilentlyContinue
    }


    if ($ExitCode -ne 0) {

        throw (
            "AWS CLI failed. ExitCode=$ExitCode. " +
            $ErrorText
        )
    }


    $Text =
        ($Output -join "`n").Trim()

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "AWS CLI returned empty JSON."
    }


    return (
        $Text |
        ConvertFrom-Json
    )
}


function Get-TerraformOutput {

    param(
        [string]$Directory,
        [string]$OutputName
    )

    $PreviousPreference =
        $ErrorActionPreference

    $ErrorActionPreference =
        "Continue"

    try {

        $Output = @(
            & terraform `
                "-chdir=$Directory" `
                output `
                -raw `
                $OutputName `
                2>$null
        )

        $ExitCode =
            $LASTEXITCODE
    }
    finally {

        $ErrorActionPreference =
            $PreviousPreference
    }


    if ($ExitCode -ne 0) {

        throw (
            "Terraform output failed: " +
            "$Directory / $OutputName"
        )
    }


    return (
        ($Output -join "`n").Trim()
    )
}


# ============================================================
# AWS PRICE LIST QUERY
# ============================================================

function Invoke-PricingQuery {

    param(
        [string]$ServiceCode,
        [string[]]$Filters,
        [string]$RawFileName
    )

    $Arguments = @(
        "pricing",
        "get-products",
        "--service-code",
        $ServiceCode,
        "--format-version",
        "aws_v1",
        "--region",
        $PricingEndpointRegion,
        "--filters"
    )

    foreach ($Filter in $Filters) {
        $Arguments += $Filter
    }


    $Response =
        Invoke-AwsJson `
            -Arguments $Arguments


    if (@($Response.PriceList).Count -eq 0) {

        throw (
            "AWS returned zero pricing products for " +
            "$ServiceCode."
        )
    }


    $RawPath =
        Join-Path `
            $PricingRawDir `
            $RawFileName


    $RawJson =
        $Response |
        ConvertTo-Json `
            -Depth 20


    $Utf8NoBom =
        New-Object `
            System.Text.UTF8Encoding($false)


    [System.IO.File]::WriteAllText(
        $RawPath,
        $RawJson,
        $Utf8NoBom
    )


    return $Response
}


# ============================================================
# ROBUST PRICE RESOLVER
#
# No mandatory Lambda/API unit string.
# ============================================================

function Resolve-PaidPrice {

    param(
        [object]$Response,
        [string]$Component,
        [string[]]$AllowedUnits = @(),
        [string]$ExcludeUsageRegex = ""
    )

    $Candidates = @()


    foreach ($PriceString in @($Response.PriceList)) {

        if (
            [string]::IsNullOrWhiteSpace(
                [string]$PriceString
            )
        ) {
            continue
        }


        $Offer =
            $PriceString |
            ConvertFrom-Json


        if ($null -eq $Offer.product) {
            continue
        }


        $AttributesProperty =
            $Offer.product.PSObject.Properties[
                "attributes"
            ]

        $Attributes = $null

        if ($null -ne $AttributesProperty) {
            $Attributes = $AttributesProperty.Value
        }


        $UsageType =
            Get-Optional `
                $Attributes `
                "usagetype"


        if (
            -not [string]::IsNullOrWhiteSpace(
                $ExcludeUsageRegex
            )
        ) {

            if (
                $UsageType -match
                $ExcludeUsageRegex
            ) {
                continue
            }
        }


        $OnDemandProperty =
            $Offer.terms.PSObject.Properties[
                "OnDemand"
            ]

        if ($null -eq $OnDemandProperty) {
            continue
        }


        foreach (
            $TermProperty in
            $OnDemandProperty.Value.
                PSObject.Properties
        ) {

            $Term =
                $TermProperty.Value


            $DimensionsProperty =
                $Term.PSObject.Properties[
                    "priceDimensions"
                ]

            if ($null -eq $DimensionsProperty) {
                continue
            }


            foreach (
                $DimensionProperty in
                $DimensionsProperty.Value.
                    PSObject.Properties
            ) {

                $Dimension =
                    $DimensionProperty.Value


                $Unit =
                    Get-Optional `
                        $Dimension `
                        "unit"


                if ($AllowedUnits.Count -gt 0) {

                    if ($Unit -notin $AllowedUnits) {
                        continue
                    }
                }


                $PricePerUnitProperty =
                    $Dimension.PSObject.Properties[
                        "pricePerUnit"
                    ]

                if ($null -eq $PricePerUnitProperty) {
                    continue
                }


                $UsdProperty =
                    $PricePerUnitProperty.Value.
                        PSObject.Properties[
                            "USD"
                        ]

                if ($null -eq $UsdProperty) {
                    continue
                }


                $UsdText =
                    [string]$UsdProperty.Value


                if (
                    [string]::IsNullOrWhiteSpace(
                        $UsdText
                    )
                ) {
                    continue
                }


                $Rate =
                    To-Decimal `
                        $UsdText `
                        "$Component rate"


                # Exclude Free Tier / zero price.
                if ($Rate -le 0) {
                    continue
                }


                $BeginText =
                    Get-Optional `
                        $Dimension `
                        "beginRange"

                if (
                    [string]::IsNullOrWhiteSpace(
                        $BeginText
                    )
                ) {
                    $BeginText = "0"
                }


                $BeginNumber = [decimal]0

                try {

                    $BeginNumber =
                        [decimal]::Parse(
                            $BeginText,
                            [Globalization.NumberStyles]::Float,
                            $Invariant
                        )
                }
                catch {

                    $BeginNumber =
                        [decimal]0
                }


                $Candidates +=
                    [PSCustomObject]@{

                        component =
                            $Component

                        rate_usd =
                            $Rate

                        unit =
                            $Unit

                        begin_range =
                            $BeginText

                        begin_numeric =
                            $BeginNumber

                        end_range =
                            Get-Optional `
                                $Dimension `
                                "endRange"

                        sku =
                            Get-Optional `
                                $Offer.product `
                                "sku"

                        usage_type =
                            $UsageType

                        description =
                            Get-Optional `
                                $Dimension `
                                "description"

                        effective_date =
                            Get-Optional `
                                $Term `
                                "effectiveDate"
                    }
            }
        }
    }


    if ($Candidates.Count -eq 0) {

        throw (
            "NO POSITIVE PRICE CANDIDATES: " +
            "$Component"
        )
    }


    # First paid tier.
    $LowestBegin =
        (
            $Candidates |
            Measure-Object `
                -Property begin_numeric `
                -Minimum
        ).Minimum


    $FirstTier = @(
        $Candidates |
        Where-Object {

            [decimal]$_.begin_numeric -eq
            [decimal]$LowestBegin
        }
    )


    $DistinctRates = @(
        $FirstTier |
        Select-Object `
            -ExpandProperty rate_usd `
            -Unique
    )


    if ($DistinctRates.Count -ne 1) {

        Write-Host ""
        Write-Host (
            "AMBIGUOUS PRICE: $Component"
        ) -ForegroundColor Red


        $FirstTier |
            Select-Object `
                rate_usd,
                unit,
                begin_range,
                usage_type,
                sku,
                description |
            Format-Table -AutoSize


        throw (
            "Multiple distinct first-tier prices " +
            "found for $Component."
        )
    }


    $SelectedRate =
        [decimal]$DistinctRates[0]


    $Selected = @(
        $FirstTier |
        Where-Object {

            [decimal]$_.rate_usd -eq
            $SelectedRate
        }
    )[0]


    Write-Host (
        "PRICE RESOLVED | {0} | {1} {2} | usage={3}" -f `
            $Component,
            $Selected.rate_usd,
            $Selected.unit,
            $Selected.usage_type
    ) -ForegroundColor Green


    return $Selected
}


# ============================================================
# DATASET SAFETY CHECK
# ============================================================

if (-not (Test-Path $DatasetPath)) {
    throw "experiments.csv missing."
}


$Dataset =
    @(Import-Csv $DatasetPath)


if ($Dataset.Count -ne 36) {
    throw "Dataset must contain 36 rows."
}


$ColumnCount =
    (
        $Dataset[0].
            PSObject.Properties |
        Measure-Object
    ).Count


if ($ColumnCount -ne 44) {
    throw "Dataset must contain 44 columns."
}


$CostPending = 0
$OtherPending = 0


foreach ($Row in $Dataset) {

    foreach (
        $Property in
        $Row.PSObject.Properties
    ) {

        if (
            $Property.Value -eq
            "TO_BE_MEASURED"
        ) {

            if (
                $Property.Name -in @(
                    "actual_cost_usd",
                    "estimated_cost_usd",
                    "cost_per_1000_successful_requests_usd"
                )
            ) {

                $CostPending++
            }
            else {

                $OtherPending++
            }
        }
    }
}


if ($CostPending -ne 108) {

    throw (
        "Expected exactly 108 pending cost cells. " +
        "Found $CostPending."
    )
}


if ($OtherPending -ne 0) {

    throw (
        "Non-cost TO_BE_MEASURED cells remain: " +
        "$OtherPending"
    )
}


if (-not (Test-Path $BackupPath)) {

    Copy-Item `
        $DatasetPath `
        $BackupPath
}


Write-Host ""
Write-Host "TASK 24 DATASET SAFETY: PASS" -ForegroundColor Green


# ============================================================
# VERIFY ACTUAL INFRASTRUCTURE
# ============================================================

$InstanceId =
    Get-TerraformOutput `
        "terraform/ec2" `
        "instance_id"


$LambdaName =
    Get-TerraformOutput `
        "terraform/serverless" `
        "lambda_function_name"


$InstanceResponse =
    Invoke-AwsJson @(
        "ec2",
        "describe-instances",
        "--instance-ids",
        $InstanceId,
        "--region",
        $Region
    )


$Instance =
    $InstanceResponse.
        Reservations[0].
        Instances[0]


if ($Instance.InstanceType -ne "t3.small") {

    throw (
        "Expected t3.small; found " +
        "$($Instance.InstanceType)"
    )
}


$HasPublicIpv4 =
    -not [string]::IsNullOrWhiteSpace(
        [string]$Instance.PublicIpAddress
    )


$VolumeResponse =
    Invoke-AwsJson @(
        "ec2",
        "describe-volumes",
        "--filters",
        "Name=attachment.instance-id,Values=$InstanceId",
        "--region",
        $Region
    )


$Volumes =
    @($VolumeResponse.Volumes)


if ($Volumes.Count -lt 1) {
    throw "No EC2 EBS volume found."
}


$TotalGp3GB = 0


foreach ($Volume in $Volumes) {

    if ($Volume.VolumeType -ne "gp3") {

        throw (
            "Non-gp3 volume detected: " +
            "$($Volume.VolumeType)"
        )
    }


    if ([int]$Volume.Iops -gt 3000) {

        throw (
            "gp3 IOPS above baseline. " +
            "Extra IOPS pricing must be modeled."
        )
    }


    if (
        $Volume.Throughput -and
        ([int]$Volume.Throughput -gt 125)
    ) {

        throw (
            "gp3 throughput above baseline. " +
            "Extra throughput pricing must be modeled."
        )
    }


    $TotalGp3GB +=
        [int]$Volume.Size
}


$LambdaConfig =
    Invoke-AwsJson @(
        "lambda",
        "get-function-configuration",
        "--function-name",
        $LambdaName,
        "--region",
        $Region
    )


$LambdaMemoryMB =
    [int]$LambdaConfig.MemorySize


$LambdaArchitecture =
    [string]$LambdaConfig.Architectures[0]


if ($LambdaArchitecture -ne "x86_64") {

    throw (
        "Expected x86_64 Lambda; found " +
        "$LambdaArchitecture"
    )
}


$LambdaMemoryGB =
    [decimal]$LambdaMemoryMB /
    [decimal]1024


# ============================================================
# CURRENT REGIONAL AWS PRICING
# ============================================================

Write-Host ""
Write-Host "Resolving current AWS prices..." -ForegroundColor Cyan


# ------------------------------------------------------------
# EC2 t3.small Linux
# ------------------------------------------------------------

$Ec2Response =
    Invoke-PricingQuery `
        -ServiceCode "AmazonEC2" `
        -RawFileName "ec2-t3-small-mumbai.json" `
        -Filters @(
            "Type=TERM_MATCH,Field=location,Value=$Location",
            "Type=TERM_MATCH,Field=instanceType,Value=t3.small",
            "Type=TERM_MATCH,Field=operatingSystem,Value=Linux",
            "Type=TERM_MATCH,Field=tenancy,Value=Shared",
            "Type=TERM_MATCH,Field=preInstalledSw,Value=NA",
            "Type=TERM_MATCH,Field=capacitystatus,Value=Used"
        )


$Ec2Price =
    Resolve-PaidPrice `
        -Response $Ec2Response `
        -Component "EC2 t3.small Linux" `
        -AllowedUnits @("Hrs")


# ------------------------------------------------------------
# EBS gp3
# ------------------------------------------------------------

$EbsResponse =
    Invoke-PricingQuery `
        -ServiceCode "AmazonEC2" `
        -RawFileName "ebs-gp3-mumbai.json" `
        -Filters @(
            "Type=TERM_MATCH,Field=location,Value=$Location",
            "Type=TERM_MATCH,Field=volumeApiName,Value=gp3"
        )


$EbsPrice =
    Resolve-PaidPrice `
        -Response $EbsResponse `
        -Component "EBS gp3 storage" `
        -AllowedUnits @("GB-Mo")


# ------------------------------------------------------------
# Lambda requests
#
# IMPORTANT:
# Match AWS usagetype, NOT Unit.
# ------------------------------------------------------------

$LambdaRequestResponse =
    Invoke-PricingQuery `
        -ServiceCode "AWSLambda" `
        -RawFileName "lambda-requests-mumbai.json" `
        -Filters @(
            "Type=TERM_MATCH,Field=location,Value=$Location",
            "Type=CONTAINS,Field=usagetype,Value=Lambda-Request"
        )


$LambdaRequestPrice =
    Resolve-PaidPrice `
        -Response $LambdaRequestResponse `
        -Component "Lambda standard requests" `
        -ExcludeUsageRegex "(?i)Edge|Managed"


# ------------------------------------------------------------
# Lambda x86 GB-second duration
#
# No hard-coded Unit.
# ARM / Provisioned / special products excluded.
# ------------------------------------------------------------

$LambdaDurationResponse =
    Invoke-PricingQuery `
        -ServiceCode "AWSLambda" `
        -RawFileName "lambda-x86-duration-mumbai.json" `
        -Filters @(
            "Type=TERM_MATCH,Field=location,Value=$Location",
            "Type=CONTAINS,Field=usagetype,Value=Lambda-GB-Second"
        )


$LambdaDurationPrice =
    Resolve-PaidPrice `
        -Response $LambdaDurationResponse `
        -Component "Lambda standard x86 duration" `
        -ExcludeUsageRegex "(?i)ARM|Provisioned|SnapStart|Managed|Ephemeral|Streaming"


# ------------------------------------------------------------
# API Gateway HTTP API
# ------------------------------------------------------------

$ApiResponse =
    Invoke-PricingQuery `
        -ServiceCode "AmazonApiGateway" `
        -RawFileName "api-gateway-http-mumbai.json" `
        -Filters @(
            "Type=TERM_MATCH,Field=location,Value=$Location",
            "Type=CONTAINS,Field=usagetype,Value=ApiGatewayHttpApi"
        )


$ApiPrice =
    Resolve-PaidPrice `
        -Response $ApiResponse `
        -Component "API Gateway HTTP API requests"


# ------------------------------------------------------------
# Public IPv4
#
# AWS commercial-region in-use public IPv4 rate.
# ------------------------------------------------------------

$PublicIpv4HourlyRate =
    [decimal]"0.005"


# ============================================================
# PRICING SNAPSHOT
# ============================================================

$PricingSnapshot = @(
    [PSCustomObject]@{
        component="EC2 t3.small Linux"
        rate_usd=$Ec2Price.rate_usd
        unit=$Ec2Price.unit
        usage_type=$Ec2Price.usage_type
        effective_date=$Ec2Price.effective_date
        region=$Region
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="EBS gp3 storage"
        rate_usd=$EbsPrice.rate_usd
        unit=$EbsPrice.unit
        usage_type=$EbsPrice.usage_type
        effective_date=$EbsPrice.effective_date
        region=$Region
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="Lambda standard requests"
        rate_usd=$LambdaRequestPrice.rate_usd
        unit=$LambdaRequestPrice.unit
        usage_type=$LambdaRequestPrice.usage_type
        effective_date=$LambdaRequestPrice.effective_date
        region=$Region
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="Lambda standard x86 duration"
        rate_usd=$LambdaDurationPrice.rate_usd
        unit=$LambdaDurationPrice.unit
        usage_type=$LambdaDurationPrice.usage_type
        effective_date=$LambdaDurationPrice.effective_date
        region=$Region
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="API Gateway HTTP API requests"
        rate_usd=$ApiPrice.rate_usd
        unit=$ApiPrice.unit
        usage_type=$ApiPrice.usage_type
        effective_date=$ApiPrice.effective_date
        region=$Region
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="Public IPv4 address"
        rate_usd=$PublicIpv4HourlyRate
        unit="Hrs"
        usage_type="PublicIPv4:InUseAddress"
        effective_date="current"
        region=$Region
        source="AWS VPC pricing"
    }
)


# ============================================================
# CALCULATE ALL 36 TRIALS
# ============================================================

$Breakdown = @()


foreach ($Row in $Dataset) {

    $Id =
        $Row.experiment_id


    Write-Host (
        "Calculating $Id..."
    ) -ForegroundColor Cyan


    $Successful =
        To-Decimal `
            $Row.successful_requests `
            "$Id successful requests"


    if ($Successful -le 0) {
        throw "$Id has zero successful requests."
    }


    $DurationSeconds =
        To-Decimal `
            $Row.duration_seconds `
            "$Id duration"


    $IdleSeconds =
        To-Decimal `
            $Row.idle_before_seconds `
            "$Id idle"


    $AllocatedSeconds =
        $DurationSeconds +
        $IdleSeconds


    $Ec2ComputeCost = [decimal]0
    $EbsCost = [decimal]0
    $Ipv4Cost = [decimal]0

    $LambdaRequestCost = [decimal]0
    $LambdaComputeCost = [decimal]0
    $ApiCost = [decimal]0

    $LambdaGbSeconds = [decimal]0


    # --------------------------------------------------------
    # EC2
    # --------------------------------------------------------

    if ($Row.architecture -eq "EC2") {

        $Ec2ComputeCost =
            [decimal]$Ec2Price.rate_usd *
            (
                $AllocatedSeconds /
                [decimal]3600
            )


        $EbsCost =
            [decimal]$EbsPrice.rate_usd *
            [decimal]$TotalGp3GB *
            (
                $AllocatedSeconds /
                [decimal]2592000
            )


        if ($HasPublicIpv4) {

            $Ipv4Cost =
                $PublicIpv4HourlyRate *
                (
                    $AllocatedSeconds /
                    [decimal]3600
                )
        }
    }


    # --------------------------------------------------------
    # SERVERLESS
    # --------------------------------------------------------

    if ($Row.architecture -eq "SVL") {

        $Invocations =
            To-Decimal `
                $Row.lambda_invocations `
                "$Id Lambda invocations"


        $DurationMs =
            To-Decimal `
                $Row.lambda_duration_avg_ms `
                "$Id Lambda duration"


        $ApiCount =
            To-Decimal `
                $Row.api_gateway_count `
                "$Id API count"


        $LambdaRequestCost =
            $Invocations *
            [decimal]$LambdaRequestPrice.rate_usd


        $LambdaGbSeconds =
            $Invocations *
            (
                $DurationMs /
                [decimal]1000
            ) *
            $LambdaMemoryGB


        $LambdaComputeCost =
            $LambdaGbSeconds *
            [decimal]$LambdaDurationPrice.rate_usd


        $ApiCost =
            $ApiCount *
            [decimal]$ApiPrice.rate_usd
    }


    $EstimatedCost =
        $Ec2ComputeCost +
        $EbsCost +
        $Ipv4Cost +
        $LambdaRequestCost +
        $LambdaComputeCost +
        $ApiCost


    if ($EstimatedCost -le 0) {
        throw "$Id calculated cost is not positive."
    }


    $CostPer1000 =
        (
            $EstimatedCost /
            $Successful
        ) *
        [decimal]1000


    $Row.actual_cost_usd =
        "NOT_DIRECTLY_ATTRIBUTABLE"


    $Row.estimated_cost_usd =
        Format-Cost `
            $EstimatedCost


    $Row.cost_per_1000_successful_requests_usd =
        Format-Cost `
            $CostPer1000


    $Row.notes =
        (
            "Formal measured trial; current AWS " +
            "list-price estimate; Free Tier, credits " +
            "and discounts excluded; exact per-trial " +
            "invoice cost not directly attributable."
        )


    $LambdaRequestsBreakdown =
        "NOT_APPLICABLE"

    $LambdaGbSecondsBreakdown =
        "NOT_APPLICABLE"


    if ($Row.architecture -eq "SVL") {

        $LambdaRequestsBreakdown =
            "$($Row.lambda_invocations)"

        $LambdaGbSecondsBreakdown =
            Format-Cost $LambdaGbSeconds
    }


    $Breakdown +=
        [PSCustomObject]@{

            experiment_id =
                $Id

            architecture =
                $Row.architecture

            workload_id =
                $Row.workload_id

            allocated_seconds =
                $AllocatedSeconds

            ec2_instance_cost_usd =
                Format-Cost $Ec2ComputeCost

            ebs_gp3_cost_usd =
                Format-Cost $EbsCost

            public_ipv4_cost_usd =
                Format-Cost $Ipv4Cost

            lambda_billed_requests =
                $LambdaRequestsBreakdown

            lambda_gb_seconds_estimated =
                $LambdaGbSecondsBreakdown

            lambda_request_cost_usd =
                Format-Cost $LambdaRequestCost

            lambda_compute_cost_usd =
                Format-Cost $LambdaComputeCost

            api_gateway_request_cost_usd =
                Format-Cost $ApiCost

            estimated_cost_usd =
                Format-Cost $EstimatedCost

            successful_requests =
                $Row.successful_requests

            cost_per_1000_successful_requests_usd =
                Format-Cost $CostPer1000

            actual_cost_usd =
                "NOT_DIRECTLY_ATTRIBUTABLE"
        }
}


# ============================================================
# WRITE RESULTS ATOMICALLY
# ============================================================

$TempDataset =
    "$DatasetPath.tmp"


$Dataset |
    Export-Csv `
        $TempDataset `
        -NoTypeInformation `
        -Encoding UTF8


Move-Item `
    $TempDataset `
    $DatasetPath `
    -Force


$Breakdown |
    Export-Csv `
        $BreakdownPath `
        -NoTypeInformation `
        -Encoding UTF8


$PricingSnapshot |
    Export-Csv `
        $SnapshotPath `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# FINAL INTEGRITY AUDIT
# ============================================================

$Final =
    @(Import-Csv $DatasetPath)


$FinalColumns =
    (
        $Final[0].
            PSObject.Properties |
        Measure-Object
    ).Count


$EstimatedCount =
    @(
        $Final |
        Where-Object {

            -not [string]::IsNullOrWhiteSpace(
                $_.estimated_cost_usd
            ) -and

            $_.estimated_cost_usd -ne
            "TO_BE_MEASURED"
        }
    ).Count


$Per1000Count =
    @(
        $Final |
        Where-Object {

            -not [string]::IsNullOrWhiteSpace(
                $_.cost_per_1000_successful_requests_usd
            ) -and

            $_.cost_per_1000_successful_requests_usd -ne
            "TO_BE_MEASURED"
        }
    ).Count


$ActualPolicyCount =
    @(
        $Final |
        Where-Object {

            $_.actual_cost_usd -eq
            "NOT_DIRECTLY_ATTRIBUTABLE"
        }
    ).Count


$RemainingTBM = 0


foreach ($Row in $Final) {

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


Clear-Host

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " DAY 2 - TASK 25 - COST ANALYSIS AUDIT" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Verified infrastructure"
Write-Host "-----------------------"
Write-Host "Region                        : $Region"
Write-Host "EC2 type                      : $($Instance.InstanceType)"
Write-Host "gp3 storage                   : $TotalGp3GB GB"
Write-Host "Public IPv4                   : $HasPublicIpv4"
Write-Host "Lambda memory                 : $LambdaMemoryMB MB"
Write-Host "Lambda architecture           : $LambdaArchitecture"

Write-Host ""
Write-Host "Resolved pricing"
Write-Host "----------------"

$PricingSnapshot |
    Select-Object `
        component,
        rate_usd,
        unit,
        usage_type |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Dataset audit"
Write-Host "-------------"
Write-Host "Rows                          : $($Final.Count) / 36"
Write-Host "Columns                       : $FinalColumns / 44"
Write-Host "Pricing components            : $($PricingSnapshot.Count) / 6"
Write-Host "Cost breakdown rows           : $($Breakdown.Count) / 36"
Write-Host "Estimated costs populated     : $EstimatedCount / 36"
Write-Host "Cost/1000 populated           : $Per1000Count / 36"
Write-Host "Actual limitation marked      : $ActualPolicyCount / 36"
Write-Host "Remaining TO_BE_MEASURED      : $RemainingTBM"


$Pass =
    (
        ($Final.Count -eq 36) -and
        ($FinalColumns -eq 44) -and
        ($PricingSnapshot.Count -eq 6) -and
        ($Breakdown.Count -eq 36) -and
        ($EstimatedCount -eq 36) -and
        ($Per1000Count -eq 36) -and
        ($ActualPolicyCount -eq 36) -and
        ($RemainingTBM -eq 0)
    )


if ($Pass) {

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host " TASK 25 PASSED" -ForegroundColor Green
    Write-Host " CURRENT REGIONAL AWS PRICING RESOLVED" -ForegroundColor Green
    Write-Host " 36 / 36 ESTIMATED COSTS CALCULATED" -ForegroundColor Green
    Write-Host " 36 / 36 COST-PER-1000 VALUES CALCULATED" -ForegroundColor Green
    Write-Host " ACTUAL PER-TRIAL COST NOT FABRICATED" -ForegroundColor Green
    Write-Host " FREE TIER / CREDITS / DISCOUNTS EXCLUDED" -ForegroundColor Green
    Write-Host " 0 TO_BE_MEASURED VALUES REMAIN" -ForegroundColor Green
    Write-Host " COST DATA READY FOR ANALYSIS" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
}
else {

    throw "TASK 25 FINAL AUDIT FAILED."
}
