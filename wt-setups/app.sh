#!/usr/bin/env bash
# Smart Wallet monorepo (`app`) worktree setup. Run automatically by `wt create`.
#
# - Symlinks the main repository's node_modules
# - Copies required gitignored certificates
# - Assigns stable, worktree-specific Hades and Zeus ports
# - Patches all relevant runtime and Nx configuration
# - Generates the Prisma client
#
# Rerun manually from inside a worktree:
#   bash /path/to/cli-utils/wt-setups/app.sh

set -euo pipefail

COMMON_DIR="$(git rev-parse --git-common-dir)"
MAIN_DIR="$(cd "$(dirname "$COMMON_DIR")" && pwd)"
WORKTREE_DIR="$(git rev-parse --show-toplevel)"
CONFIG_FILE="$WORKTREE_DIR/.worktree-config"

if [[ "$MAIN_DIR" == "$WORKTREE_DIR" ]]; then
  echo "Not in a worktree, nothing to do."
  exit 0
fi

echo "Setting up worktree: $WORKTREE_DIR"

# ── Helpers ──────────────────────────────────────────────────────────────────

mark_assume_unchanged() {
  local file="$1"

  if git -C "$WORKTREE_DIR" ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    git -C "$WORKTREE_DIR" update-index --assume-unchanged "$file"
  fi
}

ports_reserved_by_another_worktree() {
  local hades_port="$1"
  local zeus_port="$2"
  local other_config other_hades other_zeus

  while IFS= read -r other_config; do
    [[ "$other_config" == "$CONFIG_FILE" ]] && continue

    other_hades="$(
      sed -n 's/^HADES_PORT=//p' "$other_config" 2>/dev/null | head -1
    )"
    other_zeus="$(
      sed -n 's/^ZEUS_PORT=//p' "$other_config" 2>/dev/null | head -1
    )"

    if [[ "$other_hades" == "$hades_port" || "$other_zeus" == "$zeus_port" ]]; then
      return 0
    fi
  done < <(
    find "$MAIN_DIR/${WT_SUBDIR:-.claude/worktrees}" \
      -mindepth 2 \
      -maxdepth 2 \
      -name .worktree-config \
      -type f \
      2>/dev/null
  )

  return 1
}

# ── node_modules symlink ─────────────────────────────────────────────────────

if [[ -L "$WORKTREE_DIR/node_modules" ]]; then
  echo "✓ node_modules already symlinked"
elif [[ -e "$WORKTREE_DIR/node_modules" ]]; then
  echo "✓ node_modules already present"
else
  if [[ ! -d "$MAIN_DIR/node_modules" ]]; then
    echo "✗ main node_modules not found: $MAIN_DIR/node_modules" >&2
    echo "  Run 'pnpm install' in the main repository first." >&2
    exit 1
  fi

  ln -s "$MAIN_DIR/node_modules" "$WORKTREE_DIR/node_modules"
  echo "✓ node_modules symlinked"
fi

# ── gitignored files ─────────────────────────────────────────────────────────

ROOT_CERT_SOURCE="$MAIN_DIR/libs/hades/shared/assets/src/lib/config/root-cert.pem"
ROOT_CERT_TARGET="$WORKTREE_DIR/libs/hades/shared/assets/src/lib/config/root-cert.pem"

mkdir -p "$(dirname "$ROOT_CERT_TARGET")"

if [[ -f "$ROOT_CERT_SOURCE" ]]; then
  cp "$ROOT_CERT_SOURCE" "$ROOT_CERT_TARGET"
  echo "✓ root-cert.pem"
else
  echo "✗ root-cert.pem not found in main repository, skipping"
fi

CERTIFICATES_SOURCE="$MAIN_DIR/certificates"
CERTIFICATES_TARGET="$WORKTREE_DIR/certificates"

if [[ -d "$CERTIFICATES_SOURCE" ]]; then
  mkdir -p "$CERTIFICATES_TARGET"
  rsync -a --delete "$CERTIFICATES_SOURCE/" "$CERTIFICATES_TARGET/"
  echo "✓ certificates/"
else
  echo "✗ certificates/ not found in main repository, skipping"
fi

# ── Port assignment ──────────────────────────────────────────────────────────

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"

  if [[ ! "${HADES_PORT:-}" =~ ^[0-9]+$ || ! "${ZEUS_PORT:-}" =~ ^[0-9]+$ ]]; then
    echo "Invalid port configuration in $CONFIG_FILE" >&2
    exit 1
  fi

  echo "✓ ports already assigned — hades: $HADES_PORT  zeus: $ZEUS_PORT"
