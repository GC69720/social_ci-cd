FROM docker.io/library/node:20-alpine
WORKDIR /app/web

# On ne copie PAS un package-lock.json placeholder; on génère un lock propre
COPY web/package.json ./
RUN npm install

# Puis on copie le reste du code
COPY web ./

EXPOSE 3000
