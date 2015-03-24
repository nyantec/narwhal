narwhal – secure Docker networking
==================================

## Abstract

`narwhal` is used in conjunction with the `--net=none` networking mode of
Docker to establish a secure network configuration with full layer‐2
isolation.

## Background

Docker currently offers 4 different networking modes: `bridge`, `host`, 
`container` and `none`.

Most users rely on the default `bridge` mode, as it is the only one
providing Internet connectivity with network isolation out of the box.
In this mode, Docker creates seperate network namespaces for every
container as well as a connected pair of virtual Ethernet interfaces
with one end in the host’s network namespace and the other end in the
container’s namespace. This approach is fairly secure by itself as all
communication has to go through this virtual interface and no container
is capable of interfering with other containers’ or even the host’s
network stack.

Unfortunately, the Docker daemon creates an Ethernet bridge on startup,
which behaves (more or less) like a hardware Ethernet switch. Docker then
connects the host side of the virtual interfaces to it, allowing all
containers to talk to each other directly via Ethernet (layer 2). Read
[this article](https://nyantec.com/en/2015/03/20/docker-networking-considered-harmful/)
to understand why this is a bad idea. It completely undermines the
carefully crafted network isolation.

`narwhal` on the other hand does without a bridge by routing IPv4 and
IPv6 (layer 3) packets between containers and the outside world, thus
eliminating the problems that come with having all your containers in
the same Ethernet segment.

__tl;dr: Docker’s default networking mode is vulnerable to ARP and MAC
spoofing attacks. A single container under control of an attacker is
enough to compromise the whole network.__

## Usage

```
Usage: narwhal [OPTION]… [CONTAINER]

  -4, --ipv4 IPV4               container IPv4 address
  -6, --ipv6 IPV6               container IPv6 address
      --forwarding              enable packet forwarding

      --host-ipv4 IPV6          host IPv4 address [169.254.0.1]
      --host-ipv6 IPV6          host IPv6 address [fe80::1]

  -i, --interface IFACE         container interface name [eth0]
      --host-interface IFACE    host interface name [nw-CONTAINER]
      --mtu SIZE                maximum transmission unit

      --temp-interface IFACE    temporary container interface name [nwt-PID]
      --temp-namespace NS       temporary network namespace name [nwt-PID]

      --paranoid                create restrictive Ethernet filter rules

      --trace                   trace actions
  -h, --help                    display this help and exit
```

### Example

In this example, we shall create a container with `--net=none`. At first,
it will only have a loopback interface:

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

Now that our container is running, we shall run `narwhal` to create a
network configuration, using `128.66.23.42` and `2001:db8:cabb:a6e5::1` as
addresses for our container.

```bash
root@host:/# narwhal --ipv4 128.66.23.42 --ipv6 2001:db8:cabb:a6e5::1 bb9b0be2a4d3
```


We should now be able to see the new network interface on the host:

```
root@host:/# ip address
…
74: nw-bb9b0be2a4d3: <BROADCAST,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
link/ether 6a:55:5e:99:b8:1f brd ff:ff:ff:ff:ff:ff
    inet 169.254.0.1 peer 128.66.23.42/32 scope link nw-caf242370b5c
       valid_lft forever preferred_lft forever
    inet6 fe80::6855:5eff:fe99:b81f/64 scope link 
       valid_lft forever preferred_lft forever
    inet6 fe80::1 peer 2001:db8:cabb:a6e5::1/128 scope link 
       valid_lft forever preferred_lft forever

root@host:/# ip -4 route
default via 128.66.0.1 dev eth0
128.66.0.1/24 dev eth0  proto kernel  scope link  src 128.66.0.2
128.66.23.42 dev nw-bb9b0be2a4d3  proto kernel  scope link  src 169.254.0.1

root@host:/# ip -6 route
2001:db8:cabb:a6e5::1 dev nw-8a418da09ebf  proto kernel  metric 256 
2001:db8:cabb:a6e5::1 dev nw-8a418da09ebf  metric 1024 
2001:db8:dead:beef::/64 dev eth0  proto kernel  metric 256 
fe80::1 dev nw-bb9b0be2a4d3  proto kernel  metric 256 
fe80::/64 dev eth0  proto kernel  metric 256 
fe80::/64 dev nw-8a418da09ebf  proto kernel  metric 256 
default via 2001:db8:dead:beef::1 dev eth0  metric 1024 
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
    inet 128.66.23.42 peer 169.254.0.1/32 scope global eth0 
       valid_lft forever preferred_lft forever
    inet6 2001:db8:cabb:a6e5::1 peer fe80::1/128 scope global 
       valid_lft forever preferred_lft forever
    inet6 fe80::4c45:86ff:fe31:c415/64 scope link 
       valid_lft forever preferred_lft forever

root@bb9b0be2a4d3:/# ip -4 route
default via 169.254.0.1 dev eth0 
169.254.0.1 dev eth0  proto kernel  scope link  src 128.66.23.42

root@bb9b0be2a4d3:/# ip -6 route
2001:db8:cabb:a6e5::1 dev eth0  proto kernel  metric 256 
fe80::1 dev eth0  proto kernel  metric 256 
fe80::1 dev eth0  metric 1024 
fe80::/64 dev eth0  proto kernel  metric 256 
default via fe80::1 dev eth0  metric 1024 
```

To allow our container to communicate with the outside world, we have to
enable packet forwarding:

```bash
root@host:/# sysctl -w net.ipv4.conf.all.forwarding=1
net.ipv4.conf.all.forwarding = 1

root@host:/# sysctl -w net.ipv6.conf.all.forwarding=1
net.ipv6.conf.all.forwarding = 1
```

We should now be able to reach other Internet hosts:

```bash
root@bb9b0be2a4d3:/# ping -c 1 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=53 time=9.16 ms

--- 8.8.8.8 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 9.169/9.169/9.169/0.000 ms

root@bb9b0be2a4d3:/# ping6 -c 1 heise.de 
PING heise.de(redirector.heise.de) 56 data bytes
64 bytes from redirector.heise.de: icmp_seq=1 ttl=55 time=5.47 ms

--- heise.de ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 5.472/5.472/5.472/0.000 m
```

## FAQ

### How can I remove a configuration?

Simply stop the container or remove the virtual Ethernet interface:

```bash
ip link del nw-$CONTAINERID

```

All routes etc. will vanish with it.

### Does `narwhal` configure any firewall rules?

No, by default `narwhal` does not touch any firewall rules. These are your
options:

  - Assign public IPv4 or IPv6 addresses, enable IP forwarding and be happy.
    Create filter rules in the `iptables` `FORWARD` chain as you like.
  - Assign private IPv4 or unique local IPv6 addresses and just use them
    to connect your containers with the host or with each other.
    Additionally, you may configure source and/or destination NAT to
    selectively allow communication with the outside world.

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

