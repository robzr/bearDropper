#!/bin/ash -m
#
# bearDropper - dropbear log parsing ban agent for OpenWRT - rewrite of dropBrute.sh 11/2015 - @robzr
#   - No dependencies outside of default Chaos Calmer installation
#   - Optionally uses uci for configuration
#   - Can run continuously in background (ie: via included init script) or periodically (via cron)
#   - Can use BIND style time shorthand, ex: 1w5d3h1m8s is 1 week, 5 days, 3 hours, 1 minute, 8 seconds
#   - By default uses ramdisk for bddb file; can optionally write to persistent storage - routines are
#     optomized to avoid excessive writes on flash storage
#   - Runs in one of the following operational modes:
#     follow mode - follows the log file to process entries as they happen; generally launched via init 
#        script.  Responds the fastest, runs the most efficiently, but is always in memory.
#     interval mode - only processes entries going back the specified interval; requires more processing 
#        than today mode, but responds more accurately.  Generally run periodically via cron.
#     today mode - looks at log entries from the day it is being run, simple and lightweight, generally 
#        run from cron periodically (same simplistic behavior as dropBrute.sh)
#     entire mode - runs through entire contents of the syslog ring buffer
#
#  TBD: 
#   - Uses BDDB based saving of rules - do we need this AND a lease file ?? - merge the leasefile into bddb 
#     by adding a field ex: bddb_1_2_3_4=0,234246,2342342,235235 where 0 = ban status, then record last timestamp
#   - Logs actions to logger (rewrite verbosePrint as logLine, to write to logger, have 2 args for reg/verb)
#   - Add whitelisting - -1 in status; use CIDR
#   - Automatically add firewall hook, chain & rules -- or integrate into /etc/config/firewall ??
#        

# Here is a configuration example (this would be the contents of a file /etc/config/bearDropper)
#
# config bearDropper
#   option defaultMode 		today
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

uciLoad defaultMode 24h			# Mode used if no mode is specified on command line - examples would be
 					# 24h for using a 24 hour time interval mode, today for today mode, etc.

uciLoad attemptCount 3			# Failure attempts from a given IP required to trigger a ban

uciLoad attemptPeriod 1d		# Time period during which attemptCount must be exceeded in order to 
					# trigger a ban.

uciLoad banLength 1w			# How long a a ban will exist for

uciLoad persistentBanFileWritePeriod 1d	# How often to write to persistent ban file. 0 is never, otherwise the 
					# number of seconds (or a BIND style time string) can be used to specify 
					# minimum intervals between writes.  Consider the life of your flash 
					# storage when setting this.  To make it write on every run when using
					# a mode other than follow, set it to 1.

uciLoad fileBanTemp '/tmp/bearDropper.bddb'	# Temporary BDDB (state/tracking) file

uciLoad fileBanPersist '/etc/bearDropper.bddb'	# Persistent BDDB (state/tracking) file - consider
						# moving to USB or SD storage if available

uciLoad firewallHookChain 'input_wan_rule' 	# firewall chain to hook into

uciLoad firewallHookPosition 1 		# position in firewall chain to hook (-1 = do not add, 0 = append, 1+ = absolute position)


###  Advanced variables below; it is unlikely that these will need to be changed, but just in case...

uciLoad logFacility 'authpriv.notice'	# Logger facility and priority - use "stdout" to bypass logger

uciLoad verbose 0			# Verbose output (also can be set with the -v flag)

uciLoad regexLogString '^[a-zA-Z ]* [0-9: ]* authpriv.warn dropbear\['	# Regex to look for when initially parsing 
									# out auth fail log entries

uciLoad firewallChain 'bearDropper'	# the firewall chain bearDropper stores firewall commands in

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

