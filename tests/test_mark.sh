#!/bin/sh
# test_mark.sh — тесты mark.sh: отметка шага, закрытие подзадачи с признаками, что именно
# меняется в файле, и ошибки (файл не годится, не тот шаг, аргументы).
. "$(dirname "$0")/lib.sh"

mark() {
  sh "$scripts/mark.sh" "$@"
}

s006=tasks/006_в-работе/подзадачи
s007=tasks/007_пора-закрыть/подзадачи
s010=tasks/010_сломанные/подзадачи

# Отметка шага: успех и что поменялось в файле.

fresh
check 'отметить следующий шаг' 0 mark step $s006/02_вторая.md 2 <<'EOF'
MARKED <ROOT>/tasks/006_в-работе/подзадачи/02_вторая.md
step=2
steps=2/3
EOF

check 'в файле отмечен только шаг 2' 1 diff "$fixtures/$s006/02_вторая.md" $s006/02_вторая.md <<'EOF'
11c11
< - [ ] 2. Сделать второе — S
---
> - [x] 2. Сделать второе — S
EOF

# Закрытие: успех и что поменялось в файле.

fresh
check 'закрыть с обоими признаками' 0 mark done $s007/01_первая.md 1 2 <<'EOF'
CLOSED <ROOT>/tasks/007_пора-закрыть/подзадачи/01_первая.md
checks=2/2
EOF

check 'в файле status: done и оба признака' 1 diff "$fixtures/$s007/01_первая.md" $s007/01_первая.md <<'EOF'
3a4
> status: done
15,16c16,17
< - [ ] Первое сделано
< - [ ] Второе сделано
---
> - [x] Первое сделано
> - [x] Второе сделано
EOF

check 'после закрытия progress видит all=done' 0 sh "$scripts/progress.sh" tasks/007_пора-закрыть <<'EOF'
PROGRESS <ROOT>/tasks/007_пора-закрыть
П1 done steps=2/2 checks=2/2 deps=— blocked=no file=01_первая.md
all=done
EOF

fresh
check 'закрыть с одним признаком' 0 mark done $s007/01_первая.md 2 <<'EOF'
CLOSED <ROOT>/tasks/007_пора-закрыть/подзадачи/01_первая.md
checks=1/2
EOF

check 'в файле отмечен только признак 2' 1 diff "$fixtures/$s007/01_первая.md" $s007/01_первая.md <<'EOF'
3a4
> status: done
16c17
< - [ ] Второе сделано
---
> - [x] Второе сделано
EOF

# Ошибки: на одной копии, файлы не должны меняться.

fresh

check 'шаг не по порядку' 4 mark step $s006/02_вторая.md 3 <<'EOF'
NOT_NEXT 3
first=2
EOF

check 'шаг уже отмечен' 4 mark step $s006/02_вторая.md 1 <<'EOF'
ALREADY 1
EOF

check 'нет такого шага' 4 mark step $s006/02_вторая.md 4 <<'EOF'
NO_STEP 4
steps=3
EOF

check 'шаг 0' 4 mark step $s006/02_вторая.md 0 <<'EOF'
NO_STEP 0
steps=3
EOF

check 'подзадача уже закрыта' 4 mark step $s006/01_первая.md 1 <<'EOF'
ALREADY_DONE <ROOT>/tasks/006_в-работе/подзадачи/01_первая.md
EOF

check 'черновик' 4 mark step $s010/01_черновик.md 1 <<'EOF'
DRAFT <ROOT>/tasks/010_сломанные/подзадачи/01_черновик.md
EOF

check 'шагов нет' 4 mark step $s010/02_без-шагов.md 1 <<'EOF'
NO_STEPS <ROOT>/tasks/010_сломанные/подзадачи/02_без-шагов.md
EOF

check 'шаги с пропуском' 4 mark step $s010/03_шаги-с-пропуском.md 1 <<'EOF'
BAD_STEPS <ROOT>/tasks/010_сломанные/подзадачи/03_шаги-с-пропуском.md
line=11
EOF

check 'файл без шапки' 4 mark step $s010/05_чужая.md 1 <<'EOF'
NOT_SUBTASK <ROOT>/tasks/010_сломанные/подзадачи/05_чужая.md
EOF

check 'нет файла' 3 mark step $s006/09_нет.md 1 <<'EOF'
NO_FILE <ROOT>/tasks/006_в-работе/подзадачи/09_нет.md
EOF

check 'папка вместо файла' 3 mark step $s006 1 <<'EOF'
NOT_FILE <ROOT>/tasks/006_в-работе/подзадачи
EOF

check 'закрыть с неотмеченными шагами' 4 mark done $s006/02_вторая.md <<'EOF'
STEPS_OPEN <ROOT>/tasks/006_в-работе/подзадачи/02_вторая.md
first=2
EOF

check 'нет такого признака' 4 mark done $s007/01_первая.md 3 <<'EOF'
NO_CHECK 3
checks=2
EOF

check 'признак дважды' 2 mark done $s007/01_первая.md 1 1 <<'EOF'
DUP_ARG 1
EOF

check 'признак не число' 2 mark done $s007/01_первая.md x <<'EOF'
BAD_ARG x
EOF

check 'без аргументов' 2 mark <<'EOF'
NO_ARG
EOF

check 'без номера шага' 2 mark step $s006/02_вторая.md <<'EOF'
NO_ARG
EOF

check 'неизвестное действие' 2 mark undo $s006/02_вторая.md 2 <<'EOF'
BAD_ARG undo
EOF

check 'номер шага не число' 2 mark step $s006/02_вторая.md x <<'EOF'
BAD_ARG x
EOF

check 'два номера шага' 2 mark step $s006/02_вторая.md 2 3 <<'EOF'
BAD_ARG 3
EOF

check 'после ошибок файлы не изменились' 0 diff -r -x .DS_Store "$fixtures/tasks" tasks <<'EOF'
EOF

finish
