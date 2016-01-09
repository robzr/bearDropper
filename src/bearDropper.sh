#!/bin/ash
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

# Loads config variables from uci
# Args: $1 = variable_name (also used for uci option name), $2 = default_value
uciLoad () {
  local getUci uciSection='bearDropper.@[0]'
  getUci=`uci -q get ${uciSection}."$1"` || getUci="$2"
  eval $1=\'$getUci\'
}


# Common config variables - these can also be changed at runtime with command line options
#

uciLoad defaultMode 24h			# Mode used if no mode is specified on command line - modes are
					# follow, today, entire or enter a time string for interval mode.
 					# Time strings would be something like 1h30m for 1 hour 30 minutes,
					# valid types are (w)eek (d)ay (h)our (m)inutes (s)econds.

uciLoad attemptCount 5			# Failure attempts from a given IP required to trigger a ban

uciLoad attemptPeriod 1d		# Time period threshold during which attemptCount must be exceeded in order to 
					# trigger a ban.

uciLoad banLength 1w			# How long a ban exist once the attempt threshold is exceeded

uciLoad logLevel 1			# bearDropper log level, 0=silent 1=default, 2=verbose, 3=debug

uciLoad logFacility 'authpriv.notice'	# bearDropper logger facility/priority - use stdout or stderr to bypass syslog

uciLoad persistentStateWritePeriod 1d	# How often to write to persistent state file. -1 is never, 0 is on program
					# exit, and a time string can be used to specify minimum intervals between writes
                                        # for periodic saving in follow mode.  Consider the life of flash storage when 
                                        # setting this.

uciLoad fileStatePersist '/etc/bearDropper.bddb'	# Persistent state file - consider moving to USB
							# or SD storage if available to save wear & tear

uciLoad firewallHookChain 'input_wan_rule' 	# firewall chain to hook the chain containing ban rules into

uciLoad firewallHookPosition 1 		# position in firewall hook chain (-1 = don't add, 0 = append, 1+ = absolute position)

uciLoad firewallChain 'bearDropper'	# the firewall chain bearDropper stores firewall commands in


# Advanced variables below - changeable via uci only (no cmdline), it is unlikely that these will need to be changed, but just in case...
#

uciLoad logTag "bearDropper[$$]"		# bearDropper syslog tag

uciLoad fileStateTemp '/tmp/bearDropper.bddb'	# Temporary state file

uciLoad regexLogString '^[a-zA-Z ]* [0-9: ]* authpriv.warn dropbear\['	# Regex to look for when initially parsing 
									# out auth fail log entries

uciLoad firewallTarget 'DROP'		# The target for a banned IP - you could use this to jump to a custom chain
					# for logging, launching external commands, etc.

uciLoad cmdLogread 'logread'		# logread command, parameters can be added for tuning, ex: "logread -l250"

uciLoad formatLogDate '%b %e %H:%M:%S %Y'	# The format of the syslog time stamp

uciLoad followModePurgeInterval 10m  	# Time period, when in follow mode, to check for expired bans if there
					# no log activity 

# Begin functions
#
# _LOAD_MEAT_

isValidBindTime () { echo "$1" | egrep -q '^[0-9]+$|^([0-9]+[wdhms]?)+$' ; }

# expands Bind time syntax into seconds (ex: 3w6d23h59m59s)
expandBindTime () {
  if echo "$1" | egrep -q '^[0-9]+$' ; then
    echo $1
    return 0
  elif ! echo "$1" | egrep -iq '^([0-9]+[wdhms]?)+$' ; then
    logLine 0 "Error: Invalid time specified ($1)" >&2
    exit 254
  fi
  local newTime=`echo $1 | sed 's/\b\([0-9]*\)w/\1*7d+/g' | sed 's/\b\([0-9]*\)d[ +]*/\1*24h+/g' | \
    sed 's/\b\([0-9]*\)h[ +]*/\1*60m+/g' | sed 's/\b\([0-9]*\)m[ +]*/\1*60s+/g' | sed 's/s//g' | sed 's/+$//'`
  echo $(($newTime))
}

# Args: $1 = loglevel, $2 = info to log
logLine () {
  [ $1 -gt $logLevel ] && return
  shift
  
  if [ "$logFacility" == "stdout" ] ; then echo "$@"
  elif [ "$logFacility" == "stderr" ] ; then echo "$@" >&2
  else logger -t "$logTag" -p "$logFacility" "$@"
  fi
}

