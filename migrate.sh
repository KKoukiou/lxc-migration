#!/bin/bash 

CNAME=$(cat migration.conf | grep "Containers_Name"  | cut -d " " -f2)
HOST=$(cat migration.conf | grep "Destination_Host"  | cut -d " " -f2)
ITERS=$(cat migration.conf | grep "Max_Iterations"  | cut -d " " -f2)
OPTION=$(cat migration.conf | grep "Checkpoint_Option"  | cut -d " " -f2)
DESTIP=$(dig +short $HOST)
echo "$CNAME $HOST $ITERS $OPTION"

PID=$(lxc-info -n trusty13 | sed -n 3p |grep -o '[0-9]*')
echo "PID = $PID"

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
        echo "** Trapped CTRL-C"
	exit 1
}


checkpointdir=/var/lib/lxc/$CNAME/checkpoint

rm -rf  $checkpointdir/*
ssh root@$HOST "rm  -rf $checkpointdir/*"

if ! lxc-info -n $CNAME -s | grep "RUNNING"; then 
	echo "$CNAME not RUNNING: Exit migration process"
fi


if [ $OPTION -eq 1 ]
then 
	# 1: checkpoint on disk,rsync, restore from disk
	echo "Migrate $CNAME to $HOST,checkpoint on disk,rsync,restore from disk" > statistic.txt
elif [ $OPTION -eq 2 ]
then 
	# 2: checkpoint on disk. Destination host shares the checkpoint directory over nfs, so no rsync is needed.
	#configure /etc/exports, then exportfs -a, service nfs-kernel-server restart
	#restore from Disk	
	echo "Migrate $CNAME to $HOST,checkpoint on disk,restore from disk,checkpoint directory shared over NFS" > statistic.txt
	if mount|grep "$DESTIP:$checkpointdir on $checkpointdir"; then
		echo "$DESTIP:$checkpointdir allready mounted" 
	else
		echo "mount $DESTIP:$checkpointdir $checkpointdir"
		mount -t nfs -o async $DESTIP:$checkpointdir $checkpointdir
	fi
elif [ $OPTION -eq 3 ]; then
	# 3: checkpoint on tmpfs, rsync restore from tmpfs 
	echo "Migrate $CNAME to $HOST,checkpoint on tmpfs,rsync,restore from tmpfs" > statistic.txt
	if mount|grep "tmpfs on $checkpointdir"; then
		echo "$checkpointdir allready mounted" 
	else
		mount -t tmpfs -o size=1500M,mode=0777 tmpfs $checkpointdir 
	fi
	ssh root@$HOST "if mount|grep 'tmpfs on $checkpointdir'; then
	echo '$checkpointdir allready mounted' 
	else
	mount -t tmpfs -o size=1500M,mode=0777 tmpfs $checkpointdir 
	fi"
elif [ $OPTION -eq 4 ]; then 
	# 4: checkpoint on tmpfs. Destination host has nfs over tmpfs on the checkpoint directory, so no rsync is needed.
	echo "Migrate $CNAME to $HOST,checkpoint on tmpfs,restore from tmpfs,checkpoint directory shared over NFS" > statistic.txt
	#if mount|grep "tmpfs on $checkpointdir"; then
	#	echo "$checkpointdir allready mounted" 
	#else
	#	mount -t tmpfs -o size=1500M,mode=0777 tmpfs $checkpointdir 
	#fi
	ssh root@$HOST "if mount|grep 'tmpfs on $checkpointdir'; then
	echo '$checkpointdir allready mounted' 
	else
	mount -t tmpfs -o size=1500M,mode=0777 tmpfs $checkpointdir 
	fi"
	if mount|grep "$DESTIP:$checkpointdir on $checkpointdir"; then
		echo "$DESTIP:$checkpointdir allready mounted" 
	else
		mount -t nfs -o async $DESTIP:$checkpointdir $checkpointdir
	fi
elif [ $OPTION -eq 5 ]
then 
	# 5: checkpoint on disk. The checkpoint directory is of type glusterf, so no rsync is needed.
	echo "Migrate $CNAME to $HOST,checkpoint directory is of type glusterfs" > statistic.txt
	# for now do the configuration manually
fi 

HOST="root@$HOST"
source dump.sh $CNAME $ITERS $HOST $PID 
returnval=$?

if [ $returnval -eq 0 ]; then 
	exit 1
fi

echo "Total iterations = $returnval"

#Pretty print the result output
#source res-pp.sh | tee -a statistic.txt

./restore.sh $CNAME $returnval $HOST 
ssh $HOST "lxc-wait -n $CNAME -s RUNNING"

