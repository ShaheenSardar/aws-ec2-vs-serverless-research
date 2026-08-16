param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(EC2|SVL)-W0[1-6]-T0[1-3]$')]
    [string]$ExperimentId,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# FORMAL EXPERIMENT RUNNER
# Version: 1.0
# ============================================================

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$MatrixPath = Join-Path `
    $RepoRoot `
    "docs\methodology\formal-experiment-matrix.csv"

$WorkloadPath = Join-Path `
    $RepoRoot `
    "load-testing\scenarios\formal-workloads.csv"

$LocustFile = Join-Path `
    $RepoRoot `
    "load-testing\locustfile.py"

$MetadataDir = Join-Path `
    $RepoRoot `
    "data\raw\formal\metadata"


# ============================================================
# HELPERS
# ============================================================

function Get-UtcNow {
    return [DateTime]::UtcNow.ToString(
        "yyyy-MM-ddTHH:mm:ss.fffZ"
    )
}


function Get-TerraformOutput {

    param(
        [string]$Directory,
        [string]$OutputName
    )

    $Value = & terraform `
        "-chdir=$Directory" `
        output `
        -raw `
        $OutputName `
        2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read Terraform output: $OutputName"
    }

    return (($Value -join "").Trim())
}


function Write-AtomicCsv {

    param(
        [object[]]$Rows,
        [string]$Path
    )

    $TempPath = "$Path.tmp"

    if (Test-Path $TempPath) {
        Remove-Item $TempPath -Force
    }

    $Rows |
        Export-Csv `
            -Path $TempPath `
            -NoTypeInformation `
            -Encoding UTF8

    Move-Item `
        -Path $TempPath `
        -Destination $Path `
        -Force
}


function Update-MatrixStatus {

    param(
        [string]$Id,
        [string]$ExpectedCurrentStatus,
        [string]$NewStatus
    )

    $Rows = Import-Csv $MatrixPath

    $Matches = @(
        $Rows |
        Where-Object {
            $_.experiment_id -eq $Id
        }
    )

    if ($Matches.Count -ne 1) {
        throw "Experiment ID is not unique in matrix: $Id"
    }

    if (
        $Matches[0].status -ne
        $ExpectedCurrentStatus
    ) {
        throw (
            "Status transition rejected for $Id. " +
            "Expected=$ExpectedCurrentStatus; " +
            "Current=$($Matches[0].status)"
        )
    }

    $Matches[0].status = $NewStatus

    Write-AtomicCsv `
        -Rows $Rows `
        -Path $MatrixPath
}


function Test-HealthEndpoint {

    param(
        [string]$Url
    )

    try {

        $Response = Invoke-WebRequest `
            -Uri $Url `
            -UseBasicParsing `
            -TimeoutSec 20

        return (
            $Response.StatusCode -eq 200
        )
    }
    catch {
        return $false
    }
}


# ============================================================
# REQUIRED FILE CHECK
# ============================================================

foreach ($RequiredFile in @(
    $MatrixPath,
    $WorkloadPath,
    $LocustFile
)) {

    if (-not (Test-Path $RequiredFile)) {
        throw "Required file missing: $RequiredFile"
    }
}


# ============================================================
# LOCUST EXECUTABLE
# ============================================================

$LocalLocust = Join-Path `
    $RepoRoot `
    ".venv\Scripts\locust.exe"

$LocustExe = $null

if (Test-Path $LocalLocust) {
    $LocustExe = $LocalLocust
}

if (-not $LocustExe) {

    $LocustCommand = Get-Command `
        locust `
        -ErrorAction SilentlyContinue

    if ($LocustCommand) {
        $LocustExe = $LocustCommand.Source
    }
}

if (-not $LocustExe) {
    throw "Locust executable was not found."
}


# ============================================================
# LOAD EXPERIMENT MATRIX
# ============================================================

$Matrix = Import-Csv $MatrixPath

$ExperimentMatches = @(
    $Matrix |
    Where-Object {
        $_.experiment_id -eq $ExperimentId
    }
)

if ($ExperimentMatches.Count -ne 1) {
    throw (
        "Expected exactly one matrix row for " +
        "$ExperimentId"
    )
}

$Experiment = $ExperimentMatches[0]


# ============================================================
# LOAD FROZEN WORKLOAD
# ============================================================

$Workloads = Import-Csv $WorkloadPath

$WorkloadMatches = @(
    $Workloads |
    Where-Object {
        $_.workload_id -eq
        $Experiment.workload_id
    }
)

