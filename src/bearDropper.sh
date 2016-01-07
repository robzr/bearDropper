#!/bin/ash -m
#
# bearDropper - dropbear log parsing ban agent for OpenWRT (Chaos Calmer rewrite of dropBrute.sh)
#   http://github.com/robzr/bearDropper  -- Rob Zwissler 11/2015
# 
#   - lightweight, no dependencies outside of default Chaos Calmer installation
#   - Optionally uses uci for configuration, overrideable via command line arguments
#   - Can run continuously in background (ie: via included init script) or periodically (via cron)
#   - Can use BIND style time shorthand, ex: 1w5d3h1m8s is 1 week, 5 days, 3 hours, 1 minute, 8 seconds
#   - Whitelist IP or CIDR entries in UCI or state file
#   - By default uses tmpfs for state file; can optionally write to persistent storage - routines are
#     optimized to avoid excessive writes on flash storage
#   - Runs in one of the following operational modes for flexibility:
#     follow mode - follows the log file to process entries as they happen; generally launched via init
#        script.  Responds the fastest, runs the most efficiently, but is always in memory.
#     interval mode - only processes entries going back the specified interval; requires more processing
#        than today mode, but responds more accurately.  Generally run periodically via cron.
#     today mode - looks at log entries from the day it is being run, simple and lightweight, generally
#        run from cron periodically (same simplistic behavior as dropBrute.sh)
#     entire mode - runs through entire contents of the syslog ring buffer
#

# Here is a configuration example (this would be the contents of a file /etc/config/bearDropper)
#
# config bearDropper
#   option defaultMode 		24h
#   option attemptCount 	3
#   option attemptPeriod 	1d
#   option banLength    	1w
#   option firewallHookChain 	input_wan_rule
#   option firewallHookPosition	1
#   list   whitelist		10.0.1.0/24
#   list   whitelist		192.168.1.0/24

# Loads config variables from uci - Args: $1 = variable_name (also used for uci option name), $2 = default_value
uciLoad () {
  local getUci uciSection='bearDropper.@[0]'
  getUci=`uci -q get ${uciSection}."$1"` || getUci="$2"
  eval $1=\'$getUci\'
}

uciLoad defaultMode 24h			# Mode used if no mode is specified on command line - modes are
					# follow, today, entire or enter a time string for interval mode.
 					# Time strings would be something like 1h30m for 1 hour 30 minutes,
					# valid types are (w)eek (d)ay (h)our (m)inutes (s)econds.

uciLoad attemptCount 3			# Failure attempts from a given IP required to trigger a ban

uciLoad attemptPeriod 1d		# Time period during which attemptCount must be exceeded in order to 
					# trigger a ban.

uciLoad banLength 1w			# How long a ban exists for once the attempt threshhold is exceeded

uciLoad logLevel 1			# bearDropper log level - 0 = silent, 1 = standard (default), 2 = verbose...

uciLoad logFacility 'authpriv.notice'	# bearDropper logger facility/priority - use stdout or stderr to bypass syslog

uciLoad persistentBanFileWritePeriod 1d	# How often to write to persistent ban file. 0 is never, otherwise a 
					# time string can be used to specify minimum intervals between writes.
					# Consider the life of flash storage when setting this.  To make it write 
					# on every run when using a mode other than follow, set it to 1.

uciLoad fileBDDBPersist '/etc/bearDropper.bddb'	# Persistent BDDB (state/tracking) file - consider moving to USB or SD
						# storage if available to save wear & tear

uciLoad firewallHookPosition 1 		# position in firewall chain to hook (-1 = do not add, 0 = append, 1+ = absolute position)

uciLoad firewallHookChain 'input_wan_rule' 	# firewall chain to hook into

uciLoad firewallChain 'bearDropper'	# the firewall chain bearDropper stores firewall commands in

#
##  Advanced variables below - changeable via uci only (no cmdline), it is unlikely that these will need to be changed, but just in case...
#

uciLoad logTag 'bearDropper'		# bearDropper syslog tag

uciLoad fileBDDBTemp '/tmp/bearDropper.bddb'	# Temporary BDDB (state/tracking) file

uciLoad regexLogString '^[a-zA-Z ]* [0-9: ]* authpriv.warn dropbear\['	# Regex to look for when initially parsing 
									# out auth fail log entries

uciLoad firewallTarget '-j DROP'	# The target for a banned IP - you could use this to jump to a custom chain
					# for logging, launching external commands, etc.

uciLoad cmdLogread 'logread'		# logread command, parameters can be added for tuning, ex: "logread -l250"

uciLoad formatLogDate '%b %d %H:%M:%S %Y'	# The format of the syslog time stamp

uciLoad followModePurgeInterval 10m  	# Time period, when in follow mode, to check for expired bans if there
					# no log activity 
# _LOAD_MEAT_
#
# Begin functions
#

isValidBindTime () { echo "$1" | egrep -q '^[0-9]+$|^([0-9]+[wdhms]?)+$' ; }

# expands Bind time syntax into seconds (ex: 3w6d23h59m59s)
expandBindTime () {
  if echo "$1" | egrep -q '^[0-9]+$' ; then
    echo $1
    return 0
  elif ! echo "$1" | egrep -iq '^([0-9]+[wdhms]?)+$' ; then
    echo "Error: Invalid time specified ($1)" >&2
    exit 1
  fi
  local newTime=`echo $1 | sed 's/\b\([0-9]*\)w/\1*7d+/g' | sed 's/\b\([0-9]*\)d[ +]*/\1*24h+/g' | \
    sed 's/\b\([0-9]*\)h[ +]*/\1*60m+/g' | sed 's/\b\([0-9]*\)m[ +]*/\1*60s+/g' | sed 's/s//g' | sed 's/+$//'`
  echo $(($newTime))
}

