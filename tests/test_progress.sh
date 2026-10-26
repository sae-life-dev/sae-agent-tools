#!/bin/sh
# test_progress.sh — тесты progress.sh: состояния подзадач, «что дальше» и ошибки аргументов.
. "$(dirname "$0")/lib.sh"

progress() {
  sh "$scripts/progress.sh" "$@"
}

fresh

# Успех.

check 'в работе: следующий шаг' 0 progress tasks/006_в-работе <<'EOF'
PROGRESS <ROOT>/tasks/006_в-работе
П1 done steps=2/2 checks=1/1 deps=— blocked=no file=01_первая.md
П2 open steps=1/3 checks=0/2 deps=П1 blocked=no file=02_вторая.md
П3 open steps=0/2 checks=0/1 deps=П2 blocked=yes file=03_третья.md
next=П2 step=2
EOF

check 'все шаги отмечены: пора закрыть' 0 progress tasks/007_пора-закрыть <<'EOF'
PROGRESS <ROOT>/tasks/007_пора-закрыть
П1 open steps=2/2 checks=0/2 deps=— blocked=no file=01_первая.md
next=П1 close
EOF

check 'взять нечего' 0 progress tasks/008_взять-нечего <<'EOF'
PROGRESS <ROOT>/tasks/008_взять-нечего
П1 draft steps=0/0 checks=0/0 deps=— blocked=no file=01_первая.md
П2 open steps=0/1 checks=0/1 deps=П1 blocked=yes file=02_вторая.md
next=none
EOF

check 'все закрыты' 0 progress tasks/009_все-закрыты <<'EOF'
PROGRESS <ROOT>/tasks/009_все-закрыты
П1 done steps=1/1 checks=1/1 deps=— blocked=no file=01_первая.md
П2 done steps=1/1 checks=1/1 deps=П1 blocked=no file=02_вторая.md
all=done
EOF

check 'сломанные подзадачи' 0 progress tasks/010_сломанные <<'EOF'
PROGRESS <ROOT>/tasks/010_сломанные
П1 draft steps=0/1 checks=0/0 deps=— blocked=no file=01_черновик.md
П2 nosteps steps=0/0 checks=0/1 deps=— blocked=no file=02_без-шагов.md
П3 badsteps steps=0/2 checks=0/1 deps=— blocked=no line=11 file=03_шаги-с-пропуском.md
П4 dup steps=0/1 checks=0/1 deps=— blocked=no file=04_двойная-а.md
П4 dup steps=0/1 checks=0/1 deps=— blocked=no file=04_двойная-б.md
П6 open steps=0/1 checks=0/1 deps=— blocked=no file=06_старое-название.md
П7 open steps=0/1 checks=0/1 deps=— blocked=no file=07_лишняя.md
next=П6 step=1
EOF

check 'подзадач нет' 0 progress tasks/005_план <<'EOF'
NO_SUBTASKS <ROOT>/tasks/005_план
hint=анализ есть, файлов подзадач нет: разбей по steps/split.md (меню «Разбивка есть, подзадач нет»)
EOF

# Ошибки.

check 'без аргумента' 2 progress <<'EOF'
NO_ARG
EOF

check 'лишний аргумент' 2 progress tasks/006_в-работе лишний <<'EOF'
BAD_ARG лишний
EOF

check 'нет папки' 3 progress tasks/999_нет <<'EOF'
NO_DIR <ROOT>/tasks/999_нет
EOF

check 'файл вместо папки' 3 progress tasks/README.md <<'EOF'
NOT_DIR <ROOT>/tasks/README.md
EOF

check 'не задача' 3 progress tasks/014_без-описания <<'EOF'
NOT_TASK <ROOT>/tasks/014_без-описания
EOF

: >tasks/005_план/подзадачи
check 'подзадачи — файл' 3 progress tasks/005_план <<'EOF'
NOT_DIR <ROOT>/tasks/005_план/подзадачи
EOF

finish
