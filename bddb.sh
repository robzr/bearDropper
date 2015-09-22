#!/bin/bash
#
# Routines to deal with non-array for tracking failed login attempts

. bddb.db

# bddbAddEntry -> adds a time to the "array"
#bddbAddEntry () {
#  # Args:  $1 = IP address, $2 [$3 ...] = timestamp (seconds since epoch)
#  
#  if [ ! -z `eval \$bddb_$1` ] ; then 
#    echo 
#  fi
#}

bddbDump () { 
  local ip ipRaw times
  set | egrep '^bddb_[0-9_]*=' | while read entry ; do
    ipRaw=`echo $entry | cut -f1 -d= | sed 's/^bddb_//'`
    ip=`echo $ipRaw | tr _ .`
    times=`echo $entry | cut -f2 -d=`

    for time in `echo $times | tr , \ ` ; do
      printf 'IP (%s): %s\n' "$ip" "$time"
    done
  done
} 



# Expires old times; 
bddbProcess () {
  local attemptPeriod=5000
  local attemptCount=3

  local now=`date +%s`
  local ip ipRaw times freshTimes 

  set | egrep '^bddb_[0-9_]*=' | while read entry ; do
    ipRaw=`echo $entry | cut -f1 -d= | sed 's/^bddb_//'`
    ip=`echo $ipRaw | tr _ .`
    times=`echo $entry | cut -f2 -d=`

    freshTimes=""
    for time in `echo $times | tr , \ ` ; do
      printf 'IP (%s): %s\n' "$ip" "$time"
          
    done
    echo eval bddb_$ipRaw=
  done
}

bddbDump

