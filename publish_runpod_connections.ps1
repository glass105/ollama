[CmdletBinding()]
param(
    [string]$EnvFile = "$PSScriptRoot\.env",
    [string]$RuntimeFile = "$PSScriptRoot\secrets\last_runpod_runtime.json",
    [string]$OutputFile = "$PSScriptRoot\secrets\pod_connections.json",
    [string]$WorkerEnvironmentFile = "$PSScriptRoot\secrets\equipment_worker.env",
    [string]$EquipmentFile = "$PSScriptRoot\secrets\equipment.csv",
    [string]$EquipmentHelper = "$PSScriptRoot\equipment_access.py",
    [string]$IdentityFile = "$PSScriptRoot\.ssh\ollama_runpod_ed25519",
    [string]$RunPodUser = "root",
    [switch]$UseSavedRuntime,
    [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"

foreach ($requiredFile in @($EquipmentFile, $EquipmentHelper, $IdentityFile)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file not found: $requiredFile"
    }
}

function Get-DotEnvValues {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Environment file not found: $Path"
    }
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $value = $Matches[2]
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$Matches[1]] = $value
        }
    }
    return $values
}

if ($UseSavedRuntime) {
    if (-not (Test-Path -LiteralPath $RuntimeFile -PathType Leaf)) {
        throw "Saved RunPod runtime file not found: $RuntimeFile"
    }
    $runtime = Get-Content -LiteralPath $RuntimeFile -Raw | ConvertFrom-Json
}
else {
    $envValues = Get-DotEnvValues -Path $EnvFile
    $apiKey = [string]$envValues['RUNPOD_API_KEY']
    $podName = [string]$envValues['RUNPOD_POD_NAME']
    if (-not $apiKey -or -not $podName) {
        throw "RUNPOD_API_KEY and RUNPOD_POD_NAME are required in $EnvFile"
    }

    $query = @'
query {
  myself {
    pods {
      id
      name
      desiredStatus
      imageName
      machineId
      runtime {
        uptimeInSeconds
        ports { ip privatePort publicPort type }
      }
    }
  }
}
'@
    $requestBody = @{ query = $query } | ConvertTo-Json -Compress
    $requestUri = 'https://api.runpod.io/graphql?api_key=' + [uri]::EscapeDataString($apiKey)
    $response = Invoke-RestMethod -Method Post -Uri $requestUri `
        -ContentType 'application/json' -Body $requestBody
    if ($response.errors) {
        throw "RunPod API query failed: $($response.errors | ConvertTo-Json -Compress)"
    }

    $matches = @($response.data.myself.pods | Where-Object {
        $_.name -eq $podName -and $_.desiredStatus -eq 'RUNNING'
    } | Where-Object {
        @($_.runtime.ports | Where-Object {
            [int]$_.privatePort -eq 22 -and [string]$_.type -eq 'tcp' -and
            $_.ip -and $_.publicPort
        }).Count -eq 1
    })
    if ($matches.Count -ne 1) {
        throw "Expected one RUNNING pod named '$podName' with an SSH mapping; found $($matches.Count)."
    }
    $runtime = $matches[0]

    $runtimeDirectory = Split-Path -Parent $RuntimeFile
    if (-not (Test-Path -LiteralPath $runtimeDirectory)) {
        New-Item -ItemType Directory -Path $runtimeDirectory | Out-Null
    }
    $runtime | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RuntimeFile -Encoding utf8
    Write-Host "Refreshed sanitized RunPod runtime: $RuntimeFile"
}

if ($runtime.desiredStatus -ne "RUNNING") {
    throw "RunPod status is '$($runtime.desiredStatus)', not RUNNING."
}

$runtimePorts = @($runtime.runtime.ports)
$sshPort = @($runtimePorts | Where-Object {
    [int]$_.privatePort -eq 22 -and [string]$_.type -eq "tcp"
})
if ($sshPort.Count -ne 1) {
    throw "Expected one live SSH port mapping, found $($sshPort.Count)."
}

$sshHost = [string]$sshPort[0].ip
$sshPublicPort = [int]$sshPort[0].publicPort
if (-not $sshHost -or $sshPublicPort -lt 1) {
    throw "The live SSH mapping does not contain a public IP and port."
}

$sanitizedPorts = @($runtimePorts | ForEach-Object {
    $privatePort = [int]$_.privatePort
    $type = [string]$_.type
    $entry = [ordered]@{
        privatePort = $privatePort
        publicPort = if ($null -ne $_.publicPort) { [int]$_.publicPort } else { $null }
        type = $type
        ip = [string]$_.ip
    }
    if ($type -eq "http" -and $runtime.id) {
        $entry.proxyUrl = "https://$($runtime.id)-${privatePort}.proxy.runpod.net"
    }
    [PSCustomObject]$entry
})

$manifest = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    sourceRuntimeFile = [System.IO.Path]::GetFileName($RuntimeFile)
    pod = [ordered]@{
        id = [string]$runtime.id
        name = [string]$runtime.name
        status = [string]$runtime.desiredStatus
        image = [string]$runtime.imageName
        machineId = [string]$runtime.machineId
    }
    ssh = [ordered]@{
        host = $sshHost
        port = $sshPublicPort
        user = $RunPodUser
        identityFile = [System.IO.Path]::GetFullPath($IdentityFile)
    }
    ports = $sanitizedPorts
    podLocal = [ordered]@{
        ollama = "http://127.0.0.1:11434"
        anythingLlm = "http://127.0.0.1:3010"
        openClaw = "http://127.0.0.1:18789"
        equipmentInventory = "/tmp/equipment.csv"
        equipmentSshConfig = "/tmp/equipment_ssh_config"
        equipmentBridge = "http://127.0.0.1:19124"
    }
}

Write-Host "RunPod SSH endpoint: ${sshHost}:$sshPublicPort"

if ($SkipUpload) {
    $outputDirectory = Split-Path -Parent $OutputFile
    if (-not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputFile -Encoding utf8
    Write-Host "Wrote sanitized pod connections: $OutputFile"
    Write-Host "Skipped equipment upload."
    exit 0
}

$target = "${RunPodUser}@${sshHost}"
& scp.exe -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new `
    -i $IdentityFile -P $sshPublicPort $EquipmentFile $EquipmentHelper "${target}:/tmp/"
if ($LASTEXITCODE -ne 0) {
    throw "Equipment inventory/helper upload failed with exit code $LASTEXITCODE."
}

$remoteCommand = @'
chmod 600 /tmp/equipment.csv
chmod 700 /tmp/equipment_access.py
python3 /tmp/equipment_access.py prepare
'@
& ssh.exe -o BatchMode=yes -o StrictHostKeyChecking=yes `
    -i $IdentityFile -p $sshPublicPort $target $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "Pod equipment preparation failed with exit code $LASTEXITCODE."
}
$outputDirectory = Split-Path -Parent $OutputFile
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputFile -Encoding utf8
Write-Host "Wrote sanitized pod connections: $OutputFile"
Write-Host "Uploaded equipment inventory and prepared pod SSH aliases."

$bridgeMappings = @($runtimePorts | Where-Object {
    [int]$_.privatePort -eq 19124 -and [string]$_.type -eq 'http'
})
if ($bridgeMappings.Count -eq 1) {
    $workerToken = (& ssh.exe -o BatchMode=yes -o StrictHostKeyChecking=yes `
        -i $IdentityFile -p $sshPublicPort $target 'cat /tmp/equipment-bridge/worker-token').Trim()
    if ($LASTEXITCODE -ne 0 -or $workerToken.Length -lt 32) {
        throw "Equipment bridge is exposed, but its worker token could not be retrieved."
    }
    $workerUrl = "https://$($runtime.id)-19124.proxy.runpod.net"
    @(
        "BRIDGE_URL=$workerUrl"
        "BRIDGE_TOKEN=$workerToken"
        "WORKER_ID=equipment-pc-01"
        "POLL_SECONDS=5"
    ) | Set-Content -LiteralPath $WorkerEnvironmentFile -Encoding ascii
    Write-Host "Wrote protected worker configuration: $WorkerEnvironmentFile"
}
else {
    Write-Warning "Port 19124/http is not exposed; no equipment_worker.env was generated."
}
