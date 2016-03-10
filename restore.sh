#!/bin/bash


CNAME=$1
ITERS=$2
HOST=$3

ssh $HOST "lxc-checkpoint -r -n $CNAME -D /var/lib/lxc/$CNAME/checkpoint/$ITERS/ -vvvvv"

#ssh $HOST "criu restore --tcp-established --file-locks --link-remap --force-irmap --manage-cgroups --ext-mount-map auto --enable-external-sharing --enable-external-masters --enable-fs hugetlbfs --enable-fs tracefs -D /var/lib/lxc/$CNAME/checkpoint/$ITERS -o /var/lib/lxc/$CNAME/checkpoint/$ITERS/restore.log -v4 --root /var/lib/lxc/$CNAME/rootfs/ --restore-detached --restore-sibling"

ssh $HOST "(cd lxc/criu && ./crit decode -i /var/lib/lxc/$CNAME/checkpoint/$ITERS/stats-restore --pretty)" | tee -a statistic.txt