if ($WorkloadMatches.Count -ne 1) {
    throw (
        "Frozen workload not found or duplicated: " +
        $Experiment.workload_id
    )
}

$Workload = $WorkloadMatches[0]


# ============================================================
# VALIDATE STATUS
# ============================================================

if (
    (-not $DryRun) -and
    ($Experiment.status -ne "PENDING")
) {
    throw (
        "$ExperimentId cannot run because matrix status " +
        "is '$($Experiment.status)', not PENDING."
    )
}


# ============================================================
# ARCHITECTURE TARGET
# ============================================================

$ArchitectureDirectory = $null
$OutputDirectory = $null
$ComputeUrl = $null
$HealthUrl = $null

if ($Experiment.architecture -eq "EC2") {

    $ArchitectureDirectory = "ec2"

    $OutputDirectory = Join-Path `
        $RepoRoot `
        "data\raw\formal\ec2"

    $ComputeUrl = Get-TerraformOutput `
        -Directory "terraform/ec2" `
        -OutputName "compute_url"

    $HealthUrl = Get-TerraformOutput `
        -Directory "terraform/ec2" `
        -OutputName "health_url"
}

if ($Experiment.architecture -eq "SVL") {

    $ArchitectureDirectory = "serverless"

    $OutputDirectory = Join-Path `
        $RepoRoot `
        "data\raw\formal\serverless"

    $ComputeUrl = Get-TerraformOutput `
        -Directory "terraform/serverless" `
        -OutputName "compute_url"

    $HealthUrl = Get-TerraformOutput `
        -Directory "terraform/serverless" `
        -OutputName "health_url"
}

if (-not $ComputeUrl) {
    throw "Unable to resolve architecture URL."
}


# Preserve possible API Gateway stage path.
$HostUrl = (
    $ComputeUrl -replace '/compute/?$', ''
).TrimEnd('/')


# ============================================================
# FROZEN WORKLOAD PARAMETERS
# ============================================================

$Users = [int]$Workload.users
$SpawnRate = [double]$Workload.spawn_rate
$DurationSeconds = [int]$Workload.duration_seconds
$IdleBeforeSeconds = [int]$Workload.idle_before_seconds


# ============================================================
# OUTPUT PATHS
# ============================================================

New-Item `
    -ItemType Directory `
    -Force `
    -Path $OutputDirectory |
    Out-Null

New-Item `
    -ItemType Directory `
    -Force `
    -Path $MetadataDir |
    Out-Null


$Prefix = Join-Path `
    $OutputDirectory `
    $ExperimentId


$StatsPath = "${Prefix}_stats.csv"

$HistoryPath = "${Prefix}_stats_history.csv"

$FailuresPath = "${Prefix}_failures.csv"

$ExceptionsPath = "${Prefix}_exceptions.csv"

$ConsoleLogPath = "${Prefix}_console.log"

$MetadataPath = Join-Path `
    $MetadataDir `
    "${ExperimentId}_metadata.csv"


# ============================================================
# ABSOLUTE NO-OVERWRITE PROTECTION
# ============================================================

$ProtectedPaths = @(
    $StatsPath,
    $HistoryPath,
    $FailuresPath,
    $ExceptionsPath,
    $ConsoleLogPath,
    $MetadataPath
)

$ExistingFiles = @(
    $ProtectedPaths |
    Where-Object {
        Test-Path $_
    }
)

if ($ExistingFiles.Count -gt 0) {

    throw (
        "FORMAL DATA PROTECTION: files already exist for " +
        "$ExperimentId : " +
        ($ExistingFiles -join "; ")
    )
}


# ============================================================
# DRY-RUN MODE
# ============================================================

