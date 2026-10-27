import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Адаптер плагина sae-claude-plugin для VeAI CLI.
 *
 * Сканирует манифесты подкоманд plugins/<подплагин>/skills/<скилл>/commands.json из
 * установленной копии плагина и регистрирует slash-команды с автодополнением. Новый подплагин
 * или подкоманда добавляются в плагин — здесь ничего править не нужно: список
 * читается заново при каждом старте.
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

// Копии плагина рядом с этим адаптером: адаптер ставится симлинком из
// репозитория плагина, поэтому его собственный реальный путь ведёт к корню.
// Это главный способ — без установленного Claude Code.
function repoRootBesideAdapter(): string | null {
  try {
    const self = fs.realpathSync(fileURLToPath(import.meta.url));
    // .../adapters/veai/sae-task/index.ts -> корень репозитория
    const root = path.resolve(path.dirname(self), "..", "..", "..");
    return fs.existsSync(path.join(root, ".claude-plugin", "marketplace.json")) ? root : null;
  } catch {
    return null;
  }
}

// Манифесты одного корня плагина: новая структура plugins/<подплагин>/skills/<скилл>,
// запасная старая skills/<скилл> (версии до 0.3.0).
function manifestDirsIn(root: string): string[] {
  const dirs: string[] = [];
  const layouts = [
    path.join(root, "plugins"), // новая структура
    root, // старая структура: skills прямо в корне
  ];
  for (const pluginsRoot of layouts) {
    try {
      for (const plugin of fs.readdirSync(pluginsRoot)) {
        const skillsRoot = path.join(pluginsRoot, plugin, "skills");
        try {
          for (const skill of fs.readdirSync(skillsRoot)) {
            const dir = path.join(skillsRoot, skill);
            if (isSkillDir(dir) && fs.existsSync(path.join(dir, "commands.json"))) {
              dirs.push(dir);
            }
          }
        } catch {}
      }
    } catch {}
  }
  return dirs;
}

function findManifestDirs(): string[] {
  const home = os.homedir();

  const fromEnv = process.env.SAE_TASK_PLUGIN_DIR;
  if (fromEnv) {
    const dirs = manifestDirsIn(fromEnv);
    if (dirs.length > 0) return dirs;
  }

  const besideAdapter = repoRootBesideAdapter();
  if (besideAdapter) {
    const dirs = manifestDirsIn(besideAdapter);
    if (dirs.length > 0) return dirs;
  }

  const roots: string[] = [];

  // Клоны плагина, установленные как marketplace в Claude Code.
  const marketplaces = path.join(home, ".claude", "plugins", "marketplaces");
  try {
    for (const entry of fs.readdirSync(marketplaces)) {
      roots.push(path.join(marketplaces, entry));
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
          roots.push(path.join(versions, version));
        }
      }
    }
  } catch {}

  for (const root of roots) {
    const dirs = manifestDirsIn(root);
    if (dirs.length > 0) return dirs;
  }
  return [];
}

function readManifest(skillDir: string): Manifest | null {
  try {
    const raw = fs.readFileSync(path.join(skillDir, "commands.json"), "utf8");
    const parsed = JSON.parse(raw) as Manifest;
    if (!parsed || typeof parsed.skill !== "string" || !Array.isArray(parsed.commands)) return null;
    return parsed;
  } catch {
    return null;
  }
}

export default function (pi: ExtensionAPI) {
  const manifests = findManifestDirs()
    .map(readManifest)
    .filter((m): m is Manifest => m !== null);

  if (manifests.length === 0) {
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

  for (const manifest of manifests) {
    const skill = manifest.skill;
    const subs = manifest.commands.filter((c) => c && typeof c.name === "string");

    // Главная команда: /sae:<скилл> <подкоманда> [аргументы] — подсказки подкоманд.
    pi.registerCommand(`sae:${skill}`, {
      description: `задачи sae (${subs.length} подкоманд; плагин: ${skill})`,
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
        await pi.sendUserMessage(`/sae:${skill} ${args}`.trim());
      },
    });

    // Короткие формы: /sae:task:next и т.д. — та же диспетчеризация.
    for (const c of subs) {
      pi.registerCommand(`sae:${skill}:${c.name}`, {
        description: `${manifest.invoke} ${c.name} — ${c.description ?? ""}`.trim(),
        getArgumentCompletions: c.args
          ? () => [{ value: c.args!, label: c.args!, description: c.description ?? "" }]
          : undefined,
        handler: async (args: string) => {
          await pi.sendUserMessage(`/sae:${skill} ${c.name} ${args}`.trim());
        },
      });
    }
  }
}
