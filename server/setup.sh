#!/usr/bin/env bash
# Instala o servidor online do Enxame 2199 (noray) num VPS Ubuntu/Debian. Rodar como root:
#
#   sudo bash setup.sh
#
# Cria o usuário "noray", instala o bun (runtime do noray) só para ele, baixa o noray numa versão fixa,
# copia a configuração (noray.env) e liga o serviço. Abre as portas no ufw se ele estiver ativo.
# Portas: TCP 8890 (códigos de sala), UDP 8809 (registro de endereço), UDP 49152-49251 (relay).
set -euo pipefail

NORAY_REPO="https://github.com/foxssake/noray.git"
NORAY_COMMIT="e5a9ff7" # noray 1.5.5, a versão testada com o jogo
HERE="$(cd "$(dirname "$0")" && pwd)"

apt-get update -y
apt-get install -y git curl unzip ca-certificates

id noray >/dev/null 2>&1 || useradd --system --create-home --home-dir /opt/noray --shell /usr/sbin/nologin noray
if [ ! -d /opt/noray/src ]; then
	rm -rf /tmp/noray-src
	git clone "$NORAY_REPO" /tmp/noray-src
	git -C /tmp/noray-src checkout -q "$NORAY_COMMIT"
	cp -a /tmp/noray-src/. /opt/noray/
	rm -rf /tmp/noray-src
fi
cp "$HERE/noray.env" /opt/noray/.env
chown -R noray:noray /opt/noray

# bun no diretório do usuário noray
if [ ! -x /opt/noray/.bun/bin/bun ]; then
	sudo -u noray -H bash -c 'curl -fsSL https://bun.sh/install | BUN_INSTALL=/opt/noray/.bun bash'
fi
sudo -u noray -H bash -c 'cd /opt/noray && /opt/noray/.bun/bin/bun install --production'

cp "$HERE/noray.service" /etc/systemd/system/noray.service
systemctl daemon-reload
systemctl enable --now noray

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
	ufw allow 8890/tcp
	ufw allow 8809/udp
	ufw allow 49152:49251/udp
fi

sleep 3
systemctl --no-pager status noray | head -n 5
echo
echo "Pronto. No jogo: JOGAR EM REDE → Servidor: $(curl -fsS https://api.ipify.org 2>/dev/null || echo SEU_IP):8890"
