Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (
    Resolve-Path "."
).Path

$MatrixPath = Join-Path `
    $RepoRoot `
    "docs\methodology\formal-experiment-matrix.csv"

$Ec2Dir = Join-Path `
    $RepoRoot `
    "data\raw\formal\ec2"

$SvlDir = Join-Path `
    $RepoRoot `
    "data\raw\formal\serverless"

$MetadataDir = Join-Path `
    $RepoRoot `
    "data\raw\formal\metadata"

$PilotDir = Join-Path `
    $RepoRoot `
    "data\raw\pilot"

$InvalidDir = Join-Path `
    $RepoRoot `
    "data\raw\formal\invalid-attempts"

$ProcessedDir = Join-Path `
    $RepoRoot `
    "data\processed\formal"

$ManifestPath = Join-Path `
    $ProcessedDir `
    "formal-raw-sha256-manifest.csv"

New-Item `
    -ItemType Directory `
    -Force `
    $ProcessedDir |
    Out-Null


# ============================================================
# AUDIT STATE
# ============================================================

$AuditFailures = @()

$MissingFiles = @()
$UnexpectedFiles = @()
$UtcProblems = @()
$StatsProblems = @()
$MetadataProblems = @()
$IdleProblems = @()
$SeparationProblems = @()

$AcceptedFiles = @()
$MetadataRecords = @()

$FailureFileCount = 0
$FailureRows = 0
$FailureOccurrences = 0

$ExceptionFileCount = 0
$ExceptionRows = 0

$StatsValid = 0
$UtcValid = 0
$IdleValid = 0


function Add-AuditFailure {

    param(
        [string]$Message
    )

    $script:AuditFailures += $Message
}


# ============================================================
# REQUIRED DIRECTORIES / FILES
# ============================================================

foreach ($Path in @(
    $MatrixPath,
    $Ec2Dir,
    $SvlDir,
    $MetadataDir,
    $PilotDir
)) {

    if (-not (Test-Path $Path)) {
        Add-AuditFailure "Required path missing: $Path"
    }
}

if ($AuditFailures.Count -gt 0) {

    Write-Host "TASK 22 CANNOT START" -ForegroundColor Red
    $AuditFailures

    exit 1
}


# ============================================================
# MATRIX
# ============================================================

$Matrix = @(
    Import-Csv $MatrixPath
)

$MatrixTotal = $Matrix.Count

$MatrixUnique = @(
    $Matrix.experiment_id |
    Sort-Object -Unique
).Count

$DuplicateMatrixIds = @(
    $Matrix |
    Group-Object experiment_id |
    Where-Object { $_.Count -gt 1 }
)

$Completed = @(
    $Matrix |
    Where-Object { $_.status -eq "COMPLETED" }
).Count

$Pending = @(
    $Matrix |
    Where-Object { $_.status -eq "PENDING" }
).Count

$Running = @(
    $Matrix |
    Where-Object { $_.status -eq "RUNNING" }
).Count

$Errors = @(
    $Matrix |
    Where-Object { $_.status -eq "ERROR" }
).Count


# ============================================================
# BUILD EXACT EXPECTED 36 IDS
# ============================================================

$ExpectedIds = @()

foreach ($Architecture in @("EC2","SVL")) {

    foreach ($WorkloadNumber in 1..6) {

        foreach ($TrialNumber in 1..3) {

            $ExpectedIds += (
                "{0}-W{1:D2}-T{2:D2}" -f `
                    $Architecture,
                    $WorkloadNumber,
                    $TrialNumber
            )
        }
    }
}

$MatrixIdDifference = @(
    Compare-Object `
        ($ExpectedIds | Sort-Object) `
        ($Matrix.experiment_id | Sort-Object)
)

if ($MatrixTotal -ne 36) {
    Add-AuditFailure "Matrix row count is $MatrixTotal, expected 36."
}