if ($DryRun) {

    Write-Host ""
    Write-Host "========================================================" `
        -ForegroundColor Cyan

    Write-Host " FORMAL RUNNER DRY-RUN" `
        -ForegroundColor Cyan

    Write-Host "========================================================" `
        -ForegroundColor Cyan

    Write-Host "Experiment      : $ExperimentId"
    Write-Host "Matrix status   : $($Experiment.status)"
    Write-Host "Architecture    : $($Experiment.architecture)"
    Write-Host "Workload        : $($Experiment.workload_id)"
    Write-Host "Users           : $Users"
    Write-Host "Spawn rate      : $SpawnRate users/sec"
    Write-Host "Duration        : $DurationSeconds sec"
    Write-Host "Idle before     : $IdleBeforeSeconds sec"

    if ($IdleBeforeSeconds -gt 0) {

        Write-Host ""
        Write-Host (
            "Idle protocol   : health activity -> " +
            "$IdleBeforeSeconds sec idle -> formal load"
        ) -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Output protection: PASS" `
        -ForegroundColor Green

    Write-Host "Matrix lookup    : PASS" `
        -ForegroundColor Green

    Write-Host "Workload lookup  : PASS" `
        -ForegroundColor Green

    Write-Host "Architecture URL : PASS" `
        -ForegroundColor Green

    Write-Host "Locust executable: PASS" `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "DRY RUN PASSED - NO FORMAL DATA WRITTEN" `
        -ForegroundColor Green

    return
}


# ============================================================
# CRITICAL CODE-INTEGRITY CHECK
# ============================================================

$CriticalChanges = @(
    git status --porcelain -- `
        application `
        terraform `
        load-testing/locustfile.py `
        load-testing/scenarios/formal-workloads.csv `
        load-testing/run-formal-experiment.ps1
)

if ($CriticalChanges.Count -gt 0) {

    throw (
        "Critical experimental code/config has uncommitted " +
        "changes. Stop before formal execution: " +
        ($CriticalChanges -join "; ")
    )
}


# ============================================================
# SERVERLESS QUOTA CONSISTENCY
# ============================================================

if ($Experiment.architecture -eq "SVL") {

    $Quota = & aws lambda `
        get-account-settings `
        --region ap-south-1 `
        --query "AccountLimit.ConcurrentExecutions" `
        --output text

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to verify Lambda concurrency quota."
    }

    $Quota = ($Quota -join "").Trim()

    if ($Quota -ne "10") {
        throw (
            "Lambda concurrency changed from frozen " +
            "experimental value 10 to $Quota."
        )
    }
}


# ============================================================
# REPRODUCIBILITY COMMITS
# ============================================================

$RepositoryCommit = (
    git rev-parse HEAD
).Trim()

$ApplicationCommit = (
    git log -1 --format="%H" -- application
).Trim()

$TerraformCommit = (
    git log -1 --format="%H" -- terraform
).Trim()

$RunnerCommit = (
    git log -1 `
        --format="%H" `
        -- load-testing/run-formal-experiment.ps1
).Trim()


# ============================================================
# INITIAL EXECUTION METADATA
# ============================================================

$RunnerStartedUtc = Get-UtcNow

$IdleActivityUtc = ""
$IdleStartUtc = ""
$IdleEndUtc = ""

$RunStartUtc = ""
$RunEndUtc = ""

$LocustExitCode = ""
$TotalRequests = ""
$FailedRequests = ""
$SuccessfulRequests = ""

$MatrixWasSetRunning = $false