# extra validation - fails safe.  Args: $1=log line
getLogTime () {
  local logDateString=`echo "$1" | sed -n 's/^[A-Z][a-z]* \([A-Z][a-z]*  *[0-9][0-9]*  *[0-9][0-9]*:[0-9][0-9]:[0-9][0-9] [0-9][0-9]*\) .*$/\1/p'`
  date -d"$logDateString" -D"$formatLogDate" +%s || logLine 1 "Error: logDateString($logDateString) malformed line ($1)"
#  echo TESTING:::date -d"$logDateString" -D"$formatLogDate" +%s:::
}

# extra validation - fails safe.  Args: $1=log line
getLogIP () { echo "$1" | sed -n 's/^.*from \([0-9.]*\):[0-9]*$/\1/p' ; }

# Args: $1=IP
unBanIP () {
  if iptables -C $firewallChain -s $ip -j "$firewallTarget" 2>/dev/null ; then
    logLine 1 "Removing ban rule for IP $ip from iptables"
    iptables -D $firewallChain -s $ip -j "$firewallTarget"
  else
    logLine 3 "unBanIP() Ban rule for $ip not present in iptables"
  fi
}

# Args: $1=IP
banIP () {
  local ip="$1"

  if ! iptables -L $firewallChain >/dev/null 2>/dev/null ; then  
    logLine 1 "Creating iptables chain $firewallChain"
    iptables -N $firewallChain
  fi

  if [ $firewallHookPosition -ge 0 ] ; then
    if ! iptables -C $firewallHookChain -j $firewallChain 2>/dev/null ; then
      logLine 1 "Inserting hook into iptables chain $firewallHookChain"
      if [ $firewallHookPosition -eq 0 ] ; then
        iptables -A $firewallHookChain -j $firewallChain
      else
        iptables -I $firewallHookChain $firewallHookPosition -j $firewallChain
  fi ; fi ; fi
   
  if ! iptables -C $firewallChain -s $ip -j "$firewallTarget" 2>/dev/null ; then
    logLine 1 "Inserting ban rule for IP $ip into iptables chain $firewallChain"
    iptables -A $firewallChain -s $ip -j "$firewallTarget"
  else
    logLine 3 "banIP() rule for $ip already present in iptables chain"
  fi
}

wipeFirewall () {
  if [ $firewallHookPosition -ge 0 ] ; then
    if iptables -C $firewallHookChain -j $firewallChain 2>/dev/null ; then
      logLine 1 "Removing hook from iptables chain $firewallHookChain"
      iptables -D $firewallHookChain -j $firewallChain
  fi ; fi
  if iptables -L $firewallChain >/dev/null 2>/dev/null ; then  
    logLine 1 "Flushing and removing iptables chain $firewallChain"
    iptables -F $firewallChain 2>/dev/null
    iptables -X $firewallChain 2>/dev/null
  fi
}

# expunge expired records
bddbPurgeExpires () {
  local now=`date +%s`
  bddbGetAllIPs | while read ip ; do
    if [ `bddbGetStatus $ip` -eq 1 ] ; then
      if [ $((banLength + `bddbGetTimes $ip`)) -lt $now ] ; then
        logLine 1 "Ban expired for $ip, removing from iptables"
        unBanIP $ip
        bddbRemoveRecord $1 
      else 
        logLine 2 "bddbPurgeExpires($ip) not expired yet"
      fi
    elif [ `bddbGetStatus $ip` -eq 0 ] ; then
      local times=`bddbGetTimes $ip | tr , _`
      local timeCount=`echo $times | wc -w`
      local lastTime=`echo $times | cut -d\  -f$timeCount`
      if [ $((lastTime + attemptPeriod)) -lt $now ] ; then
        bddbRemoveRecord $1 
    fi ; fi
  done
}

