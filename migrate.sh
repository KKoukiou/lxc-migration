#!/bin/bash 

CNAME=$(cat migration.conf | grep "Containers_Name"  | cut -d " " -f2)
HOST=$(cat migration.conf | grep "Destination_Host"  | cut -d " " -f2)
ITERS=$(cat migration.conf | grep "Max_Iterations"  | cut -d " " -f2)
OPTION=$(cat migration.conf | grep "Checkpoint_Option"  | cut -d " " -f2)
DESTIP=147.102.4.72
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
rm statistic.txt
ssh $HOST "rm  -rf $checkpointdir/*"


if [ $OPTION -eq 1 ]
then 
	sleep 1
elif [ $OPTION -eq 2 ]
then 
	#configure /etc/exports, then exportfs -a, service nfs-kernel-server restart	
	mount $DESTIP:/var/lib/lxc/$CNAME/checkpoint /var/lib/lxc/$CNAME/checkpoint
elif [ $OPTION -eq 3 ]; then
	mount -t tmpfs -o size=1500M,mode=0777 tmpfs /var/lib/lxc/$CNAME/checkpoint/ 
	ssh $HOST "mount -t tmpfs -o size=1500M,mode=0777 tmpfs /var/lib/lxc/$CNAME/checkpoint/" 
elif [ $OPTION -eq 4 ]; then 
	mount -t tmpfs -o size=1500M,mode=0777 tmpfs /var/lib/lxc/$CNAME/checkpoint/ 
	ssh $HOST "mount -t tmpfs -o size=1500M,mode=0777 tmpfs /var/lib/lxc/$CNAME/checkpoint/"
	mount $DESTIP:/var/lib/lxc/$CNAME/checkpoint /var/lib/lxc/$CNAME/checkpoint
fi 


#Let a backround process rsync the checkpoint directory. When final dump finishes 
#kill this daemon and continue with a final rsync. This because when daemon rsync 
#might false decide that dumping is over if criu dump processes a large /proc/pid/mmaps 
#and the directory does not change for a while

nohup bash rsync.sh $CNAME $HOST& 
rsync_pid=$!
	
source dump.sh $CNAME $ITERS $HOST $PID $rsync_pid 
returnval=$?

if [ $returnval -eq 0 ]; then 
	exit 1
fi

echo "Total iterations = $returnval"

#Pretty print the result output
source res-pp.sh | tee -a statistic.txt

#while : 
#do 
#if ps -p $rsync_pid > /dev/null
#then
#  	echo "rsync($rsync_pid) is running"
#else 
#	break;	
#fi
#done 

./restore.sh $CNAME $returnval $HOST 
ssh $HOST "lxc-wait -n $CNAME -s RUNNING"

