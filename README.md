## bearDropper 

OpenWRT (Chaos Calmer) script for blocking repeated invalid dropbear ssh connection attempts (think fail2ban for OpenWRT).  Features:
 - lightweight, written in busybox ash with zero dependencies on external programs
 - runs using sane defaults out of the box, but uses uci for config, overwriteable via command line arguments
 - supports whitelisting of IP addresses or CIDR blocks in uci config or persistent state file
 - uses efficient and highly readable BIND9 time format for all time values
 - (default) running mode uses init script to constantly follow the log in real-time
 - (optional) running mode runs periodically/scheduled to optimize for low memory or serial/batch style usage
 - (optional) records state to persistent storage, with intelligent routines to avoid excessive flash writes
 - (optional) self installs hook into iptables for simple and reliable setup
 - (optional) logs actions to syslog (via logger)

TBD:
 - create opkg with procd init script, submit to official repo
 - add ipv6 support
 - add optional ipset support
