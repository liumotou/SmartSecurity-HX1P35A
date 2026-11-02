param(
 [ValidateSet('full','syn')][string]$Stage='full',
 [string]$TdRoot='',
 [string]$PythonExe='python'
)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force -Path (Join-Path $taskRoot 'build/td'),(Join-Path $taskRoot 'build/temp') | Out-Null
$env:TEMP=Join-Path $taskRoot 'build/temp'
$env:TMP=$env:TEMP
$env:PYTHONDONTWRITEBYTECODE='1'
if($TdRoot){$env:TD_RUN_EXE=Join-Path $TdRoot 'bin/run.exe'}
& $PythonExe (Join-Path $PSScriptRoot 'build_td.py') $Stage
if($LASTEXITCODE -ne 0){throw 'TD build failed; see build/td/console.log'}
