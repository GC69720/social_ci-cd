# Opérations: démarrage/arrêt/redémarrage

## Podman (dev)
```bash
make dev                # up (build + attach)
podman-compose -f infra/podman/podman-compose.dev.yml up -d
podman-compose -f infra/podman/podman-compose.dev.yml down
```

## Quadlet (systemd user, conteneurs)
```bash
# Copier les fichiers .container dans ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user enable --now template_projet-backend.container
systemctl --user enable --now template_projet-web.container
systemctl --user restart template_projet-backend.container
systemctl --user stop template_projet-backend.container
journalctl --user -u template_projet-backend -f
```

## systemd (natif, sans conteneur)
```bash
sudo cp infra/systemd/template_projet-backend.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now template_projet-backend
sudo systemctl restart template_projet-backend
sudo systemctl status template_projet-backend
```
