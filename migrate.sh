#!/bin/bash 

CNAME=$(cat migration.conf | grep "Containers_Name"  | cut -d " " -f2)
HOST=$(cat migration.conf | grep "Destination_Host"  | cut -d " " -f2)
ITERS=$(cat migration.conf | grep "Max_Iterations"  | cut -d " " -f2)
OPTION=$(cat migration.conf | grep "Checkpoint_Option"  | cut -d " " -f2)
DESTIP=$(dig +short $HOST)
echo "$CNAME $HOST $ITERS $OPTION"

PID=$(pgrep "init" | sed -n '2p') #asume only one container runnning fix this
echo "PID = $PID"

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
        echo "** Trapped CTRL-C"
	exit 1
}


checkpointdir=/var/lib/lxc/$CNAME/checkpoint

rm -rf  $checkpointdir/*
ssh $HOST "rm  -rf $checkpointdir/*"

if ! lxc-info -n $CNAME -s | grep "RUNNING"; then 
	echo "$CNAME not RUNNING: Exit migration process"
fi



if [ $OPTION -eq 1 ]
then 
	# 1: checkpoint on disk,rsync, restore from disk
	echo "Migrate $CNAME to $HOST,checkpoint on disk,rsync,restore from disk" |tee -a statistic.txt
elif [ $OPTION -eq 2 ]
then 
	# 2: checkpoint on disk. Destination host shares the checkpoint directory over nfs, so no rsync is needed.
	#configure /etc/exports, then exportfs -a, service nfs-kernel-server restart
	#restore from Disk	
	echo "Migrate $CNAME to $HOST,checkpoint on disk,restore from disk,checkpoint directory shared over NFS" |tee -a statistic.txt
	if mount|grep "$DESTIP:/var/lib/lxc/$CNAME/checkpoint on /var/lib/lxc/$CNAME/checkpoint"; then
		echo "$DESTIP:/var/lib/lxc/$CNAME/checkpoint allready mounted" 
	else
		mount $DESTIP:/var/lib/lxc/$CNAME/checkpoint /var/lib/lxc/$CNAME/checkpoint
	fi
elif [ $OPTION -eq 3 ]; then
	# 3: checkpoint on tmpfs, rsync restore from tmpfs 
	echo "Migrate $CNAME to $HOST,checkpoint on tmpfs,rsync,restore from tmpfs" |tee -a statistic.txt
	if mount|grep "tmpfs on /var/lib/lxc/$CNAME/checkpoint"; then
		echo "/var/lib/lxc/$CNAME/checkpoint allready mounted" 
	else
		mount -t tmpfs -o size=1500M,mode=0777 tmpfs /var/lib/lxc/$CNAME/checkpoint/ 
	fi
	ssh $HOST "if mount|grep 'tmpfs on /var/lib/lxc/$CNAME/checkpoint'; then
	echo '/var/lib/lxc/$CNAME/checkpoint allready mounted' 
	else
	mount -t tmpfs -o size=1500M,mode=0777 tmpfs /var/lib/lxc/$CNAME/checkpoint/ 
	fi"
elif [ $OPTION -eq 4 ]; then 
	# 4: checkpoint on tmpfs. Destination host has nfs over tmpfs on the checkpoint directory, so no rsync is needed.
	echo "Migrate $CNAME to $HOST,checkpoint on tmpfs,restore from tmpfs,checkpoint directory shared over NFS" |tee -a statistic.txt
	if mount|grep "tmpfs on /var/lib/lxc/$CNAME/checkpoint"; then
		echo "/var/lib/lxc/$CNAME/checkpoint allready mounted" 
	else
		mount -t tmpfs -o size=1500M,mode=0777 tmpfs /var/lib/lxc/$CNAME/checkpoint/ 
	fi
	ssh $HOST "if mount|grep 'tmpfs on /var/lib/lxc/$CNAME/checkpoint'; then
	echo /var/lib/lxc/$CNAME/checkpoint allready mounted' 
	else
	mount -t tmpfs -o size=1500M,mode=0777 tmpfs /var/lib/lxc/$CNAME/checkpoint/ 
	fi"
	if mount|grep "$DESTIP:/var/lib/lxc/$CNAME/checkpoint on /var/lib/lxc/$CNAME/checkpoint"; then
		echo "$DESTIP:/var/lib/lxc/$CNAME/checkpoint allready mounted" 
	else
		mount $DESTIP:/var/lib/lxc/$CNAME/checkpoint /var/lib/lxc/$CNAME/checkpoint
	fi
fi 


#Let a backround process rsync the checkpoint directory. When final dump finishes 
#kill this daemon and continue with a final rsync. This because when daemon rsync 
#might false decide that dumping is over if criu dump processes a large /proc/pid/mmaps 
#and the directory does not change for a while
if [ $OPTION -eq 1 ] || [ $OPTION -eq 3 ]; then 
	rm nohup.out
	nohup ./rsync.sh $CNAME $HOST& 
	rsync_pid=$!
	echo "rsync_pid = $rsync_pid"
else 
	rsync_pid=-1
fi
	
source dump.sh $CNAME $ITERS $HOST $PID $rsync_pid 
returnval=$?

if [ $returnval -eq 0 ]; then 
	exit 1
fi

echo "Total iterations = $returnval"

#Pretty print the result output
source res-pp.sh | tee -a statistic.txt

./restore.sh $CNAME $returnval $HOST 
ssh $HOST "lxc-wait -n $CNAME -s RUNNING"

