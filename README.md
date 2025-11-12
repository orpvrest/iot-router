# IoT Router Secure Stack

Комплект `docker-compose` поднимает:

- OpenVPN сервер + автоматизация EasyRSA (серверные/клиентские профили, stunnel-конфигурация).
- Обёртку stunnel поверх OpenVPN и фронтовый Nginx на 443/TCP с SNI-маршрутизацией между VPN и сайтом.
- Grafana + Prometheus + node-exporter + cAdvisor + openvpn-exporter для сбора метрик с хоста, контейнеров и VPN.
- Certbot (по профилю `acme`) для автоматизированного получения сертификатов Let’s Encrypt.

## Структура

```
services/openvpn      # Кастомный образ openvpn+easy-rsa
services/stunnel      # Образ stunnel с envsubst шаблоном
config/nginx-edge     # Шаблоны nginx/ssl настроек
config/prometheus     # Конфиг Prometheus
config/grafana        # Provisioning + дашборды
scripts/              # Вспомогательные скрипты (клиенты, dev certs)
data/                 # Персистентные данные (openvpn, certbot, grafana, prometheus)
```

## Подготовка

1. Скопируйте `.env.example` в `.env` и задайте значения:
   - `VPN_PUBLIC_ENDPOINT`, `VPN_SNI_DOMAIN`, `SITE_SNI_DOMAIN`, `LE_EMAIL` и т.д.
   - `DEFAULT_CLIENTS` — список профилей через запятую, которые нужно выпустить автоматически.
   - `VPN_PUSH_ROUTES` — список (через запятую) сетей в формате `CIDR_NET MASK`, например `10.0.0.0 255.0.0.0`.
   - `VPN_STATIC_CLIENTS` — статические IP для клиентов (`alice:10.8.0.10,bob:10.8.0.11`). Они попадают в `ccd/` автоматически.
   - `VPN_FORWARD_TCP` — определения проброса портов `label:public_port:client_name:client_port` (через запятую). Публичный порт должен попадать в диапазоны `FORWARD_TCP_RANGE_*`.
   - `FORWARD_TCP_RANGE_PRIMARY/SECONDARY` — диапазоны портов, которые `nginx-edge` выделяет под проброс (по умолчанию два диапазона 20020-20039 и 20060-20079; задайте `22-22` чтобы открыть конкретный порт).
   - `OPENVPN_NAT_INTERFACE` — хостовой интерфейс, через который контейнер будет маскарадинговать клиентский трафик (например, `ens1`). Контейнер запущен в `host`-режиме и сам включает `net.ipv4.ip_forward` и `iptables MASQUERADE`, поэтому ничего на хосте вручную настраивать не нужно.
   - `STUNNEL_FORWARD_HOST`/`OPENVPN_FORWARD_HOST` — куда стучатся stunnel и внутренние TCP-прокси (по умолчанию `host.docker.internal`, который указывает на хост).
   - Сразу поменяйте `GRAFANA_ADMIN_PASSWORD` (значение в `.env.example` — только пример).
2. Сгенерируйте временные self-signed сертификаты для dev/тестов (без Let’s Encrypt):
   ```bash
   make dev-certs
   ```
3. Соберите пользовательские образы:
   ```bash
   make build
   ```
4. Проинициализируйте PKI (опционально, т.к. `openvpn-core` сделает это при первом старте):
   ```bash
   make init-pki
   ```

## Запуск

```bash
make up
```

Сервисы/порты:
- `443/tcp` — Nginx stream: по SNI `vpn.example.com` → stunnel → OpenVPN, иначе → Grafana.
- `80/tcp` — HTTP→HTTPS + webroot для ACME.
- `1194/tcp` (по умолчанию) — прямой OpenVPN без stunnel.
- `8080` — cAdvisor UI (можно ограничить фаерволом).
- Перед стартом убедитесь, что порты `80/443` и `1194` не заняты другими сервисами на хосте.
- Дополнительные TCP диапазоны `FORWARD_TCP_RANGE_PRIMARY/SECONDARY` публикуются Nginx под пробросы (по умолчанию 20020-20039 и 20060-20079). На них автоматически действует HTTP rate-limiting.

## Сертификаты Let’s Encrypt

По умолчанию Certbot отключён. Когда будете готовы выйти в интернет:

```bash
docker compose --profile acme run --rm certbot
```

`nginx-edge` и `stunnel` используют общую директорию `./data/certbot`. Certbot перезаписывает сертификаты в `live/<domain>`.

## Управление клиентами

- Автовыпуск из `DEFAULT_CLIENTS` выполняется при первом старте `openvpn-core`.
- Ручной выпуск:
  ```bash
  make add-client CLIENT=alice
  ```
  Тарбол с профилями (`client.ovpn`, `client-stunnel.ovpn`, `stunnel.conf`) появится в `data/openvpn/packages`.
  - `client.ovpn` — прямое подключение к открытому TCP-порту OpenVPN.
  - `client-stunnel.ovpn` + `*.stunnel.conf` — режим «anti-DPI»: запускаете `stunnel` на клиентской машине (`stunnel client.conf`) и подключаетесь `openvpn --config client-stunnel.ovpn`.

## Advanced features

### Статические IP адреса

- Пропишите пары `client:ip` в `VPN_STATIC_CLIENTS`. При создании клиента появляются файлы `ccd/<client>` с `ifconfig-push`, а OpenVPN выдаёт тот же адрес при каждом подключении.
- Статический адрес обязателен для TCP-проброса (см. ниже), поэтому заранее выделяйте диапазон, исключая сервер.

