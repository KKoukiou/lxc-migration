#!/bin/bash


CNAME=$1
ITERS=$2
HOST=$3

ssh $HOST "lxc-checkpoint -r -n $CNAME -D /var/lib/lxc/$CNAME/checkpoint/$ITERS/ -vvvvv"

ssh $HOST "(cd lxc/criu && ./crit decode -i /var/lib/lxc/$CNAME/checkpoint/$ITERS/stats-restore --pretty)" | tee -a statistic.txt
