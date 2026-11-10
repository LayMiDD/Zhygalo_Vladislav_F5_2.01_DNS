# Лабораторна робота. DNS

| Поле | Значення |
|---|---|
| ПІБ | Жигало Владислав |
| Група | F5-2.01 |
| Ідентифікатор (`sNN`) | s09 |
| Дата виконання | 10.11.2026 |
| Середовище | GitHub Codespaces (репозиторій стенда `sergeyscherba/opism-lab-DNS`, `python3 gen.py --student s09`) |
| Версія `dig` | DiG 9.18.39-0ubuntu0.24.04.9-Ubuntu |

> Примітка щодо перезапусків. Перший запуск вимірювань (18:41) було зіпсовано: через помилку введення в терміналі одночасно запустилися дві копії скрипта з командами, і вони змінювали зону паралельно. Обидві копії зупинено, стенд перегенеровано з чистою зоною (`gen.py --force-zones`, `docker compose down` / `./up.sh`, кеші резолверів очищено) і всі завдання виконано заново з 18:43:59. Нижче наведено лише результати чистого запуску. У завданні 6 resolver-a перезапускався двічі (рядок D і вимірювання `curl`), як цього вимагає методичка.

## Параметри варіанта

| Параметр | Значення |
|---|---|
| `$TTL`, с | 45 |
| TTL запису SOA, с | 120 |
| Поле `minimum` SOA, с | 40 |
| Псевдонім (CNAME на `www`) | `portal` |
| Другий хост і його TTL, с | `test`, 25 |
| Пріоритет MX | 10 |
| Токен TXT | `lab-token=87a47075` |
| Ім'я для завдання 5 | `new-virqv.s09.lab` |

URI з картки:

1. `http://www.s09.lab/search/archive?page=82&id=x#section-2`
2. `http://portal.s09.lab:80/archive/?page=%D0%BA%D0%B8%D1%97%D0%B2`
3. `http://user:pass@test.s09.lab/search#summary`
4. `https://www.s09.lab:9443/search/../archive`
5. `mailto:admin@s09.lab?subject=search`

## Завдання 1. Складові URI

### 1.1. Розбір

| № | scheme | userinfo | host | port | path | query | fragment |
|---|---|---|---|---|---|---|---|
| 1 | http | — | www.s09.lab | 80 (за замовч.) | /search/archive | page=82&id=x | section-2 |
| 2 | http | — | portal.s09.lab | 80 (вказано явно) | /archive/ | page=%D0%BA%D0%B8%D1%97%D0%B2 | — |
| 3 | http | user:pass | test.s09.lab | 80 (за замовч.) | /search | — | summary |
| 4 | https | — | www.s09.lab | 9443 | /search/../archive | — | — |
| 5 | mailto | — | — | — | admin@s09.lab | subject=search | — |

| № | Ім'я, що запитується в DNS | Заголовок `Host` | Ціль запиту (request target) |
|---|---|---|---|
| 1 | www.s09.lab | www.s09.lab | /search/archive?page=82&id=x |
| 2 | portal.s09.lab (CNAME → www.s09.lab) | portal.s09.lab (порт 80 стандартний, тому клієнт його не додає) | /archive/?page=%D0%BA%D0%B8%D1%97%D0%B2 |
| 3 | test.s09.lab | test.s09.lab | /search |
| 4 | www.s09.lab | www.s09.lab:9443 | /archive (клієнт прибирає сегменти `..` за RFC 3986 §5.2.4) |
| 5 | HTTP-запиту немає; поштова система запитала б MX для s09.lab | — | — |

Декодоване значення параметра URI 2: `%D0%BA%D0%B8%D1%97%D0%B2` — це байти UTF-8 `D0 BA | D0 B8 | D1 97 | D0 B2`, тобто `page=київ`.

Чому URI 5 не має складової host, хоча містить символ `@`: складова authority (а з нею userinfo@host) існує лише тоді, коли після `scheme:` іде `//`. У `mailto:admin@s09.lab` подвійної косої немає, тому весь рядок `admin@s09.lab` — це path, а `@` усередині нього просто розділяє скриньку й домен, як того вимагає схема mailto (RFC 6068).

### 1.2. Перевірка (після завдання 3)

```text
root@ns-s09:/# curl -v 'http://www.s09.lab/search/archive?page=82&id=x#section-2'
* Host www.s09.lab:80 was resolved.
* IPv4: 10.53.0.80
* Connected to www.s09.lab (10.53.0.80) port 80
> GET /search/archive?page=82&id=x HTTP/1.1
> Host: www.s09.lab
> User-Agent: curl/8.5.0
> Accept: */*
>
server: web-a
Host: www.s09.lab
request URI: /search/archive?page=82&id=x
path: /search/archive
query: page=82&id=x
client: 10.53.1.1

root@ns-s09:/# curl -v 'http://portal.s09.lab:80/archive/?page=%D0%BA%D0%B8%D1%97%D0%B2'
* Host portal.s09.lab:80 was resolved.
* IPv4: 10.53.0.80
* Connected to portal.s09.lab (10.53.0.80) port 80
> GET /archive/?page=%D0%BA%D0%B8%D1%97%D0%B2 HTTP/1.1
> Host: portal.s09.lab
> User-Agent: curl/8.5.0
> Accept: */*
>
server: web-a
Host: portal.s09.lab
request URI: /archive/?page=%D0%BA%D0%B8%D1%97%D0%B2
path: /archive/
query: page=%D0%BA%D0%B8%D1%97%D0%B2
client: 10.53.1.1

root@ns-s09:/# curl -v 'http://user:pass@test.s09.lab/search#summary'
* Host test.s09.lab:80 was resolved.
* IPv4: 10.53.0.81
* Connected to test.s09.lab (10.53.0.81) port 80
* Server auth using Basic with user 'user'
> GET /search HTTP/1.1
> Host: test.s09.lab
> Authorization: Basic dXNlcjpwYXNz
> User-Agent: curl/8.5.0
> Accept: */*
>
server: web-b
Host: test.s09.lab
request URI: /search
path: /search
query:
client: 10.53.1.1
```

Значення заголовка `Authorization` і результат декодування:

```text
> Authorization: Basic dXNlcjpwYXNz

root@ns-s09:/# echo 'dXNlcjpwYXNz' | base64 -d; echo
user:pass
```

Пароль передається у відкритому вигляді: Base64 — це кодування, а не шифрування.

URI 4: етап, на якому запит не вдається (пошук імені / TCP / TLS), і рядки виводу, що це підтверджують:

