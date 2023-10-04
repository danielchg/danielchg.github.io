---
title: "How to configure dnsmasq for dual stack ipv4/ipv6"
date: 2023-10-03T13:19:23+02:00
tags: [DevOps,Networking]
draft: false
---

# Table of Contents

- [Table of Contents](#table-of-contents)
- [Scenario](#scenario)
- [Dnsmasq](#dnsmasq)
- [Installation](#installation)
- [Configuration](#configuration)
    - [Common config per interface](#common-config-per-interface)
    - [DHCP options for ipv4](#dhcp-options-for-ipv4)
    - [DHCP options for ipv6](#dhcp-options-for-ipv6)
    - [IP reservation](#ip-reservation)
    - [DNS resolution for dual stack](#dns-resolution-for-dual-stack)
    - [DNS resolution for wildcard subdomains](#dns-resolution-for-wildcard-subdomains)
- [Troubleshooting](#troubleshooting)
- [Summary](#summary)

# Scenario 

Nowadays it is more and more common to start working with networks that support ipv6, in order to adapt our environment to the new version of the ip stack. Also we want to keep our ipv4 configuration for legacy applications. In this article I'm going to explain how to configure a DHCP and a DNS server to have an environment with support of both ip stacks. This configuration is commonly named dual stack.

At the moment of this writing I had to configure a lab environment with dual stack support, and it was tedious to me to find the correct configuration for that. The goal of this article is to describe some common configurations such as ip reservations, add DNS entries, etc. Also I have written this article as a personal reference.

# Dnsmasq

Dnsmasq is a lightweight implementation of a DHCP, DNS, router advertisement and network boot, designed for small networks or development and testing environments. This is not intended to be used on production environments. 

The official documentation can be found [here](https://thekelleys.org.uk/dnsmasq/doc.html)

# Installation

Dnsmasq is very popular, and it is included in almost all the Linux distributions, and also there are a lot of community container images available. For this article I'm going to use the package available on Fedora 38.

The below command will install *dnsmasq* package.

```bash
$ sudo dnf install dnsmasq
```

Once *dnsmasq* is installed, we have to enable and start the systemd service, as described in the below capture.

```bash
$ sudo systemctl enable dnsmasq.service
[sudo] password for user: 
Created symlink /etc/systemd/system/multi-user.target.wants/dnsmasq.service → /usr/lib/systemd/system/dnsmasq.service.

$ sudo systemctl start dnsmasq
$ systemctl status dnsmasq
● dnsmasq.service - DNS caching server.
     Loaded: loaded (/usr/lib/systemd/system/dnsmasq.service; enabled; preset: disabled)
    Drop-In: /usr/lib/systemd/system/service.d
             └─10-timeout-abort.conf
     Active: active (running) since Tue 2023-10-03 19:19:25 CEST; 2s ago
    Process: 75938 ExecStart=/usr/sbin/dnsmasq (code=exited, status=0/SUCCESS)
   Main PID: 75940 (dnsmasq)
      Tasks: 1 (limit: 18847)
     Memory: 1.2M
        CPU: 6ms
     CGroup: /system.slice/dnsmasq.service
             └─75940 /usr/sbin/dnsmasq

```

# Configuration

You can find the whole config file used in this article in [this GitHub gist](https://gist.github.com/danielchg/fe59f31496d7f1d210123c4d80324565)

The main config file of *dnsmasq* in Fedora is in the path `/etc/dnsmasq.conf`. By default this file contain an entry that permit to add dnsmasq config files in the path `/etc/dnsmasq.d/` to extend the main config, so we are going to create a file in that path with the name `dualstack.conf` and the content from the gist linked above. Depending of your environment you should update the values such as the domain name, interface, ips, etc.

Now I'm going to explain each section of the config file.

### Common config per interface

In the first part of the config I would like to highlight the `interface` and `listen-address` fields. These fields allow to configure different DHCP ranges per interface, if we have a server as a central router with multiple interfaces that connect to different subnets, with this configuration we can run different configurations per subnet. In this example it is configured only one interface.

```
domain=my.domain.local
domain-needed
interface=ens1f0
bogus-priv
listen-address=192.168.1.1
expand-hosts
server=8.8.8.8
```

### DHCP options for ipv4

As mentioned above we can configure different ip ranges per interface. In this section are configured the `dhcp-range` to lease ips from `192.168.100` to `192.168.1.200` on the interface `ens1f0` of the machine. Also the rest of the network configs for the DHCP clients, such a DNS and NTP servers.

```
dhcp-range=ens1f0,192.168.1.100,192.168.1.200,24h
dhcp-option=ens1f0,option:netmask,255.255.255.0
dhcp-option=ens1f0,option:router,192.168.1.1
dhcp-option=ens1f0,option:dns-server,192.168.1.1
dhcp-option=ens1f0,option:domain-search,my.domain.local
dhcp-option=ens1f0,option:ntp-server,192.168.1.1
dhcp-option=ens1f0,option:classless-static-route,172.16.110.0/24,192.168.1.2
```

### DHCP options for ipv6

The same as for ipv4, we can configure `dhcp-range` with the ipv6 addresses to the subnet connected to the interface `ens1f0`. In this example it is used an ipv6 range of [ULA (Unique Local Address)](https://en.wikipedia.org/wiki/Unique_local_address), which is a not Internet routable, similar to the ipv4 private ips. Also I want to highlight a configuration that is specific for ipv6, the `enable-ra` parameter. This parameter enable the Router Advertisement service on *dnsmasq*. 

```
dhcp-range=ens1f0,fd02::100,fd02::200,64,24h
dhcp-option=option6:dns-server,[fd02::1]
enable-ra
dhcp-authoritative
strict-order
```

### IP reservation

When you manage a network, sometimes you need to ensure that a host get a specific ip address from the DHCP, in order to allow traffic to that ip on a firewall, or just to ensure that this machine replies to some DNS subdomains on http request. Also it is important to reserve the ip on both stacks. In this part of the config you can see how to add both ips associated with the mac address, and also create a DNS entry for that host. The notations are `dhcp-host=<mac address>,<ipv4>,<ipv6>,<DNS hostname>`.

```
dhcp-host=aa:bb:cc:dd:dd:ee,192.168.1.10,[fd02::10],host10.my.doamin.local
dhcp-host=aa:bb:cc:dd:dd:dd,192.168.1.11,[fd02::11],host11.my.doamin.local
```

### DNS resolution for dual stack

To add DNS entries that resolve two ip stacks, it is required to add two entries in the config file with the same DNS name, each with the ip of each stack. The same thing with the reverse resolution. In the ptr entry I would like to highlight the domain `ip6.arpa` for the ipv6 reverse resolution.

```
address=/www1.my.domain.local/192.168.1.10
address=/www1.my.domain.local/fd02::10
ptr-record=10.1.168.192.in-addr.arpa,www1.my.domain.local
ptr-record=10.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.2.0.d.f.ip6.arpa,www1.my.domain.local
```

### DNS resolution for wildcard subdomains

Another common use case is the add entries DNS with a wildcard, like `*.apps.my.domain.local`. With this example the subdomain `test1.apps.my.domain.local`  and `test2.apps.my.domain.local` will resolve to the same ip on both stacks.

```
address=/.apps.my.domain.local/192.168.1.10
address=/.apps.my.domain.local/fd02::10
```

# Troubleshooting

As mentioned above, in Fedora the *dnsmasq* run as a systemd service, hence to see the logs we need to use `journalctl` command.

```bash
journalctl -u dnsmasq -f
```

If we detect a problem with the lease, such as a reserved ip address that is not assigned to the host with a reservation using the mac address, we can review the lease database in the file `/var/lib/dnsmasq/dnsmasq.leases`. This is a plain text file, we can edit it with `vi`, for instance.

# Summary 

Dnsmasq is a lightweight and easy to use server to run DNS and DHCP services for small networks, or dev and test environments. This support dual stack to configure both ip stacks in the same network.
