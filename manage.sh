#!/bin/bash
# Private Marketplace Manager - Manage plugins in a private Claude Code marketplace
#
# Usage:
#   bash manage.sh init <name> --owner "Name" [--email "x"] [--description "x"]
#   bash manage.sh add <name> --description "x" [--category "x"] [--author "x"]
#   bash manage.sh import <skill-dir> [--as <plugin-name>]
#   bash manage.sh remove <name>
#   bash manage.sh list
#   bash manage.sh build
#   bash manage.sh help

set -e

# ============================================================
# Paths
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MARKETPLACE_JSON="$SCRIPT_DIR/.claude-plugin/marketplace.json"
PLUGINS_DIR="$SCRIPT_DIR/plugins"

# ============================================================
# Utility functions
# ============================================================
info()  { echo -e "\033[0;32m✓\033[0m $1"; }
warn()  { echo -e "\033[0;33m⚠\033[0m $1"; }
error() { echo -e "\033[0;31m✗\033[0m $1"; }

check_python3() {
    if ! command -v python3 &>/dev/null; then
        error "python3 is required but not found"
        exit 1
    fi
}

check_marketplace() {
    if [ ! -f "$MARKETPLACE_JSON" ]; then
        error "marketplace.json not found. Run 'manage.sh init' first."
        exit 1
    fi
}

# Extract a field from SKILL.md YAML frontmatter
extract_frontmatter_field() {
    local file="$1"
    local field="$2"
    SKILL_FILE="$file" FIELD="$field" python3 -c "
import re, os

with open(os.environ['SKILL_FILE']) as f:
    content = f.read()

m = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if not m:
    exit(1)

fm = m.group(1)
field = os.environ['FIELD']
lines = fm.split('\n')

for i, line in enumerate(lines):
    if line.startswith(field + ':'):
        val = line[len(field)+1:].strip()
        if val == '|' or val == '>':
            # Multi-line: collect indented lines
            parts = []
            for j in range(i+1, len(lines)):
                if lines[j].startswith('  '):
                    parts.append(lines[j].strip())
                else:
                    break
            print(' '.join(parts))
        else:
            print(val.strip('\"').strip(\"'\"))
        exit(0)
exit(1)
" 2>/dev/null
}

# ============================================================
# init - Initialize marketplace.json
# ============================================================
cmd_init() {
    local name=""
    local owner=""
    local email=""
    local description="Private Claude Code plugin marketplace"

    # First positional arg is name
    if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
        name="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --owner)      owner="$2"; shift 2 ;;
            --email)      email="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ -z "$name" ]; then
        error "Usage: manage.sh init <name> --owner \"Name\" [--email \"x\"] [--description \"x\"]"
        exit 1
    fi

    if [ -z "$owner" ]; then
        error "--owner is required"
        exit 1
    fi

    mkdir -p "$SCRIPT_DIR/.claude-plugin"
    mkdir -p "$PLUGINS_DIR"

    MP_NAME="$name" MP_DESC="$description" MP_OWNER="$owner" MP_EMAIL="$email" \
    MP_JSON="$MARKETPLACE_JSON" python3 -c "
import json, os
data = {
    '\$schema': 'https://anthropic.com/claude-code/marketplace.schema.json',
    'name': os.environ['MP_NAME'],
    'description': os.environ['MP_DESC'],
    'owner': {
        'name': os.environ['MP_OWNER'],
        'email': os.environ['MP_EMAIL']
    },
    'plugins': []
}
with open(os.environ['MP_JSON'], 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
"
    info "Initialized marketplace '$name'"
    echo "  Owner: $owner"
    [ -n "$email" ] && echo "  Email: $email"
    echo ""
    echo "Next: add plugins with 'manage.sh add' or 'manage.sh import'"
}

# ============================================================
# add - Create a new plugin skeleton
# ============================================================
cmd_add() {
    check_marketplace
    local name=""
    local description=""
    local category="development"
    local author=""

    if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
        name="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--description) description="$2"; shift 2 ;;
            -c|--category)    category="$2"; shift 2 ;;
            -a|--author)      author="$2"; shift 2 ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ -z "$name" ] || [ -z "$description" ]; then
        error "Usage: manage.sh add <name> --description \"x\" [--category \"x\"] [--author \"x\"]"
        exit 1
    fi

    if [ -d "$PLUGINS_DIR/$name" ]; then
        error "Plugin '$name' already exists"
        exit 1
    fi

    # Create plugin directory structure
    mkdir -p "$PLUGINS_DIR/$name/.claude-plugin"
    mkdir -p "$PLUGINS_DIR/$name/skills/$name"

    # Generate plugin.json
    P_NAME="$name" P_DESC="$description" P_AUTHOR="$author" \
    python3 -c "
