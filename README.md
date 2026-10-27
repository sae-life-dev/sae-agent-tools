# sae-agent-tools

Маркетплейс независимых подплагинов для ИИ-агентов (sae-life-dev). Подплагин `task` —
задачи в папках проекта (init / new / collect-jira / analyze / split / next).

## Структура: маркетплейс + подплагины

```
.claude-plugin/marketplace.json      # каталог маркетплейса
plugins/<подплагин>/                 # независимый подплагин
  .claude-plugin/plugin.json         # своя версия и имя
  skills/<скилл>/                    # скилл: скрипты, steps/, templates, commands.json
adapters/                            # тонкие адаптеры под клиентов (без бизнес-логики)
tests/                               # тесты ядра: скрипты на копиях tests/fixtures/
```

Новый подплагин — новая папка `plugins/<имя>/` со своим `plugin.json` и скиллом,
плюс строка в `marketplace.json`. Своя версия, выборочная установка, независимые релизы.

## Архитектура: ядро + тонкие адаптеры

- **Ядро** — скиллы подплагинов: скрипты (POSIX sh), методички (`steps/`, `SKILL.md`),
  шаблоны, манифест подкоманд `commands.json`. Не зависит от агента.
  Состояние задач — файлы на диске, конфиг — `sae.local.md` в корне проекта
  (env `SAE_CONFIG`, см. `plugins/task/skills/task/scripts/lib.sh`).
- **Адаптеры** — `adapters/`: тонкая обвязка под конкретного клиента, только
  UI-интеграция, без бизнес-логики. Каждый адаптер сканирует
  `plugins/*/skills/*/commands.json` — новый подплагин или подкоманда
  подхватывается без правки адаптера.

Подкоманды правятся в одном месте: `plugins/<подплагин>/skills/<скилл>/commands.json`,
после чего `sh scripts/sync-manifest.sh` из папки скилла перегенерирует frontmatter
`SKILL.md`.

## Подключение к агентам

| Агент | Как подключить |
| --- | --- |
| Claude Code | `/plugin marketplace add sae-life-dev/sae-agent-tools`, затем `/plugin install sae-task@sae-plugins` — скилл и его подкоманды нативно |
| VeAI CLI | `sh adapters/veai/install.sh` — ставит расширение в `~/.veai/extensions/sae-task` (симлинк на репо). Даёт команды `/sae:task <подкоманда>` и `/sae:task:<подкоманда>` с автодополнением |
| Прочие агенты | Скрипты и методички — напрямую: любому агенту достаточно уметь запускать sh и читать markdown |

Env `SAE_TASK_PLUGIN_DIR` (путь к корню плагина) переопределяет поиск ядра
для адаптеров — полезно при нестандартной установке.
