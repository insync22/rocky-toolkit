#!/bin/bash
# sysinfo.sh - shows a quick summary of this machine
clear
echo "=============================="
echo "   SYSTEM INFORMATION"
echo "=============================="
echo "Hostname : $(hostname)"
echo "IP address: $(hostname -I | awk '{print $1}')"
echo "OS       : $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
echo "Uptime   : $(uptime -p)"
echo ""
echo "--- Memory ---"
free -h | grep Mem
echo ""
echo "--- Disk (root partition) ---"
df -h / | tail -1
echo ""
echo "--- CPU ---"
echo "Cores    : $(nproc)"
echo "Load avg : $(uptime | awk -F'load average:' '{print $2}')"
echo "=============================="
