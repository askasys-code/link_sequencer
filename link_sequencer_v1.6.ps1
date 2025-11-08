# Color configuration
$headerColor = "Magenta"
$successColor = "Green"
$errorColor = "Red"
$promptColor = "Yellow"

# Function to generate links
function Generate-Links {
    # Ask for the number of links to generate
    $num_link = Read-Host "How many links do you want to create?"
    if (-not ($num_link -match '^\d+$')) {
        Write-Host "Error: Enter a valid number" -ForegroundColor $errorColor
        return $false
    }

    # Ask for the example link
    $full_link = Read-Host "Enter the complete example link (e.g., with _01)"

    # List of regex patterns to find the episode number
    $patterns = @(
        '_Ep_(\d+)_', # Ex. _Ep_01_SUB_ITA or _Ep_01_ITA
        '_(\d+)_', # Ex. _01_SUB_ITA or _01_ITA
        'Ep_(\d+)\.', # Ex. Ep_01.mp4
        '_Ep(\d+)_', # Ex. _Ep01_SUB_ITA
        '_(\d+)\.', # Ex. _01.mp4
        '-(\d+)_', # Ex. -01_SUB_ITA
        '_Episode_(\d+)_', # Ex. _Episode_01_SUB_ITA
        '_EP(\d+)_', # Ex. _EP01_SUB_ITA
        '_(\d+)$' # Ex. _01
    )

    # Try each pattern until one matches
    $match = $null
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($full_link, $pattern)
        if ($match.Success) {
            Write-Host "Pattern matched: $pattern" -ForegroundColor $promptColor
            break
        }
    }

    if (-not $match.Success) {
        Write-Host "Error: Number format not recognized in the link" -ForegroundColor $errorColor
        return $false
    }

    # Extract the number and link parts
    $number = $match.Groups[1].Value
    $base_link = $full_link.Substring(0, $match.Index + $match.Length - $number.Length - 1)
    $suffix = $full_link.Substring($match.Index + $match.Length - 1)

    # Calculate necessary padding
    $padding = $number.Length
    $start_number = [int]$number

    # Generate the links with forced out= filename
    $links = New-Object System.Collections.ArrayList
    1..$num_link | ForEach-Object {
        $current = $start_number + $_ - 1
        $padded = "{0:D$padding}" -f $current
        $url = "$base_link$padded$suffix"
        [void]$links.Add($url)
        $filename = [System.IO.Path]::GetFileName($url)
        [void]$links.Add("  out=$filename")
    }

    # Save WITHOUT BOM (fixes first-link error) + out= lines
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines("$PSScriptRoot\list.txt", $links.ToArray(), $utf8NoBom)

    Write-Host "Links generated in list.txt (NO BOM + forced out= filenames)!" -ForegroundColor $successColor
    return $true
}

# Function to start download
function Start-Download {
    # Check for aria2c existence
    $aria2cPath = "$PSScriptRoot\aria2c.exe"
    if (-not (Test-Path $aria2cPath)) {
        Write-Host "Error: aria2c.exe not found in $PSScriptRoot!" -ForegroundColor $errorColor
        return
    }

    # Create Download folder if it doesn't exist
    $downloadDir = "$PSScriptRoot\Download"
    if (-not (Test-Path $downloadDir)) {
        New-Item -ItemType Directory -Path $downloadDir | Out-Null
        Write-Host "Created Download directory at $downloadDir" -ForegroundColor $promptColor
    }

    # Check for list.txt existence
    if (-not (Test-Path "$PSScriptRoot\list.txt")) {
        Write-Host "Error: list.txt not found in $PSScriptRoot!" -ForegroundColor $errorColor
        return
    }

    # Start download with aria2c
    Write-Host "Starting download with aria2c (skipping already completed files, resuming partial ones)..." -ForegroundColor $promptColor
    try {
        $aria2cArgs = @(
            "-c"                               # <--- NEW: skip completed, resume partial
            "--input-file"
            "$PSScriptRoot\list.txt"
            "--max-concurrent-downloads"
            "16"
            "--max-connection-per-server"
            "16"
            "--dir"
            "$PSScriptRoot\Download"
            "--file-allocation"
            "none"
        )

        $process = Start-Process -FilePath $aria2cPath -ArgumentList $aria2cArgs -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Host "Download completed successfully!" -ForegroundColor $successColor
        } else {
            Write-Host "Download finished with errors (exit code $($process.ExitCode)). Check aria2c output above." -ForegroundColor $errorColor
        }
    } catch {
        Write-Host "Error: Failed to execute aria2c. $_" -ForegroundColor $errorColor
    }
}

# Main menu
do {
    Write-Host "`nMenu:" -ForegroundColor $promptColor
    Write-Host "1. Generate links" -ForegroundColor $promptColor
    Write-Host "2. Start download" -ForegroundColor $promptColor
    Write-Host "3. Exit" -ForegroundColor $promptColor
    $choice = Read-Host "Enter your choice (1-3)"

    switch ($choice) {
        "1" {
            Generate-Links
        }
        "2" {
            Start-Download
        }
        "3" {
            Write-Host "Exiting..." -ForegroundColor $promptColor
            break
        }
        default {
            Write-Host "Invalid choice. Please select 1, 2, or 3." -ForegroundColor $errorColor
        }
    }
} while ($choice -ne "3")

Write-Host "Press any key to exit..." -ForegroundColor $promptColor
[void][System.Console]::ReadKey($true)