#!/bin/ash
#
# bearDropper - dropbear log parsing ban agent for OpenWRT (Chaos Calmer rewrite of dropBrute.sh)
#   http://github.com/robzr/bearDropper  -- Rob Zwissler 11/2015
# 
#   - lightweight, no dependencies, busybox ash + native OpenWRT commands
#   - uses uci for configuration, overrideable via command line arguments
#   - runs continuously in background (via init script) or periodically (via cron)
#   - uses BIND time shorthand, ex: 1w5d3h1m8s is 1 week, 5 days, 3 hours, 1 minute, 8 seconds
#   - Whitelist IP or CIDR entries (TBD) in uci config file
#   - Records state file to tmpfs and intelligently syncs to persistent storage (can disable)
#   - Persistent sync routines are optimized to avoid excessive writes (persistentStateWritePeriod)
#   - Every run occurs in one of the following modes. If not specified, interval mode (24 hours) is 
#     the default when not specified (the init script specifies follow mode via command line)
# 
#     "follow" mode follows syslog to process entries as they happen; generally launched via init
#        script. Responds the fastest, runs the most efficiently, but is always in memory.
#     "interval" mode only processes entries going back the specified interval; requires 
#       more processing than today mode, but responds more accurately. Use with cron.
#     "today" mode looks at log entries from the day it is being run, simple and lightweight, 
#       generally run from cron periodically (same simplistic behavior as dropBrute.sh)
#     "entire" mode runs through entire contents of the syslog ring buffer
#     "wipe" mode tears down the firewall rules and removes the state files

# Load UCI config variable, or use default if not set
# Args: $1 = variable name (also uci option name), $2 = default_value
uciLoad () {
  local getUci uciSection='bearDropper.@[0]'
  getUci=`uci -q get ${uciSection}."$1"` || getUci="$2"
  eval $1=\'$getUci\'
}

# Common config variables - edit these in /etc/config/bearDropper
# or they can be overridden at runtime with command line options
#
uciLoad defaultMode 24h
uciLoad attemptCount 10
uciLoad attemptPeriod 12h
uciLoad banLength 1w
uciLoad logLevel 1
uciLoad logFacility authpriv.notice
uciLoad persistentStateWritePeriod -1
uciLoad fileStateTempPrefix /tmp/bearDropper
uciLoad fileStatePersistPrefix /etc/bearDropper
uciLoad firewallHookChain input_wan_rule
uciLoad firewallHookPosition 1
uciLoad fileStateType 'bddb'

# Not commonly changed, but changeable via uci or cmdline (primarily 
# to enable multiple parallel runs with different parameters)
#
uciLoad firewallChain 'bearDropper'
uciLoad firewallTarget 'DROP'

# Advanced variables, changeable via uci only (no cmdline), it is 
# unlikely that these will need to be changed, but just in case...
#
uciLoad syslogTag "bearDropper[$$]"
uciLoad followModePurgeInterval 30m	# how often to attempt to expire
					# bans when in follow mode
# only lines matching regexLogString are processed
uciLoad regexLogString '^[a-zA-Z ]* [0-9: ]* authpriv.warn dropbear\['
# but first lines matching regexLogStringInverse are filtered out
uciLoad regexLogStringInverse 'has invalid shell, rejected$'
uciLoad cmdLogread 'logread'		# for tuning, ex: "logread -l250"
uciLoad formatLogDate '%b %e %H:%M:%S %Y'	# used to convert syslog dates
uciLoad formatTodayLogDateRegex '^%a %b %e ..:..:.. %Y'	# filter for today mode

# Begin functions
#
# _LOAD_MEAT_

isValidBindTime () { echo "$1" | egrep -q '^[0-9]+$|^([0-9]+[wdhms]?)+$' ; }

# expands Bind time syntax into seconds (ex: 3w6d23h59m59s), Arg: $1=time string
expandBindTime () {
  isValidBindTime "$1" || { logLine 0 "Error: Invalid time specified ($1)" >&2 ; exit 254 ; }
  echo $((`echo "$1" | sed -e 's/w+*/*7d+/g' -e 's/d+*/*24h+/g' -e 's/h+*/*60m+/g' -e 's/m+*/*60+/g' \
    -e s/s//g -e s/+\$//`))
}

# Args: $1 = loglevel, $2 = info to log
logLine () {
  [ $1 -gt $logLevel ] && return
  shift
  if [ "$logFacility" = "stdout" ] ; then echo "$@"
  elif [ "$logFacility" = "stderr" ] ; then echo "$@" >&2
  else logger -t "$syslogTag" -p "$logFacility" "$@"
  fi
}

# extra validation, fails safe. Args: $1=log line
getLogTime () {
  local logDateString=`echo "$1" | sed -n \
    's/^[A-Z][a-z]* \([A-Z][a-z]*  *[0-9][0-9]*  *[0-9][0-9]*:[0-9][0-9]:[0-9][0-9] [0-9][0-9]*\) .*$/\1/p'`
  date -d"$logDateString" -D"$formatLogDate" +%s || logLine 1 \
    "Error: logDateString($logDateString) malformed line ($1)"
}

