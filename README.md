# my-sysadmin-scripts — сборщик логов

Скрипт `script.sh` читает `/var/log/syslog`, отбирает строки с ключевыми словами `error`/`fail`/`warn` и записывает структурированный отчёт в `report.txt`.

Капстоун курса «Системное администрирование» (дорожка «Продвинутый», вариант А): скрипт → Docker-образ → RAID 1 + LVM → сервис за nginx с HTTPS под управлением systemd.

## Структура

```
my-sysadmin-scripts/
├── README.md              # этот файл
├── script.sh              # сборщик логов
├── sample_output.txt      # пример отчёта
├── Dockerfile             # multi-stage: shellcheck → ubuntu:22.04 + python3 http.server :8080
├── docker-compose.yml     # запуск через docker compose
├── nginx/my-app.conf      # reverse proxy: 80 → 301 на HTTPS, 443 → 127.0.0.1:8080
├── systemd/my-app.service # контейнер my-app как служба systemd
└── bootstrap.sh           # подъём всего капстоуна с нуля одной командой
```

## Скрипт

```bash
./script.sh
cat report.txt
```

Переменные окружения (по умолчанию): `LOGFILE` (`/var/log/syslog`), `REPORT` (`report.txt`), `KEYWORDS` (`error|fail|warn` — список слов через `|` без групп и якорей; ищутся без учёта регистра, по каждому слову считается отдельный счётчик).

Коды возврата: `0` — отчёт сформирован (в том числе без совпадений); `1` — лог не найден, нет прав на чтение или отчёт не записан (сообщение в stderr).

## Docker

```bash
docker build -t my-script .
docker run -v /var/log:/var/log:ro my-script   # лог хоста передаётся томом, только чтение
docker compose up --build                     # то же через compose
```

Стадия `lint` прогоняет `shellcheck` по `script.sh`: скрипт с ошибкой (например, `x = 5`) не попадёт в образ. Контейнер запускает скрипт и отдаёт рабочий каталог `/var/www` (с `report.txt`) по HTTP на порту 8080.

## Сервис

- `my-app` — контейнер, созданный `docker create -p 127.0.0.1:8080:8080 --name my-app -v /var/log:/var/log:ro my-script` и запускаемый юнитом `systemd/my-app.service` (`enabled`, стартует после `docker.service`); порт 8080 опубликован только на `127.0.0.1`, снаружи сервис доступен лишь через nginx;
- nginx (`nginx/my-app.conf`) принимает HTTPS с самоподписанным сертификатом `/etc/ssl/certs/my-app.crt` и проксирует на `127.0.0.1:8080`; HTTP отвечает редиректом 301.

## Подъём с нуля

На чистой Ubuntu 22.04/24.04 (Multipass, облако, Killercoda):

```bash
git clone https://github.com/Timur3005/my-sysadmin-scripts.git
cd my-sysadmin-scripts
./bootstrap.sh
```

Скрипт без вопросов ставит Docker, собирает образ, создаёт RAID 1 (`/dev/md0` → `/mnt/raid`) и LVM (`vg_data/lv_logs` → `/mnt/logs`) на loop-устройствах, настраивает nginx + TLS и службу `my-app`, затем проверяет, что `https://127.0.0.1/` отвечает. Повторный запуск не трогает уже собранный RAID, а после перезагрузки подключает существующие образы дисков заново, не затирая данные.

## Проверка

```bash
curl -kI https://<host>                  # HTTP 200
curl -k https://<host>/report.txt        # отчёт сборщика
sudo systemctl status my-app             # active (running), enabled
sudo journalctl -u my-app -n 20          # запросы к приложению
sudo tail /var/log/nginx/access.log      # те же запросы со стороны nginx
cat /proc/mdstat && sudo lvs && df -h | grep -E "raid|logs"
```
