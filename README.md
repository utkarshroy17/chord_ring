# COP 5615 - Project 3
Program to implement Chord protocol

## Team members
  - Anand Chinnappan Mani,  UFID: 7399-9125
  - Utkarsh Roy,            UFID: 9109-6657

## What is working 
 - num_nodes GenServers are created. The pids of these nodes are hashed using sha-1 and encoded to hexadecimal. (This resultant hashcode is 160 bits long and is encoded to a 40 character long hexadecimal string).
 - A stable chord is initiialized along with the finger-table of each node. There are m = 160 entries in each finger-table.
 - After initialization, each node generates a random hashcode and requests find_successor(hashcode) every second upto #num_request times. 
 - A recursive implementation of find_successor has been implemented as mentioned in Section V.A of the paper.
 - A node converges (stops performing requests) once it has completed #num_request requests and informs the daemon the average number of hops each request took. Once all nodes have converged, we output average hops per request across all nodes.


## Largest working problems 
![N|Solid](https://i.imgur.com/77Vzjr1.png)

Notice that the chord protocol gaurantees a worst case of log2(num_nodes). 
Thereby, the num_hops can have values between 0 to log2(num_nodes). 
We can observe from the table that the average_hops sit in the middle of the stated range.

_Trial with num_nodes = 10,000 took ~30 mins to converge. Trials with num_nodes > 10,000 would take too long to converge, should they converge and thereby could not be documented_

## Instructions
Move to project working directory
```
  iex -S mix
  Three.start num_nodes, num_requests
```

Sample Input:
```
  iex -S mix 
  Three.start 1000, 10
```
Sample Output:
```
  Creating chord...
  .
  .
  #PID<0.164.0>
  has started requesting
  #PID<0.195.0>
  has started requesting
  #PID<0.159.0>
  has started requesting
  .
  .
  Node has converged with average hops = 2.8
  Node has converged with average hops = 2.7
  Average hops across all nodes in chord 3.162999999999999
  ** (EXIT from #PID<0.140.0>) shell process exited with reason: "All nodes have converged"
```

