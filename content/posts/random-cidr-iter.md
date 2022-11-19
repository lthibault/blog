---
title: "Randomized enumeration of IP addresses in a subnet"
date: 2022-11-18T09:09:10-05:00
draft: false
---

I recently encountered a problem that seemed trivial on the surface, and turned out to be challenging enough to warrant a blog post:

>Given a subnet, iterate through its addresses in pseudorandom order.

### Naive Approach

For small subnets like `10.8.1.0/24`, the naive implementation works well.  We enumerate each address and append it to a list, shuffle the list, and then range over the list.  The first step is the only one I had to stop and think about, but it ended up being quite straightforward.  Here's its implementation in Go, with some extra comments to make it more obvious:

```go
func incrIP(ip net.IP) {
    // Iterate over ip's bytes in reverse order
	for i := len(ip) - 1; i >= 0; i-- {
        // Increment the current byte.  If it wraps around to zero,
        // continue with the next byte, else we're done.
		if ip[i]++; ip[i] > 0 {
			break
		}
	}
}
```

With a `/16` subnet, the list-shuffling approach remains feasible, but starts to feel sloppy.  It requires allocating a 256 KB list.  With `/8`, the size grows to 64 MB.  And if we're dealing with IPv6, that number can grow much larger.

Fortunately, there is a way to iterate through arbitrarily-large subnets with constant memory.  I can't imagine I'm the first to discover this trick, but I confess to having felt a shivver of satisfaction when it clicked into place.  The intuition is simple:  generate a random bitmask and XOR it with the unmasked bits in the subnet.  The essential challenge boils down to some unobvious, albeit insanely satisfying, bit-twiddling.

### A Brief Aside:  XOR

I love XOR; it's my favorite boolean operator.  Even after all these years, it strikes me as quirky when compared to the more pedestrian AND, OR and NOT, yet it seems to turn up *everywhere*, and for good reason!  XOR has algebraic properties that make it arguably *less* quirky and more well-behaved than most of it siblings, and incredibly useful.

It seems unnecessary to introduce a definition of XOR, given its familiarity to most developers, but it can be helpful to check its more interesting properties against a truth-table.  In essence, A ⊕ B is true if **either** A or B is true, but not both.

| A | B | A ⊕ B |
| - | - | ----- |
| 0 | 0 |   0   | 
| 0 | 1 |   1   |
| 1 | 0 |   1   |
| 1 | 1 |   0   |

This naturally extends to bitwise operations on binary integers.  XOR-ing the 8-bit binary integer `0111 1111` with `1111 1110` produces `1000 0001`.  Each bit from the first integer is XORed with the corresponding bit on the second integer to produce the result.

Four properties of XOR deserve special mention.  First, A ⊕ 0 = A, for any A.  This follows from the definition of XOR.  In other words, XOR-ing by zero acts as the **identity property**.

Similarly, A ⊕ 1 = ¬A, for any A.  This also follows from the definition of XOR, and acts as an **inverse property**.

The third property we shall call the **complementary property**.  For any A, B and C, such that A ⊕ B = C, A ⊕ C = B and B ⊕ C = A.

This brings us to the fourth and final notable property:  the **uniqueness property**.  For any A, B, X and Y, if A ⊕ B = C and X ⊕ Y = C, then A = X and B = Y, or A = Y and B = X.  In other words, XOR-ing a pair of 8-bit integers produces an 8-bit integer that is unique to that pair.

>**Proof** (by contradiction).  Let A ⊕ B = C.  By the complementary property, A ⊕ C = B.  Now, suppose there is an X ≠ B such that A ⊕ X = C.  Then, A ⊕ C = X, and we arrive at a contradiction. ⃞

### XOR Bit-Mask Approach

The uniqueness property turns out to be essential, as it provides us with a way of randomizing the enumeration-order of an integer range without resorting to list-construction.  Instead, we can generate a random mask, and then iterate through the integer range in-order, XOR-ing each integer with the mask.

```go
const mask = 0xd3  // random value

for i := 0; i < 256; i++ {
    fmt.Println(i^mask)
}
```

We're now inches away from a solution.  The only wrinkle is that IP subnets are multiple bytes in length, and have a constant prefix that must *not* be modified by the XOR-mask.  In `10.8.1.0/24`, only the last 8 bits should be randomized, for example.

Let's start with an buggy implementation and refine it progressively.  Assume the subnet `10.8.1.0/24`.  The corresponding subnet mask is `255.255.255.0`.

```go
/* BUG.  Modifies the subnet address prefix. */

var subnet = net.IPNet{
    IP:   net.IP{10, 8, 1, 0},
    Mask: IPMask{255, 255, 255, 0},
}

// Create a random mask of the same length as an IPv4 address
mask := make([]byte, 4)
rand.Read(mask)

// Range over subnet IPs
var ip = make([]byte, 4)
for subnet.Contains(subnet.IP) {
    for i, b := range subnet.IP {
        ip[i] = b^mask[i]
    }

    fmt.Println(ip)

    incrIP(subnet.IP)
}
```
If you run this code, you'll observe that the final byte of the printed addresses behaves as expected.  However, the constant prefix will be mangled with near certainty.  To remedy this, we'll need our identity and inverse properties.

