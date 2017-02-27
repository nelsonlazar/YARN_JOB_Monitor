# YARN_JOB_Monitor
Monitor and alert faulty mapreduce or yarn jobs

### Introduction

- The script can be used with any hadoop distribution.
- The script checks for long running yarn jobs which helps indicate issues with the job.
- Finds out jobs with infinite loop, or infinite null joins which is a result from not using proper filters in the query.
- Sends alerts via email with details of the job.
- Prevents faulty jobs/queries to consume cluster resources.

### Pre-requistes

- Script should be run as super-user(hdfs)
- mail sending package should be present in the server.
- If using a kerberised cluster, keytab should be generated and stored in a secure location.

### Usage

Open the script "faulty_yarn_job_monitor.sh" and edit THRESHOLD, EMAIL_ADDRESS as per your cluster requirement. 

Add cron job to run every 2 hours(can be modified, depending on cluster) 
00 */2 * * * /bin/bash /PATH_TO_SCRIPT/faulty_yarn_job_monitor.sh