if ($MatrixUnique -ne 36) {
    Add-AuditFailure "Matrix has only $MatrixUnique unique experiment IDs."
}

if ($DuplicateMatrixIds.Count -gt 0) {
    Add-AuditFailure "Duplicate matrix experiment IDs detected."
}

if ($MatrixIdDifference.Count -gt 0) {
    Add-AuditFailure "Matrix experiment IDs do not match the expected 36 IDs."
}

if ($Completed -ne 36) {
    Add-AuditFailure "COMPLETED=$Completed, expected 36."
}

if ($Pending -ne 0) {
    Add-AuditFailure "PENDING=$Pending, expected 0."
}

if ($Running -ne 0) {
    Add-AuditFailure "RUNNING=$Running, expected 0."
}

if ($Errors -ne 0) {
    Add-AuditFailure "ERROR=$Errors, expected 0."
}


# ============================================================
# VERIFY EACH ACCEPTED EXPERIMENT
# ============================================================

foreach ($Experiment in $Matrix) {

    $Id = $Experiment.experiment_id

    $ArchDir = $null

    if ($Id.StartsWith("EC2-")) {
        $ArchDir = $Ec2Dir
    }

    if ($Id.StartsWith("SVL-")) {
        $ArchDir = $SvlDir
    }

    if (-not $ArchDir) {

        Add-AuditFailure "Unknown architecture for $Id"
        continue
    }


    $StatsPath = Join-Path `
        $ArchDir `
        "${Id}_stats.csv"

    $HistoryPath = Join-Path `
        $ArchDir `
        "${Id}_stats_history.csv"

    $FailuresPath = Join-Path `
        $ArchDir `
        "${Id}_failures.csv"

    $ExceptionsPath = Join-Path `
        $ArchDir `
        "${Id}_exceptions.csv"

    $ConsolePath = Join-Path `
        $ArchDir `
        "${Id}_console.log"

    $MetadataPath = Join-Path `
        $MetadataDir `
        "${Id}_metadata.csv"


    $ExpectedExperimentFiles = @(
        $StatsPath,
        $HistoryPath,
        $FailuresPath,
        $ExceptionsPath,
        $ConsolePath,
        $MetadataPath
    )


    # --------------------------------------------------------
    # EXACT FILE PRESENCE
    # --------------------------------------------------------

    foreach ($Path in $ExpectedExperimentFiles) {

        if (-not (Test-Path $Path -PathType Leaf)) {
            $MissingFiles += $Path
        }
        else {
            $AcceptedFiles += Get-Item $Path
        }
    }


    # --------------------------------------------------------
    # NO DUPLICATE / UNEXPECTED ACCEPTED FILES
    # --------------------------------------------------------

    $ArchitectureFiles = @(
        Get-ChildItem `
            $ArchDir `
            -File `
            -Filter "${Id}_*" `
            -ErrorAction SilentlyContinue
    )

    $MetadataFiles = @(
        Get-ChildItem `
            $MetadataDir `
            -File `
            -Filter "${Id}_*" `
            -ErrorAction SilentlyContinue
    )

    $ExpectedArchNames = @(
        "${Id}_stats.csv",
        "${Id}_stats_history.csv",
        "${Id}_failures.csv",
        "${Id}_exceptions.csv",
        "${Id}_console.log"
    )

    foreach ($File in $ArchitectureFiles) {

        if ($File.Name -notin $ExpectedArchNames) {
            $UnexpectedFiles += $File.FullName
        }
    }

    if ($ArchitectureFiles.Count -ne 5) {
        $UnexpectedFiles += (
            "$Id architecture artifact count=" +
            "$($ArchitectureFiles.Count), expected 5"
        )
    }

    if ($MetadataFiles.Count -ne 1) {
        $UnexpectedFiles += (
            "$Id metadata artifact count=" +
            "$($MetadataFiles.Count), expected 1"
        )
    }


    # --------------------------------------------------------
    # LOCUST STATS
    # --------------------------------------------------------

    if (Test-Path $StatsPath) {

        try {

            $Stats = @(
                Import-Csv $StatsPath
            )

            $ComputeRows = @(
                $Stats |
                Where-Object { $_.Name -eq "/compute" }
            )

            if ($ComputeRows.Count -ne 1) {

                $StatsProblems += (
                    "$Id expected exactly one /compute stats row."
                )
            }
            else {

                $RequestCount = [int](
                    $ComputeRows[0].'Request Count'
                )

                if ($RequestCount -le 0) {
                    $StatsProblems += "$Id has zero requests."
                }
                else {
                    $StatsValid++
                }
            }
        }
        catch {

            $StatsProblems += (
                "$Id stats parse error: " +
                $_.Exception.Message
            )
        }
    }


    # --------------------------------------------------------
    # FAILURE FILE PRESERVATION
    # --------------------------------------------------------

    if (Test-Path $FailuresPath) {

        $FailureFileCount++

        $Rows = @(
            Import-Csv `
                $FailuresPath `
                -ErrorAction SilentlyContinue
        )

        $FailureRows += $Rows.Count

        foreach ($Row in $Rows) {

            if ($Row.Occurrences) {

                try {
                    $FailureOccurrences += [int]$Row.Occurrences
                }
                catch {
                }
            }
        }
    }


    # --------------------------------------------------------
    # LOCUST EXCEPTION CHECK
    # --------------------------------------------------------

    if (Test-Path $ExceptionsPath) {

        $ExceptionFileCount++

        $Rows = @(
            Import-Csv `
                $ExceptionsPath `
                -ErrorAction SilentlyContinue
        )

        $ExceptionRows += $Rows.Count
    }


    # --------------------------------------------------------
    # METADATA + UTC VALIDATION
    # --------------------------------------------------------

    if (Test-Path $MetadataPath) {

        try {

            $MetaRows = @(
                Import-Csv $MetadataPath
            )

            if ($MetaRows.Count -ne 1) {

                $MetadataProblems += (
                    "$Id metadata row count=$($MetaRows.Count)"
                )

                continue
            }

            $Meta = $MetaRows[0]
            $MetadataRecords += $Meta

            if ($Meta.experiment_id -ne $Id) {
                $MetadataProblems += "$Id metadata ID mismatch."
            }

            if ($Meta.status -ne "COMPLETED") {
                $MetadataProblems += (
                    "$Id metadata status=$($Meta.status)"
                )
            }


            $UtcOK = $true

            if (
                [string]::IsNullOrWhiteSpace(
                    $Meta.run_start_utc
                )
            ) {
                $UtcOK = $false
                $UtcProblems += "$Id missing run_start_utc"
            }

            if (
                [string]::IsNullOrWhiteSpace(
                    $Meta.run_end_utc
                )
            ) {
                $UtcOK = $false
                $UtcProblems += "$Id missing run_end_utc"
            }


            if ($UtcOK) {

                if ($Meta.run_start_utc -notmatch 'Z$') {
                    $UtcOK = $false
                    $UtcProblems += "$Id start timestamp not UTC Z."
                }

                if ($Meta.run_end_utc -notmatch 'Z$') {
                    $UtcOK = $false
                    $UtcProblems += "$Id end timestamp not UTC Z."
                }
            }


            if ($UtcOK) {

                try {

                    $StartUtc = [DateTimeOffset]::Parse(
                        $Meta.run_start_utc
                    )

                    $EndUtc = [DateTimeOffset]::Parse(
                        $Meta.run_end_utc
                    )

                    if ($EndUtc -le $StartUtc) {

                        $UtcOK = $false

                        $UtcProblems += (
                            "$Id end UTC is not after start UTC."
                        )
                    }
                }
                catch {

                    $UtcOK = $false

                    $UtcProblems += (
                        "$Id UTC timestamp parse error."
                    )
                }
            }


            if ($UtcOK) {
                $UtcValid++
            }


            # ------------------------------------------------
            # W05 IDLE METADATA
            # ------------------------------------------------

            if ($Experiment.workload_id -eq "W05") {

                $W05OK = $true

                foreach ($Field in @(
                    "idle_activity_utc",
                    "idle_start_utc",
                    "idle_end_utc"
                )) {

                    if (
                        [string]::IsNullOrWhiteSpace(
                            $Meta.$Field
                        )
                    ) {

                        $W05OK = $false

                        $IdleProblems += (
                            "$Id missing $Field"
                        )
                    }
                }


                if ($W05OK) {

                    try {

                        $IdleStart =
                            [DateTimeOffset]::Parse(
                                $Meta.idle_start_utc
                            )

                        $IdleEnd =
                            [DateTimeOffset]::Parse(
                                $Meta.idle_end_utc
                            )

                        $FormalStart =
                            [DateTimeOffset]::Parse(
                                $Meta.run_start_utc
                            )

                        $IdleSeconds = (
                            $IdleEnd -
                            $IdleStart
                        ).TotalSeconds


                        if ($IdleSeconds -lt 300) {

                            $W05OK = $false

                            $IdleProblems += (
                                "$Id idle=" +
                                "$IdleSeconds sec"
                            )
                        }


                        if ($FormalStart -lt $IdleEnd) {

                            $W05OK = $false

                            $IdleProblems += (
                                "$Id formal run started before idle ended."
                            )
                        }
                    }
                    catch {

                        $W05OK = $false

                        $IdleProblems += (
                            "$Id idle timestamp parse error."
                        )
                    }
                }


                if ($W05OK) {
                    $IdleValid++
                }
            }
        }
        catch {

            $MetadataProblems += (
                "$Id metadata parse error: " +
                $_.Exception.Message
            )
        }
    }
}