# Args: $1 = loglevel, $2 = info to log
logLine () {
  [ $logLevel -gt $1 ] && return
  shift
  
  if [ "$logFacility" == "stdout" ] ; then echo $@ 
  elif [ "$logFacility" == "stderr" ] ; then echo $@ >&2
  else logger -t "$logTag" -p "$logFacility" "$@"
  fi
}

getLogTime () { date -d"`echo $1 | cut -f2-5 -d\ `" -D"$formatLogDate" +%s ;}

getLogIP () { echo $1 | sed 's/^.*from \([0-9.]*\):[0-9]*$/\1/' ;}

processAll () {
  # here is where the entire BDDB processing takes place
  # basically loop through BDDB and run processEntry for each entry
}

processEntry () {
  # process single BDDB entry
}

# Reads raw log line, if needed, adds to BDDB runs processEntry for that line
processLine () {
  local logTime=`getLogTime "$1"`
  local logIP=`getLogIP "$1"`
  local leaseLine=`printf '%s,%s\n' $logIP $logTime`
  timeNow=`date +%s`
  timeFirst=$((timeNow - attemptPeriod))

#  if [ "$logTime" -ge "$timeFirst" ] ; then
#    if ! egrep -q "^$leaseLine$" "$fileBanTemp" ; then 
#      logLine "Adding $leaseLine to temp ban file..."
#      echo $leaseLine >> "$fileBanTemp"
#  fi ; fi 
}

printUsage () {
  cat <<-_EOF_
	Usage: bearDropper [-m mode] [-a #] [-b #] [-c ...] [-C ...] [-l #] [-f ...] [-F #] [-p #] [-P #] [-s ...]

	  Running Modes (-m)
	    follow     constantly monitors log
	    entire     processes entire log contents
	    today      processes log entries from same day only
	    ...        interval mode, specify time string or seconds

	  Options
	    -a #   attempt count before banning (def: $attemptCount)
	    -b #   ban length once attempts hit threshhold (def: $banLength)
	    -c ... firewall chain to record bans (def: $firewallChain)
	    -C ... firewall chain to hook into (def: $firewallHookChain)
	    -f ... log facility (syslog facility or stdout/stderr) (def: $logFacility)
	    -F #   firewall chain hook position (def: $firewallHookPosition)
	    -l #   log level - 0=off, 1=standard, 2=verbose (def: $logLevel)
	    -p #   attempt period which attempt counts must happen in (def: $attemptPeriod)
	    -P #   persistent state file write period (def: $persistentBanFileWritePeriod)
	    -s ... persistent state file location (def: $fileBDDBPersist)

	  All time strings can be specified in seconds, or using BIND style
	  time strings, ex: 1w2d3h5m30s is 1 week, 2 days, 3 hours, etc...

	_EOF_
}

#
##  Begin main logic
#
unset logMode
while getopts a:b:c:C:f:F:l:m:p:P:s: arg ; do
  case "$arg" in 
    a) attemptCount=$OPTARG
      ;;
    b) banLength=$OPTARG
      ;;
    c) firewallChain=$OPTARG
      ;;
    C) firewallHookChain=$OPTARG
      ;;
    f) logFacility=$OPTARG
      ;;
    F) firewallHookPosition=$OPTARG
      ;;
    l) logLevel=$OPTARG
      ;;
    m) logMode=$OPTARG
      ;;
    p) attemptPeriod=$OPTARG
      ;;
    P) persistentBanFileWritePeriod=$OPTARG
      ;;
    s) fileBDDBPersist=$OPTARG
      ;;
    *) printUsage
      exit 3
  esac
  shift `expr $OPTIND - 1`
done
[ -z $logMode ] && logMode="$defaultMode"

attemptPeriod=`expandBindTime $attemptPeriod`
banLength=`expandBindTime $banLength`
persistentBanFileWritePeriod=`expandBindTime $persistentBanFileWritePeriod`
followModePurgeInterval=`expandBindTime $followModePurgeInterval`

timeNow=`date +%s`
timeFirst=$((timeNow - attemptPeriod))

# main event loops
if [ "$logMode" = 'follow' ] ; then 
  logLine 2 "Running in follow mode..."
  $cmdLogread -f | egrep "$regexLogString" | while true ; do
    read -t $followModePurgeInterval line && processLine "$line"
  done
elif [ "$logMode" = 'entire' ] ; then 
  logLine 2 "Running in entire mode..."
  $cmdLogread | egrep "$regexLogString" | while read line ; do processLine "$line" ; done
elif [ "$logMode" = 'today' ] ; then 
  logLine 2 "Running in today mode..."
  $cmdLogread | egrep "`date +'^%a %b %d ..:..:.. %Y'`" | egrep "$regexLogString" | while read line ; do processLine "$line" ; done
elif isValidBindTime "$logMode" ; then
  logInterval=`expandBindTime $logMode`
  logLine 2 "Running in interval mode (reviewing $logInterval seconds of log entries)..."
  timeStart=$((timeNow - logInterval))
  $cmdLogread | egrep "$regexLogString" | while read line ; do
    timeWhen=`getLogTime "$line"`
    [ $timeWhen -ge $timeStart ] && processLine "$line"
  done
else
  logline 0 "Error - invalid log mode $logMode
  exit -1
fi
