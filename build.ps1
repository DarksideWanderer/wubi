param([string]$ExecutableName = 'WubiCoach.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$wpf = Join-Path $framework 'WPF'
$compiler = Join-Path $framework 'csc.exe'
New-Item -ItemType Directory -Force (Join-Path $projectRoot 'dist') | Out-Null
$references = @('WindowsBase','PresentationCore','PresentationFramework','UIAutomationClient','UIAutomationTypes') | ForEach-Object { '/reference:' + (Join-Path $wpf ($_ + '.dll')) }
$sourceFiles = Get-ChildItem (Join-Path $projectRoot 'src') -Filter '*.cs' | ForEach-Object { $_.FullName }
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /utf8output /codepage:65001 ('/out:' + (Join-Path (Join-Path $projectRoot 'dist') $ExecutableName)) /reference:System.Xaml.dll @references @sourceFiles
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'data') -Destination (Join-Path $projectRoot 'dist') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md'),(Join-Path $projectRoot 'THIRD-PARTY.md'),(Join-Path $projectRoot 'LICENSE') -Destination (Join-Path $projectRoot 'dist') -Force
Write-Output ('Built dist\' + $ExecutableName)
