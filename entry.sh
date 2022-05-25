#!/bin/bash

cp -R /home /homelive

LOG=/var/log/all

touch $LOG

for a in /opt/run/*
do
    $a >> $LOG &
done

tail -f $LOG
