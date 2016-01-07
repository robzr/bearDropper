#!/bin/sh
#
# bearDropper DB - storage routines for ultralight IP/status/epoch storage
#
# TBD: Add functionality to distinguish between save to flash vs save to memory, 
#      using interim save to flash, diff, then mv to avoid unnecessary flash writes
#
# A BDDB entry has one of three states:
#   (whitelist) bddb_1_2_3_4=-1  
#   (tracking)  bddb_1_2_3_4=0,12432345234[,23423422343]  (not blacklisted, but detected bad entrie(s))
#   (blacklist) bddb_1_2_3_4=1,2342343243                 (blacklisted, time is last known bad attempt)
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
  set | egrep '^bddb_[0-9_]*=[0-9-][0-9,]*' | sed s/\'//g > "$saveFile"
  bddbStateChange=0 
}

# Set bddb entry to status=1, update ban time flag with newest
# Args: $1=IP Address $2=timeFlag
bddbEnableStatus () {
  local entry=`echo $1 | sed -e 's/\./_/g' -e 's/^/bddb_/'`
  local newestTime=`bddbGetTimes $1 | sed 's/.* //' | xargs echo $2 | tr \  '\n' | sort -n | tail -1 `
  eval $entry="1,$newestTime"
  bddbStateChange=1
}

# Args: $1=IP Address
bddbGetStatus () {
  bddbGetEntry $1 | cut -d, -f1
}

# Args: $1=IP Address
bddbGetTimes () {
  bddbGetEntry $1 | cut -d, -f2-
}

# Args: $1 = IP address, $2 [$3 ...] = timestamp (seconds since epoch)
bddbAddEntry () {
  local ip="`echo "$1" | tr . _`" ; shift
  local newEpochList="$@" status="`eval echo \\\$bddb_$ip | cut -f1 -d,`"
  local oldEpochList="`eval echo \\\$bddb_$ip | cut -f2- -d,  | tr , \ `" 
  local epochList=`echo $oldEpochList $newEpochList | xargs -n 1 echo | sort -n | xargs echo -n | tr \  ,`
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

# retrieve single IP entry, Args: $1=IP
bddbGetEntry () {
  local entry
  entry=`echo $1 | sed -e 's/\./_/g' -e 's/^/bddb_/'`
  eval echo \$$entry
}

# Expires old times - this is probably obsolete (integrate to bearDropper.sh)
#
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
#
# Here is the beginning of the test routines
#

bddbFile=/tmp/bddb.db

cat > "$bddbFile" <<_EOF_
bddb_2_3_4_5=0,1442000000
bddb_10_0_1_0_24=-1
bddb_64_242_113_77=1,1442000000,1442001000,1442002000
_EOF_

echo Save file is $bddbFile

echo Environment has `bddbCount` entries, Clearing and Dumping
bddbClear ; bddbDump

echo Environment has `bddbCount` entries

echo Loading...
bddbLoad "$bddbFile"

echo loaded `bddbCount` entries, Dumping
bddbDump

echo "Creating a new entry (1.2.3.4)"
bddbAddEntry 1.2.3.4 1440001234

echo "Adding to an existing entry (2.3.4.5)"
bddbAddEntry 2.3.4.5 1442000001 1441999999 

echo "Adding to an existing entry (64.242.113.77)"
bddbAddEntry 64.242.113.77 1441999999 1442999999 1442001050

echo Saving and Dumping
bddbSave "$bddbFile" ; bddbDump

echo Clearing and Dumping
bddbClear ; bddbDump

echo Loading and Dumping
bddbLoad "$bddbFile" ; bddbDump

echo Removing file
rm "$bddbFile"
