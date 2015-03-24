narwhal - A docker network configuration tool
=============================================

## What does `narwhal` do?

`narwhal` is used with the `--net=none` option to `docker run` and creates a
virtual ethernet device pair (with one end in the container and the other end
on the host system). It assigns static IPv4 and IPv6 addresses with the
minimum neccessary routing setup.

## What is this good for?

Docker currently offers 4 different networking modes: `bridge`, `host`, 
`container` and `none`.

Most users use `bridge` which is the default. In bridge mode Docker creates
a seperate networking namespace per container and a virtual ethernet device pair.
This is fairly secure as a container is not capable to interfere with other
containers' or even the host systems' networking stack.

In addition to that the Docker daemon creates a virtual bridge device on
startup which is (more or less) a layer 2 (ethernet) switch. It adds the host
side of your containers' virtual ethernet pair to that bridge. This allows
all containers to talk to each other via ethernet. Read 
[here](https://nyantec.com/en/2015/03/20/docker-networking-considered-harmful/)
why this is extremely dangerous. It completely undermines the carefully crafted
container isolation based on networking namespaces.

The solution proposed by `narwhal` is to just have a virtual ethernet device
and networking namespace per container and simply route IPv4 and IPv6 (layer 3)
packets between containers and the outside world.

It is common knownledge to most operators how to work with 
[iptables](http://www.netfilter.org/projects/iptables/) and 
[ip6tables](http://ipset.netfilter.org/ip6tables.man.html), but how many have
ever heard of [ebtables](http://ebtables.netfilter.org/)? ;-)

__tl;dr: Docker's default networking mode is vulnerable to ARP spoofing attacks.
A single malicious container corrupts all running containers.__

## How do I use it?

```
Usage: narwhal.sh [OPTION]… [CONTAINER]

  -4, --ipv4 IPV4               container IPv4 address
  -6, --ipv6 IPV6               container IPv6 address
      --forwarding              enable packet forwarding

      --host-ipv4 IPV6          host IPv4 address [169.254.0.1]
      --host-ipv6 IPV6          host IPv6 address [fe80::1]

      --interface IFACE         container interface name [eth0]
      --host-interface IFACE    host interface name [nw-CONTAINER]

      --temp-interface IFACE    temporary container interface name [nwt-PID]
      --temp-namespace NS       temporary network namespace name [nwt-PID]

      --trace                   trace actions
  -h, --help                    display this help and exit
```

### Example

You need to configure your container with `--net=none`:

```bash
root@host:/# docker run --rm -t -i --net=none ubuntu /bin/bash
root@bb9b0be2a4d3:/# ip address
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default 
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
```

Now that your container is running configure networking. We assume we own the public subnets
`5.9.235.144/28` and `2a01:4f8:161:310e:4::/80`:

```bash
root@host:/# narwhal --ipv4 5.9.235.147 --ipv6 2a01:4f8:161:310e:4::1 bb9b0be2a4d3
```


You should now be able to see the new device. This is what it looks like on the host:

```
root@host:/# ip address
...
74: nw-bb9b0be2a4d3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
link/ether 6a:55:5e:99:b8:1f brd ff:ff:ff:ff:ff:ff
    inet 169.254.0.1/32 scope link nw-caf242370b5c
       valid_lft forever preferred_lft forever
    inet6 fe80::6855:5eff:fe99:b81f/64 scope link 
       valid_lft forever preferred_lft forever
    inet6 fe80::1/128 scope link 
       valid_lft forever preferred_lft forever

root@host:/# ip route
default via 5.9.42.1 dev eth0 
5.9.235.147 dev nw-bb9b0be2a4d3  proto kernel  scope link  src 5.9.42.20 

root@host:/# ip -6 route
2a01:4f8:161:310e::1 dev nw-bb9b0be2a4d3  proto kernel  metric 256 
2a01:4f8:161:310e::/80 dev eth0  proto kernel  metric 256 
2a01:4f8:161:310e:4::1 dev nw-bb9b0be2a4d3  proto kernel  metric 256 
fe80::/64 dev eth0  proto kernel  metric 256 
fe80::/64 dev nw-bb9b0be2a4d3  proto kernel  metric 256 
default via fe80::1 dev eth0  metric 1024 
```

This is how it looks like from within the container: 

```bash
root@bb9b0be2a4d3:/# ip address
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default 
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
157: eth0: <BROADCAST,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 4e:45:86:31:c4:15 brd ff:ff:ff:ff:ff:ff
    inet 5.9.235.147/32 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 2a01:4f8:161:310e:4::1/128 scope global 
       valid_lft forever preferred_lft forever
    inet6 fe80::4c45:86ff:fe31:c415/64 scope link 
       valid_lft forever preferred_lft forever

root@bb9b0be2a4d3:/# ip route
default via 169.254.0.1 dev eth0 
169.254.0.1 dev eth0  scope link 

root@bb9b0be2a4d3:/# ip -6 route
2a01:4f8:161:310e:4::1 dev eth0  proto kernel  metric 256 
fe80::1 dev eth0  metric 1024 
fe80::/64 dev eth0  proto kernel  metric 256 
default via fe80::1 dev eth0  metric 1024
```

If `sysctl net/ipv4/conf/all/forwarding` and `sysctl net/ipv6/conf/all/forwarding` 
are enabled and your packet filter is not interfering your should now be able to reach the outside world:

```bash
root@bb9b0be2a4d3:/# ping 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=53 time=9.16 ms
^C
--- 8.8.8.8 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 9.169/9.169/9.169/0.000 ms
root@bb9b0be2a4d3:/# ping6 heise.de 
PING heise.de(redirector.heise.de) 56 data bytes
64 bytes from redirector.heise.de: icmp_seq=1 ttl=55 time=5.47 ms
^C
--- heise.de ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 5.472/5.472/5.472/0.000 m
```

## FAQ

### How do I undo what `narwhal` did?

Stop the container or run

```bash
ip link del nw-$CONTAINERID

```

All routes etc will vanish automatically.

### Does `narwhal` configure `iptables`?

No, but here are your options:

  - Assign public IPv4 or IPv6 addresses, enable IP forwarding and be happy.
    Perform filtering via the `FORWARDING` chain in the filter table as you like.
  - Assign private IPv4 or IPv6 addresses and just use them to connect your
    containers with the host or with each other.
    Additionally, configure source- and/or destination NAT manually.

### What happens if `narwhal` is (accidentially) applied more than once?

Nothing. It will find that an `eth0` device already exists and just fail
after rolling back alrady acquired resources.

### Can `narwhal` be used in combination with the other networking modes?

Absolutely! Your other containers may use other networking modes.
Containers you want to configure with `narwahl` should use `--net=none`.
Trying to apply `narwahl` to otherwise configured containers just fails
if an `eth0` device already exists, but it won't cause any harm.

### What happens on container termination?

The containers' networking namespace and the virtual ethernet pair are destroyed
automatically.

### What happens when I configure networking after my container started?

If the container is started with `--net=none` it only has a
[loop back device](https://en.wikipedia.org/wiki/Loop_device). When your
container has services listening on ports it should __not__ bind to
a specific address (except `127.0.0.1` or `::1`). 

Not binding to an address is usually achieved by supplying `0.0.0.0`, `*`, `:::`
as listen address. Consult your services' documentation for details.

After `narwhal` was run and created the `eth0` device your service will
automatically accept packets via the supplied addresses.