```text
root@ns-s09:/# curl -v --max-time 15 'https://www.s09.lab:9443/search/../archive'
* Host www.s09.lab:9443 was resolved.
* IPv6: (none)
* IPv4: 10.53.0.80
*   Trying 10.53.0.80:9443...
* connect to 10.53.0.80 port 9443 from 10.53.1.1 port 40476 failed: Connection refused
* Failed to connect to www.s09.lab port 9443 after 0 ms: Couldn't connect to server
curl: (7) Failed to connect to www.s09.lab port 9443 after 0 ms: Couldn't connect to server
```

Пошук імені успішний (`was resolved`, `IPv4: 10.53.0.80`). Запит падає на етапі **TCP**: вузол 10.53.0.80 відповів RST (`Connection refused`), бо на порту 9443 нічого не слухає. До TLS справа не дійшла: рядків `TLS handshake` у виводі немає.

```text
root@ns-s09:/# curl -v 'http://www.s09.lab/search/../archive'
> GET /archive HTTP/1.1
> Host: www.s09.lab
server: web-a
request URI: /archive
path: /archive

root@ns-s09:/# curl -v --path-as-is 'http://www.s09.lab/search/../archive'
> GET /search/../archive HTTP/1.1
> Host: www.s09.lab
server: web-a
request URI: /search/../archive
path: /archive
```

| Запит | `request URI`, отриманий сервером | `path`, отриманий сервером |
|---|---|---|
| звичайний | /archive | /archive |
| `--path-as-is` | /search/../archive | /archive |

Розбіжності між URI та тим, що отримав сервер, і їх пояснення:

- **fragment** (`#section-2`, `#summary`) клієнт ніколи не надсилає: він обробляється лише в браузері.
- **userinfo** (`user:pass`) не потрапляє ні в рядок запиту, ні в `Host`. curl перетворив його на заголовок `Authorization: Basic dXNlcjpwYXNz`.
- **Явний порт `:80`** у URI 2 зник із `Host`: для http порт 80 стандартний, тому curl надсилає `Host: portal.s09.lab`. Для нестандартного 9443 порт був би в `Host`.
- **query** у відсотковому кодуванні сервер отримав без змін (`%D0%BA...`): декодування — справа застосунку.
- **Сегменти `..`**: звичайний curl нормалізує шлях ще на клієнті, і сервер отримує `/archive`. З `--path-as-is` сервер отримує `/search/../archive` у сирому `request URI`, але nginx сам нормалізує шлях: змінна `path` (`$uri`) дорівнює `/archive`.

## Завдання 2. Проходження ієрархії вручну

```text
root@ns-s09:/# dig @10.53.0.2 ns.s09.lab A +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 55298
;; flags: qr; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 2
;; QUESTION SECTION:
;ns.s09.lab.                    IN      A
;; AUTHORITY SECTION:
lab.                    172800  IN      NS      ns1.nic.lab.
;; ADDITIONAL SECTION:
ns1.nic.lab.            172800  IN      A       10.53.0.3
;; Query time: 79 msec
;; SERVER: 10.53.0.2#53(10.53.0.2) (UDP)
;; WHEN: Tue Nov 10 18:44:04 UTC 2026

root@ns-s09:/# dig @10.53.0.3 ns.s09.lab A +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 40316
;; flags: qr; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 2
;; QUESTION SECTION:
;ns.s09.lab.                    IN      A
;; AUTHORITY SECTION:
s09.lab.                3600    IN      NS      ns.s09.lab.
;; ADDITIONAL SECTION:
ns.s09.lab.             3600    IN      A       10.53.1.1
;; Query time: 79 msec
;; SERVER: 10.53.0.3#53(10.53.0.3) (UDP)

root@ns-s09:/# dig @10.53.1.1 ns.s09.lab A +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 51413
;; flags: qr aa; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 1
;; QUESTION SECTION:
;ns.s09.lab.                    IN      A
;; ANSWER SECTION:
ns.s09.lab.             45      IN      A       10.53.1.1
;; AUTHORITY SECTION:
s09.lab.                45      IN      NS      ns.s09.lab.
;; Query time: 0 msec
;; SERVER: 10.53.1.1#53(10.53.1.1) (UDP)
```

<!-- ADDITIONAL у лічильнику dig включає псевдозапис OPT (EDNS). -->

| Сервер | status | flags | ANSWER | AUTHORITY | ADDITIONAL |
|---|---|---|---|---|---|
| 10.53.0.2 | NOERROR | qr | 0 | 1 (NS `lab.` → ns1.nic.lab.) | 2 (A ns1.nic.lab = 10.53.0.3; OPT) |
| 10.53.0.3 | NOERROR | qr | 0 | 1 (NS `s09.lab.` → ns.s09.lab.) | 2 (A ns.s09.lab = 10.53.1.1 — glue; OPT) |
| 10.53.1.1 | NOERROR | qr aa | 1 (A ns.s09.lab = 10.53.1.1) | 1 (NS `s09.lab.`) | 1 (OPT) |

Вивід `dig ns.s09.lab A +trace`:

```text
; <<>> DiG 9.18.39-0ubuntu0.24.04.9-Ubuntu <<>> ns.s09.lab A +trace
;; global options: +cmd
.                       86399   IN      NS      a.root-servers.net.
;; Received 59 bytes from 10.53.0.53#53(10.53.0.53) in 0 ms

lab.                    172800  IN      NS      ns1.nic.lab.
;; Received 111 bytes from 10.53.0.2#53(a.root-servers.net) in 80 ms

s09.lab.                3600    IN      NS      ns.s09.lab.
;; Received 97 bytes from 10.53.0.3#53(ns1.nic.lab) in 40 ms

ns.s09.lab.             45      IN      A       10.53.1.1
s09.lab.                45      IN      NS      ns.s09.lab.
;; Received 97 bytes from 10.53.1.1#53(ns.s09.lab) in 0 ms
```

Ланцюжок `+trace` збігається з ручним: root (10.53.0.2) → TLD `lab.` (10.53.0.3) → власний сервер (10.53.1.1). Лише список кореневих серверів `+trace` бере в резолвера (перший рядок).

```text
root@ns-s09:/# dig @10.53.0.3 s09.lab NS +norec
;; flags: qr; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 2
;; AUTHORITY SECTION:
s09.lab.                3600    IN      NS      ns.s09.lab.
;; ADDITIONAL SECTION:
ns.s09.lab.             3600    IN      A       10.53.1.1

root@ns-s09:/# dig @10.53.1.1 s09.lab NS +norec
;; flags: qr aa; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 2
;; ANSWER SECTION:
s09.lab.                45      IN      NS      ns.s09.lab.
;; ADDITIONAL SECTION:
ns.s09.lab.             45      IN      A       10.53.1.1
```

| Запит | TTL запису NS | Прапорець `aa` | Секція, у якій міститься NS |
|---|---|---|---|
| `dig @10.53.0.3 s09.lab NS +norec` | 3600 | немає | AUTHORITY |
| `dig @10.53.1.1 s09.lab NS +norec` | 45 | є | ANSWER |

