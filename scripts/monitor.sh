#!/bin/bash
#
# monitor.sh
# Top 10 one-liners for monitoring Linux system health (CPU, memory, disk, processes).
#
# Usage: sudo ./monitor.sh
#

SEP="------------------------------------------------------------"

line() {
    echo ""
    echo "$SEP"
    echo " $1"
    echo "$SEP"
}

line "1. UPTIME / LOAD AVERAGE"
uptime

line "2. TOP PROCESSES (live CPU/MEM snapshot)"
top -bn1 | head -20

line "3. MEMORY USAGE"
free -m

line "4. CPU / MEMORY / I/O OVER TIME (vmstat)"
if command -v vmstat &>/dev/null; then
    vmstat 1 5
else
    echo "vmstat not found. Install with: sudo dnf install procps-ng -y"
fi

line "5. DISK I/O UTILIZATION (iostat)"
if command -v iostat &>/dev/null; then
    iostat -xz 1 5
else
    echo "iostat not found. Install with: sudo dnf install sysstat -y"
fi

line "6. DISK SPACE USAGE"
df -h

line "7. TOP 10 PROCESSES BY CPU"
ps aux --sort=-%cpu | head -11

line "8. LISTENING PORTS / OWNING PROCESSES"
if command -v ss &>/dev/null; then
    ss -tulnp
elif command -v netstat &>/dev/null; then
    netstat -tulnp | grep LISTEN
else
    echo "Neither ss nor netstat found."
fi

line "9. RECENT ERROR-LEVEL LOGS (this boot)"
if command -v journalctl &>/dev/null; then
    journalctl -p err -b --no-pager 2>/dev/null | tail -20
else
    echo "journalctl not available. Check /var/log/messages instead."
fi

line "10. FAILED SYSTEMD SERVICES"
if command -v systemctl &>/dev/null; then
    systemctl --failed --no-pager
else
    echo "systemctl not available."
fi

echo ""
echo "$SEP"
echo " Generated: $(date)"
echo "$SEP"
