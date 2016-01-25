## bearDropper 

**dropbear log parsing ban agent for OpenWRT (Chaos Calmer rewrite of dropBrute.sh)** - @robzr

OpenWRT (Chaos Calmer) script for blocking repeated invalid dropbear ssh connection attempts (embedded fail2ban)

**Status**

Working, no known issues.

**Dependencies** 

None! Written entirely in busybox ash, uses all standard OpenWRT commands.

**Installation**

To install the latest bearDropper, run the following:

	wget -O- http://cdn.rawgit.com/robzr/bearDropper/master/install.sh | sh

  - To modify the config options, edit the uci config file (/etc/config/bearDropper)
  - Use bearDropper -h to see options for runtime config (runtime options override uci config options)
  - Consider increasing your syslog ring buffer size (/etc/config/system option log_size)

**Logging**

  - logs to the syslog ring buffer by default (view with the logread command)
  - logs to stdout with "-f stdout" (or logFacility config option)
  - increaser verbosity with "-l 2" (or logLevel config option)

**Features**

 - small size, low memory footprint, no external dependencies
 - runs using sane defaults out of the box, uses uci for config, overwriteable via command line arguments
 - uses a self managed state database, from which iptables is periodically sync'd (for resiliency)
 - optionally syncs state database to persistent storage - includes logic to avoid excessive flash writes
 - state database optionally supports compression (see config file)
 - uses highly readable BIND time syntax for all time values (ex: 9d2h3s is 9 days, 2 hours, 3 seconds)
 - when run via included init script, runs in the background for realtime monitoring
 - can also be run by hand to process historical log entries
 - self installs into iptables for simple and reliable setup (easily disabled)
 - conservative input validation for security

**TBD**

 - Add optional freegeoip.net lookups for (de|ac)cellerated banning
 - Add elegant auto-hook to forward chain (ex: forwarding_wan_rule)
 - implement whitelist
 - CIDR processing for bans & whitelists
 - self expiring ipset based ban list
 - package and submit to openwrt repo once it's reasonably bug free
 - ipv6 support

Also see the sister project sub2rbl for RBL based banning: https://github.com/robzr/sub2rbl
