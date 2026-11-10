#!/bin/bash
# Лабораторна робота DNS — автоматичне виконання завдань 1–7 для варіанта s09.
# Запуск у терміналі Codespace, у корені репозиторію стенда (opism-lab-DNS):
#     sed -i 's/\r$//' run_s09.sh && bash run_s09.sh
# Повторний запуск з чистого стану:  RESET=1 bash run_s09.sh
# Весь вивід зберігається у файл s09_log.txt.

SID=s09
Z=$SID.lab
LOG=${LOG:-s09_log.txt}
C="docker compose -f stand/compose.yaml"
ZF=stand/students/$SID/zone/$Z.zone

cd "$(dirname "$0")"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

hdr() { echo; echo "################################################################"; echo "### $*"; echo "################################################################"; }
# Виконати bash-скрипт зі stdin усередині контейнера s09 (термінал стенда).
ct() { { echo 'p(){ echo; echo "root@ns-s09:/# $*"; eval "$*"; }'; cat; } | $C exec -T $SID bash -s; }
# Збільшити serial у файлі зони.
bump() {
  python3 - "$ZF" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
t = re.sub(r'(\d{10})(\s*; serial)', lambda m: str(int(m.group(1)) + 1) + m.group(2), t, count=1)
open(p, 'w').write(t)
PY
  grep 'serial' "$ZF"
}
reload() { ct <<'EOF'
p 'named-checkzone s09.lab /lab/zone/s09.lab.zone && rndc reload s09.lab'
p 'date +%T'
EOF
}

# ---------------------------------------------------------------- 0. стенд
hdr "0. Запуск стенда"
date -u
if ! docker image inspect dnslab:latest >/dev/null 2>&1; then
  pip install -q jinja2
  docker build -t dnslab:latest image/
fi
python3 -c 'import jinja2' 2>/dev/null || pip install -q jinja2
if [ -n "$RESET" ] || [ ! -f "$ZF" ]; then
  python3 gen.py --student $SID --force-zones
  $C down 2>/dev/null
fi
chmod +x up.sh
./up.sh || { sleep 10; ./up.sh; } || { echo "СТЕНД НЕ ЗАПУСТИВСЯ"; $C logs $SID | tail -20; exit 1; }
if grep -q 'new-virqv' "$ZF"; then
  echo "Зона вже містить записи з попереднього запуску. Для повтору: RESET=1 bash run_s09.sh"; exit 1
fi
echo; echo "=== Картка варіанта"; cat stand/cards/$SID.md
echo; echo "=== Стартовий файл зони"; cat "$ZF"
ct <<'EOF'
p 'dig -v 2>&1'
EOF

# ---------------------------------------------------------------- 2. ієрархія
hdr "ЗАВДАННЯ 2. Проходження ієрархії вручну"
ct <<'EOF'
p 'dig @10.53.0.2 ns.s09.lab A +norec'
p 'dig @10.53.0.3 ns.s09.lab A +norec'
p 'dig @10.53.1.1 ns.s09.lab A +norec'
p 'dig ns.s09.lab A +trace'
p 'dig @10.53.0.3 s09.lab NS +norec'
p 'dig @10.53.1.1 s09.lab NS +norec'
EOF

# ---------------------------------------------------------------- 3. зона
hdr "ЗАВДАННЯ 3. Заповнення власної зони"
cat >> "$ZF" <<'EOF'
www     IN  A       10.53.0.80
portal  IN  CNAME   www
mail    IN  A       10.53.0.80
@       IN  MX      10 mail
@       IN  TXT     "lab-token=87a47075"
test 25 IN  A       10.53.0.81
EOF
bump
echo "--- zone-reload"; reload
ct <<'EOF'
p 'dig @10.53.1.1 www.s09.lab A +norec'
p 'dig @10.53.1.1 portal.s09.lab CNAME +norec'
p 'dig @10.53.1.1 mail.s09.lab A +norec'
p 'dig @10.53.1.1 s09.lab MX +norec'
p 'dig @10.53.1.1 s09.lab TXT +norec'
p 'dig @10.53.1.1 test.s09.lab A +norec'
echo; echo "=== Порівняння резолвер / власний сервер"
p 'dig portal.s09.lab'
p 'dig @10.53.1.1 portal.s09.lab +norec'
p 'dig s09.lab MX'
p 'dig @10.53.1.1 s09.lab MX +norec'
EOF
echo; echo "=== Експеримент: @ IN CNAME www (тимчасово)"
cp "$ZF" "$ZF.bak"
echo '@       IN  CNAME   www' >> "$ZF"
ct <<'EOF'
p 'named-checkzone s09.lab /lab/zone/s09.lab.zone'
EOF
cp "$ZF.bak" "$ZF" && rm -f "$ZF.bak"
echo "(рядок видалено, зону не перезавантажували)"