1. Які відповіді є відсиланнями і за якими ознаками це визначено?

   Відсилання (referral) — це відповіді root (10.53.0.2) і TLD (10.53.0.3). Ознаки: `status: NOERROR`, але `ANSWER: 0`; прапорця `aa` немає; у секції AUTHORITY є записи NS для ближчої до імені зони (`lab.`, потім `s09.lab.`), а в ADDITIONAL — їхні адреси. Сервер не знає відповіді й каже: «питай он тих». Відповідь 10.53.1.1 — остаточна: `aa`, запит A у секції ANSWER.

2. Для чого у відповіді TLD присутній запис у секції ADDITIONAL і що сталося б, якби його не було?

   `ns.s09.lab. A 10.53.1.1` — це glue-запис. Сервер зони `ns.s09.lab` лежить усередині тієї самої зони `s09.lab`, яку він обслуговує. Без glue резолвер отримав би лише ім'я `ns.s09.lab`. Щоб дізнатися його адресу, треба було б спитати сервер `s09.lab`, тобто той самий `ns.s09.lab`, адреси якого ще немає. Виникла б циклічна залежність, і зона була б нерезолвною (SERVFAIL).

3. Яка з двох копій запису NS є авторитативною і чому?

   Авторитативна копія — з 10.53.1.1 (TTL 45, прапорець `aa`, секція ANSWER). Її віддає сервер, що є джерелом даних зони `s09.lab` і бере TTL із `$TTL 45` у файлі зони. Копія на TLD (TTL 3600, без `aa`, у секції AUTHORITY) — лише делегування в батьківській зоні в точці розрізу (zone cut). Батьківська зона не є авторитативною для даних дочірньої, а TTL 3600 задано у файлі зони `lab.`.

## Завдання 3. Заповнення власної зони

Додані записи (нижче рядка `; ---- add records ...`), serial 2026111001 → 2026111002:

```text
www     IN  A       10.53.0.80
portal  IN  CNAME   www
mail    IN  A       10.53.0.80
@       IN  MX      10 mail
@       IN  TXT     "lab-token=87a47075"
test 25 IN  A       10.53.0.81
```

Вивід `zone-reload`:

```text
root@ns-s09:/# named-checkzone s09.lab /lab/zone/s09.lab.zone && rndc reload s09.lab
zone s09.lab/IN: loaded serial 2026111002
OK
zone reload queued
```

```text
root@ns-s09:/# dig @10.53.1.1 www.s09.lab A +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 34346
;; flags: qr aa; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 2
www.s09.lab.            45      IN      A       10.53.0.80

root@ns-s09:/# dig @10.53.1.1 portal.s09.lab CNAME +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 28662
;; flags: qr aa; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 2
portal.s09.lab.         45      IN      CNAME   www.s09.lab.

root@ns-s09:/# dig @10.53.1.1 mail.s09.lab A +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 34688
;; flags: qr aa; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 2
mail.s09.lab.           45      IN      A       10.53.0.80

root@ns-s09:/# dig @10.53.1.1 s09.lab MX +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1963
;; flags: qr aa; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 3
s09.lab.                45      IN      MX      10 mail.s09.lab.

root@ns-s09:/# dig @10.53.1.1 s09.lab TXT +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 48123
;; flags: qr aa; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 2
s09.lab.                45      IN      TXT     "lab-token=87a47075"

root@ns-s09:/# dig @10.53.1.1 test.s09.lab A +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 6953
;; flags: qr aa; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 2
test.s09.lab.           25      IN      A       10.53.0.81
```

| Запис | status | Прапорець `aa` | Значення в ANSWER | TTL | Відповідає картці (так/ні) |
|---|---|---|---|---|---|
| `www` A | NOERROR | так | 10.53.0.80 | 45 | так |
| псевдонім CNAME (`portal`) | NOERROR | так | www.s09.lab. | 45 | так |
| `mail` A | NOERROR | так | 10.53.0.80 | 45 | так |
| `@` MX | NOERROR | так | 10 mail.s09.lab. | 45 | так |
| `@` TXT | NOERROR | так | "lab-token=87a47075" | 45 | так |
| другий хост A (`test`) | NOERROR | так | 10.53.0.81 | 25 | так |

Порівняння відповідей резолвера та власного сервера:

```text
root@ns-s09:/# dig portal.s09.lab
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 38015
;; flags: qr rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1
;; ANSWER SECTION:
portal.s09.lab.         45      IN      CNAME   www.s09.lab.
www.s09.lab.            45      IN      A       10.53.0.80
;; Query time: 1 msec
;; SERVER: 10.53.0.53#53(10.53.0.53) (UDP)

root@ns-s09:/# dig @10.53.1.1 portal.s09.lab +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 36742
;; flags: qr aa; QUERY: 1, ANSWER: 2, AUTHORITY: 1, ADDITIONAL: 2
;; ANSWER SECTION:
portal.s09.lab.         45      IN      CNAME   www.s09.lab.
www.s09.lab.            45      IN      A       10.53.0.80
;; AUTHORITY SECTION:
s09.lab.                45      IN      NS      ns.s09.lab.
;; ADDITIONAL SECTION:
ns.s09.lab.             45      IN      A       10.53.1.1
;; SERVER: 10.53.1.1#53(10.53.1.1) (UDP)

root@ns-s09:/# dig s09.lab MX
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 29941
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
;; ANSWER SECTION:
s09.lab.                45      IN      MX      10 mail.s09.lab.
;; SERVER: 10.53.0.53#53(10.53.0.53) (UDP)

root@ns-s09:/# dig @10.53.1.1 s09.lab MX +norec
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 25907
;; flags: qr aa; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 3
;; ANSWER SECTION:
s09.lab.                45      IN      MX      10 mail.s09.lab.
;; AUTHORITY SECTION:
s09.lab.                45      IN      NS      ns.s09.lab.
;; ADDITIONAL SECTION:
mail.s09.lab.           45      IN      A       10.53.0.80
ns.s09.lab.             45      IN      A       10.53.1.1
;; SERVER: 10.53.1.1#53(10.53.1.1) (UDP)
```

| Запит | flags | ANSWER (кількість, типи) | AUTHORITY (кількість, типи) | ADDITIONAL (кількість, типи) | TTL |
|---|---|---|---|---|---|
| псевдонім через resolver-a | qr rd ra | 2 (CNAME, A) | 0 | 1 (OPT) | 45 / 45 (запис щойно закешовано) |
| псевдонім через 10.53.1.1 | qr aa | 2 (CNAME, A) | 1 (NS) | 2 (A для ns, OPT) | 45 |
| MX через resolver-a | qr rd ra | 1 (MX) | 0 | 1 (OPT) | 45 |
| MX через 10.53.1.1 | qr aa | 1 (MX) | 1 (NS) | 3 (A для mail, A для ns, OPT) | 45 |