# Only used when status is already 0 and possibly going to 1, Args: $1=IP
bddbEvaluateRecord () {
  local ip=$1 firstTime lastTime
  local times=`bddbGetRecord $1 | cut -d, -f2- | tr , \ `
  local timeCount=`echo $times | wc -w`
  local didBan=0
  
  # condition 0 - not enough attempts; do nothing
  # condition 1 - attempts exceed threshold in time period; ban
  # condition 2 - attempts exceed threshold but time period is too long; trim oldest time, recalculate
  while [ $timeCount -ge $attemptCount ] ; do
    firstTime=`echo $times | cut -d\  -f1`
    lastTime=`echo $times | cut -d\  -f$timeCount`
    timeDiff=$((lastTime - firstTime))
    logLine 3 "bddbEvaluateRecord($ip) count=$timeCount timeDiff=$timeDiff/$attemptPeriod"
    if [ $timeDiff -le $attemptPeriod ] ; then
      bddbEnableStatus $ip $lastTime
      logLine 2 "bddbEvaluateRecord($ip) exceeded ban threshold, adding to iptables"
      banIP $ip
      didBan=1
    fi
    # slice one off the front, see what happens now.
    times=`echo $times | cut -d\  -f2-`
    timeCount=`echo $times | wc -w`
  done  
  [ $didBan == 0 ] && logLine 2 "bddbEvaluateRecord($ip) does not exceed threshhold, skipping"
}

# Reads filtered log line and evaluates for action  Args: $1=log line
processLogLine () {
  local time=`getLogTime "$1"` 
  local ip=`getLogIP "$1"` 
  local timeNow=`date +%s`
  local timeFirst=$((timeNow - attemptPeriod))
  local status="`bddbGetStatus $ip`"
  local oldTime

  if [ "$status" == "-1" ] ; then
    logLine 2 "processLogLine($ip,$time) IP is whitelisted"
  elif [ "$status" == "1" ] ; then
    oldTime=`bddbGetTimes $ip`
    if [ $oldTime -ge $time ] ; then
      logLine 2 "processLogLine($ip,$time) already banned, ban timestamp already equal or newer"
    else
      logLine 2 "processLogLine($ip,$time) already banned, updating ban timestamp"
      bddbEnableStatus $ip $time
    fi
    banIP $ip
  elif [ ! -z $ip -a ! -z $time ] ; then
    bddbAddRecord $ip $time
    logLine 2 "processLogLine($ip,$time) Added record, comparing"
    bddbEvaluateRecord $ip 
  else
    logLine 1 "processLogLine($ip,$time) malformed line ($1)"
  fi
}

loadState () {
  bddbLoad "$fileStatePersist"
  bddbLoad "$fileStateTemp"
}

# we need to add intelligent differnetal between temp & perm
# Args, $1=-f to force a persistent write (unless lastPersistentStateWrite=-1)
saveState () {
  local forcePersistent=0
  [ "$1" = "-f" ] && forcePersistent=1

  if [ $bddbStateChange -gt 0 ] ; then
    logLine 3 "saveState() saving to temp state file"
    bddbSave "$fileStateTemp"
    logLine 3 "saveState() now=`date +%s` lPSW=$lastPersistentStateWrite pSWP=$persistentStateWritePeriod fP=$forcePersistent"
  fi    
  if [ $persistentStateWritePeriod -gt 0 ] || [ $persistentStateWritePeriod -eq 0 -a $forcePersistent -eq 1 ] ; then
    if [ $((`date +%s` - lastPersistentStateWrite)) -ge $persistentStateWritePeriod ] || [ $forcePersistent -eq 1 ] ; then
      if [ ! -f "$fileStatePersist" ] || ! cmp -s "$fileStateTemp" "$fileStatePersist" ; then
        logLine 2 "saveState() writing to persistent state file"
        bddbSave "$fileStatePersist"
        lastPersistentStateWrite="`date +%s`"
  fi ; fi ; fi
}

