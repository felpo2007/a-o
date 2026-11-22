param([switch]$SemLune)
# Todas as checagens do projeto, com saida curta. Sai com 1 se alguma falhar.
$t = "$env:LOCALAPPDATA\Programs\vt65-tools"
$env:PATH = "$t\lune;$t\rojo;$t\stylua;$t\luau-lsp;$env:PATH"
$s = "$env:TEMP\vt65_teste"
New-Item -ItemType Directory -Force $s | Out-Null
$ruim = 0
if (-not $SemLune) {
    $ok = 0; $f = 0; $n = 0; $falhos = @()
    foreach ($a in Get-ChildItem tests/luau/*.luau) {
        $o = (cmd /c "lune run `"$($a.FullName)`" 2>&1") -join "`n"
        $n++
        $m = [regex]::Matches($o, '(\d+) ok, (\d+) falhas?')
        if ($m.Count -gt 0) {
            $u = $m[$m.Count - 1]; $ok += [int]$u.Groups[1].Value; $g = [int]$u.Groups[2].Value; $f += $g
            if ($g -gt 0) { $falhos += $a.Name }
        } else { $f++; $falhos += "$($a.Name) (sem resumo)" }
    }
    "lune: $ok ok, $f falhas, $n arquivos $($falhos -join ', ')"
    if ($f -gt 0) { $ruim = 1 }
}
foreach ($c in "mapas_check", "expansao_check") {
    $l = (cmd /c "lune run tools/$c.luau 2>&1") | Select-String 'problemas:' | Select-Object -Last 1
    "${c}: $($l.Line)"
    if (-not $l -or $l.Line -notmatch 'problemas: 0') { $ruim = 1 }
}
$o = uv run --group arte pytest -q 2>&1 | Select-Object -Last 1
"pytest: $o"
if ("$o" -notmatch ' passed' -or "$o" -match 'failed|error') { $ruim = 1 }
$o = uv run ruff check . 2>&1 | Select-Object -Last 1
"ruff: $o"
if ("$o" -notmatch 'All checks passed') { $ruim = 1 }
rojo sourcemap default.project.json -o sourcemap.json | Out-Null
cmd /c "luau-lsp analyze --definitions=%LOCALAPPDATA%\Programs\vt65-tools\luau-lsp\globalTypes.None.d.luau --sourcemap=sourcemap.json --ignore ""src/ServerStorage/VT65Build/Data/**"" --ignore ""src/ServerStorage/VT65Build/Data_*/**"" --flag:LuauSolverV2=false src > ""$s\lsp.txt"" 2>&1"
$e = (Select-String -Path "$s\lsp.txt" -Pattern 'TypeError|SyntaxError').Count
"luau-lsp: $e erros"
if ($e -gt 0) { $ruim = 1 }
# guarda a saida antes de cortar: Select-Object -First fecha o pipe e o Python sai com erro
$o = cmd /c "uv run python tools/kb.py check 2>&1"
$rc = $LASTEXITCODE
"base: $($o | Select-Object -First 1)"
if ($rc -ne 0) { $ruim = 1 }
if ($ruim) { "RESULTADO: FALHOU"; exit 1 }
"RESULTADO: OK"
