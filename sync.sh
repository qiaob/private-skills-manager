#!/bin/bash
# Claude Code Skills Manager - Sync skills from multiple sources
#
# Usage:
#   bash sync.sh                Install/update all skills from all sources
#   bash sync.sh --dry-run      Check for updates only (no changes)
#   bash sync.sh --only NAME    Install/update a single skill
#   bash sync.sh --source NAME  Only sync from a specific source
#   bash sync.sh --list         List all installed skills
#   bash sync.sh --remove NAME  Remove a managed skill
#   bash sync.sh --no-hooks     Skip post-install.sh execution
#   bash sync.sh --help         Show help

set -e

# ============================================================
# Configuration
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/sources.d"
LOCAL_SKILLS_DIR="$HOME/.claude/skills"
TMP_DIR="/tmp/claude-skill-sync-$$"
SELF_NAME="$(basename "$SCRIPT_DIR")"

# ============================================================
# Parse arguments
# ============================================================
DRY_RUN=false
ONLY_SKILL=""
ONLY_SOURCE=""
NO_HOOKS=false
LIST_MODE=false
REMOVE_SKILL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|--check)
            DRY_RUN=true
            shift
            ;;
        --only)
            ONLY_SKILL="$2"
            shift 2
            ;;
        --source)
            ONLY_SOURCE="$2"
            shift 2
            ;;
        --no-hooks)
            NO_HOOKS=true
            shift
            ;;
        --list)
            LIST_MODE=true
            shift
            ;;
        --remove)
            REMOVE_SKILL="$2"
            shift 2
            ;;
        --help|-h)
            echo "Claude Code Skills Manager"
            echo ""
            echo "Usage:"
            echo "  bash sync.sh                Install/update all skills"
            echo "  bash sync.sh --dry-run      Check for updates only"
            echo "  bash sync.sh --only NAME    Install/update a single skill"
            echo "  bash sync.sh --source NAME  Only sync from a specific source"
            echo "  bash sync.sh --list         List all installed skills"
            echo "  bash sync.sh --remove NAME  Remove a managed skill"
            echo "  bash sync.sh --no-hooks     Skip post-install.sh execution"
            echo "  bash sync.sh --help         Show this help"
            echo ""
            echo "Sources: $SOURCES_DIR"
            echo "Skills:  $LOCAL_SKILLS_DIR"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1 (use --help for usage)"
            exit 1
            ;;
    esac
done

# ============================================================
# Utility functions
# ============================================================
info()  { echo -e "\033[0;32m✓\033[0m $1"; }
warn()  { echo -e "\033[0;33m⚠\033[0m $1"; }
error() { echo -e "\033[0;31m✗\033[0m $1"; }

cleanup() { rm -rf "$TMP_DIR" 2>/dev/null; }
trap cleanup EXIT

expand_tilde() { echo "${1/#\~/$HOME}"; }

file_hash() {
    if command -v md5sum &>/dev/null; then
        md5sum "$1" 2>/dev/null | cut -d' ' -f1
    else
        md5 -q "$1" 2>/dev/null || echo "none"
    fi
}

now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Read source name from .source marker file
get_skill_source() {
    local source_file="$1/.source"
    if [ -f "$source_file" ]; then
        cut -d'|' -f1 < "$source_file"
    fi
}

# ============================================================
# --list mode
# ============================================================
if $LIST_MODE; then
    echo "=== Installed Skills ==="
    echo ""
    printf "%-30s %-20s %s\n" "SKILL" "SOURCE" "SYNCED AT"
    printf "%-30s %-20s %s\n" "-----" "------" "---------"

    found=0
    for skill_dir in "$LOCAL_SKILLS_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name="$(basename "$skill_dir")"
        [ "$skill_name" = "$SELF_NAME" ] && continue

        source_file="$skill_dir/.source"
        if [ -f "$source_file" ]; then
            src=$(cut -d'|' -f1 < "$source_file")
            synced=$(cut -d'|' -f2 < "$source_file")
            printf "%-30s %-20s %s\n" "$skill_name" "$src" "$synced"
        else
            printf "%-30s %-20s %s\n" "$skill_name" "(manual)" "-"
        fi
        ((found++)) || true
    done

    if [ $found -eq 0 ]; then
        echo "(no skills installed)"
    fi
    exit 0