printUsage () {
  cat <<-_EOF_
	Usage: bearDropper [-m mode] [-a #] [-b #] [-c ...] [-C ...] [-l #] [-f ...] [-F #] [-p #] [-P #] [-s ...]

	  Running Modes (-m) (def: $defaultMode)
	    follow     constantly monitors log
	    entire     processes entire log contents
	    today      processes log entries from same day only
	    ...        interval mode, specify time string or seconds
	    wipe       wipe state files, unhook and remove firewall chain

	  Options
	    -a #   attempt count before banning (def: $attemptCount)
	    -b #   ban length once attempts hit threshold (def: $banLength)
	    -c ... firewall chain to record bans (def: $firewallChain)
	    -C ... firewall chain to hook into (def: $firewallHookChain)
	    -f ... log facility (syslog facility or stdout/stderr) (def: $logFacility)
	    -F #   firewall chain hook position (def: $firewallHookPosition)
	    -l #   log level - 0=off, 1=standard, 2=verbose (def: $logLevel)
	    -p #   attempt period which attempt counts must happen in (def: $attemptPeriod)
	    -P #   persistent state file write period (def: $persistentStateWritePeriod)
	    -s ... persistent state file location (def: $fileStatePersist)

	  All time strings can be specified in seconds, or using BIND style
	  time strings, ex: 1w2d3h5m30s is 1 week, 2 days, 3 hours, etc...

	_EOF_
}

#  Begin main logic
#
unset logMode
while getopts a:b:c:C:f:F:hl:m:p:P:s: arg ; do
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
    P) persistentStateWritePeriod=$OPTARG
      ;;
    s) fileStatePersist=$OPTARG
      ;;
    *) printUsage
      exit 254
  esac
  shift `expr $OPTIND - 1`
done
[ -z $logMode ] && logMode="$defaultMode"

attemptPeriod=`expandBindTime $attemptPeriod`
banLength=`expandBindTime $banLength`
persistentStateWritePeriod=`expandBindTime $persistentStateWritePeriod`
followModePurgeInterval=`expandBindTime $followModePurgeInterval`

timeNow=`date +%s`
timeFirst=$((timeNow - attemptPeriod))
lastPersistentStateWrite=$timeNow

loadState

# main event loops
if [ "$logMode" = follow ] ; then 
  logLine 2 "Running in follow mode..."
  local readsSinceSave=0
  trap "saveState -f" SIGHUP
  trap "saveState -f ; exit " SIGINT
  $cmdLogread -f | sed -n -e 's/[`$]//g' -e "/$regexLogString/p" | while true ; do
    if read -t $followModePurgeInterval line ; then
      processLogLine "$line"
      # instead of 30, should be persistentStateWritePeriod / followModePurgeInterval
      if [ $((++readsSinceSave)) -ge 30 ] ; then
        bddbPurgeExpires
        saveState
        readsSinceSave=0
      fi
    else
      bddbPurgeExpires
      saveState
      readsSinceSave=0
    fi
  done
elif [ "$logMode" = entire ] ; then 
  logLine 2 "Running in entire mode..."
  $cmdLogread | sed -n -e 's/[`$]//g' -e "/$regexLogString/p" | while read line ; do 
    processLogLine "$line" 
    saveState
  done
  loadState
  bddbPurgeExpires
  saveState -f
elif [ "$logMode" = today ] ; then 
  logLine 2 "Running in today mode..."
  $cmdLogread | egrep "`date +'^%a %b %e ..:..:.. %Y'`" | sed -n -e 's/[`$]//g' -e "/$regexLogString/p" | \
    while read line ; do 
      processLogLine "$line" 
      saveState
    done
  loadState
  bddbPurgeExpires
  saveState -f
elif isValidBindTime "$logMode" ; then
  logInterval=`expandBindTime $logMode`
  logLine 2 "Running in interval mode (reviewing $logInterval seconds of log entries)..."
  timeStart=$((timeNow - logInterval))
  $cmdLogread | sed -n -e 's/[`$]//g' -e "/$regexLogString/p" | while read line ; do
    timeWhen=`getLogTime "$line"`
    [ $timeWhen -ge $timeStart ] && processLogLine "$line"
    saveState
  done
  loadState
  bddbPurgeExpires
  saveState -f
elif [ "$logMode" = wipe ] ; then 
  logLine 2 "Wiping state files, unhooking and removing iptables chains"
  wipeFirewall
  if [ -f "$fileStateTemp" ] ; then
    logLine 1 "Removing non-persistent statefile ($fileStateTemp)"
    rm -f "$fileStateTemp"
  fi
  if [ -f "$fileStatePersist" ] ; then
    logLine 1 "Removing persistent statefile ($fileStatePersist)"
    rm -f "$fileStatePersist"
  fi
else
  logLine 0 "Error: invalid log mode ($logMode)"
  exit 254
fi