```go

var subnet = net.IPNet{
    IP:   net.IP{10, 8, 1, 0},
    Mask: IPMask{255, 255, 255, 0},
}

// Create a random mask of the same length as an IPv4 address
mask := make([]byte, 4)
rand.Read(mask) // let's say this now contains 42.124.33.77

// Get the inverse of the subnet mask.
inverse := make([]byte, 4)
copy(inverse, subnet.Mask)               // contains 255.255.255.0
xor(inverse, []byte{255, 255, 255, 255}) // now contains 0.0.0.255


// Zero-out the 3 leftmost bytes in the random mask, corresponding
// to the original (non-inverted) subnet mask.
xor(mask, inverse)  // mask now contains 0.0.0.77

var ip = make([]byte, 4)
for subnet.Contains(subnet.IP) {
    copy(ip, subnet.IP)
    xor(ip, mask)  // contains 10.8.1.x, where x = 77 ⊕ subnet.IP[3]
    
    fmt.Println(ip)

    incrIP(subnet.IP)
}
```

We define the helper function `xor` as follows:

```go
func xor(x, y []byte) {
    for i := range x {
        x[i] ^= y[i]
    }
}
```

And voila!  You now have pseudorandom iteration through a subnet with O(1) memory usage!  And it's blazing fast, to boot.  Here are some benchmarks for iterating through an entire `/24`, `/16` and `/8`-bit subnet.

```
goos: darwin
goarch: amd64
pkg: github.com/wetware/casm/pkg/boot/crawl
cpu: Intel(R) Core(TM) i7-1068NG7 CPU @ 2.30GHz
BenchmarkCIDR/24-8         	45287678	        24.31 ns/op	       0 B/op	       0 allocs/op
BenchmarkCIDR/16-8         	45160854	        23.83 ns/op	       0 B/op	       0 allocs/op
BenchmarkCIDR/8-8          	27968556	        41.16 ns/op	       0 B/op	       0 allocs/op
```

In fact, at 41.16 ns for 16777216 IPs, it seems _too_ fast.  That's 2.45e-06 *nanoseconds* per IP.  Even with everything in a single cache line, can CPUs even go that fast?  Or perhaps there's some ALU hardware magic going on here?  Ordinarily, I would take a peek at the assembly to see if the compiler is optimizing away the code we're trying to measure, but that's a rabbit hole I'd rather avoid at the moment.

>**Query for the Author:** Are these benchmarks correct?  If so, what accounts for this incredible performance?  Is the ALU involved?  CPU pipelining or vectorization, or some such?

### Conclusion:  Why Bother?

Judging from the lack of relevant libraries on GitHub, it seems the need for randomized IP enumeration is somewhat niche.  As such, a few words on motivation seem like an appropriate way to conclude my first blog post.

[Wetware](https://github.com/wetware/ww) is a minimal cluster environment that makes it easy to write distributed systems and applications.  Wetware is distributed as a single static binary that runs a server process on each host in your cluster.  The server is responsible for joining the cluster, after which it can share resources with other hosts, and export cluster-wide services to applications.

What sets Wetware apart is that it is entirely peer-to-peer.  There are no coordinators, no master nodes, and no central scheduler.  No node is "special", and there is no global cluster state to corrupt or synchronize.  The upshot is that it is incredibly resilient and quite easy to reason about.  For those of us developing Wetware, however, it presents a few challenges. 

One such challenge is "bootstrapping".  When a Wetware server first starts, it must somehow discover the network address of existing peers.  There are several ways of doing this, but a popular one is IP-crawling:  send a UDP packet to a known port for each address in the configured subnet, and wait for a reply.  Simple enough, and quite effective.

But here's the problem:  there's a nasty tendency for hosts to join a cluster in _groups_.  This is because generally speaking, host reboots aren't as independent as we like to think.  Moreover, we like clusters in large part for their horizontal scalability, _i.e._ the ability to quickly add more hardware to meet peak demand.  So we also tend to add hardware in batches.

To make matters worse, host failures and horizontal scaling tend to occur when the system is under load.  If we're not careful, the remedy can quickly become worse than the disease.  The batch of hosts we spun up to alleviate the load can end up flooding an overburdened peer with bootstrap packets, tipping it over the edge.  And when that peer subsequently reboots, it now contributes to the problem to which it just succumbed.  The risk of cascading failures is especially high when each host iterates through subnet IPs in the same order, as the likelihood of concentrated fire increases.

Instead, Wetware hosts iterate through the subnet in pseudorandom order, ensuring that bootstrap packets are spread evenly across the cluster.  Even under critical load, the busiest servers can generally handle an additional UDP packet or two.

There's actually quite a bit more to Wetware's bootstrap procedure, but that's a topic for another post.  I think this is enough for a first post.

Hello, world!
