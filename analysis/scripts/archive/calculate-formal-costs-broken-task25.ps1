Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Region = "ap-south-1"
$PricingRegion = "us-east-1"
$Location = "Asia Pacific (Mumbai)"

$RepoRoot = (Resolve-Path ".").Path

$DatasetPath = Join-Path `
    $RepoRoot `
    "data\final\experiments.csv"

$BackupPath = Join-Path `
    $RepoRoot `
    "data\processed\formal\experiments-before-task25.csv"

$BreakdownPath = Join-Path `
    $RepoRoot `
    "data\processed\formal\cost-breakdown.csv"

$PricingSnapshotPath = Join-Path `
    $RepoRoot `
    "data\processed\formal\aws-pricing-snapshot.csv"

$PricingRawDir = Join-Path `
    $RepoRoot `
    "data\raw\formal\pricing"

$Invariant =
    [Globalization.CultureInfo]::InvariantCulture


# ============================================================
# HELPERS
# ============================================================

function Format-Cost {

    param(
        [decimal]$Value
    )

    return $Value.ToString(
        "0.000000000000",
        $Invariant
    )
}


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


function Get-TerraformOutput {

    param(
        [string]$Directory,
        [string]$Name
    )

    $OldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {

        $Result = @(
            & terraform `
                "-chdir=$Directory" `
                output `
                -raw `
                $Name `
                2>$null
        )

        $Exit = $LASTEXITCODE
    }
    finally {

        $ErrorActionPreference = $OldPreference
    }

    if ($Exit -ne 0) {
        throw "Terraform output failed: $Directory / $Name"
    }

    return (($Result -join "").Trim())
}


function Invoke-AwsJson {

    param(
        [string[]]$Arguments
    )

    $OldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $ErrorFile = Join-Path `
        $env:TEMP `
        ("aws-" + [guid]::NewGuid().ToString() + ".err")

    try {

        $Output = @(
            & aws `
                @Arguments `
                --no-cli-pager `
                --output json `
                2>$ErrorFile
        )

        $Exit = $LASTEXITCODE
    }
    finally {

        $ErrorActionPreference = $OldPreference
    }

    $ErrorText = ""

    if (Test-Path $ErrorFile) {

        $ErrorText = Get-Content `
            $ErrorFile `
            -Raw `
            -ErrorAction SilentlyContinue

        Remove-Item `
            $ErrorFile `
            -Force `
            -ErrorAction SilentlyContinue
    }

    if ($Exit -ne 0) {
        throw "AWS CLI failed: $ErrorText"
    }

    $Text = ($Output -join "`n").Trim()

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "AWS CLI returned empty JSON."
    }

    return ($Text | ConvertFrom-Json)
}


function Invoke-PricingQuery {

    param(
        [string]$ServiceCode,
        [object[]]$Filters,
        [string]$RawFileName
    )

    $RawPath = Join-Path `
        $PricingRawDir `
        $RawFileName

    #
    # IMPORTANT:
    # Use AWS CLI shorthand filter arguments directly.
    #
    # This avoids Windows PowerShell 5.1 UTF-8 BOM problems
    # that can occur when a JSON filters file is written with
    # Set-Content -Encoding UTF8.
    #

    $AwsArguments = @(
        "pricing",
        "get-products",
        "--service-code",
        $ServiceCode,
        "--format-version",
        "aws_v1",
        "--region",
        $PricingRegion,
        "--no-cli-pager",
        "--output",
        "json",
        "--filters"
    )

    foreach ($Filter in $Filters) {

        if (
            -not $Filter.Type -or
            -not $Filter.Field -or
            -not $Filter.Value
        ) {

            throw (
                "Invalid AWS Pricing filter for " +
                "$ServiceCode"
            )
        }

        $FilterArgument = (
            "Type={0},Field={1},Value={2}" -f `
                $Filter.Type,
                $Filter.Field,
                $Filter.Value
        )

        $AwsArguments += $FilterArgument
    }


    $ErrorPath = Join-Path `
        $env:TEMP `
        ("aws-pricing-" +
        [guid]::NewGuid().ToString() +
        ".err")


    $OldErrorPreference =
        $ErrorActionPreference

    $NativePreferenceExists =
        Test-Path `
            variable:PSNativeCommandUseErrorActionPreference

    if ($NativePreferenceExists) {

        $OldNativePreference =
            $PSNativeCommandUseErrorActionPreference

        $PSNativeCommandUseErrorActionPreference =
            $false
    }


    try {

        $ErrorActionPreference = "Continue"

        $Output = @(
            & aws `
                @AwsArguments `
                2>$ErrorPath
        )

        $ExitCode = $LASTEXITCODE
    }
    finally {

        $ErrorActionPreference =
            $OldErrorPreference

        if ($NativePreferenceExists) {

            $PSNativeCommandUseErrorActionPreference =
                $OldNativePreference
        }
    }


    $ErrorText = ""

    if (Test-Path $ErrorPath) {

        $ErrorText = Get-Content `
            $ErrorPath `
            -Raw `
            -ErrorAction SilentlyContinue

        Remove-Item `
            $ErrorPath `
            -Force `
            -ErrorAction SilentlyContinue
    }


    if ($ExitCode -ne 0) {

        throw (
            "AWS Pricing query failed for " +
            "$ServiceCode. ExitCode=$ExitCode. " +
            $ErrorText
        )
    }


    $JsonText = (
        $Output -join "`n"
    ).Trim()


    if ([string]::IsNullOrWhiteSpace($JsonText)) {

        throw (
            "AWS Pricing returned empty output for " +
            "$ServiceCode."
        )
    }


    try {

        $Parsed =
            $JsonText |
            ConvertFrom-Json
    }
    catch {

        throw (
            "AWS Pricing returned invalid JSON for " +
            "$ServiceCode. " +
            $_.Exception.Message
        )
    }


    if (@($Parsed.PriceList).Count -eq 0) {

        throw (
            "AWS Pricing returned zero products for " +
            "$ServiceCode."
        )
    }


    #
    # Save raw pricing evidence as BOM-less UTF-8.
    #

    $Utf8NoBom =
        New-Object `
            System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $RawPath,
        $JsonText,
        $Utf8NoBom
    )


    return $Parsed
}

function Get-OptionalPropertyValue {

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


function Resolve-Price {

    param(
        [object]$Response,
        [string]$RequiredUnit,
        [string]$Component
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


        try {

            $Offer =
                $PriceString |
                ConvertFrom-Json
        }
        catch {

            throw (
                "Invalid PriceList product JSON for " +
                "$Component. " +
                $_.Exception.Message
            )
        }


        if ($null -eq $Offer.product) {
            continue
        }

        if ($null -eq $Offer.terms) {
            continue
        }


        $OnDemandProperty =
            $Offer.terms.PSObject.Properties["OnDemand"]

        if ($null -eq $OnDemandProperty) {
            continue
        }


        $OnDemand =
            $OnDemandProperty.Value

        $Terms = @(
            $OnDemand.PSObject.Properties |
            ForEach-Object {
                $_.Value
            }
        )


        foreach ($Term in $Terms) {

            if ($null -eq $Term) {
                continue
            }


            $PriceDimensionsProperty =
                $Term.PSObject.Properties["priceDimensions"]

            if ($null -eq $PriceDimensionsProperty) {
                continue
            }


            $PriceDimensions =
                $PriceDimensionsProperty.Value


            $Dimensions = @(
                $PriceDimensions.PSObject.Properties |
                ForEach-Object {
                    $_.Value
                }
            )


            foreach ($Dimension in $Dimensions) {

                if ($null -eq $Dimension) {
                    continue
                }


                $Unit =
                    Get-OptionalPropertyValue `
                        $Dimension `
                        "unit"

                if ($Unit -ne $RequiredUnit) {
                    continue
                }


                $BeginRange =
                    Get-OptionalPropertyValue `
                        $Dimension `
                        "beginRange"

                #
                # We want the first/current usage tier.
                #
                if (
                    -not [string]::IsNullOrWhiteSpace(
                        $BeginRange
                    ) -and
                    $BeginRange -ne "0"
                ) {
                    continue
                }


                $PricePerUnitProperty =
                    $Dimension.PSObject.Properties["pricePerUnit"]

                if ($null -eq $PricePerUnitProperty) {
                    continue
                }


                $PricePerUnit =
                    $PricePerUnitProperty.Value

                $UsdProperty =
                    $PricePerUnit.PSObject.Properties["USD"]

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


                $USD =
                    Parse-Decimal `
                        $UsdText `
                        "$Component price"

                if ($USD -le 0) {
                    continue
                }


                $Attributes = $null

                if (
                    $null -ne
                    $Offer.product.PSObject.Properties[
                        "attributes"
                    ]
                ) {

                    $Attributes =
                        $Offer.product.attributes
                }


                $UsageType =
                    Get-OptionalPropertyValue `
                        $Attributes `
                        "usagetype"

                $Group =
                    Get-OptionalPropertyValue `
                        $Attributes `
                        "group"

                $GroupDescription =
                    Get-OptionalPropertyValue `
                        $Attributes `
                        "groupDescription"

                $Operation =
                    Get-OptionalPropertyValue `
                        $Attributes `
                        "operation"

                $ProductFamily =
                    Get-OptionalPropertyValue `
                        $Offer.product `
                        "productFamily"

                $Sku =
                    Get-OptionalPropertyValue `
                        $Offer.product `
                        "sku"

                $Description =
                    Get-OptionalPropertyValue `
                        $Dimension `
                        "description"

                $EffectiveDate =
                    Get-OptionalPropertyValue `
                        $Term `
                        "effectiveDate"


                $Candidates +=
                    [PSCustomObject]@{

                        component =
                            $Component

                        rate_usd =
                            $USD

                        unit =
                            $Unit

                        sku =
                            $Sku

                        description =
                            $Description

                        effective_date =
                            $EffectiveDate

                        usage_type =
                            $UsageType

                        group =
                            $Group

                        group_description =
                            $GroupDescription

                        operation =
                            $Operation

                        product_family =
                            $ProductFamily
                    }
            }
        }
    }


    if ($Candidates.Count -eq 0) {

        throw (
            "No valid current price candidate found for " +
            "$Component with unit $RequiredUnit."
        )
    }


    #
    # Different SKUs may legitimately return the same rate.
    # What matters is that they resolve to ONE monetary rate.
    #

    $DistinctRates = @(
        $Candidates |
        Select-Object `
            -ExpandProperty rate_usd `
            -Unique
    )


    if ($DistinctRates.Count -ne 1) {

        Write-Host ""
        Write-Host (
            "AMBIGUOUS PRICE CANDIDATES: $Component"
        ) -ForegroundColor Red

        $Candidates |
            Select-Object `
                rate_usd,
                unit,
                sku,
                usage_type,
                group,
                product_family,
                description |
            Format-Table -AutoSize

        throw (
            "Multiple distinct current prices found for " +
            "$Component. Pricing filters require refinement."
        )
    }


    $SelectedRate =
        [decimal]$DistinctRates[0]


    $Selected =
        @(
            $Candidates |
            Where-Object {
                [decimal]$_.rate_usd -eq
                $SelectedRate
            }
        )[0]


    if ($null -eq $Selected) {
        throw "Unable to select price for $Component."
    }


    Write-Host (
        "PRICE RESOLVED | {0} | {1} {2}" -f `
            $Component,
            $Selected.rate_usd,
            $Selected.unit
    ) -ForegroundColor Green


    return $Selected
}

# ============================================================
# DATASET PRECONDITION
# ============================================================

if (-not (Test-Path $DatasetPath)) {
    throw "experiments.csv missing."
}

$Dataset = @(
    Import-Csv $DatasetPath
)

if ($Dataset.Count -ne 36) {
    throw "Expected 36 dataset rows."
}

$Columns = (
    $Dataset[0].PSObject.Properties |
    Measure-Object
).Count

if ($Columns -ne 44) {
    throw "Expected 44 dataset columns."
}

$NonCostTBM = @()

foreach ($Row in $Dataset) {

    foreach ($Property in $Row.PSObject.Properties) {

        if (
            $Property.Value -eq "TO_BE_MEASURED" -and
            $Property.Name -notin @(
                "actual_cost_usd",
                "estimated_cost_usd",
                "cost_per_1000_successful_requests_usd"
            )
        ) {

            $NonCostTBM += (
                "$($Row.experiment_id):" +
                "$($Property.Name)"
            )
        }
    }
}

if ($NonCostTBM.Count -gt 0) {
    throw "Non-cost TO_BE_MEASURED values remain."
}


if (-not (Test-Path $BackupPath)) {

    Copy-Item `
        $DatasetPath `
        $BackupPath
}


# ============================================================
# RESOLVE ACTUAL RESOURCES
# ============================================================

$InstanceId = Get-TerraformOutput `
    "terraform/ec2" `
    "instance_id"

$LambdaName = Get-TerraformOutput `
    "terraform/serverless" `
    "lambda_function_name"

$ComputeUrl = Get-TerraformOutput `
    "terraform/serverless" `
    "compute_url"

if (
    $ComputeUrl -notmatch
    '^https://([^.]+)\.execute-api\.'
) {
    throw "Unable to derive API Gateway ID."
}

$ApiId = $Matches[1]


$InstanceInfo = Invoke-AwsJson @(
    "ec2",
    "describe-instances",
    "--instance-ids",$InstanceId,
    "--region",$Region
)

$Instance = $InstanceInfo.Reservations[0].Instances[0]

if ($Instance.InstanceType -ne "t3.small") {
    throw "Expected t3.small; found $($Instance.InstanceType)"
}

$HasPublicIpv4 = $false

if (
    -not [string]::IsNullOrWhiteSpace(
        [string]$Instance.PublicIpAddress
    )
) {
    $HasPublicIpv4 = $true
}


$VolumeInfo = Invoke-AwsJson @(
    "ec2",
    "describe-volumes",
    "--filters",
    "Name=attachment.instance-id,Values=$InstanceId",
    "--region",$Region
)

$Volumes = @($VolumeInfo.Volumes)

if ($Volumes.Count -lt 1) {
    throw "No attached EBS volume found."
}

$TotalGp3GB = 0

foreach ($Volume in $Volumes) {

    if ($Volume.VolumeType -ne "gp3") {
        throw (
            "Non-gp3 volume detected: " +
            "$($Volume.VolumeId) / $($Volume.VolumeType)"
        )
    }

    if ([int]$Volume.Iops -gt 3000) {
        throw (
            "gp3 extra IOPS detected. " +
            "Cost model must include extra IOPS."
        )
    }

    if (
        $Volume.Throughput -and
        [int]$Volume.Throughput -gt 125
    ) {
        throw (
            "gp3 extra throughput detected. " +
            "Cost model must include extra throughput."
        )
    }

    $TotalGp3GB += [int]$Volume.Size
}


$LambdaConfig = Invoke-AwsJson @(
    "lambda",
    "get-function-configuration",
    "--function-name",$LambdaName,
    "--region",$Region
)

$LambdaMemoryMB = [int]$LambdaConfig.MemorySize

$LambdaArchitecture =
    [string]$LambdaConfig.Architectures[0]

if ($LambdaArchitecture -ne "x86_64") {
    throw (
        "Expected Lambda x86_64; found " +
        "$LambdaArchitecture"
    )
}

$LambdaMemoryGB =
    [decimal]$LambdaMemoryMB /
    [decimal]1024


$ApiInfo = Invoke-AwsJson @(
    "apigatewayv2",
    "get-api",
    "--api-id",$ApiId,
    "--region",$Region
)

if ($ApiInfo.ProtocolType -ne "HTTP") {
    throw (
        "Expected HTTP API; found " +
        "$($ApiInfo.ProtocolType)"
    )
}


# ============================================================
# CURRENT OFFICIAL AWS PRICE LIST QUERIES
# ============================================================

Write-Host ""
Write-Host "Resolving current AWS list prices..." -ForegroundColor Cyan


$Ec2Response = Invoke-PricingQuery `
    -ServiceCode "AmazonEC2" `
    -RawFileName "t3-small-mumbai.json" `
    -Filters @(
        @{
            Type="TERM_MATCH"
            Field="location"
            Value=$Location
        },
        @{
            Type="TERM_MATCH"
            Field="instanceType"
            Value="t3.small"
        },
        @{
            Type="TERM_MATCH"
            Field="operatingSystem"
            Value="Linux"
        },
        @{
            Type="TERM_MATCH"
            Field="tenancy"
            Value="Shared"
        },
        @{
            Type="TERM_MATCH"
            Field="preInstalledSw"
            Value="NA"
        },
        @{
            Type="TERM_MATCH"
            Field="capacitystatus"
            Value="Used"
        }
    )

$Ec2Price = Resolve-Price `
    $Ec2Response `
    "Hrs" `
    "EC2 t3.small Linux"


$EbsResponse = Invoke-PricingQuery `
    -ServiceCode "AmazonEC2" `
    -RawFileName "gp3-mumbai.json" `
    -Filters @(
        @{
            Type="TERM_MATCH"
            Field="location"
            Value=$Location
        },
        @{
            Type="TERM_MATCH"
            Field="volumeApiName"
            Value="gp3"
        }
    )

$EbsPrice = Resolve-Price `
    $EbsResponse `
    "GB-Mo" `
    "EBS gp3 storage"


$LambdaRequestResponse = Invoke-PricingQuery `
    -ServiceCode "AWSLambda" `
    -RawFileName "lambda-requests-mumbai.json" `
    -Filters @(
        @{
            Type="TERM_MATCH"
            Field="location"
            Value=$Location
        },
        @{
            Type="TERM_MATCH"
            Field="group"
            Value="AWS-Lambda-Requests"
        }
    )

$LambdaRequestPrice = Resolve-Price `
    $LambdaRequestResponse `
    "Requests" `
    "Lambda billed requests"


$LambdaDurationResponse = Invoke-PricingQuery `
    -ServiceCode "AWSLambda" `
    -RawFileName "lambda-duration-x86-mumbai.json" `
    -Filters @(
        @{
            Type="TERM_MATCH"
            Field="location"
            Value=$Location
        },
        @{
            Type="TERM_MATCH"
            Field="group"
            Value="AWS-Lambda-Duration"
        }
    )

$LambdaDurationPrice = Resolve-Price `
    $LambdaDurationResponse `
    "Lambda-GB-Second" `
    "Lambda x86 duration"


$ApiResponse = Invoke-PricingQuery `
    -ServiceCode "AmazonApiGateway" `
    -RawFileName "http-api-mumbai.json" `
    -Filters @(
        @{
            Type="TERM_MATCH"
            Field="location"
            Value=$Location
        },
        @{
            Type="CONTAINS"
            Field="usagetype"
            Value="ApiGatewayHttpApi"
        }
    )

$ApiPrice = Resolve-Price `
    $ApiResponse `
    "Requests" `
    "API Gateway HTTP API requests"


# ============================================================
# PUBLIC IPV4
# ============================================================

# Current AWS public IPv4 address rate across commercial regions.
$PublicIpv4HourlyRate = [decimal]0.005


# ============================================================
# SAVE PRICING SNAPSHOT
# ============================================================

$PricingSnapshot = @(
    [PSCustomObject]@{
        component="EC2 t3.small Linux"
        rate_usd=$Ec2Price.rate_usd
        unit=$Ec2Price.unit
        sku=$Ec2Price.sku
        effective_date=$Ec2Price.effective_date
        region=$Region
        source="AWS Price List API"
    },
    [PSCustomObject]@{
        component="EBS gp3 storage"
        rate_usd=$EbsPrice.rate_usd
        unit=$EbsPrice.unit
        sku=$EbsPrice.sku
        effective_date=$EbsPrice.effective_date
        region=$Region
        source="AWS Price List API"
    },
    [PSCustomObject]@{
        component="Lambda billed requests"
        rate_usd=$LambdaRequestPrice.rate_usd
        unit=$LambdaRequestPrice.unit
        sku=$LambdaRequestPrice.sku
        effective_date=$LambdaRequestPrice.effective_date
        region=$Region
        source="AWS Price List API"
    },
    [PSCustomObject]@{
        component="Lambda x86 duration"
        rate_usd=$LambdaDurationPrice.rate_usd
        unit=$LambdaDurationPrice.unit
        sku=$LambdaDurationPrice.sku
        effective_date=$LambdaDurationPrice.effective_date
        region=$Region
        source="AWS Price List API"
    },
    [PSCustomObject]@{
        component="API Gateway HTTP API requests"
        rate_usd=$ApiPrice.rate_usd
        unit=$ApiPrice.unit
        sku=$ApiPrice.sku
        effective_date=$ApiPrice.effective_date
        region=$Region
        source="AWS Price List API"
    },
    [PSCustomObject]@{
        component="Public IPv4 in-use address"
        rate_usd=$PublicIpv4HourlyRate
        unit="Hrs"
        sku="PUBLIC_IPV4"
        effective_date="current"
        region=$Region
        source="AWS VPC public pricing"
    }
)

$PricingSnapshot |
    Export-Csv `
        $PricingSnapshotPath `
        -NoTypeInformation `
        -Encoding UTF8


# ============================================================
# COST CALCULATION
# ============================================================

$Breakdown = @()

foreach ($Row in $Dataset) {

    $Id = $Row.experiment_id

    Write-Host "Calculating $Id..." -ForegroundColor Cyan

    $Successful =
        [decimal]$Row.successful_requests

    if ($Successful -le 0) {
        throw "$Id has zero successful requests."
    }

    $Duration =
        [decimal]$Row.duration_seconds

    $Idle =
        [decimal]$Row.idle_before_seconds

    $AllocatedSeconds =
        $Duration + $Idle


    $Ec2ComputeCost = [decimal]0
    $EbsCost = [decimal]0
    $Ipv4Cost = [decimal]0

    $LambdaRequestCost = [decimal]0
    $LambdaComputeCost = [decimal]0
    $ApiRequestCost = [decimal]0

    $LambdaGBSeconds = [decimal]0


    # --------------------------------------------------------
    # EC2
    # --------------------------------------------------------

    if ($Row.architecture -eq "EC2") {

        $Ec2ComputeCost =
            [decimal]$Ec2Price.rate_usd *
            ($AllocatedSeconds / [decimal]3600)

        $EbsCost =
            [decimal]$EbsPrice.rate_usd *
            [decimal]$TotalGp3GB *
            (
                $AllocatedSeconds /
                [decimal](30 * 24 * 60 * 60)
            )

        if ($HasPublicIpv4) {

            $Ipv4Cost =
                $PublicIpv4HourlyRate *
                ($AllocatedSeconds / [decimal]3600)
        }
    }


    # --------------------------------------------------------
    # SERVERLESS
    # --------------------------------------------------------

    if ($Row.architecture -eq "SVL") {

        $Invocations =
            Parse-Decimal `
                $Row.lambda_invocations `
                "$Id Lambda invocations"

        $LambdaDurationMs =
            Parse-Decimal `
                $Row.lambda_duration_avg_ms `
                "$Id Lambda duration"

        $ApiCount =
            Parse-Decimal `
                $Row.api_gateway_count `
                "$Id API count"


        $LambdaRequestCost =
            $Invocations *
            [decimal]$LambdaRequestPrice.rate_usd


        $LambdaGBSeconds =
            $Invocations *
            ($LambdaDurationMs / [decimal]1000) *
            $LambdaMemoryGB


        $LambdaComputeCost =
            $LambdaGBSeconds *
            [decimal]$LambdaDurationPrice.rate_usd


        $ApiRequestCost =
            $ApiCount *
            [decimal]$ApiPrice.rate_usd
    }


    $Estimated =
        $Ec2ComputeCost +
        $EbsCost +
        $Ipv4Cost +
        $LambdaRequestCost +
        $LambdaComputeCost +
        $ApiRequestCost


    if ($Estimated -le 0) {
        throw "$Id calculated estimated cost is not positive."
    }


    $CostPer1000 =
        ($Estimated / $Successful) *
        [decimal]1000


    # Never fabricate exact invoice attribution.
    $Row.actual_cost_usd =
        "NOT_DIRECTLY_ATTRIBUTABLE"

    $Row.estimated_cost_usd =
        Format-Cost $Estimated

    $Row.cost_per_1000_successful_requests_usd =
        Format-Cost $CostPer1000


    $Row.notes = (
        "Formal measured trial; list-price cost estimate; " +
        "actual per-trial AWS invoice cost not directly attributable; " +
        "Free Tier/credits/discounts excluded."
    )


    $Breakdown += [PSCustomObject]@{
        experiment_id              = $Id
        architecture               = $Row.architecture
        workload_id                = $Row.workload_id
        allocated_seconds          = $AllocatedSeconds

        ec2_instance_cost_usd      =
            Format-Cost $Ec2ComputeCost

        ebs_gp3_cost_usd           =
            Format-Cost $EbsCost

        public_ipv4_cost_usd       =
            Format-Cost $Ipv4Cost

        lambda_billed_requests     =
            if ($Row.architecture -eq "SVL") {
                $Row.lambda_invocations
            } else {
                "NOT_APPLICABLE"
            }

        lambda_gb_seconds          =
            if ($Row.architecture -eq "SVL") {
                Format-Cost $LambdaGBSeconds
            } else {
                "NOT_APPLICABLE"
            }

        lambda_request_cost_usd    =
            Format-Cost $LambdaRequestCost

        lambda_compute_cost_usd    =
            Format-Cost $LambdaComputeCost

        api_gateway_request_cost_usd =
            Format-Cost $ApiRequestCost

        estimated_cost_usd         =
            Format-Cost $Estimated

        successful_requests        =
            $Row.successful_requests

        cost_per_1000_successful_requests_usd =
            Format-Cost $CostPer1000

        actual_cost_usd =
            "NOT_DIRECTLY_ATTRIBUTABLE"
    }
}


# ============================================================
# ATOMIC WRITE
# ============================================================

$TempDataset = "$DatasetPath.tmp"

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


# ============================================================
# FINAL COST AUDIT
# ============================================================

$Final = @(
    Import-Csv $DatasetPath
)

$FinalColumns = (
    $Final[0].PSObject.Properties |
    Measure-Object
).Count

$ActualPolicyCount = @(
    $Final |
    Where-Object {
        $_.actual_cost_usd -eq
        "NOT_DIRECTLY_ATTRIBUTABLE"
    }
).Count

$EstimatedPopulated = @(
    $Final |
    Where-Object {
        $_.estimated_cost_usd -ne "TO_BE_MEASURED" -and
        -not [string]::IsNullOrWhiteSpace(
            $_.estimated_cost_usd
        )
    }
).Count

$CostPer1000Populated = @(
    $Final |
    Where-Object {
        $_.cost_per_1000_successful_requests_usd -ne
        "TO_BE_MEASURED" -and
        -not [string]::IsNullOrWhiteSpace(
            $_.cost_per_1000_successful_requests_usd
        )
    }
).Count

$RemainingTBM = 0

foreach ($Row in $Final) {

    foreach ($Property in $Row.PSObject.Properties) {

        if ($Property.Value -eq "TO_BE_MEASURED") {
            $RemainingTBM++
        }
    }
}

$BreakdownCount =
    @($Breakdown).Count


Clear-Host

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " DAY 2 - TASK 25 - COST ANALYSIS AUDIT" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Verified infrastructure"
Write-Host "-----------------------"
Write-Host "AWS Region                    : $Region"
Write-Host "EC2 instance type             : $($Instance.InstanceType)"
Write-Host "Attached gp3 storage          : $TotalGp3GB GB"
Write-Host "EC2 public IPv4               : $HasPublicIpv4"
Write-Host "Lambda memory                 : $LambdaMemoryMB MB"
Write-Host "Lambda architecture           : $LambdaArchitecture"
Write-Host "API Gateway type              : $($ApiInfo.ProtocolType)"

Write-Host ""
Write-Host "Current AWS list-price evidence"
Write-Host "-------------------------------"
Write-Host "EC2 t3.small / hour           : $($Ec2Price.rate_usd)"
Write-Host "gp3 / GB-month                : $($EbsPrice.rate_usd)"
Write-Host "Lambda request                : $($LambdaRequestPrice.rate_usd)"
Write-Host "Lambda GB-second              : $($LambdaDurationPrice.rate_usd)"
Write-Host "HTTP API request              : $($ApiPrice.rate_usd)"
Write-Host "Public IPv4 / hour            : $PublicIpv4HourlyRate"

Write-Host ""
Write-Host "Dataset"
Write-Host "-------"
Write-Host "Rows                          : $($Final.Count) / 36"
Write-Host "Columns                       : $FinalColumns / 44"
Write-Host "Cost breakdown rows           : $BreakdownCount / 36"
Write-Host "Estimated costs populated     : $EstimatedPopulated / 36"
Write-Host "Cost/1000 populated           : $CostPer1000Populated / 36"
Write-Host "Actual cost limitation marked : $ActualPolicyCount / 36"
Write-Host "Remaining TO_BE_MEASURED      : $RemainingTBM"

Write-Host ""
Write-Host "Cost policy"
Write-Host "-----------"
Write-Host "Free Tier/credits             : EXCLUDED"
Write-Host "Discounts/Savings Plans       : EXCLUDED"
Write-Host "Actual per-trial invoice      : NOT DIRECTLY ATTRIBUTABLE"
Write-Host "W05 EC2 allocated time        : 360 seconds"
Write-Host "Serverless idle allocation    : no compute allocation charge"


$Pass = $true

if ($Final.Count -ne 36) {
    $Pass = $false
}

if ($FinalColumns -ne 44) {
    $Pass = $false
}

if ($BreakdownCount -ne 36) {
    $Pass = $false
}

if ($EstimatedPopulated -ne 36) {
    $Pass = $false
}

if ($CostPer1000Populated -ne 36) {
    $Pass = $false
}

if ($ActualPolicyCount -ne 36) {
    $Pass = $false
}

if ($RemainingTBM -ne 0) {
    $Pass = $false
}


if ($Pass) {

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host " TASK 25 PASSED" -ForegroundColor Green
    Write-Host " CURRENT OFFICIAL AWS PRICING CAPTURED" -ForegroundColor Green
    Write-Host " 36 / 36 ESTIMATED COSTS CALCULATED" -ForegroundColor Green
    Write-Host " 36 / 36 COST-PER-1000 VALUES CALCULATED" -ForegroundColor Green
    Write-Host " ACTUAL PER-TRIAL COST NOT FABRICATED" -ForegroundColor Green
    Write-Host " FREE TIER AND ACCOUNT CREDITS EXCLUDED" -ForegroundColor Green
    Write-Host " 0 TO_BE_MEASURED VALUES REMAIN" -ForegroundColor Green
    Write-Host " COST DATA READY FOR STATISTICAL ANALYSIS" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
}

if (-not $Pass) {

    Write-Host ""
    Write-Host "TASK 25 FAILED - DO NOT ANALYZE COSTS" -ForegroundColor Red
}
