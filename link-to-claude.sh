#!/bin/bash
# link-to-claude.sh
# Creates symlinks from this repo's skills/rules/commands to ~/.claude/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create target directories if they don't exist
mkdir -p "$CLAUDE_DIR/commands"
mkdir -p "$CLAUDE_DIR/rules"
mkdir -p "$CLAUDE_DIR/skills"

# Function to clean up broken symlinks in a directory
cleanup_broken_links() {
    local dir="$1"
    for link in "$dir"/*; do
        if [[ -L "$link" && ! -e "$link" ]]; then
            log_warn "Removing broken symlink: $(basename "$link")"
            rm -f "$link"
        fi
    done
}

# Function to create a symlink (removes existing if present)
create_link() {
    local source="$1"
    local target="$2"

    if [[ -L "$target" ]]; then
        # Existing symlink - check if it points to same source
        local current_target
        current_target=$(readlink "$target")
        if [[ "$current_target" == "$source" ]]; then
            log_info "Already linked: $(basename "$target")"
            return 0
        fi
        log_warn "Updating symlink: $(basename "$target")"
        rm "$target"
    elif [[ -e "$target" ]]; then
        log_error "Target exists and is not a symlink: $target"
        return 1
    fi

    ln -s "$source" "$target"
    log_info "Created: $(basename "$target") -> $source"
}

echo "========================================"
echo "Linking commands..."
echo "========================================"
cleanup_broken_links "$CLAUDE_DIR/commands"
for file in "$SCRIPT_DIR/commands"/*.md; do
    [[ -f "$file" ]] || continue
    filename=$(basename "$file")
    create_link "$file" "$CLAUDE_DIR/commands/$filename"
done

echo ""
echo "========================================"
echo "Linking rules..."
echo "========================================"
cleanup_broken_links "$CLAUDE_DIR/rules"
for file in "$SCRIPT_DIR/rules"/*.md; do
    [[ -f "$file" ]] || continue
    filename=$(basename "$file")
    create_link "$file" "$CLAUDE_DIR/rules/$filename"
done

echo ""
echo "========================================"
echo "Linking skills..."
echo "========================================"
cleanup_broken_links "$CLAUDE_DIR/skills"
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue

    skill_name=$(basename "$skill_dir")

    # Determine the target folder:
    # - If skill has a 'skill/' subfolder, link to that
    # - Otherwise, link to the skill folder itself
    if [[ -d "${skill_dir}skill" ]]; then
        source_dir="${skill_dir}skill"
    else
        source_dir="$skill_dir"
    fi

    # Clean up skill name for the link
    # Remove trailing -skill suffix if present for cleaner names
    link_name="${skill_name%-skill}"

    create_link "$source_dir" "$CLAUDE_DIR/skills/$link_name"
done

echo ""
echo "========================================"
echo "Done! Symlinks created in $CLAUDE_DIR"
echo "========================================"
