$ErrorActionPreference='Stop'
$dest=Join-Path $PSScriptRoot 'build/package/reframework/autorun'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'src/RE4R_ShapeKeySystem.lua') $dest
Copy-Item (Join-Path $PSScriptRoot 'README.md') (Join-Path $PSScriptRoot 'build/package')
Copy-Item (Join-Path $PSScriptRoot 'LICENSE') (Join-Path $PSScriptRoot 'build/package')
