---
title: "Getting OpenVPN Up-and-Running on Linux Router"
date: 2021-06-06
description: ""
summary: ""
draft: false
tags: ["arch linux", "router"]
---

## Background

My commercial router had VPN capability (via OpenVPN and another option, I forget and didn't use) that I would use when connecting to public WiFi in order to have some semblance of security when using untrustable networks.  When transitioning to a [homemade router]({{< ref "arch_router" >}} "Building a Home Router Based on Arch Linux"), I didn't want to lose this functionality, so figured out how to install it.

## Process

The [Arch Linux Wiki](https://wiki.archlinux.org/title/OpenVPN "OpenVPN Arch Wiki") was the best source for the nuts-and-bolts of this process, but I also found the [OpenVPN documentation](https://openvpn.net/community-resources/how-to/#setting-up-your-own-certificate-authority-ca-and-generating-certificates-and-keys-for-an-openvpn-server-and-multiple-clients "OpenVPN How To") itself to be good for background and corroboration.

### Considerations

In what seems like wise advice, the wiki suggests that CA machine to be something _other than_ the one running OpenVPN.  ~~I believe it is most reasonable to either use my home server or desktop, but I'm somewhat concerned that since those machines are slated for upgrade (once Ryzen 9 5950x's become available at reasonable prices...), that I risk losing necessary information.  Hopefully I can back up the necessary pieces to a durable location (e.g., my server's backup area) in a safe manner.~~

After taking a look at some instructions for getting easy-rsa working on a debian distro (i.e., what my other, non-Windows, PCs are), I decided I didn't want to learn how to do it twice (i.e., once for CA and second for the router) and spun up an Arch Linux docker instead.  Unfortunately, per a [bug report](https://bugs.archlinux.org/task/69563 "glibc 2.33 break") I found on [Reddit](https://www.reddit.com/r/archlinux/comments/lek2ba/arch_linux_on_docker_ci_could_not_find_or_read/ "Arch Linux Docker Issue") based on a search, at the time of writing this, a glibc update has broken Arch Linux in virtualized environments like Docker so I had to jump through some hoops (i.e., use an older base image) to get a Docker image built with easy-rsa:

```
FROM archlinux:base-devel-20210131.0.14634

RUN pacman --noconfirm -Sy mg easy-rsa
```

In a fun twist, the installed `mg` **requires** glibc_2.33 (`mg: /usr/lib/libc.so.6: version 'GLIBC_2.33' not found (required by mg)`) so I ended up having to perform a system update _in_ the container: `pacman -Syu`.  Since I shouldn't need to invoke pacman again after this, I should be good.  Further, since this is in the ephemeral container (invoked with the `--rm` option, nonetheless) the extra stuff installed will vanish after I'm done with the container.

In order to allow necessary files to persist once this container has performed its task, I passed a volume to it, mapped to my server, where I copied all the CA secret stuff.  After I was done, I encrypted all the secret information (everything in the `easy-rsa` directory) with `gpg` using a symmetric algorithm (i.e., using a passphrase rather than a keypair that I can lose).

For completeness, the docker run command used was `docker run --rm -it -v /path/to/server/ca/directory:/openvpn-ca easy-rsa:1.0 bash`

Luckily I copied the `pki` directory to a persistent location because I ran into issues just signing the router's request in the container.  I was able to import it just fine, but encountered a `Easy-RSA error` `Unknown cert type 'server'`.  After trying a few suggestions online, I gave up and got easy-rsa working on my hypervisor machine (using some bootstrap pointers from [here](https://serverascode.com/2017/07/28/easy-rsa.html)) after making the `vars` files identical and copying over `pki`.  I guess I might have been better off just learning how to use easy-rsa in a Debian distro in the first place.

### iptables

[This post](https://arashmilani.com/post?id=53) was probably the most helpful at setting up iptables, but it was ultimately pretty consistent with the [Arch Linux wiki](https://wiki.archlinux.org/title/OpenVPN#iptables "OpenVPN iptables").  It turns out that all lines were necessary from the referenced post _and_ I couldn't connect unless my phone was off the network (i.e., request coming on the WAN interface).  Now that I write it out, that makes sense.  The iptables aren't set up to allow LAN devices to communicate to the router via port 1194.