Пояснення відмінностей. Авторитативний сервер ставить `aa` і на `+norec` не ставить `ra`: рекурсії він не виконує (`recursion no`). Він додає в AUTHORITY запис NS своєї зони, а в ADDITIONAL — корисні адреси: ns і, для MX, адресу `mail` (additional section processing). Резолвер відповідає без `aa`, бо дані не з першоджерела, а з кешу або отримані ітеративно. `rd ra` означає, що рекурсію запитано й вона доступна. Резолвер (unbound, `minimal-responses`) не віддає клієнту зайвих секцій AUTHORITY/ADDITIONAL. TTL збігаються (45), бо запит до резолвера був першим і запис щойно потрапив у кеш. При повторних запитах TTL у резолвера зменшувався б щосекунди (див. завдання 4).

Повідомлення `zone-check` після тимчасового додавання `@ IN CNAME www`:

```text
root@ns-s09:/# named-checkzone s09.lab /lab/zone/s09.lab.zone
dns_master_load: /lab/zone/s09.lab.zone:21: s09.lab: CNAME and other data
zone s09.lab/IN: loading from master file /lab/zone/s09.lab.zone failed: CNAME and other data
zone s09.lab/IN: not loaded due to errors.
```

Рядок одразу видалено, зону не перезавантажували.

1. Який TTL має кожен запис зони і звідки це значення взято?

   - `www`, `portal`, `mail`, `@ MX`, `@ TXT`, `@ NS`, `ns A`, а згодом і `new-virqv` — **45 с**. TTL у рядках не вказано, тому діє директива `$TTL 45` на початку файлу.
   - `test` — **25 с**, вказано явно в рядку (`test 25 IN A ...`), як вимагає картка.
   - `SOA` — **120 с**, вказано явно (`@ 120 IN SOA ...`).
   - У негативних відповідях SOA має TTL 40 = min(120, minimum 40) (див. завдання 5).

2. Скільки записів містить секція ANSWER у відповіді на запит псевдоніма і чому?

   Два: `portal.s09.lab. CNAME www.s09.lab.` і `www.s09.lab. A 10.53.0.80`. Запитано тип A, а для `portal` є лише CNAME. Сервер (і авторитативний, бо `www` у тій самій зоні, і резолвер) «розгортає» ланцюжок: віддає сам псевдонім і запис потрібного типу для канонічного імені. Так клієнту не потрібен другий запит.

3. Чому запис CNAME неможливо розмістити для імені `@`?

   CNAME означає, що ім'я — лише псевдонім іншого. Тому за RFC 1034 §3.6.2 / RFC 2181 §10.1 ім'я з CNAME не може мати жодних інших записів. Вершина зони `@` зобов'язана мати SOA і NS, тобто «інші дані» там уже є. Звідси помилка `CNAME and other data`, і BIND не завантажує зону.

## Завдання 4. TTL і видимість змін

Два запити з інтервалом 5 с:

```text
root@ns-s09:/# date +%T; dig www.s09.lab +noall +answer
18:44:05
www.s09.lab.            45      IN      A       10.53.0.80

root@ns-s09:/# date +%T; dig www.s09.lab +noall +answer
18:44:10
www.s09.lab.            40      IN      A       10.53.0.80
```

Перше значення 45 дорівнює `$TTL` (запис щойно потрапив у кеш resolver-a). Через 5 с TTL уже 40: резолвер віддає залишок часу життя запису в кеші, а не значення з файлу зони.

**Прогноз** (записано до вимірювання). Формула часу появи нової адреси через залишок R, найбільша можлива затримка:

- Якщо в момент зміни `t_зм` у кеші resolver-a залишилося R секунд, резолвер віддаватиме стару адресу, доки запис не спливе, а потім спитає сервер і отримає нову: `t_нова = t_зм + R`, затримка `Δ = R`.
- Найбільша можлива затримка — `Δmax = TTL = 45 с`, якщо запис закешовано саме в момент зміни (R = TTL).
- З урахуванням періоду циклу спостереження (2 с) спостережена затримка може бути до R + 2 с.

Перевірка, що сервер до `zone-reload` повертає стару адресу (zone-edit: `www → 10.53.0.81`, serial 2026111003, без reload):

```text
www     IN  A       10.53.0.81
root@ns-s09:/# dig @10.53.1.1 www.s09.lab +norec +short
10.53.0.80
```

Залишок R і час (крок 4), час `zone-reload` (крок 5), перевірка на сервері (крок 6):

```text
root@ns-s09:/# date +%T; dig www.s09.lab +noall +answer
18:44:10
www.s09.lab.            40      IN      A       10.53.0.80

root@ns-s09:/# named-checkzone s09.lab /lab/zone/s09.lab.zone && rndc reload s09.lab; date +%T
zone s09.lab/IN: loaded serial 2026111003
OK
zone reload queued
18:44:10

root@ns-s09:/# dig @10.53.1.1 www.s09.lab +norec +short
10.53.0.81
```

Очікуваний час появи нової адреси: R = 40 с, `t_нова = 18:44:10 + 40 с = 18:44:50`.

Вивід циклу спостереження (перші два рядки, два останні рядки зі старою адресою, рядок з новою адресою):

```text
root@ns-s09:/# while true; do echo "$(date +%T) $(dig +short www.s09.lab)"; sleep 2; done
18:44:10 10.53.0.80
18:44:12 10.53.0.80
...
18:44:47 10.53.0.80
18:44:49 10.53.0.80
18:44:51 10.53.0.81
^C
```

Рядок `server:` з відповіді `curl`:

```text
root@ns-s09:/# curl http://www.s09.lab/
server: web-b
Host: www.s09.lab
request URI: /
```

Тепер відповідає web-b (10.53.0.81), тобто клієнти resolver-a перейшли на нову адресу.

| Час зміни | Очікуваний час | Спостережений час | Виміряна затримка, с | Прогноз, с |
|---|---|---|---|---|
| 18:44:10 | 18:44:50 | 18:44:51 | 41 | 40 |

1. Чим пояснюється розбіжність між прогнозом і виміряним значенням?

   Розбіжність — 1 с, і вона в межах точності методу. (а) Цикл опитує резолвер раз на ~2 с: о 18:44:49 запис ще жив, а наступна перевірка була лише о 18:44:51. (б) `date +%T` і TTL у dig округлюються до цілих секунд. Журнал запитів власного сервера показує, що resolver-a закешував `www` о 18:44:05.094 (+45 с = 18:44:50.09), а повторно звернувся за ним о 18:44:51.167. Тобто реальний момент спливання збігається з прогнозом 18:44:50 з точністю до секунди.