fi

# ============================================================
# --remove mode
# ============================================================
if [ -n "$REMOVE_SKILL" ]; then
    skill_dir="$LOCAL_SKILLS_DIR/$REMOVE_SKILL"

    if [ ! -d "$skill_dir" ]; then
        error "Skill '$REMOVE_SKILL' not found"
        exit 1
    fi

    source_name=$(get_skill_source "$skill_dir")
    if [ -z "$source_name" ]; then
        error "Skill '$REMOVE_SKILL' is not managed by skills-manager (no .source marker)"
        echo "  To remove manually: rm -rf \"$skill_dir\""
        exit 1
    fi

    rm -rf "$skill_dir"
    info "Removed '$REMOVE_SKILL' (was from source '$source_name')"
    exit 0
fi

# ============================================================
# Sync mode - validate sources
# ============================================================
if [ ! -d "$SOURCES_DIR" ]; then
    error "Sources directory not found: $SOURCES_DIR"
    echo "  mkdir -p $SOURCES_DIR"
    echo "  Then add .conf files. See README.md for format."
    exit 1
fi

# Collect .conf files
SOURCE_FILES=()
for f in "$SOURCES_DIR"/*.conf; do
    [ -f "$f" ] && SOURCE_FILES+=("$f")
done

if [ ${#SOURCE_FILES[@]} -eq 0 ]; then
    error "No source configs found in $SOURCES_DIR"
    echo "  Create a .conf file. See sources.d/example.conf.sample"
    exit 1
fi

# Filter by --source
if [ -n "$ONLY_SOURCE" ]; then
    if [ ! -f "$SOURCES_DIR/$ONLY_SOURCE.conf" ]; then
        error "Source '$ONLY_SOURCE' not found (expected $SOURCES_DIR/$ONLY_SOURCE.conf)"
        exit 1
    fi
    SOURCE_FILES=("$SOURCES_DIR/$ONLY_SOURCE.conf")
fi

echo "=== Claude Code Skills Sync ==="
echo ""

mkdir -p "$TMP_DIR"
mkdir -p "$LOCAL_SKILLS_DIR"

# ============================================================
# Process each source
# ============================================================
TOTAL_INSTALLED=0
TOTAL_UPDATED=0
TOTAL_UNCHANGED=0
TOTAL_SKIPPED=0
SKILLS_CHANGED=()

for conf_file in "${SOURCE_FILES[@]}"; do
    source_name="$(basename "$conf_file" .conf)"

    # Reset source config variables
    REPO=""
    BRANCH=""
    SKILLS_SUBDIR=""
    TYPE="git"
    SSH_KEY=""
    GIT_TOKEN_ENV=""
    source "$conf_file"

    # Validate required fields
    if [ -z "$REPO" ] || [ -z "$SKILLS_SUBDIR" ]; then
        error "[$source_name] Missing required fields (REPO, SKILLS_SUBDIR)"
        continue
    fi
    if [ "$TYPE" = "git" ] && [ -z "$BRANCH" ]; then
        error "[$source_name] BRANCH is required for git sources"
        continue
    fi

    echo "--- Source: $source_name ---"

    # --------------------------------------------------------
    # Fetch source content
    # --------------------------------------------------------
    skills_root="$TMP_DIR/$source_name/skills_root"

    if [ "$TYPE" = "local" ]; then
        local_path="$(expand_tilde "$REPO")"
        local_skills="$local_path/$SKILLS_SUBDIR"
        if [ ! -d "$local_skills" ]; then
            error "[$source_name] Directory not found: $local_skills"
            echo ""
            continue
        fi
        mkdir -p "$TMP_DIR/$source_name"
        cp -r "$local_skills" "$skills_root"
        info "[$source_name] Loaded from local directory"
    else
        echo "Fetching from repository..."

        clone_url="$REPO"

        # SSH key authentication
        if [ -n "$SSH_KEY" ]; then
            key_path="$(expand_tilde "$SSH_KEY")"
            if [ ! -f "$key_path" ]; then
                error "[$source_name] SSH key not found: $key_path"
                echo ""
                continue
            fi
            export GIT_SSH_COMMAND="ssh -i $key_path -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
        fi

        # HTTPS token authentication
        if [ -n "$GIT_TOKEN_ENV" ]; then
            token="${!GIT_TOKEN_ENV}"
            if [ -z "$token" ]; then
                error "[$source_name] Environment variable \$$GIT_TOKEN_ENV is not set"
                unset GIT_SSH_COMMAND 2>/dev/null
                echo ""
                continue
            fi
            clone_url="${REPO/https:\/\//https://oauth2:${token}@}"
        fi

        clone_dir="$TMP_DIR/$source_name/repo"

        if git clone --depth 1 --branch "$BRANCH" --filter=blob:none --sparse \
            "$clone_url" "$clone_dir" 2>/dev/null; then
            # Use subshell to avoid changing working directory
            (
                cd "$clone_dir"
                git sparse-checkout set "$SKILLS_SUBDIR" 2>/dev/null
                git checkout "$BRANCH" -- "$SKILLS_SUBDIR" 2>/dev/null || true
            )
            if [ -d "$clone_dir/$SKILLS_SUBDIR" ]; then
                mv "$clone_dir/$SKILLS_SUBDIR" "$skills_root"
            else
                error "[$source_name] Directory '$SKILLS_SUBDIR' not found in repository"
                unset GIT_SSH_COMMAND 2>/dev/null
                echo ""
                continue
            fi
        else
            error "[$source_name] Cannot clone repository"
            echo "  Check: repo URL, branch name, access permissions, network"
            [ -n "$SSH_KEY" ] && echo "  SSH key: $(expand_tilde "$SSH_KEY")"
            [ -n "$GIT_TOKEN_ENV" ] && echo "  Token env: \$$GIT_TOKEN_ENV"
            unset GIT_SSH_COMMAND 2>/dev/null
            echo ""
            continue
        fi

        unset GIT_SSH_COMMAND 2>/dev/null
        info "[$source_name] Repository fetched"
    fi

    # --------------------------------------------------------
    # Discover skills (directories containing SKILL.md)
    # --------------------------------------------------------
    skills_found=()
    for skill_dir in "$skills_root"/*/; do
        [ -f "$skill_dir/SKILL.md" ] && skills_found+=("$(basename "$skill_dir")")
    done

    if [ ${#skills_found[@]} -eq 0 ]; then
        warn "[$source_name] No skills found (no directories with SKILL.md)"
        echo ""
        continue
    fi

    info "[$source_name] Found ${#skills_found[@]} skills: ${skills_found[*]}"

    # --------------------------------------------------------
    # Compare and sync each skill
    # --------------------------------------------------------
    for skill in "${skills_found[@]}"; do
        # Filter by --only
        if [ -n "$ONLY_SKILL" ] && [ "$skill" != "$ONLY_SKILL" ]; then
            continue
        fi

        remote_dir="$skills_root/$skill"
        local_dir="$LOCAL_SKILLS_DIR/$skill"

        # --- New install ---
        if [ ! -d "$local_dir" ]; then
            if $DRY_RUN; then
                warn "$skill: not installed (available from '$source_name')"
                ((TOTAL_INSTALLED++)) || true
            else
                mkdir -p "$local_dir"
                cp -r "$remote_dir"/. "$local_dir/"
                echo "${source_name}|$(now_iso)" > "$local_dir/.source"
                find "$local_dir" -name "*.sh" -exec chmod +x {} \; 2>/dev/null
                info "$skill: installed (from '$source_name')"
                SKILLS_CHANGED+=("$skill")
                ((TOTAL_INSTALLED++)) || true
            fi
            continue
        fi

        # --- Existing skill: check ownership ---
        existing_source=$(get_skill_source "$local_dir")

        # No .source marker → manually managed, don't touch
        if [ -z "$existing_source" ]; then
            warn "$skill: manually managed, skipping"
            ((TOTAL_SKIPPED++)) || true
            continue
        fi

        # Owned by a different source → conflict
        if [ "$existing_source" != "$source_name" ]; then
            warn "$skill: owned by '$existing_source', skipping (conflict with '$source_name')"
            ((TOTAL_SKIPPED++)) || true
            continue
        fi

        # --- Same source: compare for changes ---
        has_changes=false
        while IFS= read -r -d '' remote_file; do
            rel_path="${remote_file#$remote_dir/}"
            local_file="$local_dir/$rel_path"

            if [ ! -f "$local_file" ] || [ "$(file_hash "$remote_file")" != "$(file_hash "$local_file")" ]; then
                has_changes=true
                break
            fi
        done < <(find "$remote_dir" -type f -print0 2>/dev/null)

        if $has_changes; then
            if $DRY_RUN; then
                warn "$skill: update available"
                ((TOTAL_UPDATED++)) || true
            else
                cp -r "$remote_dir"/. "$local_dir/"
                echo "${source_name}|$(now_iso)" > "$local_dir/.source"
                find "$local_dir" -name "*.sh" -exec chmod +x {} \; 2>/dev/null
                info "$skill: updated"
                SKILLS_CHANGED+=("$skill")
                ((TOTAL_UPDATED++)) || true
            fi
        else
            info "$skill: up to date"
            ((TOTAL_UNCHANGED++)) || true
        fi
    done

    echo ""
done

# ============================================================
# Summary
# ============================================================
echo "--- Summary ---"
if $DRY_RUN; then
    echo "Dry run complete. Up to date: $TOTAL_UNCHANGED, Updates available: $((TOTAL_INSTALLED + TOTAL_UPDATED)), Skipped: $TOTAL_SKIPPED"
else
    echo "Sync complete. Installed: $TOTAL_INSTALLED, Updated: $TOTAL_UPDATED, Unchanged: $TOTAL_UNCHANGED, Skipped: $TOTAL_SKIPPED"
fi

# ============================================================
# Configuration check (only for newly installed/updated skills)
# ============================================================
if ! $DRY_RUN && [ ${#SKILLS_CHANGED[@]} -gt 0 ]; then
    echo ""
    echo "--- Configuration Check ---"

    missing=0
    for skill in "${SKILLS_CHANGED[@]}"; do
        conf="$LOCAL_SKILLS_DIR/$skill/setup.conf"
        [ -f "$conf" ] || continue

        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue

            type=$(echo "$line" | cut -d'|' -f1)
            name=$(echo "$line" | cut -d'|' -f2)
            help=$(echo "$line" | cut -d'|' -f3-)

            case "$type" in
                env)
                    if [ -z "${!name}" ]; then
                        warn "$skill requires \$$name"
                        echo "  $help"
                        ((missing++)) || true
                    else
                        info "$skill: \$$name configured"
                    fi
                    ;;
                file)
                    expanded="$(expand_tilde "$name")"
                    if [ -f "$expanded" ]; then
                        info "$skill: $name exists"
                    else
                        warn "$skill requires: $name"
                        [ -n "$help" ] && echo "  $help"
                        ((missing++)) || true
                    fi
                    ;;
                note)
                    echo "  ℹ $skill: $help"
                    ;;
            esac
        done < "$conf"
    done

    if [ $missing -eq 0 ]; then
        info "All configurations are set"
    fi
fi

# ============================================================
# Post-install hooks (only for newly installed/updated skills)
# ============================================================
if ! $DRY_RUN && ! $NO_HOOKS && [ ${#SKILLS_CHANGED[@]} -gt 0 ]; then
    for skill in "${SKILLS_CHANGED[@]}"; do
        post_install="$LOCAL_SKILLS_DIR/$skill/post-install.sh"
        if [ -f "$post_install" ]; then
            echo ""
            echo "Running $skill/post-install.sh ..."
            if bash "$post_install"; then
                info "$skill: post-install complete"
            else
                warn "$skill: post-install failed (exit code $?)"
                echo "  Run manually: bash $post_install"
            fi
        fi
    done
fi

# ============================================================
# Done
# ============================================================
echo ""
echo "=== Done ==="
if ! $DRY_RUN && [ $((TOTAL_INSTALLED + TOTAL_UPDATED)) -gt 0 ]; then
    echo "Restart Claude Code or run /reload-plugins to activate changes."
fi
