Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Region = "ap-south-1"
$PricingApiRegion = "us-east-1"
$Location = "Asia Pacific (Mumbai)"

$RepoRoot = (Resolve-Path ".").Path

$DatasetPath =
    Join-Path $RepoRoot "data\final\experiments.csv"

$BackupPath =
    Join-Path $RepoRoot "data\processed\formal\experiments-before-task25-v5.csv"

$BreakdownPath =
    Join-Path $RepoRoot "data\processed\formal\cost-breakdown.csv"

$PricingSnapshotPath =
    Join-Path $RepoRoot "data\processed\formal\aws-pricing-snapshot.csv"

$DiscoveryPath =
    Join-Path $RepoRoot "data\processed\formal\aws-pricing-candidate-discovery.csv"

$PricingRawDir =
    Join-Path $RepoRoot "data\raw\formal\pricing-v5"

New-Item `
    -ItemType Directory `
    -Force `
    $PricingRawDir |
    Out-Null

$Invariant =
    [Globalization.CultureInfo]::InvariantCulture


# ============================================================
# BASIC HELPERS
# ============================================================

function Parse-Decimal {

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
# SAFE NATIVE AWS COMMAND
# ============================================================

function Invoke-AwsJson {

    param(
        [string[]]$Arguments
    )

    $OldPreference =
        $ErrorActionPreference

    $ErrorActionPreference =
        "Continue"

    $ErrorFile =
        Join-Path `
            $env:TEMP `
            (
                "task25-" +
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
            $OldPreference
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
            "AWS CLI failure. Exit=$ExitCode. " +
            $ErrorText
        )
    }


    $Text =
        ($Output -join "`n").Trim()


    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "AWS CLI returned empty JSON."
    }


    try {

        return (
            $Text |
            ConvertFrom-Json
        )
    }
    catch {

        throw (
            "AWS CLI returned invalid JSON. " +
            $_.Exception.Message
        )
    }
}


# ============================================================
# TERRAFORM OUTPUT
# ============================================================

function Get-TerraformOutput {

    param(
        [string]$Directory,
        [string]$OutputName
    )

    $OldPreference =
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
            $OldPreference
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
# PRICE LIST QUERY
#
# IMPORTANT:
# Lambda/API queries use LOCATION ONLY.
# Product selection happens locally afterwards.
# ============================================================

function Invoke-PricingQuery {

    param(
        [string]$ServiceCode,
        [string[]]$Filters,
        [string]$RawName
    )

    $Args = @(
        "pricing",
        "get-products",
        "--service-code",
        $ServiceCode,
        "--format-version",
        "aws_v1",
        "--region",
        $PricingApiRegion
    )


    if ($Filters.Count -gt 0) {

        $Args += "--filters"

        foreach ($Filter in $Filters) {
            $Args += $Filter
        }
    }


    $Response =
        Invoke-AwsJson `
            -Arguments $Args


    $ProductCount =
        @($Response.PriceList).Count


    if ($ProductCount -eq 0) {

        throw (
            "AWS returned zero PriceList products for " +
            "$ServiceCode."
        )
    }


    $RawPath =
        Join-Path `
            $PricingRawDir `
            $RawName


    $RawJson =
        $Response |
        ConvertTo-Json `
            -Depth 30


    $Utf8NoBom =
        New-Object `
            System.Text.UTF8Encoding($false)


    [System.IO.File]::WriteAllText(
        $RawPath,
        $RawJson,
        $Utf8NoBom
    )


    Write-Host (
        "CATALOG | {0} | products={1}" -f `
            $ServiceCode,
            $ProductCount
    ) -ForegroundColor DarkCyan


    return $Response
}


# ============================================================
# TURN AWS PRODUCTS INTO SIMPLE PRICE CANDIDATES
# ============================================================

