#!/bin/sh
#
# bearDropper DB - storage routines for ultralight IP/status/epoch storage
#
# A BDDB record format is: bddb_($IPADDR)=$STATE,$TIME[,$TIME...]
#
# Where: IPADDR has periods replaced with underscores
#        TIME is in epoch-seconds
#
# A BDDB record has one of three STATES:
#   bddb_1_2_3_4=-1                            (whitelisted IP or network)
#   bddb_1_2_3_4=0,1452332535[,1452332536...]  (tracking, but not banned)
#   bddb_1_2_3_4=1,1452332535`                 (banned, time=effective ban beginning)
#
# BDDB records exist in RAM usually, but using bddbSave & bddbLoad, they are 
# written on (ram)disk with optional compression 
#
# Partially implemented is IPADDR being in CIDR format, with a fifth octet
# at the end, being the mask.  Ex: bddb_192_168_1_0_24=....
#
# TBD: finish CIDR support, add lookup/match routines
#
# _BEGIN_MEAT_
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
  local loadFile="$1.$2" fileType="$2"
  bddbClear 
  if [ "$fileType" = bddb ] ; then
    . "$loadFile"
  elif [ "$fileType" = bddbz -a -f "$loadFile" ] ; then
    local tmpFile="`mktemp`"
    zcat $loadFile > "$tmpFile"
    . "$tmpFile"
    rm -f "$tmpFile"
  fi
  bddbStateChange=0
}

# Saves environment bddb entries to file, Arg: $1 = file to save in
bddbSave () { 
  local saveFile="$1.$2" fileType="$2"
  if [ "$fileType" = bddb ] ; then
    set | egrep '^bddb_[0-9_]*=' | sed s/\'//g > "$saveFile"
  elif [ "$fileType" = bddbz ] ; then
    set | egrep '^bddb_[0-9_]*=' | sed s/\'//g | gzip -c > "$saveFile"
  fi
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

bddbFilePrefix=/tmp/bddbtest
bddbFileType=bddbz

echo seeding
bddb_2_3_4_5=0,1442000000
bddb_10_0_1_0_24=-1
bddb_64_242_113_77=1,1442000000,1442001000,1442002000

echo saving
bddbSave "$bddbFilePrefix" "$bddbFileType"

echo environment has `bddbCount` entries, clearing and dumping
bddbClear ; bddbDump

echo environment has `bddbCount` entries

echo loading
bddbLoad "$bddbFilePrefix" "$bddbFileType"

echo loaded `bddbCount` entries, dumping
bddbDump

echo creating a new record \(1.2.3.4\)
bddbAddRecord 1.2.3.4 1440001234

echo adding to an existing record \(2.3.4.5\)
bddbAddRecord 2.3.4.5 1442000001 1441999999 

echo adding to an existing record \(64.242.113.77\)
bddbAddRecord 64.242.113.77 1441999999 1442999999 1442001050

echo saving and dumping
bddbSave "$bddbFilePrefix" "$bddbFileType"
bddbDump

echo clearing and dumping
bddbClear ; bddbDump

echo loading and dumping
bddbLoad "$bddbFilePrefix" "$bddbFileType"
bddbDump

echo removing file
rm "$bddbFilePrefix.$bddbFileType"
