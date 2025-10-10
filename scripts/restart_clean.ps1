#Usage du script : Script prêt à l’emploi (toggle “hard reset”)
## reset sans perte de données
#powershell -ExecutionPolicy Bypass -File .\scripts\restart_clean.ps1
#
## reset “hard” (efface les volumes du projet)
#powershell -ExecutionPolicy Bypass -File .\scripts\restart_clean.ps1 -Hard
#





Param(
  [switch]$Hard = $false,
  [string]$ComposeFile = "infra/podman/podman-compose.dev.win.images.yml",
  [string]$Project = "podman"  # adapte si besoin
)

$ErrorActionPreference = "Stop"
Set-Location "C:\Users\gregory.catarelli\DEV\template_projet_enterprise"

Write-Host "==> Down stack..."
py -m podman_compose -f $ComposeFile down

if ($Hard) {
  Write-Host "==> Removing project volumes (data will be lost)..."
  $vols = podman volume ls --format "{{.Name}} {{.Labels}}" | Where-Object { $_ -match "io.podman.compose.project=$Project" } | ForEach-Object { ($_ -split ' ')[0] }
  foreach ($v in $vols) { podman volume rm -f $v }

  # Fallback: volumes préfixés par le nom du projet
  podman volume ls --format "{{.Name}}" | Where-Object { $_ -like "$Project*" } | ForEach-Object { podman volume rm -f $_ }

  # Dossiers de données côté host (si utilisés)
  @("infra\pgdata","infra\redisdata","infra\mongodata") | ForEach-Object {
    if (Test-Path $_) { Remove-Item -Recurse -Force $_ }
  }
}

Write-Host "==> Network prune (orphan)..."
podman network prune -f | Out-Null

Write-Host "==> Rebuild images (no cache)..."
podman build --no-cache -t localhost/template_projet-backend:dev -f infra/podman/backend.Containerfile .
podman build --no-cache -t localhost/template_projet-web:dev     -f infra/podman/web.Containerfile .

Write-Host "==> Bring up dependencies..."
py -m podman_compose -f $ComposeFile up -d db redis mongo

Write-Host "==> Bring up backend & web..."
py -m podman_compose -f $ComposeFile up -d backend web

Write-Host "==> Tail backend logs (Ctrl+C to detach)..."
py -m podman_compose -f $ComposeFile logs -f backend