# ---------------------------------------------------------------- 1.2 URI
hdr "ЗАВДАННЯ 1.2. Перевірка URI"
ct <<'EOF'
p "curl -v 'http://www.s09.lab/search/archive?page=82&id=x#section-2'"
p "curl -v 'http://portal.s09.lab:80/archive/?page=%D0%BA%D0%B8%D1%97%D0%B2'"
p "curl -v 'http://user:pass@test.s09.lab/search#summary'"
p "echo 'dXNlcjpwYXNz' | base64 -d; echo"
p "curl -v --max-time 15 'https://www.s09.lab:9443/search/../archive'"
p "curl -v 'http://www.s09.lab/search/../archive'"
p "curl -v --path-as-is 'http://www.s09.lab/search/../archive'"
EOF

# ---------------------------------------------------------------- 4. TTL
hdr "ЗАВДАННЯ 4. TTL і видимість змін"
ct <<'EOF'
p 'date +%T; dig www.s09.lab +noall +answer'
sleep 5
p 'date +%T; dig www.s09.lab +noall +answer'
EOF
echo; echo "--- крок 3: zone-edit www -> 10.53.0.81 (без zone-reload)"
sed -i -E 's/^(www[[:space:]]+IN[[:space:]]+A[[:space:]]+)10\.53\.0\.80/\110.53.0.81/' "$ZF"
bump
grep '^www' "$ZF"
ct <<'EOF'
p 'dig @10.53.1.1 www.s09.lab +norec +short'
echo; echo "--- крок 4: залишок R"
while true; do
  echo; echo "root@ns-s09:/# date +%T; dig www.s09.lab +noall +answer"
  date +%T; L=$(dig www.s09.lab +noall +answer); echo "$L"
  R=$(echo "$L" | awk '{print $2}' | head -1)
  [ -n "$R" ] && [ "$R" -ge 30 ] && break
  echo "R=$R < 30 с — чекаємо спливання запису ($((R+1)) с) і повторюємо крок 4"; sleep $((R+1))
done
echo; echo "--- крок 5: zone-reload"
p 'named-checkzone s09.lab /lab/zone/s09.lab.zone && rndc reload s09.lab; date +%T'
echo; echo "--- крок 6"
p 'dig @10.53.1.1 www.s09.lab +norec +short'
echo; echo "--- крок 7: цикл спостереження"
echo 'root@ns-s09:/# while true; do echo "$(date +%T) $(dig +short www.s09.lab)"; sleep 2; done'
for i in $(seq 1 150); do
  A=$(dig +short www.s09.lab); echo "$(date +%T) $A"
  [ "$A" = "10.53.0.81" ] && break; sleep 2
done
echo "^C"
p 'curl http://www.s09.lab/'
EOF

# ---------------------------------------------------------------- 5. негативне кешування
hdr "ЗАВДАННЯ 5. Негативне кешування"
echo "--- крок 2: додано new-virqv (без zone-reload)"
echo 'new-virqv IN  A       10.53.0.80' >> "$ZF"
bump
ct <<'EOF'
p 'dig @10.53.1.1 new-virqv.s09.lab +norec'
echo; echo "--- крок 3"
p 'date +%T; dig new-virqv.s09.lab'
echo; echo "--- крок 4: zone-reload"
p 'named-checkzone s09.lab /lab/zone/s09.lab.zone && rndc reload s09.lab; date +%T'
echo; echo "--- крок 5"
p 'dig @10.53.1.1 new-virqv.s09.lab +norec +short'
echo; echo "--- крок 6: цикл спостереження"
echo "root@ns-s09:/# while true; do echo \"\$(date +%T) \$(dig new-virqv.s09.lab +noall +comments | grep -o 'status: [A-Z]*')\"; sleep 2; done"
for i in $(seq 1 150); do
  S=$(dig new-virqv.s09.lab +noall +comments | grep -o 'status: [A-Z]*'); echo "$(date +%T) $S"
  [ "$S" = "status: NOERROR" ] && break; sleep 2
