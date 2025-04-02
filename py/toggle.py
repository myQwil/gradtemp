#!/usr/bin/env python3

path = '/tmp/gradtemp_state'
on: bool
try:
	with open(path, 'r') as f:
		on = bool(int(f.read()[0]))
except:
	on = True

with open(path, 'w') as f:
	f.write(str(int(not on)))
