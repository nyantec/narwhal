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
narwhal container ipv4container ipv4host ipv6container ipv6host
```

#### container 

The ID or name of a running Docker container. See `docker ps`.

#### ipv(4|6)container

The IPv(4|6) address assigned to the `eth0` device in the container.

#### ipv(4|6)host

The IPv(4|6) address that the host will be known as to the container. It'll
also be configured as the containers default gateway.

## FAQ

### Does `narwhal` configure `iptables`?

No, but here are your options:

  - Assign public IPv4 or IPv6 addresses, enable IP forwarding and be happy.
    Perform filtering via the `FORWARDING` chain in the filter table as you like.
  - Assign private IPv4 or IPv6 addresses and just use them to connect your
    containers with the host or with each other.
    Additionally, configure source- and/or destination NAT manually.

### What happens if `narwhal` is (incidentially) applied more than once?

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