# ============================================================
# GLOBAL FILE CHECKS
# ============================================================

if ($MissingFiles.Count -gt 0) {

    Add-AuditFailure (
        "$($MissingFiles.Count) accepted formal files missing."
    )
}

if ($UnexpectedFiles.Count -gt 0) {

    Add-AuditFailure (
        "$($UnexpectedFiles.Count) duplicate/unexpected accepted artifacts."
    )
}

if ($StatsProblems.Count -gt 0) {

    Add-AuditFailure (
        "$($StatsProblems.Count) Locust stats problems."
    )
}

if ($MetadataProblems.Count -gt 0) {

    Add-AuditFailure (
        "$($MetadataProblems.Count) metadata problems."
    )
}

if ($UtcProblems.Count -gt 0) {

    Add-AuditFailure (
        "$($UtcProblems.Count) UTC timing problems."
    )
}

if ($FailureFileCount -ne 36) {

    Add-AuditFailure (
        "Failure files=$FailureFileCount, expected 36."
    )
}

if ($ExceptionFileCount -ne 36) {

    Add-AuditFailure (
        "Exception files=$ExceptionFileCount, expected 36."
    )
}

if ($ExceptionRows -ne 0) {

    Add-AuditFailure (
        "Locust exception rows=$ExceptionRows, expected 0."
    )
}