function Get-PriceCandidates {

    param(
        [object]$Response,
        [string]$Service
    )

    $Result = @()


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


        $Attributes =
            $null


        $AttributesProperty =
            $Offer.product.PSObject.Properties[
                "attributes"
            ]


        if ($null -ne $AttributesProperty) {

            $Attributes =
                $AttributesProperty.Value
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
                    Parse-Decimal `
                        $UsdText `
                        "$Service AWS price"


                #
                # Free Tier / zero-price dimensions are
                # deliberately excluded from comparison.
                #
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


                $BeginNumeric =
                    [decimal]0


                try {

                    $BeginNumeric =
                        [decimal]::Parse(
                            $BeginText,
                            [Globalization.NumberStyles]::Float,
                            $Invariant
                        )
                }
                catch {

                    $BeginNumeric =
                        [decimal]0
                }


                $ProductFamily =
                    Get-Optional `
                        $Offer.product `
                        "productFamily"


                $UsageType =
                    Get-Optional `
                        $Attributes `
                        "usagetype"


                $Group =
                    Get-Optional `
                        $Attributes `
                        "group"


                $GroupDescription =
                    Get-Optional `
                        $Attributes `
                        "groupDescription"


                $Operation =
                    Get-Optional `
                        $Attributes `
                        "operation"


                $Description =
                    Get-Optional `
                        $Dimension `
                        "description"


                $Unit =
                    Get-Optional `
                        $Dimension `
                        "unit"


                $Sku =
                    Get-Optional `
                        $Offer.product `
                        "sku"


                $EffectiveDate =
                    Get-Optional `
                        $Term `
                        "effectiveDate"


                $SearchText =
                    (
                        "$ProductFamily " +
                        "$UsageType " +
                        "$Group " +
                        "$GroupDescription " +
                        "$Operation " +
                        "$Description " +
                        "$Unit"
                    )


                $Result +=
                    [PSCustomObject]@{

                        service =
                            $Service

                        rate_usd =
                            $Rate

                        unit =
                            $Unit

                        begin_range =
                            $BeginText

                        begin_numeric =
                            $BeginNumeric

                        product_family =
                            $ProductFamily

                        usage_type =
                            $UsageType

                        group =
                            $Group

                        group_description =
                            $GroupDescription

                        operation =
                            $Operation

                        description =
                            $Description

                        sku =
                            $Sku

                        effective_date =
                            $EffectiveDate

                        search_text =
                            $SearchText
                    }
            }
        }
    }


    return $Result
}


# ============================================================
# CHOOSE FIRST POSITIVE PAID TIER
# ============================================================