try {

    # --------------------------------------------------------
    # CLAIM EXPERIMENT ID
    # --------------------------------------------------------

    Update-MatrixStatus `
        -Id $ExperimentId `
        -ExpectedCurrentStatus "PENDING" `
        -NewStatus "RUNNING"

    $MatrixWasSetRunning = $true


    # --------------------------------------------------------
    # W05 CONTROLLED IDLE
    # --------------------------------------------------------

    if ($IdleBeforeSeconds -gt 0) {

        Write-Host ""
        Write-Host (
            "W05 controlled idle protocol beginning."
        ) -ForegroundColor Yellow

        $IdleActivityUtc = Get-UtcNow

        $HealthOK = Test-HealthEndpoint `
            -Url $HealthUrl

        if (-not $HealthOK) {
            throw (
                "Pre-idle health activity failed. " +
                "Formal workload was not started."
            )
        }

        $IdleStartUtc = Get-UtcNow

        Write-Host (
            "Controlled idle: $IdleBeforeSeconds seconds"
        ) -ForegroundColor Yellow

        Start-Sleep `
            -Seconds $IdleBeforeSeconds

        $IdleEndUtc = Get-UtcNow
    }


    # --------------------------------------------------------
    # LOCUST ARGUMENTS
    # --------------------------------------------------------

    $LocustArgs = @(
        "-f",
        $LocustFile,

        "--headless",

        "--host",
        $HostUrl,

        "--users",
        "$Users",

        "--spawn-rate",
        "$SpawnRate",

        "--run-time",
        "${DurationSeconds}s",

        "--csv",
        $Prefix,

        "--csv-full-history",

        "--only-summary"
    )


    # --------------------------------------------------------
    # EXACT FORMAL RUN START
    # --------------------------------------------------------

    $RunStartUtc = Get-UtcNow

    Write-Host ""
    Write-Host "========================================================" `
        -ForegroundColor Cyan

    Write-Host " FORMAL EXPERIMENT START" `
        -ForegroundColor Cyan

    Write-Host "========================================================" `
        -ForegroundColor Cyan

    Write-Host "Experiment : $ExperimentId"
    Write-Host "Start UTC  : $RunStartUtc"
    Write-Host "Users      : $Users"
    Write-Host "Spawn rate : $SpawnRate"
    Write-Host "Duration   : $DurationSeconds sec"


    # --------------------------------------------------------
    # RUN LOCUST
    # --------------------------------------------------------

    $LocustOutput = & $LocustExe `
        @LocustArgs `
        2>&1

    $LocustExitCode = $LASTEXITCODE

    $RunEndUtc = Get-UtcNow


    # Preserve Locust console evidence.
    $LocustOutput |
        Set-Content `
            -Path $ConsoleLogPath `
            -Encoding UTF8

    $LocustOutput |
        ForEach-Object {
            Write-Host $_
        }


    # --------------------------------------------------------
    # VALIDATE RAW OUTPUT EXISTS
    # --------------------------------------------------------

    $RequiredOutputs = @(
        $StatsPath,
        $HistoryPath,
        $FailuresPath,
        $ExceptionsPath
    )

    $MissingOutputs = @(
        $RequiredOutputs |
        Where-Object {
            -not (Test-Path $_)
        }
    )

    if ($MissingOutputs.Count -gt 0) {

        throw (
            "Locust did not create required raw output: " +
            ($MissingOutputs -join "; ")
        )
    }


    # --------------------------------------------------------
    # LOCUST PYTHON EXCEPTION CHECK
    # --------------------------------------------------------

    $ExceptionRows = @(
        Import-Csv `
            $ExceptionsPath `
            -ErrorAction SilentlyContinue
    )

    if ($ExceptionRows.Count -gt 0) {

        throw (
            "Locust/Python exception records detected: " +
            "$($ExceptionRows.Count)"
        )
    }


    # --------------------------------------------------------
    # READ /compute STATS
    # --------------------------------------------------------

    $StatsRows = Import-Csv $StatsPath

    $ComputeRows = @(
        $StatsRows |
        Where-Object {
            $_.Name -eq "/compute"
        }
    )

    if ($ComputeRows.Count -ne 1) {
        throw (
            "Expected one /compute stats row; found " +
            "$($ComputeRows.Count)."
        )
    }

    $ComputeStats = $ComputeRows[0]

    $TotalRequests = [int](
        $ComputeStats.'Request Count'
    )

    $FailedRequests = [int](
        $ComputeStats.'Failure Count'
    )

    $SuccessfulRequests = (
        $TotalRequests -
        $FailedRequests
    )

    if ($TotalRequests -le 0) {
        throw "Formal workload produced zero requests."
    }


    # --------------------------------------------------------
    # DISTINGUISH HTTP FAILURES FROM SCRIPT FAILURE
    # --------------------------------------------------------

    # Exit 0 = no request failures.
    # Exit 1 = request/error outcome recorded by Locust.
    # Both are accepted only when raw data is valid.

    if (
        ($LocustExitCode -ne 0) -and
        ($LocustExitCode -ne 1)
    ) {

        throw (
            "Unexpected Locust process exit code: " +
            "$LocustExitCode"
        )
    }


    # If absolutely every request failed, verify infrastructure
    # remains reachable before accepting that as an outcome.

    if ($SuccessfulRequests -eq 0) {

        $PostRunHealthOK = Test-HealthEndpoint `
            -Url $HealthUrl

        if (-not $PostRunHealthOK) {

            throw (
                "All requests failed and the architecture " +
                "health endpoint is unavailable."
            )
        }
    }


    # --------------------------------------------------------
    # SUCCESSFUL EXPERIMENT METADATA
    # --------------------------------------------------------

    $Metadata = [PSCustomObject]@{

        experiment_id       = $ExperimentId

        architecture        = $Experiment.architecture

        workload_id         = $Experiment.workload_id

        trial_number        = $Experiment.trial_number

        status              = "COMPLETED"

        runner_started_utc  = $RunnerStartedUtc

        idle_activity_utc   = $IdleActivityUtc

        idle_start_utc      = $IdleStartUtc

        idle_end_utc        = $IdleEndUtc

        run_start_utc       = $RunStartUtc

        run_end_utc         = $RunEndUtc

        users               = $Users

        spawn_rate          = $SpawnRate

        duration_seconds    = $DurationSeconds

        idle_before_seconds = $IdleBeforeSeconds

        total_requests      = $TotalRequests

        successful_requests = $SuccessfulRequests

        failed_requests     = $FailedRequests

        locust_exit_code    = $LocustExitCode

        repository_commit   = $RepositoryCommit

        application_commit  = $ApplicationCommit

        terraform_commit    = $TerraformCommit

        runner_commit       = $RunnerCommit
    }

    Write-AtomicCsv `
        -Rows @($Metadata) `
        -Path $MetadataPath


    # --------------------------------------------------------
    # FINAL MATRIX TRANSITION
    # --------------------------------------------------------

    Update-MatrixStatus `
        -Id $ExperimentId `
        -ExpectedCurrentStatus "RUNNING" `
        -NewStatus "COMPLETED"


    # --------------------------------------------------------
    # FINAL SUMMARY
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "========================================================" `
        -ForegroundColor Green

    Write-Host " FORMAL EXPERIMENT COMPLETED" `
        -ForegroundColor Green

    Write-Host "========================================================" `
        -ForegroundColor Green

    Write-Host "Experiment       : $ExperimentId"
    Write-Host "Run start UTC    : $RunStartUtc"
    Write-Host "Run end UTC      : $RunEndUtc"
    Write-Host "Total requests   : $TotalRequests"
    Write-Host "Successful       : $SuccessfulRequests"
    Write-Host "Failed           : $FailedRequests"
    Write-Host "Locust exit code : $LocustExitCode"

    if ($LocustExitCode -eq 1) {

        Write-Host (
            "HTTP/request failures were preserved as " +
            "experimental results."
        ) -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host (
        "Matrix status     : COMPLETED"
    ) -ForegroundColor Green

}
catch {

    $ErrorMessage = $_.Exception.Message

    if ([string]::IsNullOrWhiteSpace($RunEndUtc)) {
        $RunEndUtc = Get-UtcNow
    }


    # --------------------------------------------------------
    # SAFE ERROR STATUS
    # --------------------------------------------------------

    if ($MatrixWasSetRunning) {

        try {

            Update-MatrixStatus `
                -Id $ExperimentId `
                -ExpectedCurrentStatus "RUNNING" `
                -NewStatus "ERROR"

        }
        catch {

            Write-Warning (
                "Could not transition matrix status to ERROR."
            )
        }
    }


    # --------------------------------------------------------
    # PRESERVE ERROR METADATA WITHOUT OVERWRITE
    # --------------------------------------------------------

    if (-not (Test-Path $MetadataPath)) {

        $ErrorMetadata = [PSCustomObject]@{

            experiment_id       = $ExperimentId

            architecture        = $Experiment.architecture

            workload_id         = $Experiment.workload_id

            trial_number        = $Experiment.trial_number

            status              = "ERROR"

            runner_started_utc  = $RunnerStartedUtc

            idle_activity_utc   = $IdleActivityUtc

            idle_start_utc      = $IdleStartUtc

            idle_end_utc        = $IdleEndUtc

            run_start_utc       = $RunStartUtc

            run_end_utc         = $RunEndUtc

            users               = $Users

            spawn_rate          = $SpawnRate

            duration_seconds    = $DurationSeconds

            idle_before_seconds = $IdleBeforeSeconds

            total_requests      = $TotalRequests

            successful_requests = $SuccessfulRequests

            failed_requests     = $FailedRequests

            locust_exit_code    = $LocustExitCode

            repository_commit   = $RepositoryCommit

            application_commit  = $ApplicationCommit

            terraform_commit    = $TerraformCommit

            runner_commit       = $RunnerCommit

            error_message       = $ErrorMessage
        }

        try {

            Write-AtomicCsv `
                -Rows @($ErrorMetadata) `
                -Path $MetadataPath

        }
        catch {

            Write-Warning (
                "Unable to write error metadata."
            )
        }
    }


    Write-Host ""
    Write-Host "========================================================" `
        -ForegroundColor Red

    Write-Host " FORMAL EXPERIMENT STOPPED" `
        -ForegroundColor Red

    Write-Host "========================================================" `
        -ForegroundColor Red

    Write-Host "Experiment : $ExperimentId"
    Write-Host "Reason     : $ErrorMessage" `
        -ForegroundColor Red

    throw
}
