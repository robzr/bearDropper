#!/bin/sh
#
# bearDropper DB - basic storage routines for ultralight IP/status/epoch storage
#
# A BDDB record format is: 
#
#   bddb_($IPADDR)=$STATE,$TIME[,$TIME2...]
#
# Where IPADDR has periods replaced with underscores
#       TIME is in epoch-seconds
#
# A BDDB record has one of three STATES:
#   bddb_1_2_3_4=-1                            (whitelist)
#   bddb_1_2_3_4=0,1452332535[,1452332536...]  (tracking, but not banned)
#   bddb_1_2_3_4=1,1452332535`                 (banned)
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
  set | egrep '^bddb_[0-9_]*=' | sed s/\'//g > "$saveFile"
  bddbStateChange=0 
}

# Set bddb record status=1, update ban time flag with newest
# Args: $1=IP Address $2=timeFlag
bddbEnableStatus () {
  local record=`echo $1 | sed -e 's/\./_/g' -e 's/^/bddb_/'`
  local newestTime=`bddbGetTimes $1 | sed 's/.* //' | xargs echo $2 | tr \  '\n' | sort -n | tail -1 `
  eval $record="1,$newestTime"
  bddbStateChange=1
}

# Args: $1=IP Address
bddbGetStatus () {
  bddbGetRecord $1 | cut -d, -f1
}

# Args: $1=IP Address
bddbGetTimes () {
  bddbGetRecord $1 | cut -d, -f2-
}

# Args: $1 = IP address, $2 [$3 ...] = timestamp (seconds since epoch)
bddbAddRecord () {
  local ip="`echo "$1" | tr . _`" ; shift
  local newEpochList="$@" status="`eval echo \\\$bddb_$ip | cut -f1 -d,`"
  local oldEpochList="`eval echo \\\$bddb_$ip | cut -f2- -d,  | tr , \ `" 
  local epochList=`echo $oldEpochList $newEpochList | xargs -n 1 echo | sort -un | xargs echo -n | tr \  ,`
  [ -z "$status" ] && status=0
  eval "bddb_$ip"\=\"$status,$epochList\"
  bddbStateChange=1
}

# Args: $1 = IP address
bddbRemoveRecord () {
  local ip="`echo "$1" | tr . _`"
  eval "unset bddb_$ip"
  bddbStateChange=1
}

# Returns all IPs (not CIDR) present in records
bddbGetAllIPs () { 
  local ipRaw record
  set | egrep '^bddb_[0-9_]*=' | tr \' \  | while read record ; do
    ipRaw=`echo $record | cut -f1 -d= | sed 's/^bddb_//'`
    if [ `echo $ipRaw | tr _ \  | wc -w` -eq 4 ] ; then
      echo $ipRaw | tr _ .
    fi
  done
}

# retrieve single IP record, Args: $1=IP
bddbGetRecord () {
  local record
  record=`echo $1 | sed -e 's/\./_/g' -e 's/^/bddb_/'`
  eval echo \$$record
}

# _END_MEAT_
#
# Test routines
#

# Dump bddb from environment for debugging 
bddbDump () { 
  local ip ipRaw status times time record
  set | egrep '^bddb_[0-9_]*=' | tr \' \  | while read record ; do
    ipRaw=`echo $record | cut -f1 -d= | sed 's/^bddb_//'`
    if [ `echo $ipRaw | tr _ \  | wc -w` -eq 5 ] ; then
      ip=`echo $ipRaw | sed 's/\([0-9_]*\)_\([0-9][0-9]*\)$/\1\/\2/' | tr _ .`
    else
      ip=`echo $ipRaw | tr _ .`
    fi
    status=`echo $record | cut -f2 -d= | cut -f1 -d,`
    times=`echo $record | cut -f2 -d= | cut -f2- -d,`
    for time in `echo $times | tr , \ ` ; do printf 'IP (%s) (%s): %s\n' "$ip" "$status" "$time" ; done
  done
} 


bddbFile=/tmp/bddb.db

cat > "$bddbFile" <<_EOF_
bddb_2_3_4_5=0,1442000000
bddb_10_0_1_0_24=-1
bddb_64_242_113_77=1,1442000000,1442001000,1442002000
_EOF_

echo save file is $bddbFile

echo Environment has `bddbCount` entries, clearing and .umping
bddbClear ; bddbDump

echo Environment has `bddbCount` entries

echo Loading
bddbLoad "$bddbFile"

echo Loaded `bddbCount` entries, dumping
bddbDump

echo "creating a new record (1.2.3.4)"
bddbAddRecord 1.2.3.4 1440001234

echo "adding to an existing record (2.3.4.5)"
bddbAddRecord 2.3.4.5 1442000001 1441999999 

echo "Adding to an existing record (64.242.113.77)"
bddbAddRecord 64.242.113.77 1441999999 1442999999 1442001050

echo saving and dumping
bddbSave "$bddbFile" ; bddbDump

echo clearing and dumping
bddbClear ; bddbDump

echo loading and dumping
bddbLoad "$bddbFile" ; bddbDump

echo removing file
rm "$bddbFile"
