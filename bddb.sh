#!/usr/bin/false # Run as an include (ex: . bddb.inc)
#
# bearDropper DB - storage routines for ultralight IP/status/epoch storage
#
# TBD: Add functionality to distinguish between save to flash vs save to memory, 
#      using interim save to flash, diff, then mv to avoid unnecessary flash writes
#
# _BEGIN_MEAT_

bddbStateChange=0 

# Clear bddb entries from environment
bddbClear () { 
  local bddbVar
  for bddbVar in `set | egrep '^bddb_[0-9_]*=' | cut -f1 -d= | xargs echo -n` ; do eval unset $bddbVar ; done
  bddbStateChange=1
}

# Returns count of unique IP entries in environment
bddbCount () { set | egrep '^bddb_[0-9_]*=' | wc -l ; }

# Loads existing bddb file into environment, Arg: $1 = file
bddbLoad () { 
  local loadFile="$1"
  bddbClear 
  [ -f "$loadFile" ] && . "$loadFile"
  bddbStateChange=0
}

# Saves environment bddb entries to file, Arg: $1 = file to save in
bddbSave () { 
  local saveFile="$1"
  [ $bddbStateChange -eq 0 ] && return 
  set | egrep '^bddb_[0-9_]*=[0-9-][0-9]*' | sed s/\'//g > "$saveFile"
  bddbStateChange=0 
}

# Args: $1 = IP address, $2 [$3 ...] = timestamp (seconds since epoch)
bddbAddEntry () {
  local ip="`echo $1 | tr . _`" ; shift
  local newEpochList="$@" status="`eval echo \\\$bddb_$ip | cut -f1 -d,`"
  local oldEpochList="`eval echo \\\$bddb_$ip | cut -f2- -d,  | tr , \ `" 
  local epochList=`echo $oldEpochList $newEpochList | xargs -n 1 echo | sort -un | xargs echo -n | tr \  ,`
  [ -z "$status" ] && status=0
  eval "bddb_$ip"\=\"$status,$epochList\"
  bddbStateChange=1
}

# Dump bddb from environment for debugging 
bddbDump () { 
  local ip ipRaw status times time entry
  set | egrep '^bddb_[0-9_]*=' | tr \' \  | while read entry ; do
    ipRaw=`echo $entry | cut -f1 -d= | sed 's/^bddb_//'`
    if [ `echo $ipRaw | tr _ \  | wc -w` -eq 5 ] ; then
      ip=`echo $ipRaw | sed 's/\([0-9_]*\)_\([0-9][0-9]*\)$/\1\/\2/' | tr _ .`
    else
      ip=`echo $ipRaw | tr _ .`
    fi
    status=`echo $entry | cut -f2 -d= | cut -f1 -d,`
    times=`echo $entry | cut -f2 -d= | cut -f2- -d,`
    for time in `echo $times | tr , \ ` ; do printf 'IP (%s) (%s): %s\n' "$ip" "$status" "$time" ; done
  done
} 

# Expires old times
# Args: $1 = attemptPeriod $2 = attemptCount
bddbProcess () {
  local now=`date +%s` ip ipRaw times entry attemptPeriod="$1" attemptCount="$2"
  set | egrep '^bddb_[0-9_]*=' | tr \' \  | while read entry ; do
    ipRaw=`echo $entry | cut -f1 -d= | sed 's/^bddb_//'`
    ip=`echo $ipRaw | tr _ .`
    times=`echo $entry | cut -f2 -d=`
    for time in `echo $times | tr , \ ` ; do printf 'IP (%s) (%s): %s\n' "$ip" "$status" "$time" ; done
  done
  bddbStateChange=1 # don't forget to set this if there are any changes !
}

# _END_MEAT_
