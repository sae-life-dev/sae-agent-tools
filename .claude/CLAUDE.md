# sae-claude-plugin

## Версия плагина

- При каждом изменении `skills/` или `.claude-plugin/` поднимать `version` в
  `.claude-plugin/plugin.json`. Установленные копии лежат в кэше по версии
  (`…/sae/<version>/`) и без её подъёма не обновятся.
- Поднимать до коммита, в том же коммите, что и изменение.
- `tests/`, `.claude/` и прочая документация подъёма не требуют.
- Проверка: `sh tests/check_version.sh` — сравнивает с последним коммитом, где менялась `version`,
  и печатает `WARN version`, если файлы плагина изменились, а версия нет. Её же вызывает `run.sh`.

## Проверки

Перед коммитом — `sh tests/run.sh`: `claude plugin validate --strict` (marketplace.json и
plugin.json), проверка версии и тесты скриптов `plugins/task/skills/task/scripts/` на копиях `tests/fixtures/`.
Код выхода 0 — всё прошло; итог в строке `TOTAL`.

Этот файл лежит в `.claude/`, а не в корне: корень репозитория — корень плагина, и
`CLAUDE.md` там `validate --strict` считает ошибкой.
