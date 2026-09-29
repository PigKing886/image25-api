$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runner = Join-Path $repo 'scripts/run_image.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('image25-test-' + [guid]::NewGuid().ToString('N'))
$cliDirectory = Join-Path $testRoot 'skills/.system/imagegen/scripts'
New-Item -ItemType Directory -Path $cliDirectory -Force | Out-Null
$stub = @'
import os, sys
assert os.environ['OPENAI_BASE_URL'] == 'https://example.invalid/v1'
assert os.environ['OPENAI_API_KEY'] in ['sk-TEST-ONLY', 'TEST-JSON-KEY']
print('upstream credential: ' + os.environ['OPENAI_API_KEY'])
if sys.argv[sys.argv.index('--quality') + 1] == 'low':
    sys.exit(7)
print('stub passed')
'@
Set-Content -LiteralPath "$cliDirectory/image_gen.py" -Value $stub -Encoding utf8
Set-Content -LiteralPath "$testRoot/prompt.txt" -Value 'Test image' -Encoding utf8
Set-Content -LiteralPath "$testRoot/config.txt" -Value "https://example.invalid`nsk-TEST-ONLY" -Encoding utf8
Set-Content -LiteralPath "$testRoot/config.json" -Value '{"base_url":"https://example.invalid/v1/","api_key":"TEST-JSON-KEY"}' -Encoding utf8
$saved = @{}
foreach ($name in @('CODEX_HOME', 'OPENAI_API_KEY', 'OPENAI_BASE_URL')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $env:CODEX_HOME = $testRoot
    $env:OPENAI_API_KEY = 'TEST-PREVIOUS-KEY'
    $env:OPENAI_BASE_URL = 'https://previous.invalid/v1'
    foreach ($config in @('config.txt', 'config.json')) {
        $result = & $runner -Python (Get-Command python).Source -ConfigFile "$testRoot/$config" -PromptFile "$testRoot/prompt.txt" -Out "$testRoot/unused.png" -DryRun
        if (($result -join "`n") -match 'sk-TEST-ONLY|TEST-JSON-KEY') { throw 'Credential leaked' }
        if ($env:OPENAI_API_KEY -ne 'TEST-PREVIOUS-KEY' -or $env:OPENAI_BASE_URL -ne 'https://previous.invalid/v1') { throw 'Environment not restored' }
    }
    $expectedFailure = $false
    try {
        & $runner -Python (Get-Command python).Source -ConfigFile "$testRoot/config.txt" -PromptFile "$testRoot/prompt.txt" -Out "$testRoot/unused.png" -Quality low -DryRun | Out-Null
    } catch { $expectedFailure = $_.Exception.Message -match '7' }
    if (-not $expectedFailure -or $env:OPENAI_API_KEY -ne 'TEST-PREVIOUS-KEY' -or $env:OPENAI_BASE_URL -ne 'https://previous.invalid/v1') { throw 'Failure handling incorrect' }
    if (Test-Path -LiteralPath "$testRoot/unused.png") { throw 'Unexpected image output' }
    'PASS: config, endpoint normalization, redaction and environment restoration. No network requests.'
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    # 只清理刚创建并验证位于临时目录中的测试目录。
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'image25-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