printUsage () {
  cat <<-_EOF_
	Usage: bearDropper [-e|-f|-i #|-t] [-v]
		-e    entire mode, processes entire log contents
		-f    follow mode, constantly monitors log
		-i #  interval mode, reviewing # seconds back
		-t    today mode, processes log entries from same day
		-v    verbose output
	_EOF_
}

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

verbosePrint () { [ "$verbose" -eq 1 -o "$verbose" = "yes" -o "$verbose" = "true" -o "$verbose" = "on" ] && echo $@ ;}

# TBD
syncLeaseFile () {
  echo sync\'ing lease file...
}

getLogTime () { date -d"`echo $1 | cut -f2-5 -d\ `" -D"$formatLogDate" +%s ;}

getLogIP () { echo $1 | sed 's/^.*from \([0-9.]*\):[0-9]*$/\1/' ;}

processFileBan () {
  local logLine logTime logIP
  if [ ! -f "$fileBanTemp" -a -f "$fileBanPersist" ] ; then
    verbosePrint "Restoring persistent ban file to temp ban file..."
    cp -f "$fileBanPersist" "$fileBanTemp" 
  fi 
  if [ -f "$fileBanTemp" ] ; then
    verbosePrint "Processing temp ban file for expired records..."
    mv -f "$fileBanTemp" "${fileBanTemp}.tmp"
    touch "$fileBanTemp"
    cat "${fileBanTemp}.tmp" | while logread logLine ; do
      logTime="`echo $logLine | cut -f1 -d,`"
      [ "$logTime" -ge "$timeFirst" ] && echo $logLine >> "$fileBanTemp"
    done
  fi
  if [ $persistentBanFileWritePeriod -gt 0 ] ; then
    timeNow=`date +%s`
    lastFileBanPersistWrite=0
    [ -f "$fileBanPersist" ] && lastFileBanPersistWrite=`date -r "$fileBanPersist" +%s`
    if [ $((timeNow - lastFileBanPersistWrite)) -ge $persistentBanFileWritePeriod ] ; then
      verbosePrint "Saving temp ban file to persistent ban file..."
      cp -f "$fileBanTemp" "$fileBanPersist" 
  fi ; fi
}

processLine () {
  local logTime=`getLogTime "$1"`
  local logIP=`getLogIP "$1"`
  local leaseLine=`printf '%s,%s\n' $logIP $logTime`
  timeNow=`date +%s`
  timeFirst=$((timeNow - attemptPeriod))

  if [ "$logTime" -ge "$timeFirst" ] ; then
    if ! egrep -q "^$leaseLine$" "$fileBanTemp" ; then 
      verbosePrint "Adding $leaseLine to temp ban file..."
      echo $leaseLine >> "$fileBanTemp"
  fi ; fi 
}


#
# Begin logic
#

lastFileBanPersistWrite=0
unset logMode

while getopts efi:tv arg ; do
  case "$arg" in 
    e) logMode='entire'
      ;;
    f) logMode='follow'
      ;;
    i) logMode='interval'
      logInterval=$OPTARG
      if ! isValidBindTime $logInterval ; then
        echo "Invalid (non numeric) log interval set." >&2
        exit -1
      fi
      ;;
    t) logMode='today'
      ;;
    v) verbose=1
      ;;
    *) printUsage
      exit 1
  esac
  shift `expr $OPTIND - 1`
done
[ -z $logMode ] && logMode="$defaultMode"

attemptPeriod=`expandBindTime $attemptPeriod`
banLength=`expandBindTime $banLength`
persistentBanFileWritePeriod=`expandBindTime $persistentBanFileWritePeriod`

timeNow=`date +%s`
timeFirst=$((timeNow - attemptPeriod))

# main event loops for various modes
if [ "$logMode" = 'follow' ] ; then 
  verbosePrint "Running in follow mode..."
  $cmdLogread -f | egrep "$regexLogString" | while true ; do
    if read -t 60 logLine ; do 
      processLine "$logLine"
    else
      # here we can process our expirations
    fi
  done
#  followModePurgeInterval 
elif [ "$logMode" = 'entire' ] ; then 
  verbosePrint "Running in entire mode..."
  $cmdLogread | egrep "$regexLogString" | while read logLine ; do processLine "$logLine" ; done
elif [ "$logMode" = 'today' ] ; then 
  verbosePrint "Running in today mode..."
  $cmdLogread | egrep "`date +'^%a %b %d ..:..:.. %Y'`" | egrep "$regexLogString" | while read logLine ; do processLine "$logLine" ; done
elif [ "$logMode" = 'interval' ] ; then
  verbosePrint "Running in interval mode (reviewing $logInterval seconds of log entries)..."
  timeStart=$((timeNow - logInterval))
  $cmdLogread | egrep "$regexLogString" | while read logLine ; do
    timeWhen=`getLogTime "$logLine"`
    [ $timeWhen -ge $timeStart ] && processLine "$logLine"
  done
fi