import json, os
data = {
    'name': os.environ['P_NAME'],
    'description': os.environ['P_DESC'],
}
author = os.environ['P_AUTHOR']
if author:
    data['author'] = {'name': author}
out = os.path.join('$PLUGINS_DIR', os.environ['P_NAME'], '.claude-plugin', 'plugin.json')
with open(out, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
"

    # Generate SKILL.md template
    cat > "$PLUGINS_DIR/$name/skills/$name/SKILL.md" << SKILLEOF
---
name: $name
description: |
  $description
---

# $name

Instructions for Claude go here.
SKILLEOF

    # Update marketplace.json
    _marketplace_add "$name" "$description" "$category"

    info "Created plugin '$name'"
    echo "  Edit: plugins/$name/skills/$name/SKILL.md"
}

# ============================================================
# import - Import existing skill directory as a plugin
# ============================================================
cmd_import() {
    check_marketplace
    local skill_path=""
    local plugin_name=""

    if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
        skill_path="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --as) plugin_name="$2"; shift 2 ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [ -z "$skill_path" ]; then
        error "Usage: manage.sh import <skill-dir> [--as <plugin-name>]"
        exit 1
    fi

    # Resolve path
    skill_path="${skill_path%/}"
    if [[ "$skill_path" == ~* ]]; then
        skill_path="${skill_path/#\~/$HOME}"
    fi

    if [ ! -d "$skill_path" ]; then
        error "Directory not found: $skill_path"
        exit 1
    fi

    if [ ! -f "$skill_path/SKILL.md" ]; then
        error "No SKILL.md found in $skill_path"
        exit 1
    fi

    # Determine plugin name
    if [ -z "$plugin_name" ]; then
        plugin_name="$(basename "$skill_path")"
    fi

    if [ -d "$PLUGINS_DIR/$plugin_name" ]; then
        error "Plugin '$plugin_name' already exists. Use --as to specify a different name."
        exit 1
    fi

    # Extract metadata from SKILL.md
    local description
    description=$(extract_frontmatter_field "$skill_path/SKILL.md" "description") || description="Imported from $skill_path"

    # Create plugin structure
    mkdir -p "$PLUGINS_DIR/$plugin_name/.claude-plugin"
    mkdir -p "$PLUGINS_DIR/$plugin_name/skills/$plugin_name"

    # Copy all skill files (excluding .source marker from old system)
    for item in "$skill_path"/*; do
        [ -e "$item" ] || continue
        basename_item="$(basename "$item")"
        [ "$basename_item" = ".source" ] && continue
        cp -r "$item" "$PLUGINS_DIR/$plugin_name/skills/$plugin_name/"
    done

    # Also copy hidden files except .source
    for item in "$skill_path"/.*; do
        [ -e "$item" ] || continue
        basename_item="$(basename "$item")"
        [ "$basename_item" = "." ] || [ "$basename_item" = ".." ] || [ "$basename_item" = ".source" ] && continue
        cp -r "$item" "$PLUGINS_DIR/$plugin_name/skills/$plugin_name/"
    done

    # Generate plugin.json
    P_NAME="$plugin_name" P_DESC="$description" \
    python3 -c "
import json, os
data = {
    'name': os.environ['P_NAME'],
    'description': os.environ['P_DESC'],
}
out = os.path.join('$PLUGINS_DIR', os.environ['P_NAME'], '.claude-plugin', 'plugin.json')
with open(out, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
"

    # Update marketplace.json
    _marketplace_add "$plugin_name" "$description" "development"

    info "Imported '$plugin_name' from $skill_path"

    # Show what was imported
    local file_count
    file_count=$(find "$PLUGINS_DIR/$plugin_name/skills/$plugin_name" -type f | wc -l | tr -d ' ')
    echo "  Files: $file_count"
    echo "  Path:  plugins/$plugin_name/"
}

# ============================================================
# remove - Remove a plugin
# ============================================================
cmd_remove() {
    check_marketplace
    local name="$1"

    if [ -z "$name" ]; then
        error "Usage: manage.sh remove <name>"
        exit 1
    fi

    if [ ! -d "$PLUGINS_DIR/$name" ]; then
        error "Plugin '$name' not found"
        exit 1
    fi

    rm -rf "$PLUGINS_DIR/$name"

    # Remove from marketplace.json
    P_NAME="$name" MP_JSON="$MARKETPLACE_JSON" python3 -c "
import json, os
with open(os.environ['MP_JSON']) as f:
    data = json.load(f)
data['plugins'] = [p for p in data['plugins'] if p['name'] != os.environ['P_NAME']]
with open(os.environ['MP_JSON'], 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
"
    info "Removed '$name'"
}

# ============================================================
# list - List all plugins
# ============================================================
cmd_list() {
    check_marketplace

    MP_JSON="$MARKETPLACE_JSON" python3 -c "
import json, os
with open(os.environ['MP_JSON']) as f:
    data = json.load(f)
plugins = data.get('plugins', [])
if not plugins:
    print('(no plugins)')
else:
    print(f'Marketplace: {data[\"name\"]}')
    print(f'Plugins: {len(plugins)}')
    print()
    print(f'{\"NAME\":<30} {\"CATEGORY\":<15} DESCRIPTION')
    print(f'{\"----\":<30} {\"--------\":<15} -----------')
    for p in plugins:
        name = p['name']
        cat = p.get('category', '-')
        desc = p.get('description', '')
        if len(desc) > 60:
            desc = desc[:57] + '...'
        print(f'{name:<30} {cat:<15} {desc}')
"
}

# ============================================================
# build - Rebuild marketplace.json from plugins/
# ============================================================
cmd_build() {
    check_marketplace

    MP_JSON="$MARKETPLACE_JSON" PLUGINS="$PLUGINS_DIR" python3 -c "
import json, os, glob

mp_json = os.environ['MP_JSON']
plugins_dir = os.environ['PLUGINS']

with open(mp_json) as f:
    data = json.load(f)

# Scan plugins directory
new_plugins = []
plugin_dirs = sorted(glob.glob(os.path.join(plugins_dir, '*', '.claude-plugin', 'plugin.json')))

for pj_path in plugin_dirs:
    with open(pj_path) as f:
        pj = json.load(f)

    name = pj['name']
    plugin_dir = os.path.dirname(os.path.dirname(pj_path))
    rel_source = './plugins/' + os.path.basename(plugin_dir)

    # Preserve existing marketplace entry fields (category, homepage, etc.)
    existing = next((p for p in data['plugins'] if p['name'] == name), {})

    entry = {
        'name': name,
        'description': pj.get('description', existing.get('description', '')),
        'source': rel_source,
    }

    # Carry over optional fields
    for field in ('category', 'homepage', 'author', 'version', 'keywords', 'tags'):
        val = pj.get(field) or existing.get(field)
        if val:
            entry[field] = val

    new_plugins.append(entry)

data['plugins'] = new_plugins

with open(mp_json, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f'Built marketplace.json with {len(new_plugins)} plugins')
"
    info "marketplace.json rebuilt"
}

# ============================================================
# Helper: add plugin entry to marketplace.json
# ============================================================
_marketplace_add() {
    local name="$1"
    local description="$2"
    local category="$3"

    P_NAME="$name" P_DESC="$description" P_CAT="$category" MP_JSON="$MARKETPLACE_JSON" \
    python3 -c "
import json, os

mp_json = os.environ['MP_JSON']
with open(mp_json) as f:
    data = json.load(f)

name = os.environ['P_NAME']
for p in data['plugins']:
    if p['name'] == name:
        exit(0)  # already exists

data['plugins'].append({
    'name': name,
    'description': os.environ['P_DESC'],
    'source': f'./plugins/{name}',
    'category': os.environ['P_CAT']
})

with open(mp_json, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
"
}

# ============================================================
# help
# ============================================================
cmd_help() {
    echo "Private Marketplace Manager"
    echo ""
    echo "Setup:"
    echo "  manage.sh init <name> --owner \"Name\" [--email \"x\"] [--description \"x\"]"
    echo ""
    echo "Plugin management:"
    echo "  manage.sh add <name> -d \"description\" [-c category] [-a author]"
    echo "  manage.sh import <skill-dir> [--as <plugin-name>]"
    echo "  manage.sh remove <name>"
    echo "  manage.sh list"
    echo ""
    echo "Maintenance:"
    echo "  manage.sh build     Rebuild marketplace.json from plugins/"
    echo "  manage.sh help      Show this help"
    echo ""
    echo "Categories: development, productivity, deployment, database,"
    echo "            testing, security, monitoring, design, learning"
}

# ============================================================
# Main dispatch
# ============================================================
check_python3

cmd="${1:-help}"
shift 2>/dev/null || true

case "$cmd" in
    init)   cmd_init "$@" ;;
    add)    cmd_add "$@" ;;
    import) cmd_import "$@" ;;
    remove) cmd_remove "$@" ;;
    list)   cmd_list "$@" ;;
    build)  cmd_build "$@" ;;
    help|--help|-h) cmd_help ;;
    *)      error "Unknown command: $cmd"; cmd_help; exit 1 ;;
esac
