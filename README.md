# Сборщик логов

Скрипт `script.sh` читает `/var/log/syslog`, отбирает строки с ключевыми словами `error`/`fail`/`warn` и записывает структурированный отчёт в `report.txt`.

## Запуск

```bash
./script.sh
cat report.txt
```

Параметры через переменные окружения (значения по умолчанию в скобках):

- `LOGFILE` — какой лог читать (`/var/log/syslog`);
- `REPORT` — куда писать отчёт (`report.txt`);
- `KEYWORDS` — ключевые слова, регулярное выражение `grep -E` без учёта регистра (`error|fail|warn`).

Например: `LOGFILE=/var/log/auth.log KEYWORDS="fail|invalid" ./script.sh`.

Коды возврата: `0` — отчёт сформирован (в том числе если совпадений нет); `1` — лог не найден, нет прав на чтение или отчёт не удалось записать (сообщение в stderr).

Пример отчёта — в [`sample_output.txt`](sample_output.txt).