else
  BRANCH="$(git -C "$WORKTREE_DIR" rev-parse --abbrev-ref HEAD)"
  TICKET_NUM="$(printf '%s' "$BRANCH" | grep -oE '[0-9]+' | head -1 || true)"

  if [[ -z "$TICKET_NUM" ]]; then
    echo "⚠ Could not extract a ticket number from '$BRANCH'; using offset 1"
    TICKET_NUM=0
  fi

  INITIAL_OFFSET=$(( (TICKET_NUM % 89) + 1 ))
  OFFSET="$INITIAL_OFFSET"
  ATTEMPTS=0

  while (( ATTEMPTS < 89 )); do
    HADES_PORT=$(( 8080 + OFFSET ))
    ZEUS_PORT=$(( 4203 + OFFSET ))

    if ! ports_reserved_by_another_worktree "$HADES_PORT" "$ZEUS_PORT"; then
      break
    fi

    OFFSET=$(( (OFFSET % 89) + 1 ))
    ATTEMPTS=$(( ATTEMPTS + 1 ))
  done

  if (( ATTEMPTS >= 89 )); then
    echo "Could not find an unused worktree port pair." >&2
    exit 1
  fi

  cat >"$CONFIG_FILE" <<EOF
HADES_PORT=$HADES_PORT
ZEUS_PORT=$ZEUS_PORT
EOF

  echo "✓ ports assigned — hades: $HADES_PORT  zeus: $ZEUS_PORT  (offset: $OFFSET)"
fi

# ── Patch worktree configuration ─────────────────────────────────────────────
#
# This intentionally runs every time.
#
# Previously, patching only ran when .worktree-config was first created.
# Therefore, rerunning setup could report the correct ports while leaving
# project.json, appdiscovery.json and appconfig.json on their default ports.

ZEUS_PROJECT_REL="apps/zeus/project.json"
APPDISCOVERY_REL="libs/zeus/shared/assets/src/assets/appdiscovery.json"
APPCONFIG_REL="libs/hades/shared/assets/src/lib/config/appconfig.json"

ZEUS_PROJECT="$WORKTREE_DIR/$ZEUS_PROJECT_REL"
APPDISCOVERY="$WORKTREE_DIR/$APPDISCOVERY_REL"
APPCONFIG="$WORKTREE_DIR/$APPCONFIG_REL"

python3 - \
  "$ZEUS_PROJECT" \
  "$APPDISCOVERY" \
  "$APPCONFIG" \
  "$HADES_PORT" \
  "$ZEUS_PORT" <<'PY'
import json
import re
import sys
from pathlib import Path
from typing import Any

project_path = Path(sys.argv[1])
discovery_path = Path(sys.argv[2])
appconfig_path = Path(sys.argv[3])
hades_port = int(sys.argv[4])
zeus_port = int(sys.argv[5])


def read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise SystemExit(f"Missing required file: {path}")

    with path.open(encoding="utf-8") as file:
        return json.load(file)


def write_json(path: Path, value: dict[str, Any]) -> None:
    with path.open("w", encoding="utf-8") as file:
        json.dump(value, file, indent=2, ensure_ascii=False)
        file.write("\n")


# ── apps/zeus/project.json ───────────────────────────────────────────────────

project = read_json(project_path)
targets = project.setdefault("targets", {})

serve = targets.get("serve")
if not isinstance(serve, dict):
    raise SystemExit("Could not find targets.serve in apps/zeus/project.json")

serve_options = serve.setdefault("options", {})
serve_options["port"] = zeus_port

serve_https = targets.get("serve-https")
if not isinstance(serve_https, dict):
    raise SystemExit("Could not find targets.serve-https in apps/zeus/project.json")


def patch_serve_https_commands(commands: list[Any]) -> list[Any]:
    patched: list[Any] = []
    adb_reverse_index = 0

    for command in commands:
        if not isinstance(command, str):
            patched.append(command)
            continue

        # The serve-https sed commands contain patterns such as (:8080).
        # Point those patterns at this worktree's assigned Hades port.
        command = re.sub(
            r"\(:\d+\)",
            f"(:{hades_port})",
            command,
        )

        if command.strip().startswith("adb reverse tcp:"):
            if adb_reverse_index == 0:
                command = (
                    f"adb reverse tcp:{zeus_port} tcp:{zeus_port}"
                )
            else:
                command = (
                    f"adb reverse tcp:{hades_port} tcp:{hades_port}"
                )

            adb_reverse_index += 1

        patched.append(command)

    return patched


serve_https_options = serve_https.get("options", {})
if isinstance(serve_https_options.get("commands"), list):
    serve_https_options["commands"] = patch_serve_https_commands(
        serve_https_options["commands"]
    )

