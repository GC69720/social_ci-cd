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
systemctl --user enable --now reseau-api.container
systemctl --user enable --now reseau-web.container
systemctl --user restart reseau-api.container
systemctl --user stop reseau-api.container
journalctl --user -u reseau-api -f
```

## systemd (natif, sans conteneur)
```bash
sudo cp infra/systemd/reseau-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now reseau-api
sudo systemctl restart reseau-api
sudo systemctl status reseau-api
```