2. Якою була б найбільша можлива затримка для цього запису і за яких умов?

   45 с (`$TTL`). Так було б, якби resolver-a закешував стару адресу безпосередньо перед `zone-reload` (R = 45), наприклад якщо якийсь клієнт запитав `www` за мить до зміни. Для резолвера з serve-stale затримка могла б бути ще більшою, якщо авторитативний сервер у цей час недоступний (див. завдання 7).

3. Як слід діяти, щоб перенести сервіс на нову адресу, якщо TTL запису становить 86 400 с?

   - Щонайменше за 86 400 с (добу) до переїзду знизити TTL запису, наприклад до 60–300 с, і дочекатися, поки в усіх кешах спливе старий запис із TTL доби.
   - Підняти сервіс на новій адресі паралельно зі старою.
   - Змінити запис (serial++, reload). Тепер затримка не перевищує нового, малого TTL.
   - Старий сервер не вимикати, доки не спливе щонайменше новий TTL і не затихнуть запити на стару адресу.
   - Після стабілізації повернути великий TTL.

## Завдання 5. Негативне кешування

**Прогноз** (записано до вимірювання). Формула за RFC 2308 і розраховане значення:

`TTL_neg = min(TTL запису SOA, SOA.minimum) = min(120, 40) = 40 с`.

Ім'я має почати резолвитися через resolver-a приблизно через 40 с після того, як NXDOMAIN потрапив у кеш. Спостережено може бути до 40 + 2 с через період циклу.

Перевірка, що сервер до `zone-reload` повертає `NXDOMAIN` (додано `new-virqv IN A 10.53.0.80`, serial 2026111004, без reload):

```text
root@ns-s09:/# dig @10.53.1.1 new-virqv.s09.lab +norec
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 11063
;; flags: qr aa; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 1
;; AUTHORITY SECTION:
s09.lab.                40      IN      SOA     ns.s09.lab. admin.s09.lab. 2026111003 3600 600 86400 40
;; WHEN: Tue Nov 10 18:44:51 UTC 2026
```

Запит через resolver-a (крок 3), час `zone-reload` (крок 4), перевірка на сервері (крок 5):

```text
root@ns-s09:/# date +%T; dig new-virqv.s09.lab
18:44:51
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 63986
;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 1
;; AUTHORITY SECTION:
s09.lab.                40      IN      SOA     ns.s09.lab. admin.s09.lab. 2026111003 3600 600 86400 40
;; SERVER: 10.53.0.53#53(10.53.0.53) (UDP)

root@ns-s09:/# named-checkzone s09.lab /lab/zone/s09.lab.zone && rndc reload s09.lab; date +%T
zone s09.lab/IN: loaded serial 2026111004
OK
zone reload queued
18:44:51

root@ns-s09:/# dig @10.53.1.1 new-virqv.s09.lab +norec +short
10.53.0.80
```

Вивід циклу спостереження (перші два рядки, останній рядок з `NXDOMAIN`, перший рядок з `NOERROR`):

```text
root@ns-s09:/# while true; do echo "$(date +%T) $(dig new-virqv.s09.lab +noall +comments | grep -o 'status: [A-Z]*')"; sleep 2; done
18:44:51 status: NXDOMAIN
18:44:53 status: NXDOMAIN
...
18:45:31 status: NXDOMAIN
18:45:33 status: NOERROR
^C
```

| Негативну відповідь закешовано | Запис створено | Ім'я резолвиться через resolver-a | Виміряно, с | Прогноз, с |
|---|---|---|---|---|
| 18:44:51 | 18:44:51 | 18:45:33 | 42 | 40 |

Завдання не повторювалося, бо цикл почався з NXDOMAIN. За журналом власного сервера resolver-a спитав ім'я о 18:44:51.350 і повторно о 18:45:33.710. Перевірка о 18:45:31 ще потрапила в кеш (40 с від 18:44:51.35 = 18:45:31.35), наступна — лише через 2 с. Звідси +2 с до прогнозу.

1. Чому тривалість негативного кешування визначається записом SOA, а не записом, який запитували?

   Запитаного запису не існує, тому в нього немає власного TTL: кешувати нема чого, крім самого факту відсутності. Щоб резолвер знав, скільки пам'ятати «імені немає», авторитативний сервер кладе в секцію AUTHORITY запис SOA своєї зони. За RFC 2308 час негативного кешування — це min(TTL SOA, поле minimum SOA). Так власник зони одним параметром керує негативним кешуванням для всіх неіснуючих імен.

2. Чи збігається TTL запису SOA в секції AUTHORITY з TTL запису SOA у файлі зони? Поясніть.

   Ні. У файлі TTL SOA = 120, а у відповіді 40. За RFC 2308 §3 сервер у негативній відповіді ставить TTL SOA рівним min(TTL SOA, minimum) = min(120, 40) = 40, щоб резолвер кешував NXDOMAIN саме стільки. У відповідях resolver-a це значення далі зменшується щосекунди, як і будь-який TTL у кеші.

3. Скрипт розгортання перевіряє ім'я сервісу до створення запису, а потім одразу після. Що він побачить і як це виправити?

   Обидва рази він побачить NXDOMAIN. Перша перевірка «до» сама закешувала негативну відповідь у резолвері на 40 с. Друга, одразу після створення, отримає цю відповідь із кешу, хоча на авторитативному сервері запис уже є. Як виправити:
   - не перевіряти ім'я через рекурсивний резолвер до створення;
   - перевіряти авторитативний сервер напряму (`dig @10.53.1.1 ... +norec`), бо він не кешує;
   - або після створення чекати min(TTL SOA, minimum) і повторювати перевірку з інтервалом, а не один раз;
   - за потреби зменшити `minimum` SOA.

## Завдання 6. Затримка пошуку імені

**Прогноз** (записано до вимірювання). До яких серверів звернеться resolver-a:

| Ім'я | Перший запит | Повторний запит |
|---|---|---|
| A: нове ім'я у власній зоні | лише власний сервер 10.53.1.1 (делегування `s09.lab` уже в кеші) | жодного, з кешу (NXDOMAIN) |
| B: нове ім'я в зоні `lab.` | лише TLD 10.53.0.3 (NS `lab.` у кеші) | жодного, з кешу |
| C: ім'я в неіснуючому TLD | лише root 10.53.0.2 (NS `.` у кеші, root відповідає NXDOMAIN) | жодного, з кешу |
| D: `www.s09.lab` після перезапуску резолвера | root (priming `. NS` + referral) → TLD → власний сервер | жодного, з кешу |

