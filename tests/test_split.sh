#!/bin/sh
# test_split.sh — тесты split.sh: сверка раздела 7 с подзадачами, ошибки анализа и таблицы,
# создание заготовок (--create) и ошибки его аргументов.
. "$(dirname "$0")/lib.sh"

split() {
  sh "$scripts/split.sh" "$@"
}

fresh

# Сверка: успех.

check 'план без файлов подзадач' 0 split tasks/005_план <<'EOF'
PLAN <ROOT>/tasks/005_план
П1 new Первая
П2 new Вторая
EOF

check 'план, все подзадачи на месте' 0 split tasks/006_в-работе <<'EOF'
PLAN <ROOT>/tasks/006_в-работе
П1 ok 01_первая.md
П2 ok 02_вторая.md
П3 ok 03_третья.md
EOF

check 'план со всеми предупреждениями' 0 split tasks/010_сломанные <<'EOF'
PLAN <ROOT>/tasks/010_сломанные
П1 draft 01_черновик.md
П2 ok 02_без-шагов.md
П3 ok 03_шаги-с-пропуском.md
П4 dup 04_двойная-а.md
П4 dup 04_двойная-б.md
П5 foreign 05_чужая.md
П6 changed 06_старое-название.md
was=П6 | Старое название | `f` | — | S
now=П6 | Новое название | `f` | — | S
unfilled=no
П8 new Ссылка
gone 07_лишняя.md
extra заметки.txt
dep.missing=П8 П9
EOF

check 'без разбивки' 0 split tasks/004_без-разбивки <<'EOF'
NO_SPLIT <ROOT>/tasks/004_без-разбивки
reason=Нет: задача маленькая, делаем целиком.
EOF

# Сверка: ошибки.

check 'открытые вопросы' 4 split tasks/003_вопросы <<'EOF'
QUESTIONS_OPEN <ROOT>/tasks/003_вопросы
question=В1. Делать ли вторую часть?
EOF

check 'нет таблицы в разделе 7' 4 split tasks/011_нет-таблицы <<'EOF'
NO_TABLE <ROOT>/tasks/011_нет-таблицы/анализ.md
EOF

check 'кривая таблица' 4 split tasks/012_кривая-таблица <<'EOF'
BAD_TABLE <ROOT>/tasks/012_кривая-таблица/анализ.md
line=9 header
line=11 cells=4
EOF

check 'нет раздела 7' 4 split tasks/013_нет-раздела <<'EOF'
BAD_ANALYSIS <ROOT>/tasks/013_нет-раздела/анализ.md section=7
EOF

check 'нет анализа' 3 split tasks/002_без-анализа <<'EOF'
NO_ANALYSIS <ROOT>/tasks/002_без-анализа
EOF

check 'папка без задача.md' 3 split tasks/014_без-описания <<'EOF'
NOT_TASK <ROOT>/tasks/014_без-описания
EOF

check 'папки нет' 3 split tasks/нет-такой <<'EOF'
NO_DIR <ROOT>/tasks/нет-такой
EOF

check 'не папка' 3 split tasks/README.md <<'EOF'
NOT_DIR <ROOT>/tasks/README.md
EOF

check 'нет аргумента' 2 split <<'EOF'
NO_ARG
EOF

check 'лишний аргумент без --create' 2 split tasks/005_план лишнее <<'EOF'
BAD_ARG лишнее
EOF

fresh
printf '%s\n' '# Анализ' '' '## 6. Вопросы' '' '## 7. Подзадачи' '' 'Нет: не нужно.' '' \
  '| № | Подзадача | Где | Зависит от | Размер |' '| --- | --- | --- | --- | --- |' \
  '| П1 | Первая | `a` | — | S |' >tasks/005_план/анализ.md
check 'и таблица, и «Нет:»' 4 split tasks/005_план <<'EOF'
BAD_TABLE <ROOT>/tasks/005_план/анализ.md
line=0 table-and-none
EOF

# --create: ошибки аргументов; файлы при них не создаются.

fresh

check 'create без N=имя' 2 split --create tasks/005_план <<'EOF'
NO_ARG
EOF

check 'create: аргумент без =' 2 split --create tasks/005_план первая <<'EOF'
BAD_ARG первая
EOF

check 'create: номер не число' 2 split --create tasks/005_план x=первая <<'EOF'
BAD_ARG x=первая
EOF

check 'create: номер дважды' 2 split --create tasks/005_план 1=первая 1=другая <<'EOF'
DUP_ARG 1
EOF

check 'create: номера нет в разделе 7' 4 split --create tasks/005_план 1=первая 2=вторая 3=третья <<'EOF'
NO_ROW 3
EOF

check 'create: не все строки new' 4 split --create tasks/005_план 1=первая <<'EOF'
MISSING П2
EOF

check 'create: имя с пробелом' 4 split --create tasks/005_план '1=с пробелом' 2=вторая <<'EOF'
BAD_NAME с пробелом
EOF

check 'create: имя с .md' 4 split --create tasks/005_план 1=первая.md 2=вторая <<'EOF'
BAD_NAME первая.md extension
EOF

check 'create: имя с номером' 4 split --create tasks/005_план 1=12_первая 2=вторая <<'EOF'
BAD_NAME 12_первая number
EOF

check 'create: подзадача уже есть' 4 split --create tasks/006_в-работе 1=первая <<'EOF'
NOT_NEW П1 ok
EOF

check 'после ошибок файлов нет' 0 ls tasks/005_план <<'EOF'
анализ.md
задача.md
EOF

fresh
mkdir -p tasks/005_план/подзадачи/01_первая.md
check 'create: имя занято' 4 split --create tasks/005_план 1=первая 2=вторая <<'EOF'
EXISTS <ROOT>/tasks/005_план/подзадачи/01_первая.md
EOF

# --create: успех.

fresh

check 'create: заготовки для всех new' 0 split --create tasks/005_план 1=первая 2=вторая <<'EOF'
CREATED <ROOT>/tasks/005_план/подзадачи
file=<ROOT>/tasks/005_план/подзадачи/01_первая.md
file=<ROOT>/tasks/005_план/подзадачи/02_вторая.md
EOF

check 'create: шапка и паспорт заготовки' 0 head -n 15 tasks/005_план/подзадачи/02_вторая.md <<'EOF'
---
sae: subtask
source: 'П2 | Вторая | `b` | П1 | M'
---

# П2. Вторая

> 💡 **Коротко.** <!-- заполнить: 1–2 предложения — что даёт подзадача и зачем она задаче -->

| | |
| --- | --- |
| **Задача** | [План без подзадач](../анализ.md) |
| **Где** | `b` |
| **Зависит от** | [01 · Первая](01_первая.md) |
| **Размер** | M |
EOF

check 'после create — заготовки draft' 0 split tasks/005_план <<'EOF'
PLAN <ROOT>/tasks/005_план
П1 draft 01_первая.md
П2 draft 02_вторая.md
EOF

finish
