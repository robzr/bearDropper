#!/bin/ash

bddbFile=/tmp/bddb.db

cat > "$bddbFile" <<_EOF_
bddb_2_3_4_5=0,1442000000
bddb_10_0_1_0_24=0,1442000000
bddb_64_242_113_77=1,1442000000,1442001000,1442002000
_EOF_

echo Loading bddb.inc
. bddb.inc

echo Save file is $bddbFile

echo Environment has `bddbCount` entries, Clearing and Dumping
bddbClear ; bddbDump

echo Environment has `bddbCount` entries

echo -n Loading...
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
#rm "$bddbFile"
