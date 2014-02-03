#!/bin/bash
## Backup script 

PROGNAME=$(basename $0)

globalStartTime=$(date +%s)

usage() {
    cat <<EOF
    usage: backup.sh [ OPTION ]

    Options
    -a         Backup all databases "yes/no" Casuses the mySqlMagic function to backup all databases on
               the specified server (localhost by default)
    -u         Username; Username for scp and rsync 
    -s         Source driectory to be backed up
    -e         RsyncOptions, Default: az. eg: -e "azrP --include=/var/www/" This just gets parsed to rsync
    -p         Port; Port to be used for scp and rsync 22 by default unless SSH is set to no
    -d         Destination directory on remote server
    -j         Goofy rsync/scp; switch the transfer mode from local -> remote TO remote -> local
    -r         Remote server; Destination server for rsync or scpfeet 
    -b         Use SSH "yes/no"; By default this option is set to yes
    -l         Log directory; Default is /tmp/date-backup.log
    -m         Copy Mode "rsync/scp"; By default this is set to rsyncMagic
    -n         Mysql host, for databases that are not running on localhost (if this option is ommited -r remote server is used)
    -g         Database to backup; By default all databases are select here input database name to be
    -t         Not supported yet; Compression engine; tar by default, no other options support at the moment
    -c         Compress source into a tar file before transfer
    -y         Directory to dump/compress mysql local backup before rsyncing to desitnation - Script will exit if this is not set
    -x         Append a folder with the name %Y%m%d-%H%M%S to the destination folder and place source inside
    -k         Append a folder with the name %Y%m%d to the destination folder and place source inside
    -w         Add nice to compression and md5sum commands
    -h         Help; Display this usage message
    -E         Exlcude from compression archive; -E "regex"  
    -o         Don't send "Backup Completed" email on completion, will still send failed email
    -T         Temporary tar location, automatically creates direcory if it doesn't exist. Tar source files here doesn't
               remove directory when finished
    -I         Incremental tar [ 0 | 1 ]. 0 = Full backup, 1 = Incremental (Use in conjunction with cron)

    Examples:

    Rsync file to a remote directory 
        ./backup.sh -u backupuser -r storage.example.com -s /var/directory -d /home/backups/ 
        (destination (-d) is optional, this will transfer to dest user home dir)
        ./backup.sh -u backupuser -r storage.example.com -s /var/directory

    Rsync file/dir from remote to local
         ./backup.sh -u backupuser -j -r staging.example.com -s /var/directory -d /home/backups/

    Rsync file/dir from local(source) to remmote(destination) and compress file into a tar before transfer (deletes tar from source when complete)
        # compresses file/dir to /tmp/<sourcename>-YYYYMMDD-ssssssssss.tar.gz

        ./backup.sh -u backupuser -c -s /var/directory -d /home/backups/ 

    Rsync file/dir from remote(source) to local(destination) and compress file into a tar before transfer (deletes tar from source when complete)
        # compresses file/dir to /tmp/<sourcename>-YYYYMMDD-ssssssssss.tar.gz

        ./backup.sh -u backupuser -j -s /var/directory -r staging.example.com -d /home/backups/ -c

    MySQL backups 
    ----------------------------------------------------------------------------
    Edit script and define sqlUser= and sqlPass= under the Configuration section

    Backup only a specific database to your current directory with

        ./backup -g <database name>

    Backup all databses on the machine to current directory (ensure to fill out sqlUser and sqlPass variables)
        ./backup -a

    Backup all databases and transfer the current dir to a remote host
        ./backup.sh -u backupuser -a -s \`pwd\` -r storage.example.com

    Backup with rsync options
        ./backup.sh -u backupuser -s /var/directory -d /home/backups -r storage.example.com -e 'aPr --exclude=some-dir'
EOF
}

if ( ! getopts ":axkoiwcju:y:s:d:p:b:r:l:m:n:g:t:e:E:T:I:h" opt); then
    echo ""
    echo "    $0 requries an argument!"
    usage
    exit 1 
fi

while getopts ":axkoiwcju:y:s:d:p:b:r:l:m:n:g:t:e:E:T:I:h" opt; do
    case $opt in
        a)
            allDatabases="yes" >&2
            ;;
        u)
            rsyncUser="$OPTARG" >&2
            ;;
        s)
            sourceDirectory="$OPTARG" >&2
            ;;
        p)
            port="$OPTARG" >&2
            ;;    
        d)
            destinationDirectory="$OPTARG" >&2
            ;;
        j)
            goofy="yes" >&2
            ;;
        y)
            mysqlDir="$OPTARG" >&2
            ;;
        r)
            remoteServer="$OPTARG" >&2
            ;;
        b)
            useSsh="$OPTARG" >&2
            ;;
        l)
            log="$OPTARG" >&2
            ;;
        m)
            copyMode="$OPTARG" >&2
            ;;
        n)  mysqlHost="$OPTARG" >&2
            ;;
        g)
            backupDatabase="$OPTARG" >&2
            ;;
        t)
            compressionEngine="$OPTARG"
            ;;
        c)
            compressSource="yes"
            ;;
        k)
            timeStampDayDir="yes"
            ;;
        x)
            timeStampDir="yes"
            ;;
        w)
            addNice="yes"
            ;;
        e)
            rsyncOps="$OPTARG" >&2
            ;;
        o)
            sendEmailOnComplete=1
            ;;
        i)
            tarAllFilesInSource=0
            ;;
        I)
            incrementalTarLevel=$OPTARG
            incrementalTar=0
            ;;
        E)
            excludeFromCompression="$OPTARG"
            ;;
        T)  tempTarFileLocation="$OPTARG"
            ;;
        h)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        :)
            echo "backup.sh Requires an argument" >&2
            usage
            exit 1
            ;;
        esac
    done

#-------------------------------------------------------------------------------
# Setup defaults for backup.sh
#-------------------------------------------------------------------------------
date=`/bin/date +%y%m%d-%H%M%S`                                                # time stamp : YYYYMMDD-hhmmss
if [ -z $port ]; then port="22"; fi                                            # default SSH port
if [ -z $log ]; then log="/tmp/${date}-backup.log"; fi                         # default log file
if [ -z $copyMode ]; then copyMode="rsync"; fi                                 # defualt copy mode
if [ -z $useSsh ]; then useSsh="yes"; fi                                       # default to using ssh
if [ -z $compressionEngine ]; then compressionEngine="/bin/tar"; fi            # default to using tar & gz for compression
if [ -z $goofy ]; then goofy="no"; fi                                          # default to not using goofy
if [ -z "$rsyncOps" ]; then rsyncOps="a"; fi                                   # default rsync options
if [ -z $mysqlHost ]; then mysqlHost="localhost"; fi                           # default mysqlHost localhost
if [ -z $sendEmailOnComplete ]; then sendEmailOnComplete=0; fi                 # default send email on completion
if [ -z $tarAllFilesInSource ]; then tarAllFilesInSource=1; fi                 # default don't tar all files in source
if [ -z $incrementalTar ]; then incrementalTar=1; fi                           # default don't use incremental tar
if [ -z ${excludeFromCompression} ]; then excludeFromCompression="None"; fi    # default no exlude from compressionEngine
if [ -z ${tempTarFileLocation} ]; then tempTarFileLocation="None"; fi
#-------------------------------------------------------------------------------
# Setup defaults configurations (can be changed)
#-------------------------------------------------------------------------------

if [ -z $remoteServer ]; then
echo "From: Someone <someone@example.com>
To: Someone Else <someone.else@example.com>
Subject: Backup Complete $(hostname) $date
" >> $log
else
echo "From: Someone <someone@example.com>
To: Someone Else <someone.else@example.com>
Subject: Backup Complete $remoteServer $date
" >> $log
fi

tempDirectory="$date"
destinationDirectory="$destinationDirectory"
if [ ! -z $timeStampDir ]; then
        timeStampDir=$(date +"%Y%m%d-%H%M%S")
        destinationDirectory="${destinationDirectory}/${timeStampDir}/"
        dateTime=$timeStampDir
fi
if [ ! -z $timeStampDayDir ]; then 
        timeStampDayDir=$(date +"%Y%m%d")
        destinationDirectory="${destinationDirectory}/${timeStampDayDir}/"
        dateTime=$timeStampDayDir
fi
tarSnapshotDir="/tmp/backup-snapshots/"
tarSnapshotTimeStamp=${timeStampDayDir}
tarSnapshotFileLvl0Err=0
tarSnapshotFileLvl0Removed=1
sourceDirectory="$sourceDirectory"
log="$log"
rsyncUser="$rsyncUser"
rsyncPort="$port"
useSsh="$useSsh"                                                             # usage: [yes/no]
tarSource="$tarSource"
sqlUser=
sqlPass=
sqlBackup=0
sqlHost="$mysqlHost"
sshCmd="ssh $rsyncUser@$remoteServer -p$port"
compressionStatus=1
mysqlDir="$mysqlDir"
if [ -z $dateTime ]; then 
        dateTime=$(date +%Y%m%d%H%M%S)
fi
rsyncMagicError=0
remoteSqlCmd="\"show databases\""
remoteSqlDump="/usr/bin/mysqldump -u \$MYSQL_USER -p\$MYSQL_PASS -h \"$sqlHost\""
localSqlDump="/usr/bin/mysqldump -u $sqlUser -p\"$sqlPass\" -h \"$sqlHost\""
localSqlCmd="\"show databases\""
compress="/bin/gzip"
compressionEngine="/bin/tar"
compressionOpts="-czf"
md5sumCmd="md5sum"
remoteCheckDestDir="if [ ! -d \"${destinationDirectory}\" ]; then echo \"1\"; else echo \"0\"; fi"
if [ ! -z $addNice ]; then
    compressionEngine="nice /bin/tar"
    md5sumCmd="nice md5sum"
    echo "nice option on" >> $log
fi
if [ $incrementalTar = 0 ]; then
    if [[ $goofy == "yes" ]]; then
        remoteSnapDestDir=$($sshCmd "if [ ! -d \"${tarSnapshotDir}\" ]; then echo \"1\"; else echo \"0\"; fi")
        if [ $remoteSnapDestDir = 1 ]; then
            $sshCmd "mkdir -p $tarSnapshotDir" >> $log 2>&1
        fi
    else
        if ! [ -d $tarSnapshotDir ]; then
            mkdir -p $tarSnapshotDir >> $log 2>&1
        fi
    fi
fi
#-------------------------------------------------------------------------------
# Cleanup temporary file in case of keyboard interrupt or termination signal.
#-------------------------------------------------------------------------------

function cleanup_temp {
    [ -e $tmpfile ] && rm --force $tmpfile
    exit 0
}

#trap cleanup_temp SIGHUP SIGINT SIGPIPE SIGTERM
# if [ "$goofy" = "yes" ]; then
#     $sshCmd "tmpfile=$(mktemp) || error_exit \"$0: creation of temporary file failed\!\"" >> $log 2>&1
# else
#     tmpfile=$(mktemp) || error_exit "$0: creation of temporary file failed\!" >> $log 2>&1
# fi

function error_exit
{

#    ----------------------------------------------------------------
#    Function for exit due to fatal program error
#        Accepts 1 argument:
#            string containing descriptive error message
#    ----------------------------------------------------------------


    echo "${PROGNAME}: ${1:-"Unknown Error"}" >> $log
    sed -i 's/Subject:\ Backup\ Complete/Subject:\ Backup\ Failed/' $log
    cat $log | /usr/sbin/sendmail -t
    exit 1
}

#-------------------------------------------------------------------------------
# Check imput arguments error and exit if incomplete or incorrect
#-------------------------------------------------------------------------------

function tarBackup {
    tarSnapshotFileLvl0Err=0
    compressionStatus=1
    local _tarFile=$1
    local _tarFileName=${_tarFile}
    if ! [ -z $excludeFromCompression ]; then
        if [[ $compressionEngine == "/bin/tar" ]]; then
            # TODO: compressionOpts not here
            compressionEngine="${compressionEngine} --exclude ${excludeFromCompression}"
        else
            echo "Exclude not supported for compressionEngine: ${compressionEngine}" >> $log
        fi
    fi
    #-------------------------------------------------------------------------------
    # Setup incremental backup if selected (-I)
    #-------------------------------------------------------------------------------
    if [ $incrementalTar = 0 ]; then
        tarSnapshotFile=${tarSnapshotDir}$(basename ${_tarFileName})-${tarSnapshotTimeStamp}.snar
        if [[ $goofy == "yes" ]]; then
            tarSnapshotFileLvl0=$($sshCmd "test -a ${tarSnapshotDir}$(basename ${_tarFileName})-[0-9]*-orig.snar && ls ${tarSnapshotDir}$(basename ${_tarFileName})-[0-9]*-orig.snar || echo 1") >> $log 2>&1
        else
            tarSnapshotFileLvl0=$(test -a ${tarSnapshotDir}$(basename ${_tarFileName})-[0-9]*-orig.snar && ls ${tarSnapshotDir}$(basename ${_tarFileName})-[0-9]*-orig.snar || echo 1) >> $log 2>&1
        fi
        if [ ${tarSnapshotFileLvl0} = 1 ]; then
            tarSnapshotFileLvl0=${tarSnapshotDir}$(basename ${_tarFileName})-${tarSnapshotTimeStamp}-orig.snar
            tarSnapshotFileLvl0Err=1
            tarSnapshotFileLvl0Removed=0
        else
            tarSnapshotFileLvl0Err=0
        fi
        if [ $incrementalTarLevel = 0 ]; then
            tarSnapshotFileLvl0New=${tarSnapshotDir}$(basename ${_tarFileName})-${tarSnapshotTimeStamp}-orig.snar
            if [ ${tarSnapshotFileLvl0Removed} = 1 ]; then
                if [ "$goofy" = "yes" ]; then
                    tarSnapshotFileLvl0Removed=$($sshCmd "test -a ${tarSnapshotFileLvl0} && rm ${tarSnapshotFileLvl0} && echo 0 || echo 1") >> $log 2>&1
                else 
                    tarSnapshotFileLvl0Removed=$(test -a ${tarSnapshotFileLvl0} && rm ${tarSnapshotFileLvl0} && echo 0 || echo 1) >> $log 2>&1
                fi
                if [ $tarSnapshotFileLvl0Removed = 0 ]; then
                    tarSnapshotFileLvl0=${tarSnapshotFileLvl0New}
                else
                    echo "Could not remove original snapshot file line: $LINENO"
                fi
            fi
            compressionEngine="${compressionEngine} --listed-incremental ${tarSnapshotFile}"
            _tarFileName=${_tarFileName}-full
        elif [ $incrementalTarLevel = 1 ]; then
            _tarFileName=${_tarFileName}-incremental
            compressionEngine="${compressionEngine} --listed-incremental ${tarSnapshotFile}"
        fi
    fi
    echo -n "Compressing source before transfer: " >> $log
    # Change temp tar'ing directory if -T is specified. Auto creates dir if it does not exist.
    if [[ $tempTarFileLocation == "None" ]]; then
        local _tarFileTmp="/tmp/$(basename ${_tarFileName})-${date}.tar.gz"        # destination of tar file, should be inside /tmp for safety
    else
        local _tarFileTmp="${tempTarFileLocation}/$(basename ${_tarFileName})-${date}.tar.gz"
        if [ "$goofy" = "yes" ]; then
            # TODO: Ignore this check if its already been completed once this run
            local _tarFileTmpExist=$($sshCmd "test -d ${tempTarFileLocation} && echo 0 || echo 1") >> $log 2>&1 
                if [ ${_tarFileTmpExist} = 1 ]; then
                    echo "Temporary tar location does not exist on remote machine creating directory: ${tempTarFileLocation}" >> $log
                    $sshCmd "mkdir -p ${tempTarFileLocation}" >> $log 2>&1
                else
                    echo "Temorary tar location already exits on remote machine: ${tempTarFileLocation}" >> $log
                fi
        else
            if ! [ -d ${tempTarFileLocation} ]; then
                echo "Temporary tar location does not exist creating directory: ${tempTarFileLocation}" >> $log
                mkdir -p ${tempTarFileLocation} >> $log 2>&1
            else
                echo "Temorary tar location already exits: ${tempTarFileLocation}" >> $log
            fi
        fi
    fi
    if [ "$goofy" = "yes" ]; then
        if [ $incrementalTar = 0 ] && [ $incrementalTarLevel = 0 ]; then
            $sshCmd "$compressionEngine $compressionOpts ${_tarFileTmp} $_tarFile" >> $log 2>&1
            if [ $? -eq 0 ]; then compressionStatus=0; fi
            $sshCmd "cp ${tarSnapshotFile} ${tarSnapshotFileLvl0}" >> $log 2>&1
        elif [ $incrementalTar = 0 ] && [ $incrementalTarLevel = 1 ]; then
            if ! [ ${tarSnapshotFileLvl0Err} = 1 ]; then
                $sshCmd "cp ${tarSnapshotFileLvl0} ${tarSnapshotFile} && $compressionEngine $compressionOpts ${_tarFileTmp} $_tarFile" >> $log 2>&1
                if [ $? -eq 0 ]; then compressionStatus=0; fi
            else
                echo "No level 0 snapshot file - Run level 0 tar for ${_tarFileTmp} first. Line: $LINENO" >> $log
                tarSnapshotFileLvl0Err=1
            fi
        else
            $sshCmd "$compressionEngine $compressionOpts ${_tarFileTmp} $_tarFile" >> $log 2>&1
            if [ $? -eq 0 ]; then compressionStatus=0; fi
        fi
        if [ $compressionStatus -eq 0 ]; then
            echo "OK" >> $log
            local _md5sumStart=$(date +%s)
            local _tarFileTmpMd5=$($sshCmd "${md5sumCmd} ${_tarFileTmp} || exit 1" | awk '{ print $1 }')    >> $log 2>&1    # generate md5sum to check file for deletion
            if [ $? -ne 0 ]; then
                error_exit "md5sum could not be created at line $LINENO"
            else
                local _md5sumfinishTime=$(expr $(date +%s) - $_md5sumStart)
                echo "md5sum: $_tarFileTmpMd5" >> $log
                echo "md5sum generated in: ${_md5sumfinishTime}sec(s)" >> $log
            fi
        else
            echo "compression failed at line $LINENO" >> $log
            local _tarFileTmpMd5=Error
        fi
    else
        if [ $incrementalTar = 0 ] && [ $incrementalTarLevel = 0 ]; then
            $compressionEngine $compressionOpts ${_tarFileTmp} $_tarFile >> $log 2>&1
            if [ $? -eq 0 ]; then compressionStatus=0; fi
                cp ${tarSnapshotFile} ${tarSnapshotFileLvl0} >> $log 2>&1
        elif [ $incrementalTar = 0 ] && [ $incrementalTarLevel = 1 ]; then
            if ! [ ${tarSnapshotFileLvl0Err} = 1 ]; then
                cp ${tarSnapshotFileLvl0} ${tarSnapshotFile} && $compressionEngine $compressionOpts ${_tarFileTmp} $_tarFile >> $log 2>&1
                if [ $? -eq 0 ]; then compressionStatus=0; fi
            else
                echo "No level 0 snapshot file - Run level 0 tar for ${_tarFileTmp} first. Line: $LINENO" >> $log
                tarSnapshotFileLvl0Err=1
            fi
        else
            $compressionEngine $compressionOpts ${_tarFileTmp} $_tarFile >> $log 2>&1
            if [ $? -eq 0 ]; then compressionStatus=0; fi
        fi
        if [ $compressionStatus -eq 0 ]; then
            echo "OK" >> $log
            local _md5sumStart=$(date +%s)
            local _tarFileTmpMd5=$(${md5sumCmd} ${_tarFileTmp} | awk '{ print $1 }')    >> $log 2>&1    # generate md5sum to check file for deletion
            if [ $? -ne 0 ]; then
                error_exit "md5sum could not be created at line $LINENO"
            else
                local _md5sumfinishTime=$(expr $(date +%s) - $_md5sumStart)
                echo "md5sum: $_tarFileTmpMd5" >> $log
                echo "md5sum generated in: ${_md5sumfinishTime}sec(s)" >> $log
            fi
        else
            echo "compression failed at line $LINENO" >> $log
            local _tarFileTmpMd5=Error
        fi
    fi
    _tarFile=${_tarFileTmp}                                                             # set $rsyncFile variable to new temporary name
    if [[ $tempTarFileLocation == "None" ]]; then
        if [[ $_tarFileTmp == /tmp/*\.tar\.gz ]]; then                                  # ensure $rsyncFile ends with .tar.gz
            echo "should remove: ${_tarFileTmp}" >> $log
            echo "$_tarFileTmp $_tarFileTmpMd5 $tarSnapshotFileLvl0Err"                 # return output <tar tmp file location/name> <md5sum of tar tmp file> array
        else
            error_exit "\$_tarFileTmp isn\'t as expected, exiting for safety! $_tarFileTmp at line: $LINENO"
        fi
    else
        if [[ $_tarFileTmp == "${tempTarFileLocation}"*\.tar\.gz ]]; then               # ensure $rsyncFile ends with .tar.gz
            echo "should remove: ${_tarFileTmp}" >> $log
            echo "$_tarFileTmp $_tarFileTmpMd5 $tarSnapshotFileLvl0Err"                 # return output <tar tmp file location/name> <md5sum of tar tmp file> array
        else
            error_exit "\$_tarFileTmp isn\'t as expected, exiting for safety! $_tarFileTmp at line: $LINENO"
        fi
    fi
    }

function delTarBackup {
    local _delTarFile="$1"
    local _delTarFileTmpMd5="$2"
    if ! [[ $_delTarFileTmpMd5 == [0-9a-z]* ]]; then
        error_exit "_delTarFileTmpMd5 is incorrect: $_delTarFileTmpMd5 at line: $LINENO"
    fi
    if ! [[ ${tempTarFileLocation} == "None" ]]; then
        if ! [[ $_delTarFile == "${tempTarFileLocation}"*\.tar\.gz ]]; then
            error_exit "\$_delTarFile not a tar file, not deleting file: $_delTarFile at line: $LINENO"
        fi
    else
        if ! [[ $_delTarFile == /tmp/*\.tar\.gz ]]; then
            error_exit "\$_delTarFile not a tar file, not deleting file: $_delTarFile at line: $LINENO"
        fi
    fi
    echo "removing: ${_delTarFile}" >> $log
    if [ "$goofy" = "yes" ]; then
        if [[ ${tempTarFileLocation} == "None" ]]; then
            $sshCmd "delTarFileMd5_check=\$(${md5sumCmd} ${_delTarFile} | awk '{ print \$1 }') ; if [[ $_delTarFile == /tmp/*\.tar\.gz ]] && [[ $_delTarFileTmpMd5 = \$delTarFileMd5_check ]]; then rm -rf ${_delTarFile} && echo \"$_delTarFile deleted md5sum \$delTarFileMd5_check OK\" ; else echo \"error variable $_delTarFile inconsistent on remote server. Md5: $_delTarFileTmpMd5 Md5_check: \$delTarFileMd5_check \" && exit 1; fi" >> $log 2>&1
            if [ $? -ne 0 ]; then
                error_exit "remote delete failed at line: $LINENO"
            fi
        else
            $sshCmd "delTarFileMd5_check=\$(${md5sumCmd} ${_delTarFile} | awk '{ print \$1 }') ; if [[ $_delTarFile == ${tempTarFileLocation}*\.tar\.gz ]] && [[ $_delTarFileTmpMd5 = \$delTarFileMd5_check ]]; then rm -rf ${_delTarFile} && echo \"$_delTarFile deleted md5sum \$delTarFileMd5_check OK\" ; else echo \"error variable $_delTarFile inconsistent on remote server. Md5: $_delTarFileTmpMd5 Md5_check: \$delTarFileMd5_check \" && exit 1; fi" >> $log 2>&1
            if [ $? -ne 0 ]; then
                error_exit "remote delete failed at line: $LINENO"
            fi
        fi
    else
        if [[ ${tempTarFileLocation} == "None" ]]; then
            delTarFileMd5_check=$(${md5sumCmd} ${_delTarFile} | awk '{ print $1 }') ; if [[ $_delTarFile == /tmp/*\.tar\.gz ]] && [[ $_delTarFileTmpMd5 = $delTarFileMd5_check ]]; then rm -rf ${_delTarFile} && echo "$_delTarFile deleted md5sum $delTarFileMd5_check OK" ; else error_exit "error variable $_delTarFile inconsistent at ${LINENO}. Md5: $_delTarFileTmpMd5 Md5_check: \$delTarFileMd5_check" && exit 1; fi >> $log 2>&1
            if [ $? -ne 0 ]; then
                error_exit "remote delete failed at line: $LINENO"                                    
            fi
        else
            delTarFileMd5_check=$(${md5sumCmd} ${_delTarFile} | awk '{ print $1 }') ; if [[ $_delTarFile == ${tempTarFileLocation}*\.tar\.gz ]] && [[ $_delTarFileTmpMd5 = $delTarFileMd5_check ]]; then rm -rf ${_delTarFile} && echo "$_delTarFile deleted md5sum $delTarFileMd5_check OK" ; else error_exit "error variable $_delTarFile inconsistent at ${LINENO}. Md5: $_delTarFileTmpMd5 Md5_check: \$delTarFileMd5_check" && exit 1; fi >> $log 2>&1
            if [ $? -ne 0 ]; then
                error_exit "remote delete failed at line: $LINENO"                                    
            fi
        fi
    fi
    _delTarFileTmpMd5="" # reset md5sum to null
    
}

#-------------------------------------------------------------------------------
# rsync function to scp files from soure to destination (not used but
# could be enabled pretty easily)
#-------------------------------------------------------------------------------
function scpMagic { 
    local _scp_file=$1
    echo "starting scp of file $_scp_file at `date`" >> $log
    if [ "$goofy" = "yes" ]; then
        /usr/bin/scp -r -P $rsyncPort ${rsyncUser}@${remoteServer}:${_scp_file} ${destinationDirectory} >> $log 2>&1
        if [ $? -ne 0 ]; then
            echo "Error with scp" >> $log
        fi
    else
        /usr/bin/scp -r -P $rsyncPort "$_scp_file" ${rsyncUser}@${remoteServer}:${destinationDirectory} >> $log 2>&1
        if [ $? -ne 0 ]; then
            echo "Error with scp" >> $log
        fi
    fi
    echo "finished scp of file $_scp_file at `date`" >> $log
}

#-------------------------------------------------------------------------------
# rsync function to transfer files from soure to destination
#-------------------------------------------------------------------------------
function rsyncMagic {
    rsyncMagicError=0
    local rsyncFile="$1"
    if ! [ -z "$2" ]; then 
        local antiSqlTar=1
    else
        local antiSqlTar=0
    fi
    local startTime=$(date +%s)
    local finishTime=0
    echo "starting rsync of file $rsyncFile at `date`" >> $log
    if [ "$goofy" = "yes" ]; then
        echo "rsync running goofy!" >> $log
        if [ ! -d "${destinationDirectory}" ]; then
            echo "creating rsync backup directory ${destinationDirectory}" >> $log
            mkdir -p "${destinationDirectory}" >> $log
        else
            echo "rsync backup directory ${destinationDirectory} already exists" >> $log
        fi
        if [[ "$compressSource" = [Yy][Ee][Ss] ]] && [[ $antiSqlTar == 0 ]]; then
            tarArray=($(tarBackup $rsyncFile))								# set $rsyncFile variable to new temporary name
            if [[ ${tarArray[0]} == *\.tar\.gz ]]; then 				    # ensure $rsyncFile ends with .tar.gz
                rsyncFile="${tarArray[0]}"
                rsyncFileMd5=${tarArray[1]}
                tarSnapshotFileLvl0Err=${tarArray[2]}
            else
                error_exit "\${tarArray[0]} isn't as expected, exiting for safety! \"${tarArray[0]}\" at line: $LINENO"
            fi
        fi
        if ! [ $tarSnapshotFileLvl0Err = 1 ]; then
            echo "tarSnapshotFileLvl0Err must be 0: $tarSnapshotFileLvl0Err" >> $log
            if [[ "$useSsh" = [Yy][Ee][Ss] ]]; then
                echo "rsyncing ${remoteServer}:${rsyncFile} ${destinationDirectory}" >> $log
                /usr/bin/rsync -${rsyncOps} --rsh="ssh -p $rsyncPort" ${rsyncUser}@${remoteServer}:${rsyncFile} ${destinationDirectory} >> $log 2>&1
                if [ $? -ne 0 ]; then
                    #error_exit "Error with rsync at line: $LINENO" >> $log
                    echo "Error with rsync unable to transfer ${remoteServer}:${rsyncFile} to ${destinationDirectory} at line: $LINENO" >> $log
                    rsyncMagicError=1
                fi
                finishTime=$(expr $(date +%s) - $startTime)
                if [[ "$compressSource" = [Yy][Ee][Ss] ]] && [[ $antiSqlTar == 0 ]]; then
                    if ! [[ $rsyncFileMd5 == "Error" ]]; then
                        # TODO: Ensure this actually deletes
                        delTarBackup ${tarArray[0]} ${tarArray[1]}
                    fi
                fi
                echo " done" >> $log
            else
                echo "rsyncing ${remoteServer}:${rsyncFile} ${destinationDirectory}" >> $log
                /usr/bin/rsync -${rsyncOps} "$rsyncFile" ${rsyncUser}@${remoteServer}:${rsyncFile} ${destinationDirectory} >> $log 2>&1
                if [ $? -ne 0 ]; then
                    #error_exit "Error with rsync1 at line: $LINENO" >> $log
                    echo "Error with rsync unable to transfer ${remoteServer}:${rsyncFile} to ${destinationDirectory} at line: $LINENO" >> $log
                    rsyncMagicError=1
                fi
                echo " done" >> $log
                finishTime=$(expr $(date +%s) - $startTime)
            fi
            echo "Completed rsync of file: $rsyncFile in ${finishTime}sec(s) on `date`" >> $log
        fi
    else                                                                        # running rsync localy no goofy
            echo "rsync running normally!" >> $log
            destDirExists=$($sshCmd $remoteCheckDestDir)
            if [ $destDirExists -eq 1 ]; then
                echo "creating rsync backup directory ${destinationDirectory}" >> $log
                $sshCmd "mkdir -p \"${destinationDirectory}\"" >> $log
            elif [ $destDirExists -eq 0 ]; then
                echo "rsync backup directory ${destinationDirectory} already exists" >> $log
            else
                error_exit "Cant verifiy destination directory (ssh issue?) at line: $LINENO"
            fi
            if [[ "$compressSource" = [Yy][Ee][Ss] ]]; then
                tarArray=($(tarBackup $rsyncFile))                              # set $rsyncFile variable to new temporary name
                if [[ ${tarArray[0]} == *\.tar\.gz ]]; then                # ensure $rsyncFile ends with .tar.gz
                    rsyncFile="${tarArray[0]}"
                    rsyncFileMd5=${tarArray[1]}
                    tarSnapshotFileLvl0Err=${tarArray[2]}
            else
                error_exit "\${tarArray[0]} isn\'t as expected, exiting for safety! \"${tarArray[0]}\" at line: $LINENO"
            fi
        fi
        if ! [ $tarSnapshotFileLvl0Err = 1 ]; then
            if [[ "$useSsh" = [Yy][Ee][Ss] ]]; then
                    /usr/bin/rsync -${rsyncOps} --rsh="ssh -p $rsyncPort" "$rsyncFile" ${rsyncUser}@${remoteServer}:${destinationDirectory} >> $log 2>&1
                    if [ $? -ne 0 ]; then
                        echo "Error with rsync unable to transfer ${rsyncFile} to ${remoteServer}:${destinationDirectory} at line: $LINENO" >> $log
                        rsyncMagicError=1
                    fi
                    finishTime=$(expr $(date +%s) - $startTime)
                    if [[ "$compressSource" = [Yy][Ee][Ss] ]]; then
                        if [[ $rsyncFileMd5 == "Error" ]]; then
                           delTarBackup ${tarArray[0]} ${tarArray[1]}
                        fi
                    fi
                else
                    /usr/bin/rsync -${rsyncOps} "$rsyncFile" ${rsyncUser}@${remoteServer}:${destinationDirectory} >> $log 2>&1
                    if [ $? -ne 0 ]; then
                        echo "Error with rsync unable to transfer ${rsyncFile} to ${remoteServer}:${destinationDirectory} at line: $LINENO" >> $log
                        rsyncMagicError=0
                    fi
                    finishTime=$(expr $(date +%s) - $startTime)
                    if [[ "$compressSource" = [Yy][Ee][Ss] ]]; then
                        delTarBackup ${tarArray[0]} ${tarArray[1]}
                    fi
            fi
            echo "Completed rsync of file: $rsyncFile in ${finishTime}sec(s) on `date`" >> $log
        fi
    fi
    tarSnapshotFileLvl0Err=0
}

function mySqlMagic {
    if [ -z $mysqlDir ]; then 												# check for mysql directory error if does not exist
        error_exit "No mysql backup directory, exiting\! at line: $LINENO"
    fi 		

    backupFileDir="${mysqlDir}/${dateTime}"
    if [[ $goofy == "yes" ]]; then
        if [ '$sshCmd "! test -d ${mysqlDir}/${dateTime}"' ]; then
            echo "creating backup directory ${backupFileDir}" >> $log
            $sshCmd "mkdir -p ${backupFileDir}" >> $log 2>&1
        else
            echo "backup directory ${backupFileDir} already exists" >> $log
        fi
        if [[ $allDatabases = [Yy]es ]]; then
            sqlBackup=1
            for database in `$sshCmd "/usr/bin/mysql -u \\$MYSQL_USER -p\\"\\$MYSQL_PASS\\" -h $sqlHost -Bse $remoteSqlCmd"`
            do
                local backupFile="${backupFileDir}/$database.dump.gz"
                if { [[ ! $database == "information_schema" ]] && [[ ! $database == "performance_schema" ]]; }; then
                    echo "backing up $database to $backupFile at `date`" >> $log
                    $sshCmd "$remoteSqlDump $database | $compress > $backupFile" 2>> $log
                    echo "backing up $database to $backupFile complete at `date`" >> $log
                    if [ ${#databases[@]} -eq 0 ]; then 
                        databases[0]=$backupFile
                    else 
                        databases[$[${#databases[@]}+1]]=${backupFile}
                    fi
                fi
            done
        else
            sqlBackup=1
            database=$1
            local backupFile="${backupFileDir}/$database.dump.gz"
            echo "backing up $database to $backupFile at `date`" >> $log
            $sshCmd "$remoteSqlDump $database --lock-tables=false | $compress > $backupFile" 2>> $log
            echo "backing up $database to $backupFile complete at `date`" >> $log
            if [ ${#databases[@]} -eq 0 ]; then 
                databases[0]=$backupFile
            else 
                databases[$[${#databases[@]}+1]]=${backupFile}
            fi
        fi
    else
        if [ ! test -d ${backupFileDir} ]; then
            echo "creating backup directory ${backupFileDir}" >> $log
            mkdir -p ${backupFileDir} >> $log 2>&1
        else
            echo "backup directory ${backupFileDir} already exists" >> $log
        fi
        if [ -z $sqlUser ]; then
            error_exit "sqlUser is not defined, exiting\! at line: $LINENO"
        fi
        if [ -z $sqlPass ]; then
            error_exit "sqlPass is not defined, exiting\! at line: $LINENO"
        fi

        if [[ $allDatabases = [Yy]es ]]; then
            sqlBackup=1
            for database in `/usr/bin/mysql -u $sqlUser -p"$sqlPass" -Bse $localSqlCmd`
            do
                local backupFile="${backupFileDir}/$database.dump.gz"
                if { [[ ! $database == "information_schema" ]] && [[ ! $database == "performance_schema" ]]; }; then
                    echo "backing up $database to $backupFile at `date`" >> $log
                    $localSqlDump $database --lock-tables=false | $compress > $backupFile 2>> /dev/null
                    echo "backing up $database to $backupFile complete at `date`" >> $log
                    if [ ${#databases[@]} -eq 0 ]; then 					# make an array of database files to be copied
                        databases[0]=$backupFile
                    else 
                        databases[$[${#databases[@]}+1]]=${backupFile}
                    fi
                fi
            done
        else
            sqlBackup=1
            database=$1
            local backupFile="${backupFileDir}/$database.dump.gz"
            echo "backing up $database to $backupFile at `date`" >> $log
            $localSqlDump $database --lock-tables=false | $compress > $backupFile 2>> $log
            echo "backing up $database to $backupFile complete at `date`" >> $log
            if [ ${#databases[@]} -eq 0 ]; then 
                databases[0]=$backupFile
            else 
                databases[$[${#databases[@]}+1]]=${backupFile}
            fi
        fi
    fi
}

#-------------------------------------------------------------------------------
# Backup all databases if -a has been selected
#-------------------------------------------------------------------------------
if [ ! -z $allDatabases ]; then
    mySqlMagic
fi

#-------------------------------------------------------------------------------
# Backup single database if -g has been selected
#-------------------------------------------------------------------------------
if [[ ! -z $backupDatabase ]]; then
    mySqlMagic $backupDatabase
fi

#-------------------------------------------------------------------------------
# Execute the rsyncMagic function to initiate the copy(s)
#-------------------------------------------------------------------------------
if ! [ -z $sourceDirectory ]; then
    if [ $tarAllFilesInSource = 0 ]; then
        if [[ $goofy == "yes" ]]; then
            if ! [ $($sshCmd "test -e ${sourceDirectory} && echo 0 || echo 0") = 0 ]; then
                echo "$sourceDirectory does not exist not rsyncing at line: $LINENO" >> $log
            else
                for folder in $(${sshCmd} "ls ${sourceDirectory}");
                do
                    if [ "$copyMode" = "rsync" ]; then
                        echo "starting backup of source dir: ${folder}" >> $log
                        rsyncMagic ${sourceDirectory}/${folder}
                    elif [ "$copyMode" = "scp" ]; then
                        error_exit "Not using scpMagic - See James"
                    fi
                done
            fi
        else
            if ! [ -e $sourceDirectory ]; then
                echo "$sourceDirectory does not exist not rsyncing at line: $LINENO" >> $log
            else
                for folder in $(ls ${sourceDirectory});
                do
                    if [ "$copyMode" = "rsync" ]; then
                        echo "starting backup of source dir: $sourceDirectory" >> $log
                        rsyncMagic ${sourceDirectory}/${folder}
                    elif [ "$copyMode" = "scp" ]; then
                        error_exit "Not using scpMagic"
                    fi
                done
            fi
        fi
    else
        if [ "$copyMode" = "rsync" ]; then
            echo "starting backup of source dir: $sourceDirectory" >> $log
            rsyncMagic $sourceDirectory
        elif [ "$copyMode" = "scp" ]; then
            error_exit "Not using scpMagic"
        fi
    fi
else
    echo "Warning: No \$sourceDirectory not rsyncing at line: $LINENO" >> $log
fi

#-------------------------------------------------------------------------------
# Execute the rsyncMagic function to copy the database back to destination (-d) 
# TODO: Move this up so its completed after the dump
#-------------------------------------------------------------------------------

if [ $sqlBackup -eq 1 ]; then
    sqlBackupRemoveStatus=0
    sqlBackupRemoveDirStatus=0
    echo "rsync mysql" >> $log
    for files in ${databases[@]}; do
        echo -n "rsyncing $files... " >> $log
        if [ $(echo $files | grep [a-z0-9]) ]; then
            rsyncMagic $files "sql"
            echo "done" >> $log
            echo -n "removing $files ... " >> $log
            if [ "$goofy" = "yes" ]; then
                $sshCmd "rm $files" >> $log 2>&1
                if [ $? = 0 ]; then
                    echo "done" >> $log
                else	
                    sqlBackupRemoveStatus=1
                    echo "failed on $file" >> $log
                fi
            else
                rm $files >> $log 2>&1
                if [ $? = 0 ]; then
                    echo "done" >> $log
                else	
                    sqlBackupRemoveStatus=1
                    echo "failed on $file" >> $log
                fi
            fi
        fi
    done
    #-------------------------------------------------------------------------------
    # Remove backup directory if empty
    #-------------------------------------------------------------------------------
    if [ "$goofy" = "yes" ]; then
        echo -n "removing datetime directory: ${backupFileDir} ... " >> $log
        if [[ $($sshCmd "ls -A ${backupFileDir}") == "" ]]; then
            $sshCmd "rm -rf ${backupFileDir}" >> $log 2>&1
            echo "done" >> $log
        else
            echo "failed" >> $log
            sqlBackupRemoveDirStatus=1
        fi
    else
        echo -n "removing datetime directory: ${backupFileDir} ... " >> $log
        if [[ $(ls -A ${backupFileDir}) == "" ]]; then
            rm -rf ${backupFileDir} >> $log 2>&1
            echo "done" >> $log
        else
            echo "failed" >> $log
            sqlBackupRemoveDirStatus=1
        fi
    fi
else
    echo "No sql backup today" >> $log
fi 

globalFinishTime=$(expr $(date +%s) - $globalStartTime)

echo "Script completed in $globalFinishTime(s)" >> $log
if [ $sqlBackup = 1 ]; then
    # Error checking for rsyncMagic and sqlBackup
    if [ $sqlBackupRemoveStatus = 1 ]; then
        error_exit "Issue removing backup file(s) from source host"
    fi

    # Error checking for rsyncMagic and sqlBackup
    if [ $sqlBackupRemoveDirStatus = 1 ]; then
        error_exit "Issue removing backup directory from source host"
    fi
fi 

# Error checking for rsyncMagic and sqlBackup
if [ $rsyncMagicError = 1 ]; then
    error_exit "Issue rsycing file(s) from source host"
fi

# Send notification that we compeleted
if [ $sendEmailOnComplete = 0 ]; then
    cat $log | /usr/sbin/sendmail -t && rm $log
else
    rm $log
fi
