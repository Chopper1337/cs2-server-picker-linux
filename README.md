# cs2-server-picker-linux
ChatGPT Pasted CS2 server picker for Linux

Running `blocker.sh` will fetch data from the Steam API.

It will list all of the servers by the country short name such as "ams", "sto" etc.

You can then enter the servers you wish to block, for example `lhr ams par fra sto2 vie mad sto waw hel` will block all EU servers.

Enter your password and `iptables` will be used to block the servers.

You can also run `./blocker.sh lhr ams par fra sto2 vie mad sto waw hel`, it will work the same. Idk what it'll do with invalid data :^)

To unblock them, run `unblocker.sh` and it will read the `blocked-ips.txt` file created by `blocker.sh` and undo the changes.
