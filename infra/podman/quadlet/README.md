# Quadlet (systemd user) — Podman

Copiez ces fichiers dans `~/.config/containers/systemd/` puis:

```bash
systemctl --user daemon-reload
systemctl --user enable --now template_projet-backend.container
systemctl --user enable --now template_projet-web.container
# journalctl --user -u template_projet-backend -f
```

> Les unités utilisent `Network=host` pour simplifier le dev.
> Assurez-vous d'avoir construit ou tiré les images:
>
> - `podman build -t localhost/template_projet-backend:dev -f infra/podman/backend.Containerfile .`
> - `podman build -t localhost/template_projet-web:dev -f infra/podman/web.Containerfile .`