done
echo "^C"
EOF

# ---------------------------------------------------------------- 6. затримка
hdr "ЗАВДАННЯ 6. Затримка пошуку імені"
ct <<'EOF'
A=y$RANDOM.s09.lab; B=x$RANDOM.lab; C=x$RANDOM.zz$RANDOM
echo "root@ns-s09:/# A=$A; B=$B; C=$C"
echo "--- A ($A)"; dig $A | grep 'Query time'; dig $A | grep 'Query time'
echo "--- B ($B)"; dig $B | grep 'Query time'; dig $B | grep 'Query time'
echo "--- C ($C)"; dig $C | grep 'Query time'; dig $C | grep 'Query time'
EOF
echo; echo "codespace\$ docker compose -f stand/compose.yaml restart resolver-a   ($(date -u +%T))"
$C restart resolver-a; sleep 5
ct <<'EOF'
echo "--- D (www.s09.lab після перезапуску резолвера)"
p 'date +%T; dig www.s09.lab | grep "Query time"'
p 'dig www.s09.lab | grep "Query time"'
EOF
echo; echo "=== Журнали запитів (рядки D, A, B, C)"
echo "codespace\$ docker compose -f stand/compose.yaml exec root tail -n 25 /var/log/named/queries.log"
$C exec -T root tail -n 25 /var/log/named/queries.log
echo "codespace\$ docker compose -f stand/compose.yaml exec tld tail -n 25 /var/log/named/queries.log"
$C exec -T tld tail -n 25 /var/log/named/queries.log
echo "root@ns-s09:/# querylog (tail -n 25)"
$C exec -T $SID tail -n 25 /var/log/named/queries.log
echo; echo "codespace\$ docker compose -f stand/compose.yaml restart resolver-a   ($(date -u +%T))"
$C restart resolver-a; sleep 5
ct <<'EOF'
p "curl -so /dev/null -w '%{time_namelookup}\n' http://www.s09.lab/"
EOF

# ---------------------------------------------------------------- 7. інцидент
hdr "ЗАВДАННЯ 7. Інцидент: зупинка власного сервера"
ct <<'EOF'
echo "--- крок 2"
p 'dig @10.53.0.53 test.s09.lab +noall +answer'
p 'dig @10.53.0.54 test.s09.lab +noall +answer'
echo; echo "--- крок 3: named-stop"
p 'date +%T; rndc stop'
echo; echo "--- крок 4"
p 'sleep 35'
echo; echo "--- крок 5"
p 'date +%T; { time dig @10.53.0.53 test.s09.lab +tries=1 +timeout=30 ; } 2>&1'
p 'date +%T; { time dig @10.53.0.53 test.s09.lab +tries=1 +timeout=30 ; } 2>&1'
p 'date +%T; { time dig @10.53.0.54 test.s09.lab +tries=1 +timeout=30 ; } 2>&1'
echo; echo "--- крок 6: named-start"
p 'named -u bind -c /lab/named.conf; date +%T'
echo 'root@ns-s09:/# while true; do echo "$(date +%T) $(dig @10.53.0.53 test.s09.lab +short +tries=1 +timeout=3)"; sleep 2; done'
for i in $(seq 1 90); do
  A=$(dig @10.53.0.53 test.s09.lab +short +tries=1 +timeout=3 2>/dev/null | grep -E '^[0-9.]+$'); echo "$(date +%T) $A"
  [ -n "$A" ] && break; sleep 2
done
echo "^C"
echo; echo "--- перевірка"
p 'dig @10.53.1.1 s09.lab SOA +norec +short'
EOF

# ---------------------------------------------------------------- фінал
hdr "Фінальний файл зони"
cat "$ZF"
hdr "Готово"
date -u
echo "Лог збережено у $LOG"
