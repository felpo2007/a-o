param([string]$Tmp = "$env:TEMP\vt65_stylua", [switch]$Formatar, [string[]]$Arquivos)
# StyLua em copias LF, lendo e gravando em UTF-8 (nunca Get-Content: ele le como cp1252).
# Com -Formatar, grava de volta em LF so os arquivos que mudaram.
$u = New-Object Text.UTF8Encoding($false)
$env:PATH = "$env:LOCALAPPDATA\Programs\vt65-tools\stylua;$env:PATH"
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Tmp | Out-Null
if (Test-Path stylua.toml) { Copy-Item stylua.toml $Tmp }
# o que o projeto deixa fora do StyLua (.styluaignore: o MapConfig gerado e os dados)
$ignorar = @()
if (Test-Path .styluaignore) { $ignorar = Get-Content .styluaignore | Where-Object { $_.Trim() -ne "" } }
$Arquivos = $Arquivos | Where-Object { $f = $_ -replace '\\', '/'; -not ($ignorar | Where-Object { $f.StartsWith($_) }) }
foreach ($f in $Arquivos) {
    $t = [IO.File]::ReadAllText((Resolve-Path $f).Path, $u) -replace "`r`n", "`n"
    [IO.File]::WriteAllText((Join-Path $Tmp ($f -replace '[/\\]', '__')), $t, $u)
}
Push-Location $Tmp
if ($Formatar) { stylua . }
stylua --check . | Select-Object -First 60
Write-Output "stylua check: $LASTEXITCODE"
Pop-Location
if ($Formatar) {
    foreach ($f in $Arquivos) {
        $p = (Resolve-Path $f).Path
        $novo = [IO.File]::ReadAllText((Join-Path $Tmp ($f -replace '[/\\]', '__')), $u)
        $velho = [IO.File]::ReadAllText($p, $u) -replace "`r`n", "`n"
        if ($novo -ne $velho) {
            [IO.File]::WriteAllText($p, $novo, $u)
            Write-Output "formatado: $f"
        }
    }
}
