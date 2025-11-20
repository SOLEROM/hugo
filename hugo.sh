#!/bin/bash

# Hugo - Handy Unix Guidance Operator
# A fast command-line tool to search and display help files using fzf

set -e

# Default configuration
DEFAULT_ROOT="$HOME/.hugo"
PREVIEW_LINES=20

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Help function
show_help() {
    cat << EOF
Hugo - Handy Unix Guidance Operator

USAGE:
    hugo [OPTIONS] [SEARCH_TERM]

OPTIONS:
    --root=PATH     Set root directory for help files (default: $DEFAULT_ROOT)
    --list          List all available help files
    --help, -h      Show this help message
    --version, -v   Show version information

EXAMPLES:
    hugo                    # Interactive search with fzf
    hugo wifi               # Search for wifi-related commands
    hugo --root=/my/docs    # Use custom root directory
    hugo --list             # List all available help files

FILE FORMAT:
    Files should be named h.TOPIC and start with:
    # description | keywords;separated;by;semicolons

ENVIRONMENT VARIABLES:
    HUGO_ROOT      Default root directory (overrides built-in default)
    HUGO_EDITOR    Editor to use for viewing files (default: less)

EOF
}

# Version function
show_version() {
    echo "Hugo v1.0.0 - Handy Unix Guidance Operator"
}

# Parse command line arguments
ROOT_DIR="${HUGO_ROOT:-$DEFAULT_ROOT}"
SEARCH_TERM=""
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --root=*)
            ROOT_DIR="${1#*=}"
            shift
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            show_version
            exit 0
            ;;
        -*)
            echo "Error: Unknown option $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
        *)
            SEARCH_TERM="$1"
            shift
            ;;
    esac
done

# Check if root directory exists
if [[ ! -d "$ROOT_DIR" ]]; then
    echo -e "${RED}Error: Root directory '$ROOT_DIR' does not exist${NC}" >&2
    echo "Create it or use --root=PATH to specify a different directory" >&2
    exit 1
fi

# Check if fzf is available
if ! command -v fzf >/dev/null 2>&1; then
    echo -e "${RED}Error: fzf is not installed${NC}" >&2
    echo "Please install fzf first: https://github.com/junegunn/fzf" >&2
    exit 1
fi

# Function to extract info from help file header
extract_file_info() {
    local file="$1"
    local first_line
    first_line=$(head -n1 "$file" 2>/dev/null)

    if [[ $first_line =~ ^#[[:space:]]*(.+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "No description available"
    fi
}

# Function to build the search index
# Output format (tab-separated):
#   1) topic (from filename h.topic)
#   2) description + keywords (for searching)
#   3) full filepath
build_search_index() {
    local temp_file
    temp_file=$(mktemp)

    # Find all h.* files recursively
    while IFS= read -r -d '' file; do
        local relative_path="${file#$ROOT_DIR/}"
        local basename
        basename=$(basename "$file")
        local topic="${basename#h.}"
        local info
        info=$(extract_file_info "$file")

        local description keywords
        if [[ $info == *"|"* ]]; then
            description="${info%%|*}"
            keywords="${info##*|}"
            # Clean up whitespace
            description=$(echo "$description" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            keywords=$(echo "$keywords" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        else
            description="$info"
            keywords=""
        fi

        # Line: topic<TAB>(description + keywords)<TAB>filepath
        printf "%s\t%s %s\t%s\n" "$topic" "$description" "$keywords" "$file" >> "$temp_file"

    done < <(find "$ROOT_DIR" -name "h.*" -type f -print0 2>/dev/null)

    echo "$temp_file"
}

# List mode
if [[ $LIST_ONLY == true ]]; then
    echo -e "${BLUE}Available help files in $ROOT_DIR:${NC}"
    echo ""

    temp_index=$(build_search_index)
    while IFS=$'\t' read -r topic search_data filepath; do
        echo "  $topic"
    done < "$temp_index"
    rm -f "$temp_index"
    exit 0
fi

# Build search index
echo "Building search index..." >&2
temp_index=$(build_search_index)

# Count files
file_count=$(wc -l < "$temp_index")
if [[ $file_count -eq 0 ]]; then
    echo -e "${YELLOW}No help files found in $ROOT_DIR${NC}" >&2
    echo "Create files starting with 'h.' (e.g., h.wifi, h.git)" >&2
    rm -f "$temp_index"
    exit 1
fi

echo "Found $file_count help files" >&2

# Prepare fzf command
FZF_OPTS=(
    --delimiter="\t"
    # Display only the first field (topic) in the main list
    --with-nth=1
    # Search on topic (field 1) + description/keywords (field 2)
    --nth=1,2
    --preview='filepath=$(echo {} | cut -f3); echo "File: $filepath" && echo "==============================================" && head -n 15 "$filepath" 2>/dev/null || echo "Could not read file: $filepath"'
    --preview-window="right:50%:wrap"
    --header="Hugo - Search your help files (Press Enter to select, Ctrl+C to exit)"
    --prompt="Search > "
    --height=90%
    --border
    --tabstop=4
)

# Add initial query if search term provided
if [[ -n "$SEARCH_TERM" ]]; then
    FZF_OPTS+=(--query="$SEARCH_TERM")
fi

# Run fzf and get selection
selected=$(cat "$temp_index" | fzf "${FZF_OPTS[@]}")

# Clean up temp file
rm -f "$temp_index"

# If user made a selection, display the file
if [[ -n "$selected" ]]; then
    filepath=$(echo "$selected" | cut -f3)

    echo ""
    echo -e "${GREEN}=== $(basename "$filepath") ===${NC}"
    echo ""

    cat "$filepath"
    echo ""
fi
