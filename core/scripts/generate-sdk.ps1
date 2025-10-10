$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Out = Join-Path $Root "web\src\generated"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
npx openapi-typescript "$Root\core\openapi\openapi.yaml" --output "$Outpi-types.ts"
Write-Host "SDK TS généré dans web/src/generated/api-types.ts"