### TCP порт‑форвардинг к клиентам

1. Выберите свободный внешний порт из диапазонов `FORWARD_TCP_RANGE_PRIMARY/SECONDARY` (можно изменить в `.env`, указывая конкретные номера `22-22`, `5900-5900` и т.д.).
2. Добавьте правило в `VPN_FORWARD_TCP`, формат `label:public_port:client_name:client_port`. Пример:
   ```
   VPN_FORWARD_TCP=ssh-admin:2222:core-admin:22,vnc-lab:25900:lab-view:5900
   ```
   Здесь `public_port` должен лежать в одном из опубликованных диапазонов; `client_name` обязан иметь статический IP.
3. Перезапустите `openvpn-core` и `nginx-edge`. `openvpn-core` поднимет TCP‑прокси на указанном порту и прокинет трафик в клиента через туннель, а `nginx-edge` откроет порт наружу и отправит соединение на OpenVPN-сервер.

> Если нужен конкретный «нестандартный» порт (например 22), установите `FORWARD_TCP_RANGE_PRIMARY=22-22` — порт попадёт в docker‑портмаппинг и станет доступен для правил `VPN_FORWARD_TCP`.

### Проверка окружения и бэкапы

- `make validate-env` — убедиться, что обязательные переменные не пустые.
- `make backup` — сжать `data/openvpn`, `data/certbot` и содержимое docker volume'ов Grafana/Prometheus в `./backups/<timestamp>_*.tar.gz`. Используйте cron/CI для регулярных snapshot'ов.

### VPN_PUBLIC_ENDPOINT vs VPN_SNI_DOMAIN

- `VPN_PUBLIC_ENDPOINT` — адрес/домен, который прописывается в OpenVPN-конфигах и куда клиенты подключаются напрямую (TCP 1194 или другой порт).
- `VPN_SNI_DOMAIN` — домен, который клиенты используют при работе через stunnel/443 для маскировки. Nginx по SNI `vpn.example.com` отправляет трафик на TLS-обёртку, а другой домен (`SITE_SNI_DOMAIN`) указывает на Grafana/Prometheus.
- В большинстве сценариев домены совпадают, но вы можете разделить их: например, `vpn.company.com` (для OpenVPN/stunnel) и `obs.company.com` (для Grafana/Prometheus).

## Мониторинг

- Prometheus читает метрики: `prometheus:9090`, `node-exporter:9100`, `cadvisor:8080`, `openvpn-exporter:9176`.
- Grafana автоматически провиженит датасорс и дашборд `OpenVPN & Host Overview`.
- OpenVPN exporter читает `data/openvpn/status/openvpn-status.log` (формат `status-version 3`).
- Долговременные данные Prometheus/Grafana живут в docker volumes `iot-router_prometheus-storage` и `iot-router_grafana-storage`.
- Файл `config/prometheus/alerts.yml` содержит базовые правила (простой watchdog за OpenVPN/Prometheus). Подключите Alertmanager или CI для доставки уведомлений.

## Makefile цели

- `make help` — краткая справка по целям.
- `make up|down|logs|status`
- `make build` — пересборка openvpn/stunnel образов.
- `make init-pki` — ручная инициализация PKI.
- `make add-client CLIENT=<name>` — выпуск клиента.
- `make dev-certs` — self-signed сертификаты (тестирование без Let’s Encrypt).
- `make config-check` — проверка синтаксиса docker-compose.
- `make validate-env` — проверка обязательных переменных `.env`.
- `make backup` — создаёт архивацию PKI/мониторинговых volume'ов.

## Тестирование (без Let’s Encrypt)

Последовательность “сухих” тестов:
1. `make dev-certs`
2. `make build`
3. `make config-check`
4. `make up`
5. `docker compose logs openvpn-core` — убедиться, что PKI создан и клиент собран.
6. `docker compose ps` — проверить статусы контейнеров.

Для интеграционной проверки можно выполнить `docker compose exec openvpn-core /opt/openvpn/scripts/build-client.sh testuser` и затем протестировать `openvpn --config data/openvpn/clients/testuser.ovpn` (из внешней машины) и/или `stunnel`.

## Обновление сертификатов

Добавьте задание cron/CI, которое запускает:
```bash
docker compose --profile acme run --rm certbot
```
Nginx/stunnel используют общую директорию, поэтому перезапуск `nginx-edge`/`stunnel` подхватывает новые ключи.

## Требования/ограничения

- Хост должен иметь доступ к `/dev/net/tun` и выдавать capability `NET_ADMIN` контейнеру `openvpn-core`.
- `openvpn-core` работает в режиме `network_mode: host` и сам включает IP-forwarding и NAT (переменные `OPENVPN_NAT_INTERFACE`, `OPENVPN_ENABLE_NAT`, `ENABLE_IP_FORWARD`). Убедитесь, что значение интерфейса соответствует реальному uplink на сервере.
- Для корректных метрик node-exporter/cAdvisor требуется запуск Docker с разрешённым доступом к `/sys`, `/var/run/docker.sock`.
- В продакшене рекомендуется ограничить доступ к портам 8080/1194 через файрвол и защитить Grafana дополнительной аутентификацией.
- `GRAFANA_ADMIN_PASSWORD` из `.env.example` предназначен только для dev. Замените его перед запуском и храните отдельно (Vault/secret manager).
