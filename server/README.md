# Servidor online (noray)

O modo **ONLINE — CÓDIGO DE SALA** precisa de um servidor [noray](https://github.com/foxssake/noray) (MIT)
acessível pela internet. Ele não roda a partida: só entrega o código da sala, troca os endereços para os
jogadores se conectarem direto e, quando o roteador de alguém não deixa, repassa o tráfego (relay).

| Porta | Protocolo | Para quê |
|---|---|---|
| 8890 | TCP | códigos de sala e pedidos de conexão |
| 8809 | UDP | registro do endereço externo de cada jogador |
| 49152–49251 | UDP | relay (100 vagas simultâneas) |

Consumo: quase nada quando a conexão é direta. No relay, ~15–40 KB/s por jogador (mais em lutas grandes),
ou seja, ~100–150 MB por hora de partida com relay. 1 vCPU e 512 MB a 1 GB de RAM bastam.

## Onde hospedar

Para jogadores no Brasil, o servidor deve ficar em **São Paulo** (no relay, todo o tráfego passa por ele).

- **Oracle Cloud Always Free** (região São Paulo): grátis; a capacidade às vezes esgota. Além do `ufw`, libere as
  portas na *Security List* da VCN (entrada TCP 8890, UDP 8809 e UDP 49152–49251).
- **VPS pago em São Paulo** (Vultr, Hostinger KVM 1, Magalu Cloud…): na faixa de US$ 5–10/mês.
- Fora do Brasil (DigitalOcean, Hetzner) funciona, mas o relay soma ~120 ms de ping.

## Instalar (Ubuntu/Debian)

Copie esta pasta para o VPS e rode:

```bash
sudo bash setup.sh
```

O script cria o usuário `noray`, instala o bun só para ele, baixa o noray na versão testada (1.5.5), copia
`noray.env`, liga o serviço `noray` (systemd) e abre as portas no `ufw`. Logs:

```bash
journalctl -u noray -f
```

## Ligar o jogo ao servidor

- Cada jogador pode digitar o endereço em **JOGAR EM REDE → Servidor** (ex.: `203.0.113.10:8890`); fica salvo.
- Para o build já sair com o servidor certo, troque `NORAY_DEFAULT` em `autoload/net.gd` e gere o build de novo.

## Configuração (`noray.env`)

Diferenças para o padrão do noray: códigos de sala com 6 caracteres sem letras parecidas (`NORAY_OID_LENGTH=6`,
sem I, O, 0, 1), 100 portas de relay, limite de 512 KB/s por jogador no relay e métricas HTTP só em `127.0.0.1`.

## Testar no próprio PC

Com o [bun](https://bun.sh) instalado, numa cópia do noray com `noray.env` como `.env`: `bun bin/noray.ts`. Depois:

```bash
godot --headless --path . -- --net-host-online --mission=3 --net-start-when=2 --net-log --quit-after=40
```

O host imprime `NET room=CÓDIGO`. Em outra janela:

```bash
godot --path . -- --net-join-code=CÓDIGO --net-bot --net-log
```

`--noray-relay` força o caminho pelo relay; o `--net-log` do cliente mostra `link=direct` ou `link=relay`.
