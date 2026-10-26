# sae-claude-plugin

Скиллы командной работы для ИИ-агентов. Скилл `task` — задачи в папках проекта
(init / new / collect-jira / analyze / split / next).

Скилл агенто-нейтрален: скрипты — POSIX sh, инструкции — обычный markdown,
конфиг — `sae.local.md` в корне проекта (env `SAE_CONFIG`, см. `skills/task/scripts/lib.sh`).

## Подключение к агентам

| Агент | Как подключить |
| --- | --- |
| Claude Code | Установка плагином из marketplace / git (как сейчас, см. `.claude-plugin/plugin.json`) |
| Veai (OpenIDE) | `ln -s <путь-к-репо>/skills/task <проект>/.veai/skills/task` — скилл станет родным через механизм навыков |
| Агенты с поддержкой MCP | Через MCP-обёртку над скриптами (скоро, раздел `server/`) |
