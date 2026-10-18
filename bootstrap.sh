#!/usr/bin/env bash
# Без pipefail: "yes | mdadm" завершается с 141 (SIGPIPE у yes)
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

echo "== Шаг 0: Docker =="
sudo apt-get update -qq
if ! command -v docker >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io docker-buildx > /dev/null
    sudo systemctl enable --now docker
fi
DOCKER=(docker)
docker info >/dev/null 2>&1 || DOCKER=(sudo docker)

echo "== Шаг 1: образ и контейнер =="
"${DOCKER[@]}" build -t my-script .
sudo systemctl stop my-app 2>/dev/null || true
"${DOCKER[@]}" rm -f my-app 2>/dev/null || true
"${DOCKER[@]}" create -p 127.0.0.1:8080:8080 --name my-app -v /var/log:/var/log:ro my-script

echo "== Шаг 2: RAID и LVM =="
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mdadm lvm2 > /dev/null
sudo mkdir -p /mnt/raid-lab /mnt/raid /mnt/logs
cd /mnt/raid-lab
if grep -q "^md0" /proc/mdstat 2>/dev/null; then
    echo "RAID уже собран — создание пропущено"
elif [ -f disk1.img ]; then
    # после перезагрузки loop-устройства исчезают, а образы целы: подключаем, не затирая данные
    echo "Образы дисков найдены — подключаем заново"
    LOOP1=$(sudo losetup -fP --show disk1.img)
    LOOP2=$(sudo losetup -fP --show disk2.img)
    sudo losetup -fP disk3.img
    sudo mdadm --assemble /dev/md0 "$LOOP1" "$LOOP2" || true
    sudo vgchange -ay vg_data
else
    for i in 1 2 3; do
        sudo dd if=/dev/zero of="disk$i.img" bs=1M count=512 status=none
    done
    LOOP1=$(sudo losetup -fP --show disk1.img)
    LOOP2=$(sudo losetup -fP --show disk2.img)
    LOOP3=$(sudo losetup -fP --show disk3.img)
    yes | sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 "$LOOP1" "$LOOP2"
    sudo mkfs.ext4 -F -q /dev/md0
    yes | sudo pvcreate "$LOOP3"
    sudo vgcreate vg_data "$LOOP3"
    yes | sudo lvcreate -L 200M -n lv_logs vg_data
    sudo mkfs.ext4 -F -q /dev/vg_data/lv_logs
fi
mountpoint -q /mnt/raid || sudo mount /dev/md0 /mnt/raid
mountpoint -q /mnt/logs || sudo mount /dev/vg_data/lv_logs /mnt/logs
cd "$REPO_DIR"

echo "== Шаг 3: nginx и TLS =="
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx openssl > /dev/null
if [ ! -f /etc/ssl/certs/my-app.crt ]; then
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/my-app.key -out /etc/ssl/certs/my-app.crt \
        -subj "/CN=my-app.local" 2>/dev/null
fi
sudo install -m 644 nginx/my-app.conf /etc/nginx/sites-available/my-app
sudo ln -sf /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/my-app
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload-or-restart nginx

echo "== Шаг 4: systemd =="
sudo install -m 644 systemd/my-app.service /etc/systemd/system/my-app.service
sudo systemctl daemon-reload
sudo systemctl enable my-app
sudo systemctl restart my-app
sleep 3

echo "== Шаг 5: проверка =="
ready=0
for _ in $(seq 1 15); do
    if curl -ksf -o /dev/null https://127.0.0.1/; then
        ready=1
        break
    fi
    sleep 2
done
if [ "$ready" -eq 1 ]; then
    curl -ksI https://127.0.0.1/ | head -1
else
    echo "ПРЕДУПРЕЖДЕНИЕ: https://127.0.0.1/ не отвечает" >&2
    exit 1
fi
cat /proc/mdstat
sudo lvs
df -h | grep -E "raid|logs" || echo "ВНИМАНИЕ: тома RAID/LVM не смонтированы"
sudo systemctl status my-app --no-pager | head -5
curl -ksf https://127.0.0.1/report.txt | head -8 || echo "ВНИМАНИЕ: report.txt не отдаётся"

echo "bootstrap.sh: готово"
