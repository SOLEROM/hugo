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

show_help() {
    cat << EOF
Hugo - Handy Unix Guidance Operator

USAGE:
    hugo [OPTIONS] [SEARCH_TERM]

OPTIONS:
    --root=PATH     Set root directory for help files (default: $DEFAULT_ROOT)
    --list          List all available help files (topic - description)
    --help, -h      Show this help message
    --version, -v   Show version information

EXAMPLES:
    hugo                    # Interactive search with fzf
    hugo wifi               # Filter by keyword 'wifi'
    hugo --root=/my/docs    # Use custom root directory
    hugo --list             # List all available help files

FILE FORMAT:
    Files should be named h.TOPIC and start with:
      # description | keyword1 ; keyword2 ; keyword3

ENVIRONMENT VARIABLES:
    HUGO_ROOT      Default root directory (overrides built-in default)
    HUGO_EDITOR    Editor to use for viewing files (default: less)

EOF
}

show_version() {
    echo "Hugo v1.0.0 - Handy Unix Guidance Operator"
}

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

if [[ ! -d "$ROOT_DIR" ]]; then
    echo -e "${RED}Error: Root directory '$ROOT_DIR' does not exist${NC}" >&2
    echo "Create it or use --root=PATH to specify a different directory" >&2
    exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
    echo -e "${RED}Error: fzf is not installed${NC}" >&2
    echo "Please install fzf first: https://github.com/junegunn/fzf" >&2
    exit 1
fi

# Expects first line like:
#   # wifi cmds |  wifi connect ; wifi scan
extract_file_info() {
    local file="$1"
    local first_line
    first_line=$(head -n1 "$file" 2>/dev/null)

    if [[ $first_line =~ ^#[[:space:]]*(.+) ]]; then
        # NOTE: correct var name is BASH_REMATCH
        echo "${BASH_REMATCH[1]}"
    else
        echo "No description available"
    fi
}


# Build index:
#   1) topic
#   2) description
#   3) keywords (exact text after |, normalized spaces around ';')
#   4) filepath
build_search_index() {
    local temp_file
    temp_file=$(mktemp)

    while IFS= read -r -d '' file; do
        local basename topic info description raw_keywords keywords

        basename=$(basename "$file")
        topic="${basename#h.}"

        info=$(extract_file_info "$file")

        if [[ $info == *"|"* ]]; then
            description="${info%%|*}"
            raw_keywords="${info#*|}"

            # trim spaces
            description=$(echo "$description" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            raw_keywords=$(echo "$raw_keywords" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # normalize spaces around ';' but KEEP ';'
            keywords=$(echo "$raw_keywords" \
                | sed 's/[[:space:]]*;[[:space:]]*/ ; /g' \
                | sed 's/[[:space:]]\+/ /g' \
                | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        else
            description="$info"
            keywords=""
        fi

        printf "%s\t%s\t%s\t%s\n" "$topic" "$description" "$keywords" "$file" >> "$temp_file"

    done < <(find "$ROOT_DIR" -name "h.*" -type f -print0 2>/dev/null)

    echo "$temp_file"
}

# --list: show "topic - description"
if [[ $LIST_ONLY == true ]]; then
    echo -e "${BLUE}Available help files in $ROOT_DIR:${NC}"
    echo ""

    temp_index=$(build_search_index)
    while IFS=$'\t' read -r topic description keywords filepath; do
        if [[ -n "$description" && "$description" != "No description available" ]]; then
            echo "  $topic - $description"
        else
            echo "  $topic"
        fi
    done < "$temp_index"
    rm -f "$temp_index"
    exit 0
fi

echo "Building search index..." >&2
temp_index=$(build_search_index)

file_count=$(wc -l < "$temp_index")
if [[ $file_count -eq 0 ]]; then
    echo -e "${YELLOW}No help files found in $ROOT_DIR${NC}" >&2
    echo "Create files starting with 'h.' (e.g., h.wifi, h.git)" >&2
    rm -f "$temp_index"
    exit 1
fi

# If SEARCH_TERM is provided, filter index by keyword column (3)
if [[ -n "$SEARCH_TERM" ]]; then
    echo "Filtering by keyword: '$SEARCH_TERM'" >&2
    filtered_index=$(mktemp)

    awk -v term="$SEARCH_TERM" -F'\t' '
        BEGIN { IGNORECASE = 1 }
        {
            # $3 is the keywords column, e.g. "wifi connect ; wifi scan ; radio"
            n = split($3, arr, /;/)
            for (i = 1; i <= n; i++) {
                gsub(/^[ \t]+|[ \t]+$/, "", arr[i])
                if (tolower(arr[i]) == tolower(term)) {
                    print $0
                    next
                }
            }
        }
    ' "$temp_index" > "$filtered_index"

    mv "$filtered_index" "$temp_index"

    file_count=$(wc -l < "$temp_index")
    if [[ $file_count -eq 0 ]]; then
        echo -e "${YELLOW}No help files match keyword '$SEARCH_TERM'${NC}" >&2
        rm -f "$temp_index"
        exit 1
    fi

    echo "Found $file_count file(s) matching keyword '$SEARCH_TERM'" >&2
else
    echo "Found $file_count help files" >&2
fi

FZF_OPTS=(
    --delimiter=$'\t'
    # Show topic and description in the list
    --with-nth=1,2
    # Search over topic (1), description (2), and keywords (3)
    --nth=1,2,3
    --preview='filepath=$(echo {} | cut -f4); echo "File: $filepath" && echo "==============================================" && head -n '"$PREVIEW_LINES"' "$filepath" 2>/dev/null || echo "Could not read file: $filepath"'
    --preview-window="right:50%:wrap"
    --header="Hugo - Select help topic (filtered by keyword if given; Enter to open)"
    --prompt="Search > "
    --height=90%
    --border
    --tabstop=4
)

# We *don’t* pass SEARCH_TERM to fzf here; it was already used as a keyword filter.

selected=$(command fzf "${FZF_OPTS[@]}" < "$temp_index")

rm -f "$temp_index"

if [[ -n "$selected" ]]; then
    filepath=$(echo "$selected" | cut -f4)

    echo ""
    echo -e "${GREEN}=== $(basename "$filepath") ===${NC}"
    echo ""

    cat "$filepath"
    echo ""
fi
