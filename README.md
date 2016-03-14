## bearDropper 

**dropbear log parsing ban agent for OpenWRT (Chaos Calmer rewrite of dropBrute.sh)** - @robzr

OpenWRT (Chaos Calmer) script for blocking repeated invalid dropbear ssh connection attempts (embedded fail2ban)

**Status**

Working, no known issues.

**Dependencies** 

None! Written entirely in busybox ash, uses all standard OpenWRT commands.

**Installation**

To install the latest bearDropper, run:

	wget -qO- http://rawgit.com/robzr/bearDropper/master/install.sh | sh

 - To modify the config options, edit the uci config file (/etc/config/bearDropper)
 - Use bearDropper -h to see options for runtime config (runtime options override uci config options)
 - Consider increasing your syslog ring buffer size (/etc/config/system option log_size)

**Logging**

 - logs to the syslog ring buffer by default (view with the logread command)
 - logs to stdout with "-f stdout" (or logFacility config option)
 - increaser verbosity with "-l 2" (or logLevel config option)

**Features**

 - small size, low memory footprint, no external dependencies
 - uses uci for config, overridable via command line arguments
 - uses a state database which periodically syncs to iptables (for resiliency)
 - can sync state database to persistent storage, with logic to avoid excessive flash writes
 - state database supports optional compression
 - uses highly readable BIND time syntax for all time values (ex: 9d2h3s is 9 days, 2 hours, 3 seconds)
 - runs in the background for realtime monitoring when run via included init script
 - can also be run by hand to process historical log entries
 - self installs into iptables for simple and reliable setup (easily disabled)
 - conservative input validation for security

**TBD**

 - Add optional freegeoip.net lookups for (de|ac)cellerated banning
 - implement whitelist
 - CIDR processing for bans & whitelists
 - self expiring ipset based ban list
 - package and submit to openwrt repo once it's reasonably bug free
 - ipv6 support

Also see the sister project sub2rbl for RBL based banning: https://github.com/robzr/sub2rbl
Discussion of these projects at OpenWRT forums: https://forum.openwrt.org/viewtopic.php?id=62084
