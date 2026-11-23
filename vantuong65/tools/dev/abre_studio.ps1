param([string]$Nome = "VT65_teste", [switch]$ComJogo)
# Formata o que mudou, confere tipos, gera o place e abre uma COPIA no Studio (nunca o da nuvem).
# -ComJogo: abre mesmo com o jogo do dono aberto (o dono autorizou; mantenha a qualidade baixa).
$s = "$env:TEMP\vt65_teste"
New-Item -ItemType Directory -Force $s | Out-Null
$t = "$env:LOCALAPPDATA\Programs\vt65-tools"
$env:PATH = "$t\lune;$t\rojo;$t\stylua;$t\luau-lsp;$env:PATH"
Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
$arqs = @(git -c core.quotepath=off status --porcelain --untracked-files=all -- src tests tools | ForEach-Object { $_.Substring(3).Trim('"') } | Where-Object { $_ -like '*.luau' -and $_ -notlike '*VT65Build/Data*' } | ForEach-Object { $_ -replace '^vantuong65/', '' } | Where-Object { Test-Path $_ })
& "$PSScriptRoot\stylua_utf8.ps1" -Tmp "$s\sty" -Formatar -Arquivos $arqs | Select-Object -Last 1
rojo sourcemap default.project.json -o sourcemap.json | Out-Null
cmd /c "luau-lsp analyze --definitions=%LOCALAPPDATA%\Programs\vt65-tools\luau-lsp\globalTypes.None.d.luau --sourcemap=sourcemap.json --ignore ""src/ServerStorage/VT65Build/Data/**"" --ignore ""src/ServerStorage/VT65Build/Data_*/**"" --flag:LuauSolverV2=false src > ""$s\lsp.txt"" 2>&1"
"lsp: $LASTEXITCODE; erros: $((Select-String -Path "$s\lsp.txt" -Pattern 'TypeError|SyntaxError').Count)"
Select-String -Path "$s\lsp.txt" -Pattern 'TypeError|SyntaxError' | Select-Object -First 6 | ForEach-Object { $_.Line.Replace((Get-Location).Path, '') }
rojo build default.project.json -o build/VanTuong65_base.rbxl 2>&1 | Select-Object -Last 1
lune run tools/bake_place.luau 2>&1 | Select-Object -Last 1
Copy-Item build\VanTuong65_F1.rbxl "$s\$Nome.rbxl" -Force
if (-not $ComJogo -and (Get-Process RobloxPlayerBeta -ErrorAction SilentlyContinue | Where-Object { $_.WorkingSet64 -gt 300MB })) { "JOGO DO DONO ABERTO: Studio nao abre"; exit }
$v = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Directory | Where-Object { Test-Path "$($_.FullName)\RobloxStudioBeta.exe" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Start-Process "$($v.FullName)\RobloxStudioBeta.exe" -ArgumentList "`"$s\$Nome.rbxl`""
Start-Sleep -Seconds 50
"studio aberto"
