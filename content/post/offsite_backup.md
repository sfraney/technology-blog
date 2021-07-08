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
    - Full backup for first
    - Incremental backups for others
    - Would like to know how to skip certain datasets (e.g., zoneminder)
  - **TODO:** figure out proper encryption command