if ($IdleValid -ne 6) {

    Add-AuditFailure (
        "Valid W05 idle metadata=$IdleValid, expected 6."
    )
}

if ($IdleProblems.Count -gt 0) {

    Add-AuditFailure (
        "$($IdleProblems.Count) W05 idle metadata problems."
    )
}


# ============================================================
# METADATA UNIQUENESS
# ============================================================

$MetadataCount = $MetadataRecords.Count

$UniqueMetadataIds = @(
    $MetadataRecords.experiment_id |
    Sort-Object -Unique
).Count

$DuplicateMetadataIds = @(
    $MetadataRecords |
    Group-Object experiment_id |
    Where-Object { $_.Count -gt 1 }
)

if ($MetadataCount -ne 36) {

    Add-AuditFailure (
        "Accepted metadata records=$MetadataCount, expected 36."
    )
}

if ($UniqueMetadataIds -ne 36) {

    Add-AuditFailure (
        "Unique metadata IDs=$UniqueMetadataIds, expected 36."
    )
}

if ($DuplicateMetadataIds.Count -gt 0) {

    Add-AuditFailure "Duplicate metadata experiment IDs detected."
}


# ============================================================
# PILOT / FORMAL SEPARATION
# ============================================================

$PilotFiles = @(
    Get-ChildItem `
        $PilotDir `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue
)

