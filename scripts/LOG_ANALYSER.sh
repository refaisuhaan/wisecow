#!/usr/bin/env bash
# log_analyzer.sh - Web Server Log Analyzer

LOG_FILE=""
TOP_COUNT=5

usage() {
    echo "Usage: $0 -f <log_file> [-n <top_count>]"
    echo "  -f    Path to the access log file (Apache or Nginx standard format)"
    echo "  -n    Number of top results to display (default: 5)"
    exit 1
}

# Parse command line options
while getopts "f:n:h" opt; do
    case "$opt" in
        f) LOG_FILE="$OPTARG" ;;
        n) TOP_COUNT="$OPTARG" ;;
        h|*) usage ;;
    esac
done

if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file not found or not specified."
    usage
fi

echo "=================================================="
echo "          WEB SERVER LOG ANALYSIS REPORT          "
echo "=================================================="
echo "Log File: $LOG_FILE"
echo "Date Generated: $(date +"%Y-%m-%d %H:%M:%S")"
echo "=================================================="
echo ""

# Total Requests
TOTAL_REQUESTS=$(wc -l < "$LOG_FILE" | xargs)
echo "Total Requests Processed: $TOTAL_REQUESTS"
echo ""

# 404 Error Count
COUNT_404=$(awk '$9 == "404" {print $0}' "$LOG_FILE" | wc -l | xargs)
echo "Total 404 Errors: $COUNT_404"
echo ""

# Top IP Addresses
echo "--------------------------------------------------"
echo "Top $TOP_COUNT IP Addresses with Most Requests:"
echo "--------------------------------------------------"
awk '{print $1}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -n "$TOP_COUNT" | awk '{printf "  %-15s : %s requests\n", $2, $1}'
echo ""

# Top Requested Pages
echo "--------------------------------------------------"
echo "Top $TOP_COUNT Most Requested Pages:"
echo "--------------------------------------------------"
awk '{print $7}' "$LOG_FILE" | sort | uniq -c | sort -nr | head -n "$TOP_COUNT" | awk '{printf "  %-35s : %s requests\n", $2, $1}'
echo ""

# Top Response Status Codes
echo "--------------------------------------------------"
echo "HTTP Response Code Breakdown:"
echo "--------------------------------------------------"
awk '{print $9}' "$LOG_FILE" | grep -E '^[0-9]{3}$' | sort | uniq -c | sort -nr | awk '{printf "  HTTP %-5s : %s times\n", $2, $1}'
echo ""

echo "=================================================="
echo "                  END OF REPORT                   "
echo "=================================================="
