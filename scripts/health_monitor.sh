#!/bin/bash
#
# health_monitor.sh
# Monitors CPU, memory, disk usage and process count.
# Logs an ALERT line to the console and to a log file when any metric
# crosses its threshold.
#
# Usage:
#   ./health_monitor.sh                # single check
#   ./health_monitor.sh --watch 60     # loop every 60s (Ctrl+C to stop)
#
# Suggested cron for periodic checks (every 5 min):
#   */5 * * * * /path/to/health_monitor.sh >> /var/log/health_monitor_cron.log 2>&1

set -euo pipefail

# ---- Thresholds (override via env vars if desired) ----
CPU_THRESHOLD="${CPU_THRESHOLD:-80}"      # percent
MEM_THRESHOLD="${MEM_THRESHOLD:-80}"      # percent
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"    # percent
PROC_THRESHOLD="${PROC_THRESHOLD:-300}"   # running process count

LOG_FILE="${LOG_FILE:-/var/log/health_monitor.log}"
# Fall back to a local file if /var/log isn't writable (e.g. non-root demo)
if ! touch "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="./health_monitor.log"
fi

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
    local level="$1"; shift
    local msg="$*"
    local line="[$(timestamp)] [$level] $msg"
    echo "$line"
    echo "$line" >> "$LOG_FILE"
}

check_cpu() {
    # 100 - idle% from top, averaged over 1 sample
    local idle cpu_usage
    idle=$(top -bn1 | grep -i "Cpu(s)" | awk -F',' '{print $4}' | awk '{print $1}' | tr -d '%')
    cpu_usage=$(awk -v idle="$idle" 'BEGIN{printf "%.0f", 100-idle}')
    if [ "$cpu_usage" -ge "$CPU_THRESHOLD" ]; then
        log "ALERT" "CPU usage high: ${cpu_usage}% (threshold ${CPU_THRESHOLD}%)"
    else
        log "OK" "CPU usage: ${cpu_usage}%"
    fi
}

check_memory() {
    local mem_usage
    mem_usage=$(free | awk '/Mem:/ {printf "%.0f", ($3/$2)*100}')
    if [ "$mem_usage" -ge "$MEM_THRESHOLD" ]; then
        log "ALERT" "Memory usage high: ${mem_usage}% (threshold ${MEM_THRESHOLD}%)"
    else
        log "OK" "Memory usage: ${mem_usage}%"
    fi
}

check_disk() {
    # Check every mounted real filesystem, flag any over threshold
    while read -r line; do
        local usep mount
        usep=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount=$(echo "$line" | awk '{print $6}')
        if [ "$usep" -ge "$DISK_THRESHOLD" ]; then
            log "ALERT" "Disk usage high on $mount: ${usep}% (threshold ${DISK_THRESHOLD}%)"
        else
            log "OK" "Disk usage on $mount: ${usep}%"
        fi
    done < <(df -hP -x tmpfs -x devtmpfs | tail -n +2)
}

check_processes() {
    local proc_count
    proc_count=$(ps -e --no-headers | wc -l)
    if [ "$proc_count" -ge "$PROC_THRESHOLD" ]; then
        log "ALERT" "Running process count high: ${proc_count} (threshold ${PROC_THRESHOLD})"
    else
        log "OK" "Running process count: ${proc_count}"
    fi
}

run_checks() {
    log "INFO" "----- Health check started -----"
    check_cpu
    check_memory
    check_disk
    check_processes
    log "INFO" "----- Health check complete -----"
}

if [[ "${1:-}" == "--watch" ]]; then
    interval="${2:-60}"
    echo "Watching every ${interval}s. Logging to: $LOG_FILE"
    while true; do
        run_checks
        sleep "$interval"
    done
else
    run_checks
fi
