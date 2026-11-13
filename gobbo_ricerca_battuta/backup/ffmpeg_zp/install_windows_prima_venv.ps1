# ZP Speech Engine: installazione o aggiornamento per Windows (OpenAI Whisper locale).
#
# Uso (da PowerShell):
#   powershell -NoProfile -ExecutionPolicy Bypass -File speech-engine\install_windows.ps1 [-Model small]
param(
    [string]$Model = $env:ZP_WHISPER_MODEL
)

$ErrorActionPreference = "Stop"

# Un programma installato dopo l'avvio di REAPER (Python, FFmpeg con winget) non e' nel PATH
# ereditato: rilegge il PATH di sistema e dell'utente.
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

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
$PyMinor = & $Py -c "import sys; print(sys.version_info[1])"
if ($PyMinor -and [int]$PyMinor -ge 14) {
    Write-Host "Attenzione: Python 3.$PyMinor e' molto recente e PyTorch/openai-whisper potrebbero non avere ancora i pacchetti per Windows." -ForegroundColor Yellow
    Write-Host "Se l'installazione si ferma, installa anche Python 3.12 (python.org, senza togliere questa) e rilancia: lo script lo preferisce." -ForegroundColor Yellow
}

# I comandi nativi (pip, python, zp-speech) non fermano lo script quando falliscono:
# si controlla il codice di uscita, cosi' non si stampa un falso "pronto".
function Assert-Ok([string]$What) {
    if ($LASTEXITCODE -ne 0) {
        Write-Error "$What non riuscito (codice $LASTEXITCODE). Leggi i messaggi qui sopra."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "runtimes"), $ModelsDir, $ControlDir, $LogDir | Out-Null

# FFmpeg: serve a OpenAI Whisper per leggere l'audio. Se non e' nel PATH, ZP ne tiene una copia
# privata in %LOCALAPPDATA%\ZP\ffmpeg\bin (build "essentials" di gyan.dev): niente PATH da toccare.
$FfmpegDir = Join-Path $InstallRoot "ffmpeg\bin"
$FfmpegExe = Join-Path $FfmpegDir "ffmpeg.exe"
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue) -and -not (Test-Path $FfmpegExe)) {
    Write-Host "FFmpeg non trovato: lo scarico (circa 100 MB) in $FfmpegDir ..."
    $FfTmp = Join-Path $env:TEMP ("zp_ffmpeg_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $FfTmp | Out-Null
    try {
        $Zip = Join-Path $FfTmp "ffmpeg.zip"
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile $Zip
        Expand-Archive -Path $Zip -DestinationPath $FfTmp -Force
        $Found = Get-ChildItem -Path $FfTmp -Recurse -Filter ffmpeg.exe | Select-Object -First 1
        if (-not $Found) { throw "ffmpeg.exe non trovato nell'archivio scaricato" }
        New-Item -ItemType Directory -Force -Path $FfmpegDir | Out-Null
        Copy-Item -Path $Found.FullName -Destination $FfmpegExe -Force
        $Lic = Get-ChildItem -Path $FfTmp -Recurse -Filter "LICENSE*" | Select-Object -First 1
        if ($Lic) { Copy-Item -Path $Lic.FullName -Destination (Join-Path $InstallRoot "ffmpeg\LICENSE.txt") -Force }
    } catch {
        Write-Error "Non riesco a scaricare FFmpeg: $($_.Exception.Message). Installalo a mano (https://www.gyan.dev/ffmpeg/builds/) e rilancia."
        exit 1
    } finally {
        Remove-Item -Recurse -Force $FfTmp -ErrorAction SilentlyContinue
    }
    & $FfmpegExe -version | Out-Null
    Assert-Ok "Verifica di FFmpeg"
    Write-Host "FFmpeg pronto in $FfmpegDir"
}

$ServicePy = Join-Path $EnvDir "Scripts\python.exe"
if (-not (Test-Path $ServicePy)) {
    & $Py -m venv $EnvDir
    Assert-Ok "Creazione dell'ambiente del servizio"
}
& $ServicePy -m pip install --quiet --upgrade pip
Assert-Ok "Aggiornamento di pip"
& $ServicePy -m pip install --quiet --force-reinstall $SourceDir
Assert-Ok "Installazione di ZP Speech"

$WhisperPy = Join-Path $WhisperEnvDir "Scripts\python.exe"
if (-not (Test-Path $WhisperPy)) {
    & $Py -m venv $WhisperEnvDir
    Assert-Ok "Creazione dell'ambiente OpenAI Whisper"
}
Write-Host "Installo PyTorch e openai-whisper nell'ambiente dedicato..."
& $WhisperPy -m pip install --upgrade pip
Assert-Ok "Aggiornamento di pip (Whisper)"
# openai-whisper si costruisce con uno script che importa pkg_resources, tolto dalle versioni
# recenti di setuptools: si installa setuptools < 81 e si costruisce senza l'ambiente isolato.
& $WhisperPy -m pip install "setuptools<81" wheel
Assert-Ok "Installazione di setuptools"
& $WhisperPy -m pip install --no-build-isolation openai-whisper
Assert-Ok "Installazione di PyTorch e openai-whisper"

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
    Assert-Ok "Download del modello '$Model'"
}

Start-Process -FilePath $ZpSpeechExe -ArgumentList "serve" -WorkingDirectory $InstallRoot -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $LogDir "speech-service.out.log") `
    -RedirectStandardError (Join-Path $LogDir "speech-service.err.log")

$ServiceUp = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/v1/health" -TimeoutSec 1
        if ($resp.status -eq "ok") {
            Write-Host "Servizio attivo su http://127.0.0.1:$Port"
            $ServiceUp = $true
            break
        }
    } catch {}
    Start-Sleep -Seconds 1
}
if (-not $ServiceUp) {
    Write-Error "Il servizio non risponde su http://127.0.0.1:$Port dopo 30 secondi. Controlla i log in $LogDir."
    exit 1
}

& $ZpSpeechExe doctor | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "OpenAI Whisper: pronto."
} else {
    Write-Host "OpenAI Whisper installato, ma il controllo (doctor) non e' passato. Scarica un modello con: $ZpSpeechExe download-model small"
}
