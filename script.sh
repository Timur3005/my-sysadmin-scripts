#!/bin/bash

LOGFILE=${LOGFILE:-/var/log/syslog}
REPORT=${REPORT:-report.txt}
KEYWORDS=${KEYWORDS:-error|fail|warn}

if [ ! -f "$LOGFILE" ]; then
    echo "Ошибка: файл $LOGFILE не найден" >&2
    exit 1
fi

if [ ! -r "$LOGFILE" ]; then
    echo "Ошибка: нет прав на чтение $LOGFILE" >&2
    exit 1
fi

MATCHES=$(mktemp) || exit 1
trap 'rm -f "$MATCHES"' EXIT

# -a: в syslog бывают бинарные байты; код 1 (нет совпадений) не ошибка
grep -aiE -- "$KEYWORDS" "$LOGFILE" > "$MATCHES"
if [ $? -gt 1 ]; then
    echo "Ошибка: не удалось обработать $LOGFILE" >&2
    exit 1
fi

total=$(grep -ac '' "$LOGFILE")
found=$(grep -ac '' "$MATCHES")

write_report() {
    echo "============================================"
    echo "Отчёт сборщика логов"
    echo "============================================"
    echo "Дата:               $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Хост:               $(hostname)"
    echo "Источник:           $LOGFILE"
    echo "Ключевые слова:     $KEYWORDS"
    echo "Всего строк в логе: $total"
    echo "Найдено совпадений: $found"
    echo
    echo "--------------------------------------------"
    echo "Совпадения по ключевым словам"
    echo "--------------------------------------------"
    IFS='|' read -ra words <<< "$KEYWORDS"
    for word in "${words[@]}"; do
        echo "$word: $(grep -aicE -- "$word" "$MATCHES")"
    done
    echo
    echo "--------------------------------------------"
    echo "Найденные строки"
    echo "--------------------------------------------"
    cat "$MATCHES"
}

if ! { write_report > "$REPORT"; } 2>/dev/null; then
    echo "Ошибка: не удалось записать отчёт $REPORT" >&2
    exit 1
fi

echo "Готово: $REPORT — найдено $found совпадений из $total строк $LOGFILE"
