#!/bin/sh
# test_locate.sh — тесты locate.sh: поиск по номеру и по пути, состояния задачи, ошибки
# аргумента и настроек проекта.
. "$(dirname "$0")/lib.sh"

locate() {
  sh "$scripts/locate.sh" "$@"
}

fresh

# Успех: по номеру.

check 'номер 001: пустая задача' 0 locate 001 <<'EOF'
FOUND <ROOT>/tasks/001_пустая
task=empty
analysis=none
archived=no
jira=none
materials=none
EOF

check 'номер 1 без нулей — та же задача' 0 locate 1 <<'EOF'
FOUND <ROOT>/tasks/001_пустая
task=empty
analysis=none
archived=no
jira=none
materials=none
EOF

check 'номер 002: задача без анализа' 0 locate 002 <<'EOF'
FOUND <ROOT>/tasks/002_без-анализа
task=filled
analysis=none
archived=no
jira=none
materials=none
EOF

check 'номер 004: задача с анализом' 0 locate 004 <<'EOF'
FOUND <ROOT>/tasks/004_без-разбивки
task=filled
analysis=exists
archived=no
jira=none
materials=none
EOF

check 'номер 016: пустой анализ.md — как нет анализа' 0 locate 016 <<'EOF'
FOUND <ROOT>/tasks/016_пустой-анализ
task=filled
analysis=none
archived=no
jira=none
materials=none
EOF

check 'номер 017: пустой раздел «Как пойму, что готово»' 0 locate 017 <<'EOF'
FOUND <ROOT>/tasks/017_без-признаков
task=filled
done_criteria=empty
analysis=none
archived=no
jira=none
materials=none
EOF

check 'номер 014: нет задача.md' 0 locate 014 <<'EOF'
FOUND <ROOT>/tasks/014_без-описания
task=missing
analysis=none
archived=no
jira=none
materials=none
EOF

check 'номер 020: задача в архиве' 0 locate 020 <<'EOF'
FOUND <ROOT>/tasks/_архив/020_закрытая
task=filled
analysis=none
archived=yes
jira=none
materials=none
EOF

# Успех: по пути.

check 'путь относительный' 0 locate tasks/006_в-работе <<'EOF'
FOUND <ROOT>/tasks/006_в-работе
task=filled
analysis=exists
archived=no
jira=none
materials=none
EOF

check 'путь с ./' 0 locate ./tasks/001_пустая <<'EOF'
FOUND <ROOT>/tasks/001_пустая
task=empty
analysis=none
archived=no
jira=none
materials=none
EOF

check 'путь абсолютный в архив' 0 locate "$root/tasks/_архив/020_закрытая" <<'EOF'
FOUND <ROOT>/tasks/_архив/020_закрытая
task=filled
analysis=none
archived=yes
jira=none
materials=none
EOF

# Ошибки аргумента и поиска.

check 'нет аргумента' 2 locate <<'EOF'
NO_ARG
EOF

check 'пустой аргумент' 2 locate '' <<'EOF'
NO_ARG
EOF

check 'номера нет' 3 locate 999 <<'EOF'
NOT_FOUND 999
tasks.root=<ROOT>/tasks
EOF

check 'номер у двух задач' 4 locate 015 <<'EOF'
AMBIGUOUS 015
<ROOT>/tasks/015_а
<ROOT>/tasks/015_б
EOF

check 'путь не существует' 3 locate tasks/нет-такой <<'EOF'
NO_DIR <ROOT>/tasks/нет-такой
EOF

check 'путь — файл, не папка' 3 locate tasks/README.md <<'EOF'
NOT_DIR <ROOT>/tasks/README.md
EOF

check 'путь к папке без задача.md' 3 locate tasks/014_без-описания <<'EOF'
NOT_TASK <ROOT>/tasks/014_без-описания
EOF

printf ' \n\t\n\n' >tasks/016_пустой-анализ/анализ.md
check 'анализ.md из одних пробелов — как нет анализа' 0 locate 016 <<'EOF'
FOUND <ROOT>/tasks/016_пустой-анализ
task=filled
analysis=none
archived=no
jira=none
materials=none
EOF

printf '%s\n' '# Задача: Без признаков' '' '## Что хочу' '' 'Описание.' >tasks/017_без-признаков/задача.md
check 'нет раздела «Как пойму, что готово» — как пустой' 0 locate 017 <<'EOF'
FOUND <ROOT>/tasks/017_без-признаков
task=filled
done_criteria=empty
analysis=none
archived=no
jira=none
materials=none
EOF

printf '%s\n' '# Задача' '## Как пойму, что готово' '### Проверка' '- Признак.' '## Что хочу' >tasks/017_без-признаков/задача.md
check 'признаки под подзаголовком ### — строки нет' 0 locate 017 <<'EOF'
FOUND <ROOT>/tasks/017_без-признаков
task=filled
analysis=none
archived=no
jira=none
materials=none
EOF

# Ошибки настроек проекта: каждая — на своей копии.

fresh
rm .claude/sae.local.md
check 'нет файла настроек' 3 locate 001 <<'EOF'
NO_CONFIG <ROOT>/.claude/sae.local.md
EOF

fresh
printf '%s\n' '---' 'other: x' '---' >.claude/sae.local.md
check 'в настройках нет task.dir' 3 locate 001 <<'EOF'
CONFIG_NO_KEY <ROOT>/.claude/sae.local.md task.dir
EOF

fresh
printf '%s\n' '---' 'task.dir: нет-такой' '---' >.claude/sae.local.md
check 'папки задач нет' 3 locate 001 <<'EOF'
TASKS_MISSING <ROOT>/нет-такой
EOF

fresh
printf '%s\n' '# Без шапки' >tasks/README.md
check 'папка задач не помечена' 3 locate 001 <<'EOF'
TASKS_UNMARKED <ROOT>/tasks
EOF

finish
