#!/usr/bin/env bash
# vm-health.sh - Quick health report and light maintenance for a Rocky Linux VM
#
# Usage:
#   ./vm-health.sh              Show the health report
#   ./vm-health.sh --cleanup    Report, then clean dnf cache and old journal logs
#   ./vm-health.sh --update     Report, then apply all pending updates
#   ./vm-health.sh -h|--help    Show this help
#
# Tested logic for: Rocky Linux 8 / 9 (uses dnf and systemd)

set -u

# ---------- helpers ----------
if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RESET=$'\e[0m'
else
    BOLD=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi

section() { printf '\n%s== %s ==%s\n' "$BOLD" "$1" "$RESET"; }
ok()      { printf '%s[ OK ]%s %s\n'   "$GREEN"  "$RESET" "$1"; }
warn()    { printf '%s[WARN]%s %s\n'   "$YELLOW" "$RESET" "$1"; }
bad()     { printf '%s[FAIL]%s %s\n'   "$RED"    "$RESET" "$1"; }

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

need_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This action needs root. Run with sudo." >&2
        exit 1
    fi
}

# ---------- report sections ----------
show_system() {
    section "System"
    echo "Hostname : $(hostname)"
    echo "OS       : $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "Kernel   : $(uname -r)"
    echo "Uptime   : $(uptime -p)"
    echo "Date     : $(date '+%F %T %Z')"
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        echo "Virt     : $(systemd-detect-virt 2>/dev/null || echo none)"
    fi
}

show_cpu_load() {
    section "CPU / Load"
    local cores load1
    cores=$(nproc)
    load1=$(awk '{print $1}' /proc/loadavg)
    echo "Cores    : $cores"
    echo "Load avg : $(awk '{print $1", "$2", "$3}' /proc/loadavg) (1, 5, 15 min)"
    if awk -v l="$load1" -v c="$cores" 'BEGIN{exit !(l > c)}'; then
        warn "1-minute load is higher than the number of cores"
    else
        ok "Load is healthy"
    fi
}

show_memory() {
    section "Memory"
    free -h
    local used_pct
    used_pct=$(free | awk '/^Mem:/ {printf "%d", ($3/$2)*100}')
    if   (( used_pct >= 90 )); then bad  "Memory usage at ${used_pct}%"
    elif (( used_pct >= 75 )); then warn "Memory usage at ${used_pct}%"
    else                            ok   "Memory usage at ${used_pct}%"
    fi
}

show_disk() {
    section "Disk"
    df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null
    echo
    local found=0
    while read -r pct mount; do
        pct=${pct%\%}
        if   (( pct >= 90 )); then bad  "$mount is ${pct}% full"; found=1
        elif (( pct >= 80 )); then warn "$mount is ${pct}% full"; found=1
        fi
    done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay | awk 'NR>1 {print $5, $6}')
    (( found == 0 )) && ok "All filesystems below 80%"
}

show_top_processes() {
    section "Top 5 processes (by memory)"
    ps -eo pid,user,%mem,%cpu,comm --sort=-%mem | head -n 6
}

show_network() {
    section "Network"
    ip -brief address show | grep -v '^lo'
    echo
    echo "Default route : $(ip route show default | head -n1)"
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        ok "Internet reachable (ping 1.1.1.1)"
    else
        warn "No ping reply from 1.1.1.1 (check VM network mode)"
    fi
    echo
    echo "Listening ports:"
    ss -tulnp 2>/dev/null | awk 'NR==1 || /LISTEN|UNCONN/' | head -n 15
}

show_services() {
    section "Services"
    local failed
    failed=$(systemctl --failed --no-legend --plain 2>/dev/null)
    if [[ -z "$failed" ]]; then
        ok "No failed systemd units"
    else
        bad "Failed units:"
        echo "$failed"
    fi
    for svc in sshd firewalld chronyd; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "$svc is running"
        else
            warn "$svc is not running"
        fi
    done
}

show_security() {
    section "Security"
    if command -v getenforce >/dev/null 2>&1; then
        local mode
        mode=$(getenforce)
        [[ "$mode" == "Enforcing" ]] && ok "SELinux: $mode" || warn "SELinux: $mode"
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        echo "Firewall zones : $(firewall-cmd --get-active-zones | grep -v '^ ' | tr '\n' ' ')"
        echo "Allowed        : $(firewall-cmd --list-services)"
    fi
    echo
    echo "Last 5 logins:"
    last -n 5 -w 2>/dev/null | head -n 5
    if [[ $EUID -eq 0 ]]; then
        local fails
        fails=$(journalctl -u sshd --since "24 hours ago" --no-pager 2>/dev/null | grep -c "Failed password")
        (( fails > 0 )) && warn "$fails failed SSH password attempts in last 24h" \
                        || ok "No failed SSH passwords in last 24h"
    fi
}

show_updates() {
    section "Updates"
    local out rc
    out=$(dnf -q check-update 2>/dev/null); rc=$?
    if   (( rc == 100 )); then
        warn "Updates available: $(echo "$out" | grep -Ec '^[A-Za-z0-9_.+-]+\.[A-Za-z0-9_]+ ')"
        echo "(run: $0 --update)"
    elif (( rc == 0 )); then
        ok "System is up to date"
    else
        warn "Could not check for updates (network or repo issue)"
    fi
    if command -v needs-restarting >/dev/null 2>&1; then
        needs-restarting -r >/dev/null 2>&1 || warn "A reboot is recommended (kernel/core libs updated)"
    fi
}

# ---------- actions ----------
do_cleanup() {
    need_root
    section "Cleanup"
    dnf clean all -q && ok "dnf cache cleaned"
    journalctl --vacuum-time=14d 2>&1 | tail -n 1
    dnf -y autoremove -q && ok "Unused dependencies removed"
}

do_update() {
    need_root
    section "Applying updates"
    dnf -y upgrade
}

# ---------- main ----------
ACTION="report"
case "${1:-}" in
    "")          ;;
    --cleanup)   ACTION="cleanup" ;;
    --update)    ACTION="update" ;;
    -h|--help)   usage; exit 0 ;;
    *)           echo "Unknown option: $1" >&2; usage; exit 1 ;;
esac

show_system
show_cpu_load
show_memory
show_disk
show_top_processes
show_network
show_services
show_security
show_updates

case "$ACTION" in
    cleanup) do_cleanup ;;
    update)  do_update ;;
esac

echo
echo "Done."
