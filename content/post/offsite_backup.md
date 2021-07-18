---
title: "Offsite Backup"
date: 2021-07-07
description: ""
summary: ""
draft: false
tags: []
---

## Misc. Questions (mostly ZFS)

- Would 'zfs send -R ...' send all the sub-datasets (e.g., be >15G)?
  - `sudo zfs send -Rnv tank@<latest snapshot>` gives promising output (lots of 'send from <snapshot>' with intermediate rollups showing 'full send of <snapshot>' and finally `total estimated size is 1.63T`)

### Test full backup/restore process on a simple dataset (maybe win10?)

- Create sub-datasets
- Send to bucket (snapshot of root dataset)
  - encrypted
  - full backup, followed by incremental
- Wait for propagation to glacier
- Recover from glacier
- Receive from bucket
  - decrypt
  - final from incremental

## AWS Glacier

- Can't stream (e.g., `zfs send`) => need to stream to S3 bucket and transition to glacier via "Lifecycle Rule"

### Using CLI (via `aws-cli`)

Currently learning using Alpine Linux docker container

- Install aws-cli on hypervisor
- [Setup user credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html "Configuration Basics") - `aws configure`
  - **TODO:** figure out how to provide credentials on CLI for automation
- [Stream data to bucket](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html#examples "aws s3 cp"): `zfs send <pool>/<dataset>@<snapshot> | <encryption> | aws s3 cp --expected-size $(zfs ) - s3://<bucket_name>/<filename>`
  - **TODO:** figure out proper send commands
    - ~~Full backup for first~~
    - Incremental backups for others
    - Would like to know how to skip certain datasets (e.g., zoneminder)

## Test Process

**Still need to incorporate verification of recursive datasets and restoration from sequence of incremental backups from outline above (*add link here*)**

1. copy a dataset to test pool (currently have 'win10' sitting around)
1. make a snapshot of the dataset: `zfs snapshot -r $POOL_NAME/$DATASET_NAME@$SNAP_NAME`
1. dump identifying statistics for dataset: `find /win10/data -type f -exec sha256sum '{}' \; >> offsite_backup_test.txt`
1. backup dataset copy to AWS (currently bash with `$(` syntax, but could be modified for another shell)
   - `aws configure`
     - Currently have to manually enter credentials 'cause I didn't figure out how to automate it with a quick search
   - The following script encapsulates a sequence of straightforward `bash` commands for backing up
```
#!/bin/bash

ARGC=$#
if [[ $ARGC -lt 5 ]] || [[ $ARGC -gt 6 ]]; then
	echo "USAGE: <cmd> POOL_NAME DATASET_NAME SNAP_NAME BUCKET_NAME PASSWORD [PREV_SNAP_NAME]"
	exit
fi

POOL_NAME=$1
DATASET_NAME=$2
if [ $ARGC -eq 6 ]; then
	PREV_SNAP_NAME="-I $6"
fi
SNAP_NAME=$3
RECV_FILENAME=$POOL_NAME"_"$DATASET_NAME"_"$SNAP_NAME
BUCKET_NAME=$4
PASSWORD=$5

EXP_SIZE=$(sudo zfs send -Rnv $PREV_SNAP_NAME $POOL_NAME/$DATASET_NAME@$SNAP_NAME | grep "total estimated size is" | perl -nle 'if($_ =~ m/([\d.]+)([KMGT])/){$size=$1;$type=$2;$multiplier=1;if($type eq "K"){$multiplier=1024;}elsif($type eq "M"){$multiplier=1024*1024}elsif($type eq "G"){$multiplier=1024*1024*1024}elsif($type eq "T"){$multiplier=1024*1024*1024*1024}else{print "Unknown multiplier"}print int($multiplier * $size)}')
sudo zfs send -R $PREV_SNAP_NAME $POOL_NAME/$DATASET_NAME@$SNAP_NAME | gpg --yes --batch --passphrase=$PASSWORD -c - | aws s3 cp --expected-size $EXP_SIZE - s3://$BUCKET_NAME/$RECV_FILENAME
```
1. verify transfer to S3 on web console (alternatively via aws-cli)
1. destroy local test pool: `sudo zpool destroy win10`
1. receive locally to get quick feedback on success
   - `POOL_NAME="win10_recv"`
   - `DATASET_NAME="data"`
   - Create new pool: `sudo zpool create $POOL_NAME ata-WDC_WD1600JS-75NCB1_WD-WCANM3331822`
   - `aws s3 cp s3://$BUCKET_NAME/$RECV_FILENAME - | gpg --yes --batch --passphrase=$PASSWORD -d - | sudo zfs receive $POOL_NAME/$DATASET_NAME`
1. verify transfer from S3 to Glacier on web console (alternatively via aws-cli): currently have 0 day transfer, so I _think_ it should move after the first midnight (UTC)
1. unthaw Glacier image (i.e., transfer to normal S3), if necessary (i.e., I assume a Glacier image can't be transferred directly)
   - probably not worth learning programmatically, just use web console
1. 'receive' dataset
   - `POOL_NAME="win10_recv"`
   - `DATASET_NAME="data"`
   - Create new pool: `sudo zpool create $POOL_NAME ata-WDC_WD1600JS-75NCB1_WD-WCANM3331822`
   - `aws s3 cp s3://$BUCKET_NAME/$RECV_FILENAME - | gpg --yes --batch --passphrase=$PASSWORD -d - | sudo zfs receive $POOL_NAME/$DATASET_NAME`
1. verify receipt against identifying statistics from above
1. modify received dataset (e.g., add/delete/modify some files) and create new snapshot

### modify steps 4 on to accommodate incremental backup
1. send incremental backup
   - **TODO:** learn how to send incremental backup
      - [this post](https://www.grendelman.net/wp/fast-frequent-incremental-zfs-backups-with-zrep/) has a good, short discussion (I ignored the discussion of `zrep` 'cause I'm not interested in learning a new tool)
      -	From [Oracle](https://docs.oracle.com/cd/E19253-01/819-5461/gbchx/index.html) `zfs send -I snap1 tank/dana@snap2 > ssh host2 zfs recv newtank/dana` (`-I` ensures "all snapshots between snapA and snapD are sent. If -i is used, only snapD (for all descendents) are sent."
      - combining original step 4 with incremental send (omitting `aws configure` because it doesn't seem to be necessary after the initial setup):
   - `POOL_NAME="win10_recv"`
   - `DATASET_NAME="data"`
   - `PREV_SNAP_NAME="test_backup_snap"`
   - `SNAP_NAME="test_backup_incremental_snap"`
   - `EXP_SIZE=$(sudo zfs send -Rnv -I $PREV_SNAP_NAME $POOL_NAME/$DATASET_NAME@$SNAP_NAME | grep "total estimated size is" | perl -nle 'if($_ =~ m/([\d.]+)([KMGT])/){$size=$1;$type=$2;$multiplier=1;if($type eq "K"){$multiplier=1024;}elsif($type eq "M"){$multiplier=1024*1024}elsif($type eq "G"){$multiplier=1024*1024*1024}elsif($type eq "T"){$multiplier=1024*1024*1024*1024}else{print "Unknown multiplier"}print int($multiplier * $size)}')`
   - `RECV_FILENAME=$POOL_NAME"_"$DATASET_NAME"_"$SNAP_NAME`
   - `BUCKET_NAME="913048231745bucket"`
   - `PASSWORD="<password>"`
   - `sudo zfs send -R -I $PREV_SNAP_NAME $POOL_NAME/$DATASET_NAME@$SNAP_NAME | gpg --yes --batch --passphrase=$PASSWORD -c - | aws s3 cp --expected-size $EXP_SIZE - s3://$BUCKET_NAME/$RECV_FILENAME`
1. 
   - **TODO:** learn how to recreate dataset from base + incremental backup(s)
