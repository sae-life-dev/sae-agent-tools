import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Адаптер плагина sae-claude-plugin для VeAI CLI.
 *
 * Читает skills/task/commands.json из установленного клона плагина и регистрирует
 * slash-команды с автодополнением. Подкоманды добавляются в плагин — здесь ничего
 * править не нужно: список читается заново при каждом старте.
 */

interface Subcommand {
  name: string;
  args?: string;
  description?: string;
}

interface Manifest {
  skill: string;
  invoke: string;
  commands: Subcommand[];
}

function isSkillDir(dir: string): boolean {
  try {
    return fs.existsSync(path.join(dir, "scripts", "lib.sh"));
  } catch {
    return false;
  }
}

// Ядро рядом с этим адаптером: адаптер ставится симлинком из репозитория
// плагина, поэтому его собственный реальный путь ведёт к skills/task.
// Это главный способ — без установленного Claude Code.
function coreBesideAdapter(skillName: string): string | null {
  try {
    const self = fs.realpathSync(fileURLToPath(import.meta.url));
    const repoRoot = path.resolve(path.dirname(self), "..", "..", "..");
    const dir = path.join(repoRoot, "skills", skillName);
    return isSkillDir(dir) ? dir : null;
  } catch {
    return null;
  }
}

function findSkillDir(skillName: string): string | null {
  const home = os.homedir();

  const fromEnv = process.env.SAE_TASK_PLUGIN_DIR;
  if (fromEnv && isSkillDir(fromEnv)) return fromEnv;

  const besideAdapter = coreBesideAdapter(skillName);
  if (besideAdapter) return besideAdapter;

  const candidates: string[] = [];

  // Клоны плагина, установленные как marketplace в Claude Code.
  const marketplaces = path.join(home, ".claude", "plugins", "marketplaces");
  try {
    for (const entry of fs.readdirSync(marketplaces)) {
      candidates.push(path.join(marketplaces, entry, "skills", skillName));
    }
  } catch {}

  // Кэш установленных версий плагина.
  const cache = path.join(home, ".claude", "plugins", "cache");
  try {
    for (const marketplace of fs.readdirSync(cache)) {
      const versionsRoot = path.join(cache, marketplace);
      for (const plugin of fs.readdirSync(versionsRoot)) {
        const versions = path.join(versionsRoot, plugin);
        for (const version of fs.readdirSync(versions)) {
          candidates.push(path.join(versions, version, "skills", skillName));
        }
      }
    }
  } catch {}

  // Первая копия с commands.json — рабочая (новая версия плагина);
  // без манифеста — старая версия, берём как запасной вариант.
  let fallback: string | null = null;
  for (const dir of candidates) {
    if (!isSkillDir(dir)) continue;
    if (fs.existsSync(path.join(dir, "commands.json"))) return dir;
    fallback ??= dir;
  }
  return fallback;
}

function readManifest(skillDir: string): Manifest | null {
  try {
    const raw = fs.readFileSync(path.join(skillDir, "commands.json"), "utf8");
    const parsed = JSON.parse(raw) as Manifest;
    if (!parsed || !Array.isArray(parsed.commands)) return null;
    return parsed;
  } catch {
    return null;
  }
}

export default function (pi: ExtensionAPI) {
  const skillDir = findSkillDir("task");
  const manifest = skillDir ? readManifest(skillDir) : null;

  if (!manifest) {
    // Плагин не найден или устарел: команда-проходняк без подсказок,
    // чтобы ввод "/sae:task ..." продолжал работать как обычный текст.
    pi.registerCommand("sae:task", {
      description:
        "sae-claude-plugin не найден: команды скилла task недоступны (SAE_TASK_PLUGIN_DIR?)",
      handler: async (args) => {
        await pi.sendUserMessage(`/sae:task ${args}`.trim());
      },
    });
    return;
  }

  const subs = manifest.commands.filter((c) => c && typeof c.name === "string");

  // Главная команда: /sae:task <подкоманда> [аргументы] — подсказки подкоманд.
  pi.registerCommand("sae:task", {
    description: `задачи sae (${subs.length} подкоманд; плагин: ${path.basename(path.dirname(skillDir))})`,
    getArgumentCompletions: (argumentPrefix: string) => {
      const first = argumentPrefix.trim().split(/\s+/)[0] ?? "";
      return subs
        .filter((c) => c.name.startsWith(first))
        .map((c) => ({
          value: c.name,
          label: `${c.name}${c.args ? " " + c.args : ""}`,
          description: c.description ?? "",
        }));
    },
    handler: async (args: string) => {
      await pi.sendUserMessage(`/sae:task ${args}`.trim());
    },
  });

  // Короткие формы: /sae:task:next и т.д. — та же диспетчеризация.
  for (const c of subs) {
    pi.registerCommand(`sae:task:${c.name}`, {
      description: `${manifest.invoke} ${c.name} — ${c.description ?? ""}`.trim(),
      getArgumentCompletions: c.args
        ? () => [{ value: c.args!, label: c.args!, description: c.description ?? "" }]
        : undefined,
      handler: async (args: string) => {
        await pi.sendUserMessage(`/sae:task ${c.name} ${args}`.trim());
      },
    });
  }
}
