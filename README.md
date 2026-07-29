# cs2-server-picker-linux

CS2 server picker for Linux

Fetches data from the Steam API and blocks/unblocks matchmaking server addresses using `iptables`.

## Usage

### List all available servers

To list all available matchmaking servers:

```
./server-picker.sh --list-servers
```

Once a ping cache exists (see [Cache server pings](#cache-server-pings)), the list
is shown as a table sorted by latency, with each server's cached average ping and
friendly location name:

```
SERVER   PING(ms)  LOCATION
------   --------  --------
par      26        Paris (France)
fra      34        Frankfurt (Germany)
sto2     41        Stockholm - Bromma (Sweden)
...
```

### List blocked servers

To list of all currently blocked matchmaking servers:

```
./server-picker.sh --list-blocked
```

### Block servers

To block matchmaking servers, provide their identifiers as arguments to the `--block` or `-b` option:

```
./server-picker.sh --block <mm1> <mm2> ...
```

For example, to block European servers:

```
./server-picker.sh --block lhr ams ams4 par fra sto2 vie mad sto waw hel
```

### Cache server pings

To measure and cache the average ping to every server, run:

```
./server-picker.sh --update-cache
```

This pings every relay of every datacenter in parallel and stores the lowest
average ping per server in `~/.cache/cs2-server-picker/pings.csv` (one
`server,avg` line each, e.g. `ams,23`). The cache is reused by `--list-servers`
and by the ping-based blocking options below.

Note: some datacenters (currently the China pops) do not respond to ICMP and are
omitted from the cache.

### Block servers by ping

To block every cached server whose average ping is **above** a threshold (in ms):

```
./server-picker.sh --block-over 100
```

To block every cached server whose average ping is **below** a threshold (in ms):

```
./server-picker.sh --block-under 30
```

If no cache exists yet, one is built automatically before blocking. Servers with
no cached ping (those that don't respond to ICMP) are never blocked by these
options; block them explicitly with `--block` if needed.

### Unblock servers

To unblock all previously blocked matchmaking servers:

```
./server-picker.sh --unblock
```

### Check ping to servers

1. Start CS2
2. Enable the developer console in settings if not already enabled
2. Queue for a match (This will allow the client to fetch server data and perform pings)
3. Open the developer console and wait for the datacenter ping information to appear (this should only take a few seconds)
4. Cancel the match search

The console should display ping information similar to the following:

```
Obtained direct RTT measurements to relays in 40 POPs.  Closest 15 are:
  jfk: 79ms
  atl: 101ms
  ord: 104ms
  iad: 115ms
  bom2: 141ms
  lax: 141ms
  bom: 146ms
  dfw: 147ms
  sea: 155ms
  maa2: 161ms
  maa: 168ms
  hkg: 183ms
  jnb: 187ms
  sgp: 190ms
  lim: 191ms
Confirmed best official datacenter ping: 101 ms
```

### Notes

For whatever reason, https://github.com/Jyben/csgo-mm-server-picker no longer works for me and I am not bothered to fix it. These scripts achieve the same result anyway.
