## bearDropper 
--Rob Zwissler @robzr

**dropbear log parsing ban agent for OpenWRT (Chaos Calmer rewrite of dropBrute.sh)**

OpenWRT (Chaos Calmer) script for blocking repeated invalid dropbear ssh connection attempts (embedded fail2ban)

Dependencies: nothing (stock Chaos Calmer - written entirely in busybox ash)

Installation:
	opkg install http://........
	/etc/init.d/bearDropper enable
	/etc/init.d/bearDropper start
  - To modify the config options, edit the uci config file (/etc/config/bearDropper)
  - To see options for run-time config, run bearDropper -h (run time options override uci config options)
  - Consider increasing your syslog ring buffer size if you have memory to spare - see /etc/config/system option log_size (in kb), particularily if not using follow mode

Logging: 
  - logs to the syslog ring buffer by default (view with the logread command)
  - can log to stdout by changing the config option logFacility in the config file or by using the command line option -f (ex: -f stdout)
  - Verbosity changed with the config option logLevel or by using -l (for increased verbosity use: -l 2)

Features:
 - lightweight, small size, uses only out of the box OpenWRT commands
 - uses a self managed state database, which iptables is periodically sync'd (for resiliency)
 - runs using sane defaults out of the box, uses uci for config, overwriteable via command line arguments
 - supports whitelisting of IP addresses or CIDR blocks (TBD)
 - uses highly readable BIND9 time format for all time values
 - (default) running mode uses init script to follow the log in real-time
 - (optional) 3 other running modes can runs periodically/scheduled to optimize for low memory or serial/batch style usage
 - (optional) records state to persistent storage, with intelligent routines to avoid excessive flash writes
 - (optional) self installs hook into iptables for simple and reliable setup
 - stripping all comments shrinks to 62% file space, gzips to 18%

TBD:
 - optional inline compression on bddb (bddbz)
 - make whitelisting functional
 - procd init script
 - opkg, incorporate to makefile
 - native CIDR processing for better whitelisting/banning (/24 based bans?)
 - possibly add (optional) ipset support instead of chain based ?
 - support for a file based syslog
 - ipv6

Also see the sister project for sync'ing with RBLs: https://github.com/robzr/sub2rbl