function Select-PaidPrice {

    param(
        [object[]]$Candidates,
        [string]$Component
    )


    if ($Candidates.Count -eq 0) {

        throw (
            "No candidate products found for " +
            "$Component."
        )
    }


    $LowestBegin =
        (
            $Candidates |
            Measure-Object `
                -Property begin_numeric `
                -Minimum
        ).Minimum


    $FirstPaidTier =
        @(
            $Candidates |
            Where-Object {

                [decimal]$_.begin_numeric -eq
                [decimal]$LowestBegin
            }
        )


    $DistinctRates =
        @(
            $FirstPaidTier |
            Select-Object `
                -ExpandProperty rate_usd `
                -Unique
        )


    if ($DistinctRates.Count -ne 1) {

        Write-Host ""
        Write-Host (
            "AMBIGUOUS AWS PRICE: $Component"
        ) -ForegroundColor Red


        $FirstPaidTier |
            Select-Object `
                rate_usd,
                unit,
                begin_range,
                product_family,
                usage_type,
                group,
                description |
            Format-Table `
                -AutoSize


        throw (
            "More than one first-tier rate found " +
            "for $Component."
        )
    }


    $Rate =
        [decimal]$DistinctRates[0]


    $Selected =
        @(
            $FirstPaidTier |
            Where-Object {

                [decimal]$_.rate_usd -eq
                $Rate
            }
        )[0]


    Write-Host (
        "PRICE RESOLVED | {0} | {1} {2} | {3}" -f `
            $Component,
            $Selected.rate_usd,
            $Selected.unit,
            $Selected.usage_type
    ) -ForegroundColor Green


    return $Selected
}


# ============================================================
# DATASET PRECHECK
# ============================================================

if (-not (Test-Path $DatasetPath)) {
    throw "experiments.csv missing."
}


$Dataset =
    @(Import-Csv $DatasetPath)


if ($Dataset.Count -ne 36) {
    throw "Expected 36 experimental rows."
}


$Columns =
    (
        $Dataset[0].
            PSObject.Properties |
        Measure-Object
    ).Count


if ($Columns -ne 44) {
    throw "Expected 44 dataset columns."
}


$PendingCostCells = 0
$PendingOtherCells = 0


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

                $PendingCostCells++
            }
            else {

                $PendingOtherCells++
            }
        }
    }
}


if ($PendingCostCells -ne 108) {

    throw (
        "Dataset cost state unexpected. " +
        "Expected 108 pending cost cells; " +
        "found $PendingCostCells."
    )
}


if ($PendingOtherCells -ne 0) {

    throw (
        "Non-cost TO_BE_MEASURED values remain: " +
        "$PendingOtherCells"
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
# VERIFY INFRASTRUCTURE
# ============================================================

$InstanceId =
    Get-TerraformOutput `
        "terraform/ec2" `
        "instance_id"


$LambdaName =
    Get-TerraformOutput `
        "terraform/serverless" `
        "lambda_function_name"


$ComputeUrl =
    Get-TerraformOutput `
        "terraform/serverless" `
        "compute_url"


if (
    $ComputeUrl -notmatch
    '^https://([^.]+)\.execute-api\.'
) {

    throw "Unable to derive API Gateway ID."
}


$ApiId =
    $Matches[1]


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
    throw "No attached EBS volume found."
}


$TotalGp3GB = 0


foreach ($Volume in $Volumes) {

    if ($Volume.VolumeType -ne "gp3") {

        throw (
            "Non-gp3 volume found: " +
            "$($Volume.VolumeType)"
        )
    }


    if ([int]$Volume.Iops -gt 3000) {

        throw (
            "Extra gp3 IOPS are configured. " +
            "Cost model requires additional pricing."
        )
    }


    if (
        $Volume.Throughput -and
        ([int]$Volume.Throughput -gt 125)
    ) {

        throw (
            "Extra gp3 throughput is configured. " +
            "Cost model requires additional pricing."
        )
    }


    $TotalGp3GB +=
        [int]$Volume.Size
}


$LambdaConfiguration =
    Invoke-AwsJson @(
        "lambda",
        "get-function-configuration",
        "--function-name",
        $LambdaName,
        "--region",
        $Region
    )


$LambdaMemoryMB =
    [int]$LambdaConfiguration.MemorySize


$LambdaArchitecture =
    [string]$LambdaConfiguration.Architectures[0]


if ($LambdaArchitecture -ne "x86_64") {

    throw (
        "Expected Lambda x86_64; found " +
        $LambdaArchitecture
    )
}


$LambdaMemoryGB =
    [decimal]$LambdaMemoryMB /
    [decimal]1024


$Api =
    Invoke-AwsJson @(
        "apigatewayv2",
        "get-api",
        "--api-id",
        $ApiId,
        "--region",
        $Region
    )


if ($Api.ProtocolType -ne "HTTP") {

    throw (
        "Expected API Gateway HTTP API; found " +
        "$($Api.ProtocolType)"
    )
}


# ============================================================
# AWS PRICE RESOLUTION
# ============================================================

Write-Host ""
Write-Host "Resolving current AWS prices..." -ForegroundColor Cyan


# ------------------------------------------------------------
# EC2
# ------------------------------------------------------------

$Ec2Response =
    Invoke-PricingQuery `
        -ServiceCode "AmazonEC2" `
        -RawName "ec2-t3-small-mumbai.json" `
        -Filters @(
            "Type=TERM_MATCH,Field=location,Value=$Location",
            "Type=TERM_MATCH,Field=instanceType,Value=t3.small",
            "Type=TERM_MATCH,Field=operatingSystem,Value=Linux",
            "Type=TERM_MATCH,Field=tenancy,Value=Shared",
            "Type=TERM_MATCH,Field=preInstalledSw,Value=NA",
            "Type=TERM_MATCH,Field=capacitystatus,Value=Used"
        )


$Ec2Candidates =
    @(
        Get-PriceCandidates `
            -Response $Ec2Response `
            -Service "EC2"
    )


$Ec2Candidates =
    @(
        $Ec2Candidates |
        Where-Object {

            $_.unit -eq "Hrs" -and
            $_.search_text -notmatch
            "(?i)Windows|SQL|Dedicated|Reserved"
        }
    )


$Ec2Price =
    Select-PaidPrice `
        -Candidates $Ec2Candidates `
        -Component "EC2 t3.small Linux"


# ------------------------------------------------------------
# EBS
# ------------------------------------------------------------

$EbsResponse =
    Invoke-PricingQuery `
        -ServiceCode "AmazonEC2" `
        -RawName "ebs-gp3-mumbai.json" `
        -Filters @(
            "Type=TERM_MATCH,Field=location,Value=$Location",
            "Type=TERM_MATCH,Field=volumeApiName,Value=gp3"
        )


$EbsCandidates =
    @(
        Get-PriceCandidates `
            -Response $EbsResponse `
            -Service "EBS"
    )


$EbsCandidates =
    @(
        $EbsCandidates |
        Where-Object {

            $_.unit -eq "GB-Mo" -and
            $_.search_text -match
            "(?i)gp3|storage|volume"
        }
    )


$EbsPrice =
    Select-PaidPrice `
        -Candidates $EbsCandidates `
        -Component "EBS gp3 storage"


# ------------------------------------------------------------
# LAMBDA
#
# CRITICAL FIX:
# LOCATION ONLY. No guessed Lambda usagetype.
# ------------------------------------------------------------

$LambdaResponse =
    Invoke-PricingQuery `
        -ServiceCode "AWSLambda" `
        -RawName "lambda-mumbai-all-products.json" `
        -Filters @(
            "Type=TERM_MATCH,Field=location,Value=$Location"
        )


$LambdaAllCandidates =
    @(
        Get-PriceCandidates `
            -Response $LambdaResponse `
            -Service "Lambda"
    )


# Save exact Lambda candidates for reproducibility/debugging.
$LambdaAllCandidates |
    Export-Csv `
        $DiscoveryPath `
        -NoTypeInformation `
        -Encoding UTF8


# ------------------------------------------------------------
# Lambda standard request pricing
# ------------------------------------------------------------

$LambdaRequestCandidates =
    @(
        $LambdaAllCandidates |
        Where-Object {

            $_.search_text -match
            "(?i)request" -and

            $_.search_text -notmatch
            "(?i)ARM|Graviton|edge|managed|provisioned|streaming|snapstart"
        }
    )


if ($LambdaRequestCandidates.Count -eq 0) {

    Write-Host ""
    Write-Host "Lambda catalog candidates:" -ForegroundColor Yellow

    $LambdaAllCandidates |
        Select-Object `
            rate_usd,
            unit,
            usage_type,
            group,
            product_family,
            description |
        Format-Table `
            -AutoSize

    throw "Unable to discover standard Lambda request pricing."
}


$LambdaRequestPrice =
    Select-PaidPrice `
        -Candidates $LambdaRequestCandidates `
        -Component "Lambda standard requests"


# ------------------------------------------------------------
# Lambda standard x86 execution GB-second
# ------------------------------------------------------------

$LambdaDurationCandidates =
    @(
        $LambdaAllCandidates |
        Where-Object {

            (
                $_.search_text -match
                "(?i)GB.?Second|duration"
            ) -and

            $_.search_text -notmatch
            "(?i)ARM|Graviton|Provisioned|SnapStart|Managed|Ephemeral|Streaming|Edge"
        }
    )


if ($LambdaDurationCandidates.Count -eq 0) {

    Write-Host ""
    Write-Host "Lambda catalog candidates:" -ForegroundColor Yellow

    $LambdaAllCandidates |
        Select-Object `
            rate_usd,
            unit,
            usage_type,
            group,
            product_family,
            description |
        Format-Table `
            -AutoSize

    throw "Unable to discover standard Lambda x86 duration pricing."
}


$LambdaDurationPrice =
    Select-PaidPrice `
        -Candidates $LambdaDurationCandidates `
        -Component "Lambda standard x86 duration"


# ------------------------------------------------------------
# API GATEWAY
#
# LOCATION ONLY as well.
# ------------------------------------------------------------

$ApiPricingResponse =
    Invoke-PricingQuery `
        -ServiceCode "AmazonApiGateway" `
        -RawName "api-gateway-mumbai-all-products.json" `
        -Filters @(
            "Type=TERM_MATCH,Field=location,Value=$Location"
        )


$ApiAllCandidates =
    @(
        Get-PriceCandidates `
            -Response $ApiPricingResponse `
            -Service "APIGateway"
    )


$ApiHttpCandidates =
    @(
        $ApiAllCandidates |
        Where-Object {

            $_.search_text -match
            "(?i)HTTP.?API|HttpApi" -and

            $_.search_text -match
            "(?i)request|call"
        }
    )


if ($ApiHttpCandidates.Count -eq 0) {

    Write-Host ""
    Write-Host "API Gateway catalog candidates:" -ForegroundColor Yellow

    $ApiAllCandidates |
        Select-Object `
            rate_usd,
            unit,
            usage_type,
            group,
            product_family,
            description |
        Format-Table `
            -AutoSize

    throw "Unable to discover HTTP API request pricing."
}


$ApiPrice =
    Select-PaidPrice `
        -Candidates $ApiHttpCandidates `
        -Component "API Gateway HTTP API requests"


# ------------------------------------------------------------
# PUBLIC IPV4
#
# Current AWS commercial public IPv4 rate.
# ------------------------------------------------------------

$PublicIpv4HourlyRate =
    [decimal]"0.005"


# ============================================================
# SANITY CHECK RESOLVED RATE SCALE
# ============================================================

if (
    [decimal]$LambdaRequestPrice.rate_usd -ge
    [decimal]"0.001"
) {

    throw (
        "Lambda request rate appears too large for a " +
        "per-request price. Stopping to prevent bad data."
    )
}


if (
    [decimal]$LambdaDurationPrice.rate_usd -ge
    [decimal]"0.001"
) {

    throw (
        "Lambda duration rate appears too large. " +
        "Stopping to prevent bad data."
    )
}


if (
    [decimal]$ApiPrice.rate_usd -ge
    [decimal]"0.01"
) {

    throw (
        "API Gateway request rate appears too large. " +
        "Stopping to prevent bad data."
    )
}


# ============================================================
# PRICING SNAPSHOT
# ============================================================

$PricingSnapshot = @(
    [PSCustomObject]@{
        component="EC2 t3.small Linux"
        rate_usd=$Ec2Price.rate_usd
        unit=$Ec2Price.unit
        usage_type=$Ec2Price.usage_type
        region=$Region
        effective_date=$Ec2Price.effective_date
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="EBS gp3 storage"
        rate_usd=$EbsPrice.rate_usd
        unit=$EbsPrice.unit
        usage_type=$EbsPrice.usage_type
        region=$Region
        effective_date=$EbsPrice.effective_date
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="Lambda standard requests"
        rate_usd=$LambdaRequestPrice.rate_usd
        unit=$LambdaRequestPrice.unit
        usage_type=$LambdaRequestPrice.usage_type
        region=$Region
        effective_date=$LambdaRequestPrice.effective_date
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="Lambda standard x86 duration"
        rate_usd=$LambdaDurationPrice.rate_usd
        unit=$LambdaDurationPrice.unit
        usage_type=$LambdaDurationPrice.usage_type
        region=$Region
        effective_date=$LambdaDurationPrice.effective_date
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="API Gateway HTTP API requests"
        rate_usd=$ApiPrice.rate_usd
        unit=$ApiPrice.unit
        usage_type=$ApiPrice.usage_type
        region=$Region
        effective_date=$ApiPrice.effective_date
        source="AWS Price List API"
    },

    [PSCustomObject]@{
        component="Public IPv4 in-use"
        rate_usd=$PublicIpv4HourlyRate
        unit="Hrs"
        usage_type="PublicIPv4:InUseAddress"
        region=$Region
        effective_date="current"
        source="AWS VPC pricing"
    }
)


# ============================================================
# CALCULATE COSTS
# ============================================================

$FormalWorkloadPath =
    Join-Path `
        $RepoRoot `
        "load-testing\scenarios\formal-workloads.csv"


if (-not (Test-Path $FormalWorkloadPath)) {

    throw (
        "Frozen formal workload definition missing: " +
        $FormalWorkloadPath
    )
}


$FormalWorkloads =
    @(
        Import-Csv $FormalWorkloadPath
    )


if ($FormalWorkloads.Count -ne 6) {

    throw (
        "Expected 6 frozen formal workloads; found " +
        "$($FormalWorkloads.Count)."
    )
}


$Breakdown = @()


foreach ($Row in $Dataset) {

    $Id =
        $Row.experiment_id


    $FrozenWorkloadRows =
        @(
            $FormalWorkloads |
            Where-Object {

                $_.workload_id -eq
                $Row.workload_id
            }
        )


    if ($FrozenWorkloadRows.Count -ne 1) {

        throw (
            "$Id expected exactly one frozen workload " +
            "definition for $($Row.workload_id); found " +
            "$($FrozenWorkloadRows.Count)."
        )
    }


    $FrozenWorkload =
        $FrozenWorkloadRows[0]


    Write-Host (
        "Calculating $Id..."
    ) -ForegroundColor Cyan


    $Successful =
        Parse-Decimal `
            $Row.successful_requests `
            "$Id successful requests"


    if ($Successful -le 0) {
        throw "$Id has zero successful requests."
    }


    $Duration =
        Parse-Decimal `
            $FrozenWorkload.duration_seconds `
            "$Id duration"


    $Idle =
        Parse-Decimal `
            $FrozenWorkload.idle_before_seconds `
            "$Id idle"


    $AllocatedSeconds =
        $Duration + $Idle


    $Ec2ComputeCost =
        [decimal]0

    $EbsStorageCost =
        [decimal]0

    $Ipv4Cost =
        [decimal]0

    $LambdaRequestCost =
        [decimal]0

    $LambdaComputeCost =
        [decimal]0

    $ApiRequestCost =
        [decimal]0

    $LambdaGbSeconds =
        [decimal]0


    # --------------------------------------------------------
    # EC2 architecture
    # --------------------------------------------------------

    if ($Row.architecture -eq "EC2") {

        $Ec2ComputeCost =
            [decimal]$Ec2Price.rate_usd *
            (
                $AllocatedSeconds /
                [decimal]3600
            )


        $EbsStorageCost =
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
    # Serverless architecture
    # --------------------------------------------------------

    if ($Row.architecture -eq "SVL") {

        $Invocations =
            Parse-Decimal `
                $Row.lambda_invocations `
                "$Id Lambda invocations"


        $AverageDurationMs =
            Parse-Decimal `
                $Row.lambda_duration_avg_ms `
                "$Id Lambda duration"


        $ApiCount =
            Parse-Decimal `
                $Row.api_gateway_count `
                "$Id API Gateway count"


        $LambdaRequestCost =
            $Invocations *
            [decimal]$LambdaRequestPrice.rate_usd


        $LambdaGbSeconds =
            $Invocations *
            (
                $AverageDurationMs /
                [decimal]1000
            ) *
            $LambdaMemoryGB


        $LambdaComputeCost =
            $LambdaGbSeconds *
            [decimal]$LambdaDurationPrice.rate_usd


        $ApiRequestCost =
            $ApiCount *
            [decimal]$ApiPrice.rate_usd
    }


    $EstimatedCost =
        $Ec2ComputeCost +
        $EbsStorageCost +
        $Ipv4Cost +
        $LambdaRequestCost +
        $LambdaComputeCost +
        $ApiRequestCost


    if ($EstimatedCost -le 0) {

        throw (
            "$Id estimated cost is not positive."
        )
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
            "Formal measured trial; current AWS list-price " +
            "estimate; Free Tier, credits and discounts excluded; " +
            "exact invoice-level per-trial cost not directly attributable."
        )


    $LambdaRequestsForBreakdown =
        "NOT_APPLICABLE"

    $LambdaGbSecondsForBreakdown =
        "NOT_APPLICABLE"


    if ($Row.architecture -eq "SVL") {

        $LambdaRequestsForBreakdown =
            $Row.lambda_invocations

        $LambdaGbSecondsForBreakdown =
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

            ec2_compute_cost_usd =
                Format-Cost $Ec2ComputeCost

            ebs_gp3_cost_usd =
                Format-Cost $EbsStorageCost

            public_ipv4_cost_usd =
                Format-Cost $Ipv4Cost

            lambda_invocations =
                $LambdaRequestsForBreakdown

            lambda_gb_seconds_estimated =
                $LambdaGbSecondsForBreakdown

            lambda_request_cost_usd =
                Format-Cost $LambdaRequestCost

            lambda_compute_cost_usd =
                Format-Cost $LambdaComputeCost

            api_gateway_request_cost_usd =
                Format-Cost $ApiRequestCost

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
# ATOMIC WRITES
# ============================================================

$TempDataset =
    "$DatasetPath.task25.tmp"


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
        $PricingSnapshotPath `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# FINAL AUDIT
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

            $_.estimated_cost_usd -ne
            "TO_BE_MEASURED" -and

            -not [string]::IsNullOrWhiteSpace(
                $_.estimated_cost_usd
            )
        }
    ).Count


$CostPer1000Count =
    @(
        $Final |
        Where-Object {

            $_.cost_per_1000_successful_requests_usd -ne
            "TO_BE_MEASURED" -and

            -not [string]::IsNullOrWhiteSpace(
                $_.cost_per_1000_successful_requests_usd
            )
        }
    ).Count


$ActualLimitationCount =
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
Write-Host " DAY 2 - TASK 25 - FINAL COST ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Infrastructure"
Write-Host "--------------"
Write-Host "Region                        : $Region"
Write-Host "EC2                           : $($Instance.InstanceType)"
Write-Host "gp3 storage                   : $TotalGp3GB GB"
Write-Host "Public IPv4                   : $HasPublicIpv4"
Write-Host "Lambda memory                 : $LambdaMemoryMB MB"
Write-Host "Lambda architecture           : $LambdaArchitecture"
Write-Host "API Gateway                   : $($Api.ProtocolType)"

Write-Host ""
Write-Host "Resolved AWS prices"
Write-Host "-------------------"

$PricingSnapshot |
    Select-Object `
        component,
        rate_usd,
        unit,
        usage_type |
    Format-Table `
        -AutoSize


Write-Host ""
Write-Host "Dataset audit"
Write-Host "-------------"
Write-Host "Rows                          : $($Final.Count) / 36"
Write-Host "Columns                       : $FinalColumns / 44"
Write-Host "Pricing components            : $($PricingSnapshot.Count) / 6"
Write-Host "Cost breakdown rows           : $($Breakdown.Count) / 36"
Write-Host "Estimated costs populated     : $EstimatedCount / 36"
Write-Host "Cost/1000 populated           : $CostPer1000Count / 36"
Write-Host "Actual limitation marked      : $ActualLimitationCount / 36"
Write-Host "Remaining TO_BE_MEASURED      : $RemainingTBM"


$Pass =
    (
        ($Final.Count -eq 36) -and
        ($FinalColumns -eq 44) -and
        ($PricingSnapshot.Count -eq 6) -and
        ($Breakdown.Count -eq 36) -and
        ($EstimatedCount -eq 36) -and
        ($CostPer1000Count -eq 36) -and
        ($ActualLimitationCount -eq 36) -and
        ($RemainingTBM -eq 0)
    )


if (-not $Pass) {
    throw "TASK 25 FINAL AUDIT FAILED."
}


Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " TASK 25 PASSED" -ForegroundColor Green
Write-Host " CURRENT AWS LIST PRICING CAPTURED" -ForegroundColor Green
Write-Host " 36 / 36 ESTIMATED COSTS CALCULATED" -ForegroundColor Green
Write-Host " 36 / 36 COST-PER-1000 VALUES CALCULATED" -ForegroundColor Green
Write-Host " ACTUAL PER-TRIAL COST NOT FABRICATED" -ForegroundColor Green
Write-Host " FREE TIER / CREDITS / DISCOUNTS EXCLUDED" -ForegroundColor Green
Write-Host " 0 TO_BE_MEASURED VALUES REMAIN" -ForegroundColor Green
Write-Host " COST DATA READY FOR STATISTICAL ANALYSIS" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
