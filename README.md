narwhal - A docker network configuration tool
=============================================

## What does `narwhal` do?

`narwhal` sets up a networking namespace (an exclusive instance of the whole
Linux networking stack with own arp, routing and netfilter etc), creates a
virtual ethernet device pair (with one end in the container and the other end
on the host system) and assigns static IPv4 and IPv6 addresses with the
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
all containers to talk to each other via layer 2 protocols (i.e. arp). Read 
[here](https://nyantec.com/en/2015/03/20/docker-networking-considered-harmful)
why this is extremely dangerous. It completely undermines the carefully crafted
container isolation based on networking namespaces.

The solution proposed by `narwhal` is to just have a virtual ethernet device
and networking namespace per container and to just only IPv4 and IPv6 (layer 3)
routing between containers and the outside world.

It is common knownledge to most operators how to work with 
[iptables](http://www.netfilter.org/projects/iptables/) and 
[ip6tables](http://ipset.netfilter.org/ip6tables.man.html), but how many have
ever heard of [ebtables](http://ebtables.netfilter.org/)? ;-)

## How do I use it?

```bash
narwhal container ipv4address ipv4gateway ipv6address ipv6gateway
```

### What happens on container termination?

The containers' networking namespace and the virtual ethernet pair are destroyed
automatically.



