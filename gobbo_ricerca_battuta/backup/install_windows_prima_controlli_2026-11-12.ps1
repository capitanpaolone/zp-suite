# ZP Speech Engine: installazione o aggiornamento per Windows (OpenAI Whisper locale).
#
# Uso (da PowerShell):
#   powershell -NoProfile -ExecutionPolicy Bypass -File speech-engine\install_windows.ps1 [-Model small]
param(
    [string]$Model = $env:ZP_WHISPER_MODEL
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceDir = if ($env:ZP_SPEECH_SOURCE) { $env:ZP_SPEECH_SOURCE } else { $ScriptDir }
$InstallRoot = if ($env:ZP_DATA_DIR) { $env:ZP_DATA_DIR } else { Join-Path $env:LOCALAPPDATA "ZP" }
$EnvDir = Join-Path $InstallRoot "runtimes\speech"
$WhisperEnvDir = Join-Path $InstallRoot "runtimes\openai-whisper"
$ModelsDir = Join-Path $InstallRoot "models\whisper"
$ControlDir = Join-Path $InstallRoot "control"
$LogDir = Join-Path $InstallRoot "logs"
$Port = 8770

if (-not (Test-Path (Join-Path $SourceDir "pyproject.toml"))) {
    Write-Error "Sorgente ZP Speech Engine non trovato in $SourceDir"
    exit 1
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "Serve FFmpeg nel PATH per OpenAI Whisper (es. winget install Gyan.FFmpeg)."
    exit 1
}

function Find-Python311Plus {
    foreach ($ver in @("-3.11", "-3.12", "-3.13", "-3.14", "-3")) {
        try {
            $exe = & py $ver -c "import sys; print(sys.executable if sys.version_info >= (3,11) else '')" 2>$null
            if ($exe -and (Test-Path $exe.Trim())) { return $exe.Trim() }
        } catch {}
    }
    foreach ($cmd in @("python3.11", "python3", "python")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            try {
                $ok = & $found.Source -c "import sys; print('1' if sys.version_info >= (3,11) else '0')" 2>$null
                if ($ok.Trim() -eq "1") { return $found.Source }
            } catch {}
        }
    }
    return $null
}

$Py = Find-Python311Plus
if (-not $Py) {
    Write-Error "Serve Python 3.11 (consigliato per OpenAI Whisper). Installalo da python.org selezionando 'Add Python to PATH'."
    exit 1
}
Write-Host "Python rilevato: $Py"

New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "runtimes"), $ModelsDir, $ControlDir, $LogDir | Out-Null

$ServicePy = Join-Path $EnvDir "Scripts\python.exe"
if (-not (Test-Path $ServicePy)) {
    & $Py -m venv $EnvDir
}
& $ServicePy -m pip install --quiet --upgrade pip
& $ServicePy -m pip install --quiet --force-reinstall $SourceDir

$WhisperPy = Join-Path $WhisperEnvDir "Scripts\python.exe"
if (-not (Test-Path $WhisperPy)) {
    & $Py -m venv $WhisperEnvDir
}
Write-Host "Installo PyTorch e openai-whisper nell'ambiente dedicato..."
& $WhisperPy -m pip install --upgrade pip
& $WhisperPy -m pip install openai-whisper

$ZpSpeechExe = Join-Path $EnvDir "Scripts\zp-speech.exe"

if (-not $Model) {
    Write-Host ""
    Write-Host "Scegli il modello OpenAI Whisper da scaricare in ${ModelsDir}:"
    Write-Host "  1) small           (~465 MB)  - veloce, ottimo per test e macchine leggere"
    Write-Host "  2) large-v3-turbo  (~1550 MB) - consigliato: alta qualita' italiano e veloce"
    Write-Host "  3) medium          (~1460 MB) - intermedio"
    Write-Host "  4) large-v3        (~2950 MB) - massima precisione, piu' pesante"
    Write-Host "  0) Non scaricare ora"
    $choice = Read-Host "Scelta [1]"
    switch ($choice) {
        "2" { $Model = "large-v3-turbo" }
        "3" { $Model = "medium" }
        "4" { $Model = "large-v3" }
        "0" { $Model = "" }
        default { $Model = "small" }
    }
}

if ($Model) {
    Write-Host "Scarico il modello '$Model' in $ModelsDir..."
    & $ZpSpeechExe download-model $Model
}

Start-Process -FilePath $ZpSpeechExe -ArgumentList "serve" -WorkingDirectory $InstallRoot -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $LogDir "speech-service.out.log") `
    -RedirectStandardError (Join-Path $LogDir "speech-service.err.log")

for ($i = 0; $i -lt 10; $i++) {
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/v1/health" -TimeoutSec 1
        if ($resp.status -eq "ok") {
            Write-Host "Servizio attivo su http://127.0.0.1:$Port"
            break
        }
    } catch {}
    Start-Sleep -Seconds 1
}

try {
    & $ZpSpeechExe doctor | Out-Null
    Write-Host "OpenAI Whisper: pronto."
} catch {
    Write-Host "OpenAI Whisper installato. Scarica un modello con: $ZpSpeechExe download-model small"
}