$AcceptedFormalFiles = @(
    Get-ChildItem `
        $Ec2Dir `
        -File `
        -ErrorAction SilentlyContinue

    Get-ChildItem `
        $SvlDir `
        -File `
        -ErrorAction SilentlyContinue

    Get-ChildItem `
        $MetadataDir `
        -File `
        -ErrorAction SilentlyContinue
)

$PilotNamedFilesInFormal = @(
    $AcceptedFormalFiles |
    Where-Object {
        $_.Name -match '^P-'
    }
)

$FormalNamedFilesInPilot = @(
    $PilotFiles |
    Where-Object {
        $_.Name -match '^(EC2|SVL)-W0[1-6]-T0[1-3]'
    }
)

if ($PilotNamedFilesInFormal.Count -gt 0) {

    $SeparationProblems += (
        "Pilot-named files found in accepted formal directories."
    )
}

if ($FormalNamedFilesInPilot.Count -gt 0) {

    $SeparationProblems += (
        "Formal experiment files found in pilot directory."
    )
}

if ($SeparationProblems.Count -gt 0) {

    Add-AuditFailure "Pilot/formal raw-data separation failed."
}


# ============================================================
# ARCHIVED INVALID ATTEMPTS
# ============================================================

$ArchivedInvalidFiles = 0

if (Test-Path $InvalidDir) {

    $ArchivedInvalidFiles = @(
        Get-ChildItem `
            $InvalidDir `
            -Recurse `
            -File `
            -ErrorAction SilentlyContinue
    ).Count
}


# ============================================================
# ACCEPTED FILE COUNT
# ============================================================

$AcceptedFileCount = @(
    $AcceptedFiles |
    Sort-Object FullName -Unique
).Count

if ($AcceptedFileCount -ne 216) {

    Add-AuditFailure (
        "Accepted raw artifact count=" +
        "$AcceptedFileCount, expected 216."
    )
}


# ============================================================
# CREATE SHA-256 MANIFEST ONLY IF AUDIT IS CLEAN
# ============================================================

$ManifestCount = 0

if ($AuditFailures.Count -eq 0) {

    $Manifest = @()

    foreach (
        $File in (
            $AcceptedFiles |
            Sort-Object FullName -Unique
        )
    ) {

        $Hash = Get-FileHash `
            -LiteralPath $File.FullName `
            -Algorithm SHA256

        $RelativePath = (
            $File.FullName.Substring(
                $RepoRoot.Length
            )
        ).TrimStart("\")

        $Manifest += [PSCustomObject]@{
            relative_path    = $RelativePath
            sha256           = $Hash.Hash.ToLower()
            size_bytes       = $File.Length
            last_write_utc   = $File.LastWriteTimeUtc.ToString(
                "yyyy-MM-ddTHH:mm:ss.fffZ"
            )
        }
    }

    $Manifest |
        Export-Csv `
            $ManifestPath `
            -NoTypeInformation `
            -Encoding UTF8

    $ManifestCount = $Manifest.Count
}


# ============================================================
# FINAL SCREEN
# ============================================================

Clear-Host

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " DAY 2 - TASK 22 - 36-RUN COMPLETENESS AUDIT" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Experiment matrix"
Write-Host "-----------------"
Write-Host "Total IDs              : $MatrixTotal / 36"
Write-Host "Unique IDs             : $MatrixUnique / 36"
Write-Host "COMPLETED              : $Completed"
Write-Host "PENDING                : $Pending"
Write-Host "RUNNING                : $Running"
Write-Host "ERROR                  : $Errors"

