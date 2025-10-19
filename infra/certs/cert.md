#Installer/mettre a jour ce CA dans la VM depuis le repo
#a executer quand tu changes le certificat dans Git :


cd ~/DEV/social_ci-cd
podman machine ssh 'sudo tee /etc/pki/ca-trust/source/anchors/enterprise-root-ca.crt >/dev/null' \
  < infra/certs/enterprise-root-ca.pem
podman machine ssh 'sudo update-ca-trust'
podman machine stop && podman machine start