# extra validation, fails safe. Args: $1=log line
getLogIP () { echo "$1" | sed -n 's/^.*[^0-9]\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p'; }

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
      if [ $firewallHookPosition = 0 ] ; then
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

# review state file for expired records - we could add the bantime to
# the rule via --comment but I can't think of a reason why that would
# be necessary unless there is a bug in the expiration logic. The
# state db should be more resiliant than the firewall in practice.
#
bddbPurgeExpires () {
  local now=`date +%s`
  bddbGetAllIPs | while read ip ; do
    if [ `bddbGetStatus $ip` = 1 ] ; then
      if [ $((banLength + `bddbGetTimes $ip`)) -lt $now ] ; then
        logLine 1 "Ban expired for $ip, removing from iptables"
        unBanIP $ip
        bddbRemoveRecord $1 
      else 
        logLine 2 "bddbPurgeExpires($ip) not expired yet"
      fi
    elif [ `bddbGetStatus $ip` = 0 ] ; then
      local times=`bddbGetTimes $ip | tr , \ `
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
  
  # 1: not enough attempts => do nothing and exit
  # 2: attempts exceed threshold in time period => ban
  # 3: attempts exceed threshold but time period is too long => trim oldest time, recalculate
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
    times=`echo $times | cut -d\  -f2-`
    timeCount=`echo $times | wc -w`
  done  
  [ $didBan = 0 ] && logLine 2 "bddbEvaluateRecord($ip) does not exceed threshhold, skipping"
}

# Reads filtered log line and evaluates for action  Args: $1=log line
processLogLine () {
  local time=`getLogTime "$1"` 
  local ip=`getLogIP "$1"` 
  local status="`bddbGetStatus $ip`"

  if [ "$status" = -1 ] ; then
    logLine 2 "processLogLine($ip,$time) IP is whitelisted"
  elif [ "$status" = 1 ] ; then
    if [ "`bddbGetTimes $ip`" -ge $time ] ; then
      logLine 2 "processLogLine($ip,$time) already banned, ban timestamp already equal or newer"
    else
      logLine 2 "processLogLine($ip,$time) already banned, updating ban timestamp"
      bddbEnableStatus $ip $time
    fi
    banIP $ip
  elif [ -n "$ip" -a -n "$time" ] ; then
    bddbAddRecord $ip $time
    logLine 2 "processLogLine($ip,$time) Added record, comparing"
    bddbEvaluateRecord $ip 
  else
    logLine 1 "processLogLine($ip,$time) malformed line ($1)"
  fi
}

# Args, $1=-f to force a persistent write (unless lastPersistentStateWrite=-1)
saveState () {
  local forcePersistent=0
  [ "$1" = "-f" ] && forcePersistent=1

  if [ $bddbStateChange -gt 0 ] ; then
    logLine 3 "saveState() saving to temp state file"
    bddbSave "$fileStateTempPrefix" "$fileStateType"
    logLine 3 "saveState() now=`date +%s` lPSW=$lastPersistentStateWrite pSWP=$persistentStateWritePeriod fP=$forcePersistent"
  fi    
  if [ $persistentStateWritePeriod -gt 1 ] || [ $persistentStateWritePeriod -eq 0 -a $forcePersistent -eq 1 ] ; then
    if [ $((`date +%s` - lastPersistentStateWrite)) -ge $persistentStateWritePeriod ] || [ $forcePersistent -eq 1 ] ; then
      if [ ! -f "$fileStatePersist" ] || ! cmp -s "$fileStateTemp" "$fileStatePersist" ; then
        logLine 2 "saveState() writing to persistent state file"
        bddbSave "$fileStatePersistPrefix" "$fileStateType"
        lastPersistentStateWrite="`date +%s`"
  fi ; fi ; fi
}

loadState () {
  bddbLoad "$fileStatePersistPrefix" "$fileStateType"
  bddbLoad "$fileStateTempPrefix" "$fileStateType"
}