Write-Host ""
Write-Host "Accepted raw evidence"
Write-Host "---------------------"
Write-Host "Metadata records       : $MetadataCount / 36"
Write-Host "Valid UTC start/end    : $UtcValid / 36"
Write-Host "Valid Locust stats     : $StatsValid / 36"
Write-Host "Failure files preserved: $FailureFileCount / 36"
Write-Host "Failure occurrences    : $FailureOccurrences"
Write-Host "Exception files checked: $ExceptionFileCount / 36"
Write-Host "Locust exception rows  : $ExceptionRows"
Write-Host "Accepted raw files     : $AcceptedFileCount / 216"
Write-Host "Missing raw files      : $($MissingFiles.Count)"
Write-Host "Duplicate/extra files  : $($UnexpectedFiles.Count)"

Write-Host ""
Write-Host "Special validation"
Write-Host "------------------"
Write-Host "W05 idle metadata      : $IdleValid / 6"

$SeparationStatus = "FAIL"

if ($SeparationProblems.Count -eq 0) {
    $SeparationStatus = "PASS"
}

Write-Host "Pilot/formal separation: $SeparationStatus"
Write-Host "Archived invalid files : $ArchivedInvalidFiles"
Write-Host "SHA256 manifest rows   : $ManifestCount"

Write-Host ""
Write-Host "Audit failures         : $($AuditFailures.Count)"


if ($AuditFailures.Count -eq 0) {

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host " TASK 22 PASSED" -ForegroundColor Green
    Write-Host " 36 / 36 EXPERIMENT IDs COMPLETED" -ForegroundColor Green
    Write-Host " PENDING = 0" -ForegroundColor Green
    Write-Host " NO MISSING OR DUPLICATE ACCEPTED EXPERIMENTS" -ForegroundColor Green
    Write-Host " ALL UTC TIMESTAMPS VERIFIED" -ForegroundColor Green
    Write-Host " ALL LOCUST RAW EVIDENCE VERIFIED" -ForegroundColor Green
    Write-Host " FAILURES PRESERVED AS RESULTS" -ForegroundColor Green
    Write-Host " W05 CONTROLLED-IDLE METADATA VERIFIED" -ForegroundColor Green
    Write-Host " PILOT AND FORMAL DATA REMAIN SEPARATE" -ForegroundColor Green
    Write-Host " FORMAL RAW DATASET READY FOR METRIC EXTRACTION" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
}


if ($AuditFailures.Count -gt 0) {

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Red
    Write-Host " TASK 22 FAILED" -ForegroundColor Red
    Write-Host " DO NOT START ANALYSIS OR CLOUDWATCH EXTRACTION" -ForegroundColor Red
    Write-Host "========================================================" -ForegroundColor Red

    Write-Host ""

    foreach ($Failure in $AuditFailures) {
        Write-Host "- $Failure" -ForegroundColor Red
    }

    if ($MissingFiles.Count -gt 0) {
        Write-Host "`nMissing files:" -ForegroundColor Yellow
        $MissingFiles
    }

    if ($UnexpectedFiles.Count -gt 0) {
        Write-Host "`nUnexpected/duplicate files:" -ForegroundColor Yellow
        $UnexpectedFiles
    }

    if ($StatsProblems.Count -gt 0) {
        Write-Host "`nStats problems:" -ForegroundColor Yellow
        $StatsProblems
    }

    if ($UtcProblems.Count -gt 0) {
        Write-Host "`nUTC problems:" -ForegroundColor Yellow
        $UtcProblems
    }

    if ($IdleProblems.Count -gt 0) {
        Write-Host "`nW05 idle problems:" -ForegroundColor Yellow
        $IdleProblems
    }
}
