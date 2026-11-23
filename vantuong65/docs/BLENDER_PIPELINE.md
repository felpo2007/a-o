# Pipeline Blender → Roblox da área piloto

Sempre na CPU (`VT65_CPU=1`), a partir de `vantuong65/`.

```powershell
$env:VT65_CPU="1"; & "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b --factory-startup -P tools/blender/ret.py -- ret_vila_palafita_a
```
```powershell
$env:VT65_CPU="1"; & "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b --factory-startup -P tools/blender/ret.py -- ret_vila_palafita_a --trim --sem-previa
```
```powershell
uv run python tools/ret_registrar.py plano
```
```powershell
uv run --env-file .env python tools/roblox_cloud.py upload-assets Models.ret_vila_
```
```powershell
uv run python tools/ret_registrar.py jogo
```

| Arquivo | Função |
|---|---|
| `tools/blender/ret_vila.py` | Receitas paramétricas das construções e dos objetos |
| `tools/vila_decais.py` | Poça, trilha de roda e folhas (textura com alfa) |
| `tools/manifesto_assets.py` | Gera `docs/ASSET_MANIFEST.md` |
| `Shared/VilaPiloto` | Lugar de cada peça e regra do chão |
| `Modules/VilaPilotoService` | Monta a área no jogo |

- Refazer um modelo publicado: tire a chave do `assets/roblox_ids.json` antes de subir.
- Ver a área no Studio: no modo Edit, `workspace:SetAttribute("VT65DevPiloto", true)` e dê Play.
- `Shared/VilaPiloto.LIGADA` continua `false` até a aprovação do dono.