configurations = serve_https.get("configurations", {})
if isinstance(configurations, dict):
    for configuration in configurations.values():
        if not isinstance(configuration, dict):
            continue

        commands = configuration.get("commands")
        if isinstance(commands, list):
            configuration["commands"] = patch_serve_https_commands(commands)

# Keep the static CI server internally consistent as well.
serve_static = targets.get("serve-static-ci")
if isinstance(serve_static, dict):
    static_options = serve_static.get("options", {})
    static_commands = static_options.get("commands")

    if isinstance(static_commands, list):
        patched_static_commands: list[Any] = []

        for command in static_commands:
            if isinstance(command, str):
                command = re.sub(
                    r"(?<=\s-p\s)\d+",
                    str(zeus_port),
                    command,
                )
                command = re.sub(
                    r"localhost:\d+",
                    f"localhost:{zeus_port}",
                    command,
                )

            patched_static_commands.append(command)

        static_options["commands"] = patched_static_commands

write_json(project_path, project)

# ── appdiscovery.json ────────────────────────────────────────────────────────

discovery = read_json(discovery_path)
discovery["appConfigUrl"] = (
    f"https://localhost:{hades_port}/appconfig.json"
)
write_json(discovery_path, discovery)

# ── appconfig.json ───────────────────────────────────────────────────────────

appconfig = read_json(appconfig_path)
appconfig["hadesApiUrl"] = (
    f"https://localhost:{hades_port}/api/v1/"
)
appconfig["hadesApiUrl2"] = (
    f"https://localhost:{hades_port}/api/v2/"
)
write_json(appconfig_path, appconfig)
PY

mark_assume_unchanged "$ZEUS_PROJECT_REL"
mark_assume_unchanged "$APPDISCOVERY_REL"
mark_assume_unchanged "$APPCONFIG_REL"

echo "✓ patched apps/zeus/project.json"
echo "✓ patched appdiscovery.json"
echo "✓ patched appconfig.json"

# ── Verify patched values ────────────────────────────────────────────────────

python3 - \
  "$ZEUS_PROJECT" \
  "$APPDISCOVERY" \
  "$APPCONFIG" \
  "$HADES_PORT" \
  "$ZEUS_PORT" <<'PY'
import json
import sys
from pathlib import Path

project_path = Path(sys.argv[1])
discovery_path = Path(sys.argv[2])
appconfig_path = Path(sys.argv[3])
hades_port = int(sys.argv[4])
zeus_port = int(sys.argv[5])

project = json.loads(project_path.read_text(encoding="utf-8"))
discovery = json.loads(discovery_path.read_text(encoding="utf-8"))
appconfig = json.loads(appconfig_path.read_text(encoding="utf-8"))

actual_zeus_port = project["targets"]["serve"]["options"]["port"]
expected_discovery = f"https://localhost:{hades_port}/appconfig.json"
expected_api_v1 = f"https://localhost:{hades_port}/api/v1/"
expected_api_v2 = f"https://localhost:{hades_port}/api/v2/"

errors = []

if actual_zeus_port != zeus_port:
    errors.append(
        f"Zeus port is {actual_zeus_port}, expected {zeus_port}"
    )

if discovery.get("appConfigUrl") != expected_discovery:
    errors.append(
        "appConfigUrl is "
        f"{discovery.get('appConfigUrl')!r}, expected {expected_discovery!r}"
    )

if appconfig.get("hadesApiUrl") != expected_api_v1:
    errors.append(
        "hadesApiUrl is "
        f"{appconfig.get('hadesApiUrl')!r}, expected {expected_api_v1!r}"
    )

if appconfig.get("hadesApiUrl2") != expected_api_v2:
    errors.append(
        "hadesApiUrl2 is "
        f"{appconfig.get('hadesApiUrl2')!r}, expected {expected_api_v2!r}"
    )

if errors:
    print("Port patch verification failed:", file=sys.stderr)

    for error in errors:
        print(f"  - {error}", file=sys.stderr)

    raise SystemExit(1)

print(
    f"✓ verified ports — hades: {hades_port}  zeus: {zeus_port}"
)
PY

# ── Prisma client ────────────────────────────────────────────────────────────

echo "Generating Prisma client..."

if (
  cd "$WORKTREE_DIR" &&
  NX_ISOLATE_PLUGINS=false \
    npx nx run hades-shared-domain:generate-prisma-client
); then
  echo "✓ Prisma client"
else
  echo "✗ Prisma client generation failed" >&2
  exit 1
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo
echo "Done. To start the stack:"
echo "  Terminal 1 (hades):"
echo "    PORT=$HADES_PORT npx nx serve hades --configuration=development"
echo
echo "  Terminal 2 (zeus):"
echo "    npx nx run zeus:serve-https"
echo
echo "  Open:"
echo "    https://localhost:$ZEUS_PORT"
