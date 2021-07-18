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
1. dump identifying statistics for dataset: `find /win10/data -type f -exec sha256sum '{}' \; >> offsite_backup_test.txt`
1. backup dataset copy to AWS (currently bash with `$(` syntax, but could be modified for another shell)
   - `aws configure`
     - Currently have to manually enter credentials 'cause I didn't figure out how to automate it with a quick search
   - `POOL_NAME="win10"`
   - `DATASET_NAME="data"`
   - `SNAP_NAME="test_backup_snap"`
   - `EXP_SIZE=$(sudo zfs send -Rnv $POOL_NAME/$DATASET_NAME@$SNAP_NAME | grep "total estimated size is" | perl -nle 'if($_ =~ m/([\d.]+)([KMGT])/){$size=$1;$type=$2;$multiplier=1;if($type eq "K"){$multiplier=1024;}elsif($type eq "M"){$multiplier=1024*1024}elsif($type eq "G"){$multiplier=1024*1024*1024}elsif($type eq "T"){$multiplier=1024*1024*1024*1024}else{print "Unknown multiplier"}print int($multiplier * $size)}')`
   - `RECV_FILENAME=$POOL_NAME"_"$DATASET_NAME"_"$SNAP_NAME`
   - `BUCKET_NAME="913048231745bucket"`
   - `PASSWORD="<password>"`
   - `sudo zfs send -R $POOL_NAME/$DATASET_NAME@$SNAP_NAME | gpg --yes --batch --passphrase=$PASSWORD -c - | aws s3 cp --expected-size $EXP_SIZE - s3://$BUCKET_NAME/$RECV_FILENAME`
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
1. modify received dataset and create new snapshot
1. send incremental, encrypted backup
   - **TODO:** learn how to send incremental backup
1. return to step 4 and perform for combined initial backup and incremental
   - **TODO:** learn how to recreate dataset from base + incremental backup(s)
