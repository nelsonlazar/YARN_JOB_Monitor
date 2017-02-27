#!/bin/bash
# Author: Nelson Lazar
# Monitor and alert yarn jobs which are running for long time, also jobs which are running into infinite loop.

SCRIPT_LOC_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )    # Folder where script is located
THRESHOLD=10     # Threshold in hours(depends on cluster size, basically the average time in which the jobs should be complete), above this value an alert is sent
JOB_LIST="$SCRIPT_LOC_DIR/job_list"    # Temporary file to hold list of currently running yarn jobs
TASK_LIST="$SCRIPT_LOC_DIR/task_list"    # Temporary file to hold all tasks of a job
EMAIL_MSG="$SCRIPT_LOC_DIR/email_message"    # Temporary file to hold email subject which is sent as alert
EMAIL_ADDRESS=""    # specify the email addresses, seperated by space to which alert should be sent

kinit -kt hdfs.keytab hdfs@REALM    # Used in kerberised cluster, provide superuser keytab(path should be correctly specified), here I have used hdfs as superuser

if [ ! -f $JOB_LIST ];
then
        touch  $JOB_LIST
fi

if [ ! -f $TASK_LIST ];
then
        touch  $TASK_LIST
fi

if [ ! -f $EMAIL_MSG ];
then
        touch  $EMAIL_MSG
fi

> $JOB_LIST

#List currently running yarn jobs
mapred  job -list | awk '$1 ~ /job_/ {print $0}' > $JOB_LIST

# This loop will run untill all jobs are read
while read line
do
        JOB_ID=`echo $line | awk '{print $1}'`
        APPLICATION_ID=`mapred job -status $JOB_ID | grep "Job Tracking URL" | cut -d'/' -f5`
        USER=`yarn application -status $APPLICATION_ID |  grep User | cut -d: -f2`
        QUEUE=`yarn application -status $APPLICATION_ID |  grep Queue | cut -d: -f2`
        CURRENT_TIME=`date +%s%3N`
        JOB_START_TIME=`echo $line | awk '{print $3}'`
        JOB_RUN_TIME=$(( ($CURRENT_TIME - $JOB_START_TIME) /3600000 ))

	# Condition to check if the job is running for more than threshold time
        if [[ $JOB_RUN_TIME -ge $THRESHOLD  ]]; then
                echo -e "APPLICATION ID = $APPLICATION_ID\n\nUSER = $USER\n\nQUEUE = $QUEUE\n\nThis job is running for $JOB_RUN_TIME hour, please check" | mail -s "[WARNING] Long running job" $EMAIL_ADDRESS
                TOTAL_MAPS=`mapred job -status $JOB_ID | grep "Number of maps" | awk -F':' '{ print $2 }'`
                TOTAL_REDUCERS=`mapred job -status $JOB_ID | grep "Number of reduces" |  awk -F':' '{ print $2 }'`
                MAPS_COMPLETED=`echo "$(mapred job -status $JOB_ID | grep 'map() completion' | awk -F':' '{ print $2 }' | sed 's/^ *//g') * 100" | bc -l`
                REDUCERS_COMPLETED=`echo "$(mapred job -status $JOB_ID | grep 'reduce() completion' | awk -F':' '{ print $2 }' | sed 's/^ *//g') * 100" | bc -l`
                P_MAPS_COMPLETED="${MAPS_COMPLETED%.*}"
                P_REDUCERS_COMPLETED="${REDUCERS_COMPLETED%.*}"

		# Condition to check if all map tasks are completed and reduce task is more than 95% complete
                if [[ $P_MAPS_COMPLETED -eq 100 ]] && [[ $P_REDUCERS_COMPLETED -lt 100 ]] && [[ $P_REDUCERS_COMPLETED -ge 95 ]];
                then
                        > $TASK_LIST
                        > $EMAIL_MSG
                        APP_ATTEMPT=`yarn applicationattempt -list $APPLICATION_ID |  awk '$1 ~ /appattempt_/ {print $1}'`
                        yarn container -list $APP_ATTEMPT | awk '$1 ~ /container_/ {print $1":"$2 }' > $TASK_LIST
                        T_TASKS=`cat $TASK_LIST | grep -o 'container_'| wc -l`
                        echo -e "APPLICATION ID = $APPLICATION_ID\n\nUSER = $USER\n\nQUEUE = $QUEUE\n\nThis job is running for $JOB_RUN_TIME hour and the job has total $TOTAL_MAPS mappers which are $P_MAPS_COMPLETED% completed, and total $TOTAL_REDUCERS reducers which is $P_REDUCERS_COMPLETED% complete, and currently $T_TASKS tasks running.\n\nIt seems the reducers are stuck and unable to finish the job, this implies the query might be running into infinite loop and it needs to be optimized.\nPlease take necessary action and help to free up cluster resources.\nKindly find below the reduce tasks and how long it's running for:\n" >> $EMAIL_MSG

			# Lists all reduce tasks and how long it is running for
                        while read i
                        do
                                TASK_ID=`echo $i | awk -F':' '{print $1}'`
                                TASK_START_TIME=`echo $i | awk -F':' '{print $2}'`
                                TASK_RUN_TIME=$(( ($CURRENT_TIME - $TASK_START_TIME) /3600000 ))
                                echo -e "$TASK_ID is running for $TASK_RUN_TIME hours"  >> $EMAIL_MSG
                        done < $TASK_LIST
                        cat $EMAIL_MSG | mail -s "[WARNING] Long running job and suspected to be running into infinite loop" $EMAIL_ADDRESS
                fi
        fi
done < $JOB_LIST
