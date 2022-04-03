---
title: "Getting OpenVPN Up-and-Running on Linux Router"
date: 2021-06-06
description: ""
summary: ""
draft: false
tags: ["arch linux", "router"]
---

## Background

My commercial router had VPN capability (via OpenVPN and another option I forget and didn't use) that I would use when connecting to public WiFi in order to have some semblance of security when using untrustable networks.  When transitioning to a [homemade router]({{< relref "arch_router" >}} "Building a Home Router Based on Arch Linux"), I didn't want to lose this functionality, so figured out how to install it.

## Process

The [Arch Linux Wiki](https://wiki.archlinux.org/title/OpenVPN "OpenVPN Arch Wiki") was the best source for the nuts-and-bolts of this process, but I also found the [OpenVPN documentation](https://openvpn.net/community-resources/how-to/#setting-up-your-own-certificate-authority-ca-and-generating-certificates-and-keys-for-an-openvpn-server-and-multiple-clients "OpenVPN How To") itself to be good for background and corroboration.

1. Decrypt OpenVPN_CA tarball from backups: `gpg -d -o /tmp/OpenVPN_CA.tgz /path/to/OpenVPN_CA.tgz`
1. Deflate tarball: `pushd /tmp && tar -xvf OpenVPN_CA.tgz`
1. (if not already present) Create docker image: `pushd /path/to/directory-containing-easy-rsa-Dockerfile docker build -t easy-rsa .`
1. (optional) Tag image as newest version: `docker tag easy-rsa easy-rsa:<latest version number +1>`
   1. From https://medium.com/@mccode/the-misunderstood-docker-tag-latest-af3babfd6375
1. Launch docker container: `docker run --rm -it -v /tmp/OpenVPN_CA:/openvpn-ca -v /home/sean/docker/easy-rsa/ovpngen/:/scripts easy-rsa:latest bash`
1. Generate the client key and certificate:
   1. `pushd /openvpn-ca/easy-rsa`
   1. Fulfill equirements for generating proper keys using ecliptic curves (per OpenVPN client file generation [instructions](https://wiki.archlinux.org/title/Easy-RSA#OpenVPN_client_files)
      1. `export EASYRSA=$(pwd)`
      1. `export EASYRSA_VARS_FILE=/openvpn-ca/easy-rsa/vars`
   1. `easyrsa gen-req <client-name> nopass`
      - 'nopass' option - do not encrypt the private key (default is encrypted) - will be encrypted symmetrically with gpg later
        - **Might be worth seeing if the default encryption can be used to skip this second step and improve security.** My worry is that it will use keypair (a.k.a., asymmetric) encryption and then I'll have to track that keypair to decrypt.
      - Should be able to leave only question (Common Name) the default (client-name)
1. Sign requests (done on same docker container since it has the router's CA information, too): `easyrsa sign-req client <client-name>`
1. Copy router ta.key file to docker container
   1. On router: `sudo scp /path/to/ta.key <container-host>:/tmp`
   1. On container host
      1. `docker cp /tmp/ta.key <container-name>:/tmp`
      1. `rm /tmp/ta.key`
1. Create .ovpn files from .crt: `/scripts/ovpngen <current-router-public-ip-address> /openvpn-ca/easy-rsa/pki/ca.crt /openvpn-ca/easy-rsa/pki/issued/<client-name>.crt /openvpn-ca/easy-rsa/pki/private/<client-name>.key /tmp/ta.key > /tmp/<client-name>.ovpn`
1. Copy .ovpn file out of docker container's /tmp directory to RaspberryPi (which is the machine that makes sure these are encrypted and available)
   1. (On container host) `docker cp <container-name>:/tmp/<client-name>.ovpn /tmp`
   1. (Either on RaspberryPi or on container host) Make ovpn consistent with server expectations
      1. Add `redirect-gateway def1 bypass-dhcp`
      1. Uncomment `cipher AES-256-CBC` and `auth SHA-512` lines
      1. Replace '<tls-auth>' with '<tls-crypt>' in /tmp/<client-name>.ovpn
   1. (On container host) `scp /tmp/<client-name>.ovpn <raspberrypi>:/home/pi`
1. **At this point, the generated .ovpn file and an old .ovpn file that I know works, differ => might have some more issues.** Need to test new file to see if it works.
   - In particular, the new certificate is 2048-bit rsaEncryption rather than 521-bit id-ecPublicKey.  This might be due to incorrect arguments when generating the client request (`easyrsa gen-req...` above)
1. Remove sensitive data from container host
   1. Shutdown container
      1. Optionally verify no container persists (Won't if launched with `--rm` as above): `docker container ls --all`
   1. `rm /path/to/OpenVPN_CA.tgz`
   1. `rm -fr /tmp/OpenVPN_CA`
   1. `rm -fr /tmp/*.ovpn`
   1. `rm /tmp/ta.key` (if not removed above, as directed)

### Considerations

In what seems like wise advice, the wiki suggests that CA machine to be something _other than_ the one running OpenVPN.  ~~I believe it is most reasonable to either use my home server or desktop, but I'm somewhat concerned that since those machines are slated for upgrade (once Ryzen 9 5950x's become available at reasonable prices...), that I risk losing necessary information.  Hopefully I can back up the necessary pieces to a durable location (e.g., my server's backup area) in a safe manner.~~

After taking a look at some instructions for getting easy-rsa working on a debian distro (i.e., what my other, non-Windows, PCs are), I decided I didn't want to learn how to do it twice (i.e., once for CA and second for the router) and spun up an Arch Linux docker instead.  Unfortunately, per a [bug report](https://bugs.archlinux.org/task/69563 "glibc 2.33 break") I found on [Reddit](https://www.reddit.com/r/archlinux/comments/lek2ba/arch_linux_on_docker_ci_could_not_find_or_read/ "Arch Linux Docker Issue") based on a search, at the time of writing this, a glibc update has broken Arch Linux in virtualized environments like Docker so I had to jump through some hoops (i.e., use an older base image) to get a Docker image built with easy-rsa:
    
```
FROM archlinux:base-devel-20210131.0.14634

RUN pacman --noconfirm -Sy mg easy-rsa
```

In a fun twist, the installed `mg` **requires** glibc_2.33 (`mg: /usr/lib/libc.so.6: version 'GLIBC_2.33' not found (required by mg)`) so I ended up having to perform a system update _in_ the container: `pacman -Syu`.  Since I shouldn't need to invoke pacman again after this, I should be good.  Further, since this is in the ephemeral container (invoked with the `--rm` option, nonetheless) the extra stuff installed will vanish after I'm done with the container.

In order to allow necessary files to persist once this container has performed its task, I passed a volume to it, mapped to my server, where I copied all the CA secret stuff.  After I was done, I encrypted all the secret information (everything in the `easy-rsa` directory) with `gpg` using a symmetric algorithm (i.e., using a passphrase rather than a keypair that I can lose more easily).

For completeness, the docker run command used was `docker run --rm -it -v /path/to/server/ca/directory:/openvpn-ca easy-rsa:1.0 bash`

Luckily I copied the `pki` directory to a persistent location because I ran into issues just signing the router's request in the container.  I was able to import it just fine, but encountered a `Easy-RSA error` `Unknown cert type 'server'`.  After trying a few suggestions online, I gave up and got easy-rsa working on my hypervisor machine (using some bootstrap pointers from [here](https://serverascode.com/2017/07/28/easy-rsa.html)) after making the `vars` files identical and copying over `pki`.  I guess I might have been better off just learning how to use easy-rsa in a Debian distro in the first place.

### iptables

[This post](https://arashmilani.com/post?id=53) was probably the most helpful at setting up iptables, but it was ultimately pretty consistent with the [Arch Linux wiki](https://wiki.archlinux.org/title/OpenVPN#iptables "OpenVPN iptables").  It turns out that all lines were necessary from the referenced post _and_ I couldn't connect unless my phone was off the network (i.e., request coming on the WAN interface).  Now that I write it out, that makes sense.  The iptables aren't set up to allow LAN devices to communicate to the router via port 1194.
