#!/bin/bash 

CNAME=$1
ITERS=$2
HOST=$3
PID=$4
PORT=12345
echo "CANEM = $CNAME ITERS = $ITERS HOST = $HOST pid = $PID "

PAUSE=0


checkpointdir=/var/lib/lxc/$CNAME/checkpoint

general_args="--tcp-established \
--file-locks \
--link-remap \
--force-irmap \
--manage-cgroups \
--ext-mount-map auto \
--enable-external-sharing \
--enable-external-masters \
--enable-fs hugetlbfs \
--enable-fs tracefs \
-vvvvvv \
-t $PID"

mkdir $checkpointdir	
ssh $HOST "mkdir $checkpointdir"
pages_written=10000000
fin=0
for iter in $(seq 1 $ITERS); do 
	echo "Iteration $iter"
	sleep $PAUSE
	mkdir "$checkpointdir/$iter/"
	if [ $iter -eq 1 ] ; then
		# First snapshot -- no parent, kill afterwards
		if [ $ITERS -eq 1 ]; then 
			action="dump"
			args="-s --track-mem"
		else
			action="pre-dump"
			args="--leave-running --track-mem"
		fi
	elif [ $iter -eq $ITERS ] || [ $pages_written -lt 1024 ]; then 
		# Last snapshot -- has parent, kill afterwards
		args="--prev-images-dir=../$((iter - 1))/ --track-mem --leave-stopped"
		action="dump"
		fin=1
	else
		# Other snapshots -- have parent, keep running
		args="--prev-images-dir=../$((iter - 1))/ --track-mem --leave-running"
		action="pre-dump"
	fi
	echo "criu $action -D $checkpointdir/$iter -o $checkpointdir/$iter/$action.log $general_args $args "
	
	criu $action -D $checkpointdir/$iter -o $checkpointdir/$iter/$action.log $general_args $args 
	if grep -q "finished successfully" $checkpointdir/$iter/$action.log 
	then
		grep "finished successfully" $checkpointdir/$iter/$action.log  
	else	
		grep "Error" $checkpointdir/$iter/$action.log 
		echo "Seems to have failed"
		return 0 
	fi
 	
	
	sync_start=$(date -u +"%s%6N")
	rsync -aAXHltzh --numeric-ids --devices --rsync-path="sudo rsync" $checkpointdir/$iter/ $HOST:/$checkpointdir/$iter/
	sync_finish=$(date -u +"%s%6N")	
	diff=$(($sync_finish- $sync_start))
	echo "Rsync $iter: $diff μ"  |tee -a statistic.txt
	
	du -sh $checkpointdir/$iter/ | tee -a statistic.txt
	
	if [ $fin -eq 1 ] && [ $ITERS -eq 1 ]; then 
		echo "Final dump completed"
		break 
	else
		echo "$action: Iteration $iter "2>$1 | tee -a statistic.txt
		(cd criu && ./crit decode -i $checkpointdir/$iter/stats-dump --pretty) 2>$1 | tee -a statistic.txt
		pages_written="$(cd criu && ./crit decode -i $checkpointdir/$iter/stats-dump --pretty |& grep "pages_written" | awk '{print $2}' | head -c -2 )"
		echo "pages_written = $pages_written"
		if [ $fin -eq 1 ]; then 
			echo "Final dump completed"
			break 
		fi
	fi
done

return $iter


