param([string]$ExecutableName = 'WubiCoach.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
& (Join-Path $projectRoot 'build.ps1') -ExecutableName $ExecutableName
$program = Join-Path (Join-Path $projectRoot 'dist') $ExecutableName
function Invoke-CoachTest([string[]]$TestArguments) {
    $testProcess = Start-Process -FilePath $program -ArgumentList $TestArguments -Wait -PassThru -WindowStyle Hidden
    if ($testProcess.ExitCode -ne 0) {
        Get-Content (Join-Path $projectRoot 'dist\test-error.log') -ErrorAction SilentlyContinue
        throw ('Test failed: ' + ($TestArguments -join ' '))
    }
}
Invoke-CoachTest @('--self-test', ('"' + (Join-Path $PSScriptRoot 'self-test-result.txt') + '"'))
Invoke-CoachTest @('--render', ('"' + (Join-Path $PSScriptRoot 'preview.png') + '"'))
Invoke-CoachTest @('--render', '--ime-demo', ('"' + (Join-Path $PSScriptRoot 'ime-preview.png') + '"'))
Invoke-CoachTest @('--render', '--ime-demo', '--keyboard-demo', ('"' + (Join-Path $PSScriptRoot 'keyboard-preview.png') + '"'))
Invoke-CoachTest @('--keyboard-test', ('"' + (Join-Path $PSScriptRoot 'keyboard-result.txt') + '"'))
$fixture = Start-Process -FilePath $program -ArgumentList '--fixture' -PassThru -WindowStyle Hidden
try {
    Start-Sleep -Seconds 2
    Invoke-CoachTest @('--capture-test', ('"' + (Join-Path $PSScriptRoot 'capture-result.txt') + '"'))
    Start-Sleep -Seconds 13
    Invoke-CoachTest @('--capture-test', '--password', ('"' + (Join-Path $PSScriptRoot 'password-result.txt') + '"'))
} finally {
    $fixture.WaitForExit(25000) | Out-Null
}
Get-Content (Join-Path $PSScriptRoot 'self-test-result.txt'), (Join-Path $PSScriptRoot 'keyboard-result.txt'), (Join-Path $PSScriptRoot 'capture-result.txt'), (Join-Path $PSScriptRoot 'password-result.txt')
