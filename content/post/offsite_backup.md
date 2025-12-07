---
title: "Offsite Backup"
date: 2021-07-07
description: ""
summary: ""
draft: false
tags: ["server"]
---

## Misc. Questions (mostly ZFS)

- **How to skip certain datasets** - this is relatively important to avoid sending an extra 110G+ data on initial backup consisting of ZoneMinder data
  - Not a killer, but would rather not back it up if I can avoid it
  - **Just backup datasets independently** (e.g., tank/data/sean, tank/media/pictures) => could skip the zoneminder set)
    - This also allows for recovering individual datasets (and maybe restructuring a pool's dataset hierarchy)
- Would 'zfs send -R ...' send all the sub-datasets (e.g., be >15G)? **Per tests below, yes, this is the flag to use**
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

- Install `aws-cli` on ZFS system
- [Setup user credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html "Configuration Basics") - `aws configure`
  - **TODO:** figure out how to provide credentials on CLI for automation **- seems unnecessary since I didn't have to re-enter my credentials after the first part of the tests below, despite performing the test over multiple sessions and days**
- [Stream data to bucket](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html#examples "aws s3 cp"): `zfs send <pool>/<dataset>@<snapshot> | <encryption> | aws s3 cp --expected-size $(zfs ) - s3://<bucket_name>/<filename>`
  - **TODO:** figure out how to skip certain datasets (e.g., zoneminder)

## Test Process

The following process was followed successfully to verify commands and flow before using on my real pool.

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
1. send incremental backup via script above, passing previous backup snapshot name as last argument
1. destroy local dataset
1. restore local dataset
   1. receive base backup
      ```
      POOL_NAME="win10_recv_inc"
      DATASET_NAME="data"
      BUCKET_NAME="913048231745bucket"
      RECV_FILENAME_BASE="win10_data_test_backup_snap"
      PASSWORD=<password>

      sudo zpool create $POOL_NAME ata-WDC_WD1600JS-75NCB1_WD-WCANM3331822
      aws s3 cp s3://$BUCKET_NAME/$RECV_FILENAME_BASE - | gpg --yes --batch --passphrase=$PASSWORD -d - | sudo zfs receive $POOL_NAME/$DATASET_NAME
      ```
   1. verify receipt of base: `find /$POOL_NAME/$DATASET_NAME -type f -exec sha256sum '{}' \; >> offsite_backup_base_recv_test.txt`
   1. receive each(?) incremental backup, in order, using `-F` flag to avoid having to "rollback" the receiving system, [per Oracle](https://docs.oracle.com/cd/E19253-01/819-5461/gbimy/index.html) (I don't know why, if all I've done is receive and not modified, that this is necessary, but it appears to be as evidenced by doing this test and having the incremental receipt fail on "cannot receive: destination has been modified since most recent snapshot" error)
      ```
      RECV_FILENAME_INC="win10_recv_data_test_backup_incremental_snap"

      aws s3 cp s3://$BUCKET_NAME/$RECV_FILENAME_INC - | gpg --yes --batch --passphrase=$PASSWORD -d - | sudo zfs receive -F $POOL_NAME/$DATASET_NAME
      ```
      1. verify receipt of each, in order: `find /$POOL_NAME/$DATASET_NAME -type f -exec sha256sum '{}' \; >> offsite_backup_incremental_recv_test.txt`
      - might just be a normal receive of each, in order