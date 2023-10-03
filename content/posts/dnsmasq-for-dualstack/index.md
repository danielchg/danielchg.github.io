---
title: "How configure dnsmasq for dual stack ipv4/ipv6"
date: 2023-10-03T13:19:23+02:00
tags: [DevOps,Networking]
draft: true
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

## Scenario 

Nowadays it is more and more common to start working with networks that support ipv6, in order to adapt our environment to the new version of the ip stack. Also we want to keep our ipv4 configuration for legacy applications. In this article I'm going to explain how to configure a DHCP and a DNS server to have an environment with support of both ip stacks. This configurations is commonly named dual stack.

At the moment of this writing I had to configure one lab environment with this requirement, the support of dual stack, and it was tedious to find the correct configuration for that, so the goal of this article is describe some common configurations like how to reserve ip addresses based on the mac of the NIC, configure the DNS resolution for both stacks, etc. Also to keep these configs as reference for myself.

## Dnsmasq

Dnsmasq is a lightweight implementation of a DHCP, DNS, router advertisement and network boot, designed for small networks or development and testing environments. This is not intended to be used on production environments. 

The official documentation can be found [here](https://thekelleys.org.uk/dnsmasq/doc.html)

## Installation

Dnsmasq is very popular, and it is included in almost all the Linux distributions, and also there are a lot of community container images available. For this article I'm going to use Fedora 38.

The below command will install the package of dnsmasq in our system running Fedora.

```bash
$ sudo dnf install dnsmasq
```

Once the *dnsmasq* package is installed, it  is available as a systemd service, hence it is required to enabled and start the service.

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

## Configuration

The whole config file described in this section is available as a GitHub gist in [here](https://gist.github.com/danielchg/fe59f31496d7f1d210123c4d80324565)

The main config file of *dnsmasq* in Fedora is in the path `/etc/dnsmasq.conf`. By default this file contain an entry that permit to add dnsmasq config files in the path `/etc/dnsmasq.d`, so we are going to create a file in that path with the name `dualstack.conf` and the content from the gist linked above.

Now I'm going to explain each section of the config file.

### Common config per interface

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

```
dhcp-range=ens1f0,fd02::100,fd02::200,64,24h
dhcp-option=option6:dns-server,[fd02::1]
enable-ra
dhcp-authoritative
strict-order
```

### IP reservation

```
dhcp-host=aa:bb:cc:dd:dd:ee,192.168.1.10,[fd02::10],host10.my.doamin.local
dhcp-host=aa:bb:cc:dd:dd:dd,192.168.1.11,[fd02::11],host11.my.doamin.local
```

### DNS resolution for dual stack

```
address=/www1.my.domain.local/192.168.1.10
address=/www1.my.domain.local/fd02::10
ptr-record=10.1.168.192.in-addr.arpa,master1.my.domain.local
```

### DNS resolution for wildcard subdomains

```
address=/.apps.my.domain.local/192.168.1.10
address=/.apps.my.domain.local/fd02::10
```

## Troubleshooting

## Summary 
