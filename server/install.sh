#!/usr/bin/env bash
# Picto Voix : installation du serveur de synchronisation (PocketBase) sur un VPS Ubuntu/Debian.
# Usage (en root) :  curl -fsSL https://graphikup.github.io/VoiceApp/server/install.sh | bash
# Relançable sans risque : les données existantes sont conservées, le programme est mis à jour.
set -euo pipefail

PB_VERSION="0.40.6"
APP_URL="https://graphikup.github.io/VoiceApp"
DIR="/opt/pictovoix"
PORT="8090"
NAME="pictovoix"

say()  { printf '\n\033[1;34m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*"; exit 1; }
ask()  { local q="$1" def="${2:-}" v; read -r -p "$q${def:+ [$def]} : " v </dev/tty; echo "${v:-$def}"; }
askpw(){ local q="$1" a b; while true; do read -r -s -p "$q : " a </dev/tty; echo >&2; read -r -s -p "Confirmez : " b </dev/tty; echo >&2
         [ "$a" = "$b" ] && [ ${#a} -ge 10 ] && { echo "$a"; return; }; warn "Les deux saisies diffèrent ou font moins de 10 caractères, recommencez." >&2; done; }
json_get(){ python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))"; }

api_setup() {   # $1 = URL locale du serveur ; crée/maj le compte famille et règle sauvegardes + limites
  local base="$1" tok uid
  tok=$(curl -fsS -X POST "$base/api/collections/_superusers/auth-with-password" -H 'Content-Type: application/json' \
        -d "$(python3 -c 'import json,sys; print(json.dumps({"identity":sys.argv[1],"password":sys.argv[2]}))' "$ADMIN_EMAIL" "$ADMIN_PW")" | json_get token)
  [ -n "$tok" ] || die "Connexion administrateur impossible."
  uid=$(curl -fsS "$base/api/collections/users/records?filter=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote("email=\""+sys.argv[1]+"\""))' "$FAMILY_EMAIL")" \
        -H "Authorization: $tok" | python3 -c "import json,sys; d=json.load(sys.stdin)['items']; print(d[0]['id'] if d else '')")
  local body; body=$(python3 -c 'import json,sys; print(json.dumps({"email":sys.argv[1],"password":sys.argv[2],"passwordConfirm":sys.argv[2],"verified":True,"name":"Famille"}))' "$FAMILY_EMAIL" "$FAMILY_PW")
  if [ -n "$uid" ]; then
    curl -fsS -X PATCH "$base/api/collections/users/records/$uid" -H "Authorization: $tok" -H 'Content-Type: application/json' -d "$body" >/dev/null
    ok "Compte famille mis à jour : $FAMILY_EMAIL"
  else
    curl -fsS -X POST "$base/api/collections/users/records" -H "Authorization: $tok" -H 'Content-Type: application/json' -d "$body" >/dev/null
    ok "Compte famille créé : $FAMILY_EMAIL"
  fi
  curl -fsS -X PATCH "$base/api/settings" -H "Authorization: $tok" -H 'Content-Type: application/json' \
    -d '{"meta":{"appName":"Picto Voix"},"backups":{"cron":"30 3 * * *","cronMaxKeep":14},"rateLimits":{"enabled":true}}' >/dev/null
  ok "Sauvegarde automatique chaque nuit à 3 h 30 (14 gardées) et protection contre les essais de mot de passe."
}

# Mode test (utilisé pendant le développement) : configure un serveur déjà lancé
if [ "${PV_TEST_API:-}" != "" ]; then api_setup "$PV_TEST_API"; exit 0; fi

[ "$(id -u)" = "0" ] || die "Lancez ce script en root (ou avec sudo)."
command -v apt-get >/dev/null || die "Ce script prévoit un serveur Ubuntu ou Debian."

echo
echo "  Picto Voix — serveur de synchronisation"
echo "  ---------------------------------------"
DOMAIN=$(ask "Adresse du serveur (sous-domaine qui pointe vers ce VPS)" "api-pictovoix.gkup.link")
FAMILY_EMAIL=$(ask "E-mail du compte famille (à saisir dans l'appli)" "agence@graphikup.fr")
FAMILY_PW=$(askpw "Mot de passe du compte famille (10 caractères minimum)")
ADMIN_EMAIL=$(ask "E-mail administrateur (tableau de bord du serveur)" "$FAMILY_EMAIL")
ADMIN_PW=$(askpw "Mot de passe administrateur (différent, 10 caractères minimum)")

say "Paquets nécessaires"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq curl unzip ca-certificates python3 dnsutils >/dev/null
ok "curl, unzip, python3"

say "Vérification du sous-domaine $DOMAIN"
MYIP=$(curl -fsS -4 https://api.ipify.org || true)
DNSIP=$(dig +short A "$DOMAIN" @1.1.1.1 | tail -n1 || true)
if [ -z "$DNSIP" ]; then
  warn "$DOMAIN ne pointe encore nulle part. Créez un enregistrement DNS de type A : $DOMAIN → $MYIP"
  [ "$(ask "Continuer quand même ? (o/n)" "n")" = "o" ] || exit 1
elif [ "$DNSIP" != "$MYIP" ]; then
  warn "$DOMAIN pointe vers $DNSIP, alors que ce VPS a l'adresse $MYIP."
  [ "$(ask "Continuer quand même ? (o/n)" "n")" = "o" ] || exit 1
else ok "$DOMAIN → $MYIP"; fi

say "PocketBase $PB_VERSION"
case "$(uname -m)" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) die "Processeur non pris en charge : $(uname -m)";; esac
mkdir -p "$DIR/pb_migrations" "$DIR/pb_data"
TMP=$(mktemp -d)
curl -fsSL -o "$TMP/pb.zip" "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_${ARCH}.zip"
unzip -oq "$TMP/pb.zip" pocketbase -d "$TMP" && install -m 755 "$TMP/pocketbase" "$DIR/pocketbase"
curl -fsSL -o "$DIR/pb_migrations/1700000000_pictovoix.js" "$APP_URL/server/pb_migrations/1700000000_pictovoix.js"
rm -rf "$TMP"
ok "Installé dans $DIR"

# Arrêt d'une éventuelle version précédente avant de toucher aux données
systemctl stop "$NAME" 2>/dev/null || true
command -v docker >/dev/null && docker rm -f "$NAME" >/dev/null 2>&1 || true

"$DIR/pocketbase" superuser upsert "$ADMIN_EMAIL" "$ADMIN_PW" --dir "$DIR/pb_data" --migrationsDir "$DIR/pb_migrations" >/dev/null
ok "Structure des données en place, administrateur $ADMIN_EMAIL"

# ---- Exposition en HTTPS : Traefik (modèle n8n d'Hostinger), sinon Caddy, sinon arrêt ----
TRAEFIK=""
if command -v docker >/dev/null; then TRAEFIK=$(docker ps --format '{{.Names}} {{.Image}}' | awk 'tolower($2) ~ /traefik/ {print $1; exit}'); fi
PORTS_BUSY=$(ss -ltnH '( sport = :80 or sport = :443 )' 2>/dev/null | wc -l)

if [ -n "$TRAEFIK" ]; then
  say "Traefik détecté ($TRAEFIK) : PocketBase tourne dans un conteneur à côté de n8n"
  ARGS=$(docker inspect "$TRAEFIK" --format '{{join .Args " "}} {{join .Config.Cmd " "}}')
  RESOLVER=$(grep -oE 'certificatesresolvers\.[A-Za-z0-9_-]+\.acme' <<<"$ARGS" | head -n1 | cut -d. -f2 || true)
  EP=$(grep -oE 'entrypoints\.[A-Za-z0-9_-]+\.address=:443' <<<"$ARGS" | head -n1 | cut -d. -f2 || true)
  NET=$(grep -oE 'providers\.docker\.network=[^ ]+' <<<"$ARGS" | head -n1 | cut -d= -f2 || true)
  [ -n "$NET" ] || NET=$(docker inspect "$TRAEFIK" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
  [ -n "$RESOLVER" ] || die "Impossible de trouver le certificat HTTPS de Traefik : envoyez à Claude le résultat de « docker inspect $TRAEFIK »."
  EP=${EP:-websecure}
  docker run -d --name "$NAME" --restart unless-stopped --network "$NET" \
    -p "127.0.0.1:${PORT}:${PORT}" -v "$DIR:/pb" -w /pb \
    -l traefik.enable=true \
    -l "traefik.http.routers.${NAME}.rule=Host(\`${DOMAIN}\`)" \
    -l "traefik.http.routers.${NAME}.entrypoints=${EP}" \
    -l "traefik.http.routers.${NAME}.tls=true" \
    -l "traefik.http.routers.${NAME}.tls.certresolver=${RESOLVER}" \
    -l "traefik.http.services.${NAME}.loadbalancer.server.port=${PORT}" \
    -l "traefik.docker.network=${NET}" \
    alpine:3.20 /pb/pocketbase serve --http="0.0.0.0:${PORT}" --dir=/pb/pb_data --migrationsDir=/pb/pb_migrations >/dev/null
  ok "Conteneur $NAME lancé (réseau $NET, certificat $RESOLVER)"
elif [ "$PORTS_BUSY" = "0" ]; then
  say "Aucun serveur web sur les ports 80/443 : installation de Caddy (HTTPS automatique)"
  apt-get install -y -qq caddy >/dev/null || die "Installation de Caddy impossible."
  cat > "/etc/systemd/system/${NAME}.service" <<EOF
[Unit]
Description=Picto Voix (PocketBase)
After=network.target
[Service]
ExecStart=$DIR/pocketbase serve --http=127.0.0.1:${PORT} --dir=$DIR/pb_data --migrationsDir=$DIR/pb_migrations
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload && systemctl enable --now "$NAME" >/dev/null 2>&1
  grep -q "^${DOMAIN} " /etc/caddy/Caddyfile 2>/dev/null || printf '\n%s {\n\treverse_proxy 127.0.0.1:%s\n}\n' "$DOMAIN" "$PORT" >> /etc/caddy/Caddyfile
  systemctl reload caddy || systemctl restart caddy
  if command -v ufw >/dev/null && ufw status | grep -q active; then ufw allow 80,443/tcp >/dev/null; fi
  ok "Service $NAME + Caddy configurés"
else
  die "Un autre serveur web occupe les ports 80/443 (ni Traefik ni libre). Envoyez à Claude le résultat de « ss -ltnp | grep -E ':80|:443' »."
fi

say "Démarrage"
for i in $(seq 1 30); do curl -fsS "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://127.0.0.1:${PORT}/api/health" >/dev/null || die "Le serveur ne répond pas. Voir : docker logs $NAME  ou  journalctl -u $NAME"
api_setup "http://127.0.0.1:${PORT}"

say "Vérification en HTTPS (le certificat peut prendre une minute)"
HTTPS_OK=""
for i in $(seq 1 24); do curl -fsS "https://${DOMAIN}/api/health" >/dev/null 2>&1 && { HTTPS_OK=1; break; }; sleep 5; done
echo
if [ -n "$HTTPS_OK" ]; then ok "Serveur en ligne : https://${DOMAIN}"; else warn "Le HTTPS ne répond pas encore : vérifiez le DNS, puis réessayez https://${DOMAIN}/api/health dans quelques minutes."; fi
cat <<EOF

  Dans l'appli Picto Voix : cadenas › Réglages › Synchronisation entre appareils
    Adresse du serveur : https://${DOMAIN}
    E-mail             : ${FAMILY_EMAIL}
    Mot de passe       : celui du compte famille choisi ci-dessus
  Commencez par l'appareil qui a le bon contenu, puis connectez les autres.

  Tableau de bord du serveur : https://${DOMAIN}/_/   (compte administrateur)
  Sauvegardes : $DIR/pb_data/backups
EOF
