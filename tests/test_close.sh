#!/bin/sh
# test_close.sh — тесты close.sh: перенос задачи в _архив/, отказ при открытых подзадачах,
# --open-ok и ошибки (уже в архиве, не в папке задач, место занято, аргументы).
. "$(dirname "$0")/lib.sh"

close() {
  sh "$scripts/close.sh" "$@"
}

# Успех: папка переехала в архив.

fresh
check 'все подзадачи закрыты' 0 close tasks/009_все-закрыты <<'EOF'
ARCHIVED <ROOT>/tasks/009_все-закрыты
to=<ROOT>/tasks/_архив/009_все-закрыты
EOF

check 'папка в архиве' 0 ls tasks/_архив <<'EOF'
009_все-закрыты
020_закрытая
EOF

check 'на старом месте папки нет' 1 test -e tasks/009_все-закрыты <<'EOF'
EOF

fresh
rm -rf tasks/_архив
check 'архива ещё нет, без подзадач' 0 close tasks/004_без-разбивки <<'EOF'
ARCHIVED <ROOT>/tasks/004_без-разбивки
to=<ROOT>/tasks/_архив/004_без-разбивки
EOF

check 'архив создан' 0 ls tasks/_архив <<'EOF'
004_без-разбивки
EOF

fresh
check 'открытые подзадачи с --open-ok' 0 close --open-ok tasks/006_в-работе <<'EOF'
ARCHIVED <ROOT>/tasks/006_в-работе
to=<ROOT>/tasks/_архив/006_в-работе
EOF

# Ошибки: на одной копии, ничего не должно переехать.

fresh

check 'открытые подзадачи' 4 close tasks/006_в-работе <<'EOF'
SUBTASKS_OPEN <ROOT>/tasks/006_в-работе
open=02_вторая.md
open=03_третья.md
EOF

check 'уже в архиве' 4 close tasks/_архив/020_закрытая <<'EOF'
ALREADY_ARCHIVED <ROOT>/tasks/_архив/020_закрытая
EOF

check 'не задача' 3 close tasks/014_без-описания <<'EOF'
NOT_TASK <ROOT>/tasks/014_без-описания
EOF

check 'нет папки' 3 close tasks/999_нет <<'EOF'
NO_DIR <ROOT>/tasks/999_нет
EOF

check 'файл вместо папки' 3 close tasks/README.md <<'EOF'
NOT_DIR <ROOT>/tasks/README.md
EOF

check 'без аргумента' 2 close <<'EOF'
NO_ARG
EOF

check 'только --open-ok' 2 close --open-ok <<'EOF'
NO_ARG
EOF

check 'лишний аргумент' 2 close tasks/009_все-закрыты лишний <<'EOF'
BAD_ARG лишний
EOF

check 'после ошибок ничего не переехало' 0 diff -r -x .DS_Store "$fixtures/tasks" tasks <<'EOF'
EOF

# Ошибки, для которых копию нужно подготовить.

fresh
mkdir -p другое/030_вне-папки-задач
: >другое/030_вне-папки-задач/задача.md
check 'задача не в папке задач' 4 close другое/030_вне-папки-задач <<'EOF'
NOT_IN_TASKS <ROOT>/другое/030_вне-папки-задач
EOF

fresh
mkdir tasks/_архив/009_все-закрыты
check 'в архиве место занято' 4 close tasks/009_все-закрыты <<'EOF'
EXISTS <ROOT>/tasks/_архив/009_все-закрыты
EOF

fresh
rm -rf tasks/_архив
: >tasks/_архив
check 'архив — файл' 3 close tasks/009_все-закрыты <<'EOF'
NOT_DIR <ROOT>/tasks/_архив
EOF

check 'задача осталась на месте' 0 test -f tasks/009_все-закрыты/задача.md <<'EOF'
EOF

finish
