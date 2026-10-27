#!/bin/sh
# next.sh <путь или номер> — роутер подкоманды next: находит задачу (те же правила, что
# locate.sh) и печатает маршрут — какое действие вести дальше по методичке steps/. Ничего
# не меняет. Чтобы агент без загруженного SKILL.md не блуждал: маршрут диктует скрипт.
# Первая строка вывода — итог: ROUTE <маршрут> либо код отказа locate.sh (NO_ARG,
# NOT_FOUND, AMBIGUOUS, NO_DIR, NOT_DIR, NOT_TASK, NO_CONFIG, …) как есть. После ROUTE —
# task=<папка>, hint=<что делать>; для маршрута work — следом вывод split.sh и progress.sh.
# Маршруты (по шагу 2 steps/next.md):
#   fill-task    — задача.md пустой, ключ Jira есть, не в архиве: веди steps/fill-task.md;
#   owner-fill   — задача.md пустой, ключа Jira нет: заполняет владелец;
#   task-missing — в папке нет задача.md;
#   archived     — задача закрыта и лежит в архиве;
#   collect      — анализа нет, а материалов нет или выгрузка не закончена:
#                  steps/collect-jira.md с шага 2;
#   analyze      — анализа нет, материалы есть: steps/analyze.md с шага 4;
#   work         — анализ есть: веди steps/next.md с шага 3 (сверка split.sh + progress.sh).
set -u
. "$(dirname "$0")/lib.sh"

if [ $# -lt 1 ] || [ -z "$1" ]; then
  say "NO_ARG"
  exit 2
fi
if [ $# -gt 1 ]; then
  say "BAD_ARG $2"
  exit 2
fi

dir=$(dirname "$0")
out=$(sh "$dir/locate.sh" "$1")
status=$?
if [ "$status" -ne 0 ]; then
  printf '%s\n' "$out"
  exit "$status"
fi

task=$(printf '%s\n' "$out" | sed -n 's/^FOUND //p')
tstate=$(printf '%s\n' "$out" | sed -n 's/^task=//p')
analysis=$(printf '%s\n' "$out" | sed -n 's/^analysis=//p')
archived=$(printf '%s\n' "$out" | sed -n 's/^archived=//p')
jira=$(printf '%s\n' "$out" | sed -n 's/^jira=//p')
materials=$(printf '%s\n' "$out" | sed -n 's/^materials=//p')

route=
hint=
if [ "$archived" = yes ]; then
  route=archived
  hint="задача закрыта и лежит в архиве; веди по steps/next.md (шаг «archived=yes»)"
elif [ "$tstate" = missing ]; then
  route=task-missing
  hint="в папке нет задача.md; файл сам не создавай — решает владелец"
elif [ "$tstate" = empty ] && [ "$jira" != none ]; then
  route=fill-task
  hint="задача.md пустой, ключ Jira есть: веди steps/fill-task.md (сначала спроси, кто заполняет)"
elif [ "$tstate" = empty ]; then
  route=owner-fill
  hint="задача.md пустой: сначала владелец заполняет «Что хочу» и «Как пойму, что готово» — $task/задача.md"
elif [ "$analysis" = none ] && [ "$jira" != none ] && [ "$materials" != done ]; then
  route=collect
  hint="анализа нет, материалов нет или выгрузка не закончена: steps/collect-jira.md с шага 2"
elif [ "$analysis" = none ]; then
  route=analyze
  hint="анализа нет: steps/analyze.md с шага 4"
else
  route=work
  hint="анализ есть: веди steps/next.md с шага 3 — сверка split.sh, затем progress.sh"
fi

say "ROUTE $route"
say "task=$task"
say "hint=$hint"

if [ "$route" = work ]; then
  sh "$dir/split.sh" "$task"
  sh "$dir/progress.sh" "$task"
fi