printUsage () {
  cat <<-_EOF_
	Usage: bearDropper [-m mode] [-a #] [-b #] [-c ...] [-C ...] [-f ...] [-F #] [-l #] [-j ...] [-p #] [-P #] [-s ...]

	  Running Modes (-m) (def: $defaultMode)
	    follow     constantly monitors log
	    entire     processes entire log contents
	    today      processes log entries from same day only
	    #          interval mode, specify time string or seconds
	    wipe       wipe state files, unhook and remove firewall chain

	  Options
	    -a #   attempt count before banning (def: $attemptCount)
	    -b #   ban length once attempts hit threshold (def: $banLength)
	    -c ... firewall chain to record bans (def: $firewallChain)
	    -C ... firewall chain to hook into (def: $firewallHookChain)
	    -f ... log facility (syslog facility or stdout/stderr) (def: $logFacility)
	    -F #   firewall chain hook position (def: $firewallHookPosition)
	    -j ... firewall target (def: $firewallTarget)
	    -l #   log level - 0=off, 1=standard, 2=verbose (def: $logLevel)
	    -p #   attempt period which attempt counts must happen in (def: $attemptPeriod)
	    -P #   persistent state file write period (def: $persistentStateWritePeriod)
	    -s ... persistent state file prefix (def: $fileStatePersistPrefix)
	    -t ... temporary state file prefix (def: $fileStateTempPrefix)

	  All time strings can be specified in seconds, or using BIND style
	  time strings, ex: 1w2d3h5m30s is 1 week, 2 days, 3 hours, etc...

	_EOF_
}

#  Begin main logic
#
unset logMode
while getopts a:b:c:C:f:F:hj:l:m:p:P:s:t: arg ; do
  case "$arg" in 
    a) attemptCount=$OPTARG ;;
    b) banLength=$OPTARG ;;
    c) firewallChain=$OPTARG ;;
    C) firewallHookChain=$OPTARG ;;
    f) logFacility=$OPTARG ;;
    F) firewallHookPosition=$OPTARG ;;
    j) firewallTarget=$OPTARG ;;
    l) logLevel=$OPTARG ;;
    m) logMode=$OPTARG ;;
    p) attemptPeriod=$OPTARG ;;
    P) persistentStateWritePeriod=$OPTARG ;;
    s) fileStatePersistPrefix=$OPTARG ;;
    s) fileStatePersistPrefix=$OPTARG ;;
    *) printUsage
      exit 254
  esac
  shift `expr $OPTIND - 1`
done
[ -z $logMode ] && logMode="$defaultMode"

fileStateTemp="$fileStateTempPrefix.$fileStateType"
fileStatePersist="$fileStatePersistPrefix.$fileStateType"

attemptPeriod=`expandBindTime $attemptPeriod`
banLength=`expandBindTime $banLength`
[ $persistentStateWritePeriod != -1 ] && persistentStateWritePeriod=`expandBindTime $persistentStateWritePeriod`
followModePurgeInterval=`expandBindTime $followModePurgeInterval`

lastPersistentStateWrite="`date +%s`"

loadState

# main event loops
if [ "$logMode" = follow ] ; then 
  logLine 1 "Running in follow mode..."
  local readsSinceSave=0 lastPurge=0
  tmpFile="`mktemp`"
  trap "saveState -f" SIGHUP
  trap "saveState -f ; rm -f "$tmpFile" ; exit " SIGINT
  worstCaseReads=1
  [ $persistentStateWritePeriod -gt 1 ] && worstCaseReads=$((persistentStateWritePeriod / followModePurgeInterval))
  $cmdLogread -f | while read -t $followModePurgeInterval line || true ; do
    sed -nE -e 's/[`$"'\'']//g' -e '\#'"$regexLogStringInverse"'#d' -e '\#'"$regexLogString"'#p' > "$tmpFile" <<-_EOF_
	$line
	_EOF_
    line="`cat $tmpFile`"
    [ -n "$line" ] && processLogLine "$line"
    logLine 3 "ReadComp:$readsSinceSave/$worstCaseReads"
    if [ $((++readsSinceSave)) -ge $worstCaseReads ] ; then
      local now="`date +%s`"
      if [ $((now - lastPurge)) -ge $followModePurgeInterval ] ; then
        bddbPurgeExpires
        saveState
        readsSinceSave=0
        lastPurge="$now"
      fi
    fi
  done
elif [ "$logMode" = entire ] ; then 
  logLine 1 "Running in entire mode..."
  $cmdLogread | sed -nE -e 's/[`$"'\'']//g' -e '\#'"$regexLogStringInverse"'#d' -e '\#'"$regexLogString"'#p' | \
    while read line ; do 
    processLogLine "$line" 
    saveState
  done
  loadState
  bddbPurgeExpires
  saveState -f
elif [ "$logMode" = today ] ; then 
  logLine 1 "Running in today mode..."
  # merge the egrep into the sed command 
  $cmdLogread | egrep "`date +\'$formatTodayLogDateRegex\'`" | sed -nE -e 's/[`$"'\'']//g' -e \
    '\#'"$regexLogStringInverse"'#d' -e '\#'"$regexLogString"'#p' | while read line ; do 
      processLogLine "$line" 
      saveState
    done
  loadState
  bddbPurgeExpires
  saveState -f
elif isValidBindTime "$logMode" ; then
  logInterval=`expandBindTime $logMode`
  logLine 1 "Running in interval mode (reviewing $logInterval seconds of log entries)..."
  timeStart=$((`date +%s` - logInterval))
  $cmdLogread | sed -nE -e 's/[`$"'\'']//g' -e '\#'"$regexLogStringInverse"'#d' -e '\#'"$regexLogString"'#p' | \
    while read line ; do
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
