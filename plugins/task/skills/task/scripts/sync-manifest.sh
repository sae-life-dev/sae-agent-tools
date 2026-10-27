#!/bin/sh
# sync-manifest.sh — единый источник правды по подкомандам: commands.json.
# Перегенерирует description и argument-hint в frontmatter SKILL.md из манифеста.
# Запуск: sh scripts/sync-manifest.sh  (из папки скилла или из корня репо).
# Нужен jq. Идемпотентен: без изменений файл не переписывает.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
skill_dir=$(CDPATH= cd -- "$here/.." && pwd)
SKILL="$skill_dir/SKILL.md"
MANIFEST="$skill_dir/commands.json"

command -v jq >/dev/null 2>&1 || {
  echo "нужен jq (brew install jq)" >&2
  exit 1
}

[ -f "$SKILL" ] || { echo "нет $SKILL" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "нет $MANIFEST" >&2; exit 1; }

description=$(jq -r '
  .summary + ": " +
  ([.commands[] | .name + (.args // "" | if length > 0 then " " + . else "" end)
    + " — " + (.description // "")] | join("; ")) + ". " +
  "Вызывать, когда просят " +
  ([.triggers[] | "«" + . + "»"] | join(", ")) + "."
' "$MANIFEST")
argument_hint=$(jq -r '[.commands[] | .name + (.args // "" | if length > 0 then " " + . else "" end)] | join(" | ")' "$MANIFEST")

tmp=$(mktemp "${TMPDIR:-/tmp}/sae-sync.XXXXXX") || exit 6
trap 'rm -f "$tmp"' EXIT

in_front=0
changed=0
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ---)
      printf '%s\n' "$line" >>"$tmp"
      if [ "$in_front" -eq 0 ]; then in_front=1; else in_front=0; fi
      ;;
    description:*)
      if [ "$in_front" -eq 1 ]; then
        printf 'description: "%s"\n' "$description" >>"$tmp"
        [ "$line" = "description: \"$description\"" ] || changed=1
      else
        printf '%s\n' "$line" >>"$tmp"
      fi
      ;;
    argument-hint:*)
      if [ "$in_front" -eq 1 ]; then
        printf 'argument-hint: "%s"\n' "$argument_hint" >>"$tmp"
        [ "$line" = "argument-hint: \"$argument_hint\"" ] || changed=1
      else
        printf '%s\n' "$line" >>"$tmp"
      fi
      ;;
    *)
      printf '%s\n' "$line" >>"$tmp"
      ;;
  esac
done <"$SKILL"

if [ "$changed" -eq 0 ]; then
  echo "OK: SKILL.md уже синхронен с commands.json"
  exit 0
fi

cat "$tmp" >"$SKILL"
echo "SKILL.md обновлён из commands.json"
