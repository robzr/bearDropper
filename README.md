## bearDropper 

**dropbear log parsing ban agent for OpenWRT (Chaos Calmer rewrite of dropBrute.sh)** - @robzr

OpenWRT (Chaos Calmer) script for blocking repeated invalid dropbear ssh connection attempts (embedded fail2ban)

**Status**

Probably has some bugs, still a work in progress, but I'm using it.

**Dependencies** 

None! Written entirely in busybox ash, uses only stock Chaos Calmer commands.

**Installation**

Make bearDropper, place in /usr/sbin, config file goes in /etc/config and init script in /etc/init.d

	/etc/init.d/bearDropper enable
	/etc/init.d/bearDropper start

  - To modify the config options, edit the uci config file (/etc/config/bearDropper)
  - Use bearDropper -h to see options for runtime config (runtime options override uci config options)
  - Consider increasing your syslog ring buffer size if you have memory to spare (/etc/config/system option log_size), particularily if not using follow mode

**Logging**
  - logs to the syslog ring buffer by default (view with the logread command)
  - can log to stdout by changing the config option logFacility in the config file or by using the command line option -f (ex: -f stdout)
  - Verbosity changed with the config option logLevel or by using -l (for increased verbosity use: -l 2)

**Features**
 - lightweight, small size, uses only out of the box OpenWRT commands
 - uses a self managed state database, from which iptables is periodically sync'd (for resiliency)
 - state database file(s) are compressed by default (easily disabled with config option)
 - runs using sane defaults out of the box, uses uci for config, overwriteable via command line arguments
 - supports whitelisting of IP addresses or CIDR blocks (TBD)
 - uses highly readable BIND time syntax for all time values
 - default running mode follows the log in real-time (usually run via included init script)
 - 3 other available running modes that examine historical logs (to optimize for low memory or serial/batch style usage)
 - (optional) records state file to persistent storage with intelligent routines to avoid excessive flash writes
 - self installs hook into iptables for simple and reliable setup (easily disabled)
 - stripping all comments shrinks to 62% file space, gzip shrinks to 18% (if 20k is too big for ya)
 - lots of input validation for paranoid prevention of injection attacks

**TBD**
 - fix init script - signal handling to quit properly?
 - make whitelisting functional
 - package!
 - native CIDR processing for better whitelisting/banning (/24 based bans?)
 - possibly add (optional) ipset support instead of chain based ?
 - support for a file based syslog (would anyone use this)
 - ipv6

Also see the sister project sub2rbl for RBL based banning: https://github.com/robzr/sub2rbl