Очікувані затримки: root ≈ 80 мс, TLD ≈ 40 мс (параметри netem стенда), власний ≈ 0 мс. Для D: ≥ 2·80 (priming + referral) + 40 + 0 ≈ 200–300 мс.

Вивід вимірювань:

```text
root@ns-s09:/# A=y25132.s09.lab; B=x31116.lab; C=x24730.zz11705
--- A (y25132.s09.lab)
;; Query time: 1 msec
;; Query time: 0 msec
--- B (x31116.lab)
;; Query time: 40 msec
;; Query time: 0 msec
--- C (x24730.zz11705)
;; Query time: 81 msec
;; Query time: 0 msec

codespace$ docker compose -f stand/compose.yaml restart resolver-a   (18:45:34)
 Container dnslab-resolver-a-1 Restarting
 Container dnslab-resolver-a-1 Started
--- D (www.s09.lab після перезапуску резолвера)
root@ns-s09:/# date +%T; dig www.s09.lab | grep "Query time"
18:45:39
;; Query time: 402 msec
root@ns-s09:/# dig www.s09.lab | grep "Query time"
;; Query time: 0 msec
```

| Ім'я | Перший запит, мс | Повторний, мс | Сервери, до яких звернувся резолвер (за журналами) |
|---|---|---|---|
| A | 1 | 0 | лише власний 10.53.1.1 (`18:45:33.862 ... y25132.s09.lab`) |
| B | 40 | 0 | лише TLD 10.53.0.3 (`18:45:33.891 ... x31116.lab`) |
| C | 81 | 0 | лише root 10.53.0.2 (`18:45:33.971 ... x24730.zz11705`) |
| D | 402 | 0 | root ×3 (`. NS`, `a.root-servers.net A`, `www.s09.lab A`) → TLD (`www.s09.lab`) → власний (`www.s09.lab`) |

Значення `time_namelookup` з `curl` після перезапуску резолвера (resolver-a перезапущено ще раз о 18:45:40):

```text
root@ns-s09:/# curl -so /dev/null -w '%{time_namelookup}\n' http://www.s09.lab/
0.402469
```

Тобто 402 мс — стільки ж, скільки показав dig у рядку D. Застосунок чекає на DNS той самий час.

Фрагменти журналів запитів root, TLD і власного сервера для рядка D:

```text
=== root (10.53.0.2)
10-Nov-2026 18:45:33.971 client 10.53.0.53#57028 (x24730.zz11705): query: x24730.zz11705 IN A -E(0)DC (10.53.0.2)
10-Nov-2026 18:45:39.644 client 10.53.0.53#49895 (.): query: . IN NS -E(0)DC (10.53.0.2)
10-Nov-2026 18:45:39.724 client 10.53.0.53#30325 (a.root-servers.net): query: a.root-servers.net IN A -E(0)DC (10.53.0.2)
10-Nov-2026 18:45:39.804 client 10.53.0.53#33343 (www.s09.lab): query: www.s09.lab IN A -E(0)DC (10.53.0.2)
=== TLD (10.53.0.3)
10-Nov-2026 18:45:33.891 client 10.53.0.53#43294 (x31116.lab): query: x31116.lab IN A -E(0)DC (10.53.0.3)
10-Nov-2026 18:45:39.925 client 10.53.0.53#15027 (www.s09.lab): query: www.s09.lab IN A -E(0)DC (10.53.0.3)
=== власний сервер (querylog, 10.53.1.1)
10-Nov-2026 18:45:33.862 client 10.53.0.53#62000 (y25132.s09.lab): query: y25132.s09.lab IN A -E(0)DC (10.53.1.1)
10-Nov-2026 18:45:39.965 client 10.53.0.53#46313 (www.s09.lab): query: www.s09.lab IN A -E(0)DC (10.53.1.1)
```

(Адреси `@0x...` у рядках журналу прибрано для стислості.)

1. Яку затримку вносить кожен із серверів root, TLD і власний сервер? Покажіть, з яких рядків таблиці це випливає.

   - **root ≈ 80 мс** — з рядка C (81 мс). Журнал показує, що резолвер звертався лише до root.
   - **TLD ≈ 40 мс** — з рядка B (40 мс): лише TLD.
   - **Власний сервер ≈ 0–1 мс** — з рядка A (1 мс): лише власний сервер.
   - Те саме видно в журналі рядка D: запити до root ідуть з кроком 80 мс (39.644 → 39.724 → 39.804), від запиту до TLD до запиту до власного сервера минає 40 мс (39.925 → 39.965).
   - Повторні запити (0 мс) обслуговуються з кешу, без звернень до серверів.
   - Рядок D (402 мс) складається з трьох звернень до root (priming `. NS`, адреса `a.root-servers.net`, referral для `www.s09.lab`), одного до TLD і одного до власного сервера: 3·80 + 40 + 0 ≈ 280 мс. Решту ≈ 120 мс до кінця пояснити не вдалося (див. «Висновки»).

2. Чому в рядку A перший запит не проходить через root і TLD, хоча ім'я нове?

   Нове ім'я, але не нова зона. У кеші resolver-a вже лежало делегування `s09.lab` (NS `ns.s09.lab` + адреса 10.53.1.1): його оновили о 18:44:51 під час завдань 4–5, TTL 45 с, тобто воно жило до ≈18:45:36. Резолвер починає ітерацію з найближчого відомого предка імені і відразу питає авторитативний сервер `s09.lab`. Root і TLD потрібні лише тоді, коли делегування в кеші немає.

3. Вебсторінка завантажує ресурси з п'яти різних доменів. Як це впливає на час першого відкриття сторінки?

   Для кожного з п'яти доменів при холодному кеші потрібен окремий пошук імені. У найгіршому разі це повний ланцюжок root → TLD → авторитативний (тут до ≈400 мс), а реально — по одному звертанню до кожного ще не закешованого рівня. Браузер може резолвити паралельно, але ресурси часто залежать один від одного: HTML → CSS → шрифти/скрипти з іншого домену. Тоді затримки DNS додаються послідовно до TCP/TLS-рукостискань і першого відкриття сторінки. Повторні відкриття вже швидкі (кеш). Як зменшити: менше сторонніх доменів, `<link rel="dns-prefetch">`/`preconnect`, достатньо великі TTL.

## Завдання 7. Інцидент: зупинка власного сервера

**Прогноз** (записано до вимірювання). Що поверне кожен резолвер після зупинки сервера та спливання TTL і скільки часу займе відповідь:

