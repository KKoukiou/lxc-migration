#!/bin/bash

CNAME=$1
HOST=$2

checkpointdir=/var/lib/lxc/$CNAME/checkpoint

prev_size=$(du -sk $checkpointdir | cut -f1)
mb_thres=1000

while sleep 0.1; 
do 
	cur_size=$(du -sk $checkpointdir | cut -f1)
	dif=$(( cur_size - prev_size ))
	if (( dif > mb_thres ))
	then 
		#check the correctness of the inplace flag
		#--partial does not delete partial tranferred files if tranfer interrupted
		rsync -aAXHltzh --partial --progress --numeric-ids --devices --inplace --stats --rsync-path="sudo rsync" $checkpointdir/ $HOST:/$checkpointdir/
	else 
		if ((dif == 0 ))
		then 
			echo "Not enough data changes, skippig rsync"
		fi
	fi
done 
	 
