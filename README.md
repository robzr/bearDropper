## bearDropper 

OpenWRT (Chaos Calmer) script for blocking repeated invalid dropbear ssh connection attempts (think fail2ban for OpenWRT).  Features:
 - lightweight, written in busybox ash with zero dependencies on external programs
 - runs using sane defaults out of the box, uses uci for config, overwriteable via command line arguments
 - supports whitelisting of IP addresses or CIDR blocks
 - uses highly readable BIND9 time format for all time values
 - (default) running mode uses init script to follow the log in real-time
 - (optional) 3 other running modes can runs periodically/scheduled to optimize for low memory or serial/batch style usage
 - (optional) records state to persistent storage, with intelligent routines to avoid excessive flash writes
 - (optional) self installs hook into iptables for simple and reliable setup
 - (optional) logs actions to syslog (via logger)
 - stripping all comments shrinks to 62% file space, gzips to 18%

TBD:
 - more testing of expiration logic
 - more testing of peristent storage logic
 - make whitelisting functional
 - finish/test procd init script
 - create opkg, incorporate to makefile
 - add native CIDR processing for better whitelisting/blacklisting
 - possibly add (optional) ipset support instead of the chain
 - possibly add support for a file based syslog
 - add ipv6 support