- **resolver-a** (звичайний кеш). Через 25 с запис `test` спливе, і резолвер піде до 10.53.1.1, який не відповідає. Він повторюватиме спроби (тайм-аут на сервер до 3 с, `infra-cache-max-rtt 3000`). Очікую SERVFAIL через кілька секунд або тайм-аут клієнта dig (30 с), якщо резолвер намагатиметься довше. Другий запит — так само або швидкий SERVFAIL, якщо резолвер уже позначив сервер як недоступний.
- **resolver-b** (serve-stale, RFC 8767). Віддасть прострочений запис `test.s09.lab A 10.53.0.81` зі status NOERROR. Відповідь надійде через ≈1,8 с (`serve-expired-client-timeout 1800` мс — стільки він чекає авторитативний сервер, перш ніж віддати старе) з TTL 30 с.

Кешування запису в обох резолверах (крок 2) і час зупинки сервера (крок 3):

```text
root@ns-s09:/# dig @10.53.0.53 test.s09.lab +noall +answer
test.s09.lab.           25      IN      A       10.53.0.81

root@ns-s09:/# dig @10.53.0.54 test.s09.lab +noall +answer
test.s09.lab.           25      IN      A       10.53.0.81

root@ns-s09:/# date +%T; rndc stop
18:45:46

root@ns-s09:/# sleep 35
```

Запити із заміром часу (крок 5):

```text
root@ns-s09:/# date +%T; { time dig @10.53.0.53 test.s09.lab +tries=1 +timeout=30 ; } 2>&1
18:46:21
;; communications error to 10.53.0.53#53: timed out

; <<>> DiG 9.18.39-0ubuntu0.24.04.9-Ubuntu <<>> @10.53.0.53 test.s09.lab +tries=1 +timeout=30
; (1 server found)
;; global options: +cmd
;; no servers could be reached

real    0m30.043s
user    0m0.004s
sys     0m0.006s

root@ns-s09:/# date +%T; { time dig @10.53.0.53 test.s09.lab +tries=1 +timeout=30 ; } 2>&1
18:46:51
;; communications error to 10.53.0.53#53: timed out

; <<>> DiG 9.18.39-0ubuntu0.24.04.9-Ubuntu <<>> @10.53.0.53 test.s09.lab +tries=1 +timeout=30
; (1 server found)
;; global options: +cmd
;; no servers could be reached

real    0m30.032s
user    0m0.006s
sys     0m0.004s

root@ns-s09:/# date +%T; { time dig @10.53.0.54 test.s09.lab +tries=1 +timeout=30 ; } 2>&1
18:47:21
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 6281
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
;; ANSWER SECTION:
test.s09.lab.           30      IN      A       10.53.0.81
;; Query time: 1799 msec
;; SERVER: 10.53.0.54#53(10.53.0.54) (UDP)
;; WHEN: Tue Nov 10 18:47:23 UTC 2026

real    0m1.810s
user    0m0.005s
sys     0m0.005s
```

| Запит | status або тайм-аут | ANSWER, TTL | `real` |
|---|---|---|---|
| resolver-a, перший | тайм-аут (`no servers could be reached`) | — | 0m30.043s |
| resolver-a, другий | тайм-аут (`no servers could be reached`) | — | 0m30.032s |
| resolver-b | NOERROR (stale) | `test.s09.lab. 30 IN A 10.53.0.81`, TTL 30 | 0m1.810s |

Час `named-start` і вивід циклу спостереження до першої успішної відповіді (крок 6):

```text
root@ns-s09:/# named -u bind -c /lab/named.conf; date +%T
18:47:23
root@ns-s09:/# while true; do echo "$(date +%T) $(dig @10.53.0.53 test.s09.lab +short +tries=1 +timeout=3)"; sleep 2; done
18:47:23
18:47:25
18:47:27
18:47:29
18:47:31
18:47:33
18:47:35
18:47:37
18:47:39
18:47:41
18:47:43
18:47:45
18:47:47
18:47:49
18:47:51
18:47:53 10.53.0.81
^C
```

Перевірка після завдання (`dig @10.53.1.1 s09.lab SOA +norec +short`):

```text
ns.s09.lab. admin.s09.lab. 2026111004 3600 600 86400 40
```

### Постмортем

1. **Що сталося:** о 18:45:46 зупинено єдиний авторитативний сервер зони `s09.lab` (10.53.1.1, `rndc stop`). Резервного (secondary) сервера в зони немає, тому після спливання кешів ім'я `test.s09.lab` (TTL 25 с) стало нерезолвним.
2. **Вплив на клієнтів resolver-a і resolver-b:**
   - Клієнти resolver-a повністю втратили ім'я: кожен запит висів 30 с і закінчувався тайм-аутом, без жодної відповіді (два запити поспіль — 30,04 с і 30,03 с).
   - Клієнти resolver-b майже не помітили збою: отримували стару (але правильну) адресу 10.53.0.81 зі статусом NOERROR. Кожна відповідь затримувалася на ≈1,8 с (`Query time: 1799 msec`).
3. **Хронологія з виміряним часом:**
   - 18:45:46 — `named-stop`.
   - ≈18:46:11 — у кешах сплив запис `test` (закешовано ≈18:45:46, TTL 25 с).
   - 18:46:21–18:46:51 — перший запит до resolver-a: тайм-аут 30,043 с.
   - 18:46:51–18:47:21 — другий запит до resolver-a: тайм-аут 30,032 с.
   - 18:47:21 — resolver-b віддав stale-запис за 1,810 с.
   - 18:47:23 — `named-start`.
   - 18:47:53 — resolver-a знову резолвить `test.s09.lab` (через 30 с після запуску сервера).
   - Тривалість інциденту для клієнтів resolver-a ≈ 18:46:11–18:47:53, тобто ≈ 1 хв 42 с. Для клієнтів resolver-b — лише сповільнення ≈ 1,8 с на запит.
4. **Чому кеш допоміг або не допоміг:**
   - Звичайний кеш resolver-a не допоміг: TTL 25 с закінчився раніше, ніж сервер повернувся, а прострочені дані unbound без serve-stale не віддає.
   - Кеш resolver-b допоміг: за RFC 8767 він віддає прострочений запис (до `serve-expired-ttl 3600` с), якщо авторитативний сервер не відповів за 1,8 с.
   - Короткий TTL (25 с) зробив зону дуже чутливою до простою сервера.
5. **Що слід змінити:**
   - Додати щонайменше другий авторитативний сервер зони (secondary) в іншій мережі/локації й прописати обидва NS у делегуванні в TLD.
   - Увімкнути serve-stale на рекурсивних резолверах.
   - Не ставити без потреби дуже малі TTL для стабільних записів.
   - Додати моніторинг доступності авторитативного сервера (перевірка SOA +norec).

