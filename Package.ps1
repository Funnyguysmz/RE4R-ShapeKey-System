$ErrorActionPreference='Stop'
$stage=Join-Path $PSScriptRoot 'build/package'
$files=[ordered]@{
    'src/RE4R_ShapeKeySystem.lua'='reframework/autorun/RE4R_ShapeKeySystem.lua'
    'data/RE4R_ShapeKeySystem_native_leon.json'='reframework/data/RE4R_ShapeKeySystem_native_leon.json'
    'data/RE4R_ShapeKeySystem_native_leon_mouth9.json'='reframework/data/RE4R_ShapeKeySystem_native_leon_mouth9.json'
    'README.md'='README.md'
    'LICENSE'='LICENSE'
    'docs/API.md'='docs/API.md'
    'docs/PROFILE_FORMAT.md'='docs/PROFILE_FORMAT.md'
    'docs/MOUTH9_TEST.md'='docs/MOUTH9_TEST.md'
    'docs/验证记录.md'='docs/验证记录.md'
    'examples/profile_mouth9_synthetic.json'='examples/profile_mouth9_synthetic.json'
}
foreach($source in $files.Keys){
    $target=Join-Path $stage $files[$source]
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $source) -Destination $target
}
# Refuse to package stale/unrelated stage files rather than deleting history.
$allowed=@($files.Values | ForEach-Object { $_.Replace('/','\') })
foreach($file in Get-ChildItem -LiteralPath $stage -Recurse -File){
    $relative=$file.FullName.Substring($stage.Length+1)
    if($relative -notin $allowed){throw "Unexpected package file: $relative"}
}
