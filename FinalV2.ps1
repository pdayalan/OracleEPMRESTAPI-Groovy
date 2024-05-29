# Define variables
$env:PATH += ";C:\oracle\EPM Automate\bin"
$pwds = "VeCg2@12345678"
$logs = "C:\Users\E106573\Documents\logs"
$URL = "https://pcm-test-resmedepm.epm.ap-sydney-1.ocs.oraclecloud.com"
$datafiles = "C:\Oracle\EPM Automate\datafiles"
$awsCliPath = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

# Create logs directory if it doesn't exist
if (!(Test-Path -Path $logs)) {
    New-Item -Path $logs -ItemType Directory
}

# Create datafiles directory if it doesn't exist
if (!(Test-Path -Path $datafiles)) {
    New-Item -Path $datafiles -ItemType Directory
}

# Function to run epmautomate and capture output
function Run-EpmAutomate {
    param (
        [string]$command,
        [string]$outputLog
    )
    Start-Process -NoNewWindow -FilePath "epmautomate" -ArgumentList $command -RedirectStandardOutput $outputLog -Wait -PassThru | Out-Null
    Get-Content -Path $outputLog
}

# Login to EPM
$loginLog = "$logs\login.log"
Write-Output "Login Output:"
Run-EpmAutomate "login dayalan.punniyamoorthy@rsmus.com $pwds $URL" $loginLog

# Get the Sub Var CurMth
$curMonthLog = "$logs\curmonth.log"
Write-Output "CurMth Output:"
Run-EpmAutomate "getSubstVar ALL name=CurMth" $curMonthLog

# Get the Sub Var CurYr
$curYearLog = "$logs\curyear.log"
Write-Output "CurYr Output:"
Run-EpmAutomate "getSubstVar ALL name=CurYr" $curYearLog

# Read and debug the contents of the logs
Write-Output "Contents of $($curMonthLog):"
Get-Content -Path $curMonthLog

Write-Output "Contents of $($curYearLog):"
Get-Content -Path $curYearLog

# Extract the current month and year from the logs
$curMonth = (Get-Content -Path $curMonthLog | Select-String -Pattern "ALL\.CurMth=" | ForEach-Object { $_ -replace ".*ALL\.CurMth=", "" }).Trim()
$curYear = (Get-Content -Path $curYearLog | Select-String -Pattern "ALL\.CurYr=" | ForEach-Object { $_ -replace ".*ALL\.CurYr=", "" }).Trim()

# Debug output to verify extraction
Write-Output "Extracted CurMth: $curMonth"
Write-Output "Extracted CurYr: $curYear"

if (-not $curMonth) {
    Write-Error "Failed to extract current month."
    exit 1
}

if (-not $curYear) {
    Write-Error "Failed to extract current year."
    exit 1
}

# Adjust the year for fiscal year (FY24 = 2024 - 2000)
$curYearAdjusted = [int]$curYear.Substring(2, 2) + 2000 - 2000
# Format the adjusted year as a two-digit number
$curYearFormatted = $curYearAdjusted.ToString("00")

Write-Output "Current Month: $curMonth"
Write-Output "Adjusted Year (FY24): $curYearFormatted"

# Run Data Extraction Rule with the adjusted fiscal year
$dataExtractionLog = "$logs\dataExtraction.log"
$periodName = "$curMonth-$curYearFormatted"
$integrationCommand = "runIntegration `"(DM12) ICPCMRPT to Snowflake Actual IC Calculations`" importMode=Replace exportMode=Replace periodName=`"{$periodName}`""

Write-Output "Data Extraction Output:"
Run-EpmAutomate $integrationCommand $dataExtractionLog

# List files to verify the file existence
$listFilesLog = "$logs\listFiles.log"
Run-EpmAutomate "listfiles" $listFilesLog | Out-Null

# Read the contents of the listFiles.log for diagnostics
$listFilesContent = Get-Content -Path $listFilesLog

# Parse the list of files to find the file that matches the pattern
$filePattern = "outbox/PCM-SF-PCM Outbound Data_*"
$fileToDownload = $listFilesContent | Select-String -Pattern $filePattern | ForEach-Object { $_.Line.Trim() } | Sort-Object -Property { [int]($_ -replace '\D', '') } | Select-Object -Last 1

if ($fileToDownload) {
    Write-Output "Latest file found: $fileToDownload"

    # Encode the file name for URL compatibility
    $encodedFileToDownload = $fileToDownload -replace ' ', '%20'
    Write-Output "Encoded file name for download: $encodedFileToDownload"

    # Specify the download path
    $downloadFilePath = Join-Path -Path $datafiles -ChildPath ($fileToDownload -replace 'outbox/', '' -replace ' ', '')
    $downloadLog = "$logs\downloadfile.log"
    Write-Output "Download File Output:"

    # Run the download command with the correct arguments
    Run-EpmAutomate "downloadfile `"$fileToDownload`" `"$downloadFilePath`"" $downloadLog

    # Check the download log for success
    $downloadLogContent = Get-Content -Path $downloadLog
    Write-Output $downloadLogContent

    if ($downloadLogContent -match "completed successfully" -or $downloadLogContent -match "downloaded to") {
        if (Test-Path -Path $downloadFilePath) {
            Write-Output "File downloaded successfully to $downloadFilePath"

            # AWS S3 copy command
            $s3Destination = "s3://rapid-finance-us-03000-landing-zone-tlzprd/input/epm/"
            $awsUploadLog = "$logs\uploadaws.log"

            # Upload the file to S3 bucket
            & $awsCliPath s3 cp $downloadFilePath $s3Destination | Out-File -FilePath $awsUploadLog -Append
            Write-Output "AWS Upload Output:"
            Get-Content -Path $awsUploadLog

            # Quiet mode if needed
            & $awsCliPath s3 cp --quiet $downloadFilePath "s3://rapid-finance-us-03000-landing-zone-tlzdev/input/epm/" | Out-File -FilePath "$logs\uploadaws.log" -Append
        } else {
            Write-Output "Downloaded file not found at $downloadFilePath"
        }
    } else {
        Write-Output "File download failed. Check $downloadLog for details."
    }
} else {
    Write-Output "No file matching the pattern '$filePattern' was found."
}

# Logout
$logoutLog = "$logs\logout.log"
Write-Output "Logout Output:"
Run-EpmAutomate "logout" $logoutLog
