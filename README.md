# backup-picnic

A backup script written using bash aiming to combine a multitude of linux tools into a central script focusing on backups, ease of use an clarity through notifications and syntax. 

This project aims to make linux system administration jobs specifically backups easy. It is intended to be used with cron at the moment. 

## Features
- mysqldump 
- rsync 
- tar
- tar incrementals (bandwidth and time conservative)
- ability to pull or push backup
- ability to do all of the above in one line (good for cron)
- notifications and logs can be sent when backup is complete advising on backup status 

Though not a feature the script was written at the time using bash for cross server compatability. 

### Todo

- concatenate / reduce the mount of SSH connections used when pulling backups
- reduce and clean up log output