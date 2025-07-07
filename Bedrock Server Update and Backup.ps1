Write-Host "MINECRAFT BEDROCK SERVER UPDATE SCRIPT (7/7/2025)"
Write-Host "`n" "`n" "`n"

$gameDir = "C:\bedrock-server"
$logFilePath = Join-Path -Path $gameDir -ChildPath ScriptLogs\Log.txt
Start-Transcript -Path $logFilePath -Force

function Backup-Worlds {
    $source = Join-Path -Path $gameDir -ChildPath worlds
    $destination = Join-Path -Path $gameDir -ChildPath ScriptBackups
    $numBackup = 10

    $latestModification = Get-ChildItem -Path $source -Recurse -File | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1

    $existingBackups = Get-ChildItem -Path $destination -Directory | Sort-Object -Property CreationTime -Descending
    if ($existingBackups) {
        $lastBackupDate = $existingBackups[0].CreationTime
        $timeDifference = New-TimeSpan -Start $lastBackupDate -End $latestModification.LastWriteTime

        if ($timeDifference.TotalMinutes -le 2) {
            Write-Host "NO MODIFICATIONS FOUND AFTER THE LAST BACKUP. SKIPPING BACKUP"
            return
        }
    }

    $date = Get-Date -Format "yyyy-MM-dd_HHmmss"

    if (Get-Process -Name bedrock_server -ErrorAction SilentlyContinue) {
        Write-Host "STOPPING SERVICE..."
        Stop-Process -Name "bedrock_server"
    }

    if (!(Test-Path -Path $destination)) {
        New-Item -ItemType Directory -Path $destination
    }

    $backupPath = Join-Path -Path $destination -ChildPath $date
    New-Item -ItemType Directory -Path $backupPath
    Copy-Item -Path $source -Destination $backupPath -Recurse
    Write-Host "WORLDS FOLDER BACKUP COMPLETE"
    Start-Sleep -Seconds 3

    Write-Host "REMOVING OLDER BACKUPS"
    Get-ChildItem -Path $destination -Directory |
        Sort-Object -Property CreationTime -Descending |
        Select-Object -Skip $numBackup |
        Remove-Item -Recurse -Force
    Start-Sleep -Seconds 2
}

Set-Location $gameDir

try {
    $json = Invoke-WebRequest -Uri "https://net-secondary.web.minecraft-services.net/api/v1.0/download/links" -UseBasicParsing
    $data = $json.Content | ConvertFrom-Json
    $win = $data.result.links | Where-Object { $_.downloadType -eq "serverBedrockWindows" }

    if ($null -eq $win) {
        Write-Host "ERROR: JSON LINK FOR BEDROCK SERVER FOR WINDOWS NOT FOUND."
        Stop-Transcript
        exit
    }

    $url = $win.downloadUrl
    $filename = [System.IO.Path]::GetFileName($url)
} catch {
    Write-Host "ERROR FETCHING SERVER LINK FROM JSON."
    Stop-Transcript
    exit
}

$outputDir = Join-Path -Path $gameDir -ChildPath "ScriptUpdateFiles"
$output = Join-Path -Path $outputDir -ChildPath $filename

Write-Host "NEWEST UPDATE AVAILABLE: $filename"

if (!(Test-Path -Path $output -PathType Leaf)) {
    if (Get-Process -Name bedrock_server -ErrorAction SilentlyContinue) {
        Write-Host "STOPPING SERVICE..."
        Stop-Process -Name "bedrock_server"
    }

    Write-Host "BACKING UP WORLDS FOLDER"
    Start-Sleep -Seconds 2
    Backup-Worlds

    if (!(Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir
    }

    if (Test-Path -Path "server.properties" -PathType Leaf) {
        Write-Host "BACKING UP server.properties..."
        Copy-Item -Path "server.properties" -Destination $outputDir
    } else {
        Write-Host "NO server.properties FOUND ... EXITING"
        Stop-Transcript
        exit
    }

    if (Test-Path -Path "allowlist.json" -PathType Leaf) {
        Write-Host "BACKING UP allowlist.json..."
        Copy-Item -Path "allowlist.json" -Destination $outputDir
    }

    if (Test-Path -Path "permissions.json" -PathType Leaf) {
        Write-Host "BACKING UP permissions.json..."
        Copy-Item -Path "permissions.json" -Destination $outputDir
    }

    Write-Host "DOWNLOADING $filename..."
    $start_time = Get-Date
    Invoke-WebRequest -Uri $url -OutFile $output

    Write-Host "UPDATING SERVER FILES..."
    Expand-Archive -LiteralPath $output -DestinationPath $gameDir -Force

    Write-Host "RESTORING server.properties..."
    Copy-Item -Path "$outputDir\server.properties" -Destination $gameDir -Force

    if (Test-Path -Path "$outputDir\allowlist.json" -PathType Leaf) {
        Write-Host "RESTORING allowlist.json..."
        Copy-Item -Path "$outputDir\allowlist.json" -Destination $gameDir -Force
    }

    if (Test-Path -Path "$outputDir\permissions.json" -PathType Leaf) {
        Write-Host "RESTORING permissions.json..."
        Copy-Item -Path "$outputDir\permissions.json" -Destination $gameDir -Force
    }

    Write-Host "STARTING SERVER..."
    Start-Process "$gameDir\bedrock_server.exe"
} else {
    Write-Host "UPDATE ALREADY INSTALLED..."

    Write-Host "BACKING UP WORLDS FOLDER..."
    Start-Sleep -Seconds 3
    Backup-Worlds

    $exePath = "$gameDir\bedrock_server.exe"
    if (-not (Get-Process -Name bedrock_server -ErrorAction SilentlyContinue)) {
        Write-Host "STARTING SERVER..."
        Start-Process $exePath
        Write-Host "STARTED"
        Start-Sleep -Seconds 2
    }
}

Write-Host "CLOSING SCRIPT"
Stop-Transcript
Start-Sleep -Seconds 5
exit
