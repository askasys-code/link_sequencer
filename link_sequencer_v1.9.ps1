# Color configuration
$headerColor = "Cyan"
$successColor = "Green"
$errorColor = "Red"
$promptColor = "Yellow"

# Display title banner (larger appearance via repetition and color; font size not controllable in console)
Write-Host ""
Write-Host "========================================" -ForegroundColor $headerColor
Write-Host "       LINK SEQUENCER v1.9              " -ForegroundColor $headerColor
Write-Host "========================================" -ForegroundColor $headerColor
Write-Host ""

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
    $pre_link = $full_link.Substring(0, $match.Groups[1].Index)
    $suffix = $full_link.Substring($match.Groups[1].Index + $number.Length)

    # Calculate necessary padding
    $padding = $number.Length
    $start_number = [int]$number

    # Generate the links with out= on separate indented line (correct aria2c format)
    $links = New-Object System.Collections.ArrayList
    1..$num_link | ForEach-Object {
        $current = $start_number + $_ - 1
        $padded = "{0:D$padding}" -f $current
        $url = "$pre_link$padded$suffix"
        $filename = [System.IO.Path]::GetFileName($url)
        [void]$links.Add($url)
        [void]$links.Add("  out=$filename")
    }

    # Save WITHOUT BOM (fixes first-link error)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines("$PSScriptRoot\list.txt", $links.ToArray(), $utf8NoBom)

    Write-Host "Links generated in list.txt" -ForegroundColor $successColor
    return $true
}

# Function to start download
function Start-Download {
    # Check for aria2c existence
    $aria2cPath = "$PSScriptRoot\aria2c.exe"
    if (-not (Test-Path $aria2cPath)) {
        Write-Host "Error: aria2c.exe not found" -ForegroundColor $errorColor
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
        Write-Host "Error: list.txt not found" -ForegroundColor $errorColor
        return
    }

    # Determine total number of URLs from list.txt (every other line is a URL)
    $listContent = Get-Content "$PSScriptRoot\list.txt"
    $total = ($listContent | Where-Object { $_ -notmatch '^\s*out=' }).Count
    if ($total -eq 0) {
        Write-Host "Error: No valid URLs found in list.txt" -ForegroundColor $errorColor
        return
    }

    # Log files for aria2c output (separate for stdout and stderr to avoid Start-Process error)
    $stdoutLog = "$PSScriptRoot\aria2c_stdout.log"
    $stderrLog = "$PSScriptRoot\aria2c_stderr.log"

    # Start download with aria2c (output redirected to log files to suppress console spam)
    Write-Host "Starting download with aria2c..." -ForegroundColor $promptColor
    try {
        $aria2cArgs = @(
            "-c"                               # skip completed, resume partial
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

        $process = Start-Process -FilePath $aria2cPath -ArgumentList $aria2cArgs -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -NoNewWindow -PassThru

        # Monitor progress by parsing the stdout log file (loop waits for process to exit)
        $completed = 0
        $percent = 0
        while (!$process.HasExited) {
            Start-Sleep -Milliseconds 250
            if (Test-Path $stdoutLog) {
                $logLines = Get-Content $stdoutLog -ErrorAction SilentlyContinue
                # Count "Download complete:" lines (excluding "not complete")
                $completed = ($logLines | Select-String 'Download complete:(?!\s*not)').Count

                # Extract percentages from the last progress line for partial progress
                $progressLine = $logLines | Where-Object { $_ -match '^\[DL:' } | Select-Object -Last 1
                if ($progressLine -and $completed -lt $total) {
                    $pctMatches = [regex]::Matches($progressLine, '\((\d+)%\)')
                    $activePcts = $pctMatches | ForEach-Object { [int]$_.Groups[1].Value }
                    if ($activePcts.Count -gt 0) {
                        $avgPct = ($activePcts | Measure-Object -Average).Average
                        $partialProgress = ($total - $completed) * ($avgPct / 100.0)
                        $overallProgress = $completed + $partialProgress
                        $percent = [math]::Round(($overallProgress / $total) * 100)
                    } else {
                        $percent = [math]::Round(($completed / $total) * 100)
                    }
                } else {
                    $percent = [math]::Round(($completed / $total) * 100)
                }

                Write-Host "`rProgress: $percent%" -NoNewline -ForegroundColor $promptColor
            }
        }

        # Final newline after progress
        Write-Host "`n" -ForegroundColor $promptColor

        # Combine logs for final parsing
        $combinedLog = @()
        if (Test-Path $stdoutLog) { $combinedLog += Get-Content $stdoutLog }
        if (Test-Path $stderrLog) { $combinedLog += Get-Content $stderrLog }

        # Improved parsing for Download Results section: find start index and take subsequent lines until end or empty
        $startIndex = -1
        for ($i = 0; $i -lt $combinedLog.Length; $i++) {
            if ($combinedLog[$i] -match '^Download Results:') {
                $startIndex = $i
                break
            }
        }

        $resultsSection = @()
        if ($startIndex -ge 0) {
            for ($i = $startIndex; $i -lt $combinedLog.Length; $i++) {
                if ($combinedLog[$i].Trim() -eq '' -and $i -gt $startIndex + 1) { break }  # Stop at double empty line or similar
                $resultsSection += $combinedLog[$i]
            }
        }

        # Count successful downloads from results (lines with |OK|)
        $successCount = ($combinedLog | Select-String '\|OK\s+\|').Count

        # Final check and output: Prioritize successCount over exitCode for determination
        $exitCode = if ($null -eq $process.ExitCode) { 0 } else { $process.ExitCode }
        if ($successCount -eq $total) {
            Write-Host "Download completed successfully! ($successCount of $total files)" -ForegroundColor $successColor
        } else {
            Write-Host "Download finished with errors (exit code $exitCode). $successCount of $total files completed." -ForegroundColor $errorColor
        }

        # Print the Download Results section
        if ($resultsSection.Count -gt 1) {
            Write-Host "`nDownload Results:" -ForegroundColor $promptColor
            $resultsSection | ForEach-Object { Write-Host $_ }
            Write-Host "`nStatus Legend:" -ForegroundColor $promptColor
            Write-Host "(OK): download completed." -ForegroundColor $promptColor
        } else {
            Write-Host "No detailed Download Results found; all files completed successfully." -ForegroundColor $successColor
        }

    } catch {
        Write-Host "Error: Failed to execute aria2c. $_" -ForegroundColor $errorColor
    } finally {
        # Clean up log files
        if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -Force -ErrorAction SilentlyContinue }
        if (Test-Path $stderrLog) { Remove-Item $stderrLog -Force -ErrorAction SilentlyContinue }
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