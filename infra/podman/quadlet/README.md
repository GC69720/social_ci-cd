# Quadlet (systemd user) — Podman

Copiez ces fichiers dans `~/.config/containers/systemd/` puis:

```bash
systemctl --user daemon-reload
systemctl --user enable --now reseau-api.container
systemctl --user enable --now reseau-web.container
# journalctl --user -u reseau-api -f
```

> Les unités utilisent `Network=host` pour simplifier le dev.
> Assurez-vous d'avoir construit ou tiré les images:
>
> - `podman build -t localhost/reseau-api:dev -f infra/podman/backend.Containerfile .`
> - `podman build -t localhost/reseau-web:dev -f infra/podman/web.Containerfile .`
