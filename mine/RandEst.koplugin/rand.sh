#!/bin/bash

# randCSV.sh: Generate a pseudo-random odd number (1..603) and print that CSV row
# Based on rand.sh, but instead of selecting an HTML file and reading XPaths,
# it selects the N-th row (where N is the random odd number) from a CSV and prints
# each of its columns on a new line.

# Linear Congruential Generator (LCG) params
A=1103515245  # Multiplier
C=12345       # Increment
M=2147483647  # Modulus (2^31 - 1)

# CSV file to search; can be overridden by environment variable or first arg
CSV_FILE_ENV=${CSV_FILE:-}
CSV_FILE_ARG=${1:-}

gen_seed() {
    # Use /dev/urandom because Kindle 'date' does not support nanoseconds (%N)
    # This reads bytes, keeps only digits, and takes the first 9
    # Note: May occasionally start with 0; callers must force base-10 in $(( )) using 10#
    local s
    s=$(head -n 1 /dev/urandom | tr -dc '0-9' | cut -c 1-9)
    # Fallback if pipeline produced nothing (very unlikely but safer on busybox)
    if [ -z "$s" ]; then
        s=$(date +%s 2>/dev/null | tr -dc '0-9' | tail -c 9)
        if [ -z "$s" ]; then s=1; fi
    fi
    echo "$s"
}

# Function to generate the next pseudo-random number
gen_prn() {
    local current_seed=$1
    # Force base-10 for numbers that may have leading zeros to avoid octal interpretation
    # Use awk to avoid shell arithmetic overflow on platforms with 32-bit math
    local next_seed
    next_seed=$(awk -v A="$A" -v C="$C" -v M="$M" -v S="$current_seed" 'BEGIN {
        # Coerce to numeric, strip any sign for modulo stability
        if (S+0 < 0) S = -(S+0); else S = S+0;
        ns = (A * S + C) % M;
        printf "%d", ns
    }')
    echo "$next_seed"
}

next_rand(){
    local seed
    seed=$(gen_seed)
    local rand
    rand=$(gen_prn "$seed")

    # Map to an odd number in [1, 603]
    # Take modulo 302 to get k in [0..301], then map to odd N = 2*k + 1 → [1..603]
    # Force base-10 in modulo to avoid octal errors when the number has leading zeros
    # Use awk to avoid shell arithmetic pitfalls and ensure a value in 1..603
    local n
    n=$(awk -v R="$rand" 'BEGIN {
        # Ensure non-negative
        if (R+0 < 0) R = -(R+0); else R = R+0;
        printf "%d",(R % 302)
    }')
    echo "$n"
}

usage() {
    cat <<EOF
Usage: ./randCSV.sh [CSV_FILE]

Description:
  Generates a pseudo-random odd integer in the range 1..603 and selects the row
  at that 1-based index from the provided CSV (i.e., the N-th row), then prints
  each column in that row on a new line.

CSV selection order:
  1) First positional argument [CSV_FILE], if provided
  2) Environment variable CSV_FILE, if set
  3) Defaults to ./source.csv

Environment variables:
  CSV_FILE   Override path to the CSV file

Exit codes:
  0  Row printed successfully (each column on its own line)
  1  CSV file not found or not readable
  2  Requested row does not exist (CSV has fewer rows)
EOF
}

resolve_csv_file() {
    local chosen
    if [[ -n "$CSV_FILE_ARG" ]]; then
        chosen="$CSV_FILE_ARG"
    elif [[ -n "$CSV_FILE_ENV" ]]; then
        chosen="$CSV_FILE_ENV"
    else
        # Fallback: resolve CSV relative to this script's directory
        # Works even when the current working directory is different (as in KOReader)
        local script_dir
        script_dir="$(cd "$(dirname "$0")" && pwd)"
        chosen="${script_dir}/source.csv"
    fi
    echo "$chosen"
}

select_row_by_number() {
    local csv_file=$1
    local row_num=$2

    # Print the N-th (1-based) row exactly. If not found, exit with code 3.
    awk -v target="${row_num}" '
        NR == target { print $0; exit 0 }
        END { if (NR < target) exit 3 }
    ' "$csv_file"
}

main() {
    # Help flag
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        usage
        exit 0
    fi

    local csv
    csv=$(resolve_csv_file)
    if [[ ! -f "$csv" ]]; then
        echo "CSV file not found: $csv" >&2
        exit 1
    fi

    local n
    n=$(next_rand)

    local row
    # Capture the N-th row (if any)
    row=$(select_row_by_number "$csv" "$n")
    local code=$?

    if [ $code -eq 0 ] && [ -n "$row" ]; then
        # Print each column of the selected row on a new line (trim spaces)
        # Changed: used 'echo | awk' instead of bash '<<<'
        echo "$row" | awk -F',' '{
            for (i=1; i<=NF; i++) {
                gsub(/^\s+|\s+$/, "", $i)
                print $i
            }
        }'
        exit 0
    else
        # Determine row count to provide a helpful message
        local total_rows
        total_rows=$(wc -l < "$csv" 2>/dev/null | tr -d '[:space:]')
        if [[ -z "$total_rows" ]]; then total_rows=0; fi
        echo "Requested row $n does not exist in $csv (total rows: $total_rows)" >&2
        exit 2
    fi
}

main "$@"