1. Який TTL мав запис у відповіді resolver-b і навіщо такий TTL?

   30 с — не початкові 25 с і не залишок, а фіксоване значення для stale-відповідей (у unbound `serve-expired-reply-ttl`, за замовчуванням 30, як рекомендує RFC 8767). Короткий TTL каже клієнту, що дані сумнівні: не тримай їх довго, спитай знову незабаром. Коли сервер повернеться, клієнти швидко отримають свіжі дані. Водночас 30 с не дає клієнтам засипати резолвер повторними запитами.

2. Порівняйте результат і тривалість двох запитів до resolver-a. Якщо вони різняться, сформулюйте гіпотезу щодо причини; якщо ні, поясніть, що робить резолвер протягом цього часу.

   Обидва однакові: тайм-аут dig рівно через 30 с (30,043 і 30,032 с), resolver-a нічого не відповів, навіть SERVFAIL. Весь цей час резолвер намагається отримати відповідь від єдиного авторитативного сервера `s09.lab`. Він надсилає повторні запити до 10.53.1.1 зі зростаючим тайм-аутом (до 3 с, `infra-cache-max-rtt`) і, ймовірно, перевіряє делегування `s09.lab` у TLD. Сумарний бюджет спроб у unbound більший за 30 с, тому SERVFAIL не встигає надійти до кінця тайм-ауту dig. Другий запит потрапив у ту саму ситуацію: попередня спроба не закешувала SERVFAIL, бо так і не завершилась відмовою до приходу нового запиту. У одногрупників другий запит іноді повертав швидкий SERVFAIL. Ймовірно, у них перша спроба резолвера встигла завершитися й закешувати збій.

3. Чому після `named-start` ім'я через resolver-a зарезолвилося не одразу?

   Сервер запустився о 18:47:23, а resolver-a почав резолвити ім'я лише о 18:47:53, через 30 с. Unbound після серії тайм-аутів позначив 10.53.1.1 в infra-кеші як недоступний (`infra-host-ttl 60`, накопичений RTT-штраф). Поки цей стан діє, резолвер не надсилає туди звичайних запитів, лише зрідка «пробує» сервер. Додатково запити циклу з `+timeout=3` обривалися раніше, ніж резолвер встигав завершити спробу. Ім'я з'явилося, коли запис про недоступність сервера сплив або пробний запит пройшов успішно.

4. У якій ситуації serve-stale шкодить, а не допомагає? Пов'яжіть відповідь із завданням 4.

   Коли запис свідомо змінили (як `www` 10.53.0.80 → 10.53.0.81 у завданні 4), а потім авторитативний сервер став недоступним. Резолвер із serve-stale продовжує роздавати стару адресу до `serve-expired-ttl` (тут 3600 с) замість нової. Якщо старий сервер (web-a) уже вимкнено, клієнти отримують «правильну на вигляд» відповідь NOERROR, але йдуть на мертву адресу. Діагностувати це важче, ніж явний SERVFAIL: збій маскується. Також serve-stale ховає від моніторингу саму недоступність авторитативного сервера.

## Фінальний файл зони

`stand/students/s09/zone/s09.lab.zone` після завершення роботи:

```text
; Zone s09.lab — starting version.
; After every change: increase the serial, then run  zone-reload
$TTL 45
@     120 IN SOA ns.s09.lab. admin.s09.lab. (
            2026111004 ; serial
            3600       ; refresh
            600        ; retry
            86400      ; expire
            40         ; minimum
        )
@     IN NS ns.s09.lab.
ns    IN A  10.53.1.1

; ---- add records from your variant card below this line ----
www     IN  A       10.53.0.81
portal  IN  CNAME   www
mail    IN  A       10.53.0.80
@       IN  MX      10 mail
@       IN  TXT     "lab-token=87a47075"
test 25 IN  A       10.53.0.81
new-virqv IN  A       10.53.0.80
```

Усі записи завдання 3 присутні, serial збільшено з 2026111001 до 2026111004, `www` вказує на 10.53.0.81, ім'я `new-virqv` створене, сервер після завдання 7 запущено (відповідь SOA вище).

## Висновки

**Що виявилося несподіваним.**

1. У завданні 7 **обидва** запити до resolver-a завершилися тайм-аутом клієнта (30 с), без SERVFAIL. Я очікував, що другий запит отримає швидкий SERVFAIL із кешу збоїв:

   ```text
   18:46:51
   ;; communications error to 10.53.0.53#53: timed out
   real    0m30.032s
   ```

2. Під час завдання 4 resolver-a, оновлюючи `www` після спливання TTL, звернувся не тільки до власного сервера, а й до TLD:

   ```text
   10-Nov-2026 18:44:51.126 client 10.53.0.53#52385 (www.s09.lab): query: www.s09.lab IN A -E(0)DC (10.53.0.3)
   ```

   Пояснення: делегування `s09.lab` резолвер зберігає з TTL дочірньої зони (NS з TTL 45 від авторитативного сервера замінив копію з TTL 3600 від TLD). Тому делегування спливло разом із `www`, і його довелося отримувати знову в TLD.

**Яке питання залишилося без відповіді.** У рядку D завдання 6 перший запит тривав 402 мс (`;; Query time: 402 msec`, `time_namelookup` 0.402469). За журналами резолвер зробив три звернення до root (80 мс кожне), одне до TLD (40 мс) і одне до власного сервера (≈0 мс), разом ≈ 280 мс. Що вже перевірено:

- журнали root/TLD/власного сервера: інших запитів від 10.53.0.53 у цей момент немає;
- між відповіддю root на referral (≈18:45:39.884) і приходом запиту до TLD (18:45:39.925) є пауза ≈ 41 мс;
- ще ≈ 80 мс минає до першого запиту priming (`. NS` о 18:45:39.644).

Не вдалося з'ясувати, на що unbound витрачає ці ≈ 120 мс. Можливо, це повторна відправка першого запиту після холодного старту або внутрішні запити, які не потрапляють у журнали серверів. Для перевірки варто запустити `tcpdump` на інтерфейсі resolver-a під час рядка D.

## Декларація використання ШІ

Використовувалися інструменти ШІ: так

| № | Інструмент | Промпт (дослівно)                | Що використано у звіті і що змінено самостійно                                                      |
|---|---|----------------------------------|-----------------------------------------------------------------------------------------------------|
| 1 | Claude (Claude Code, Anthropic) | «Що такое прапорці qr/aa/rd/ra?» | Отримано теоретичне поясненя стосовно прапорців аа - авторитетна, rd - кліент просіть рекурсію і тд |
| 2 | Claude (Claude Code, Anthropic) | «Чому CNAME не можна на @?»      | Отримано приклад на вершині зони @ уже є обов'язкові SOA і NS, а CNAME означає, що в імені не може бути інших записів, тому BIND видає помилку «CNAME and other data» і не завантажує зону. У звіті використано пояснення до питання 3 завдання 3. Самостійно: перевірив на своєму виводі zone-check                                                                                   |
