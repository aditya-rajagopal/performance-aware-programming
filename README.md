# performance-aware-programming

Casey Muratori's performance aware programming course. This project is an exploaration of the concepts of how the computer works and what are the things that affect performance.

This is written in zig 0.14 in [zig](https://ziglang.org/download) and it needs to be downloaded to compile the project.

```
>> zig build --help
  haversine_data_gen           Generate haversine data
  parser                       Parse haversine data
  file_read_test               Repetition testing of file read
  page_file_test               Test page fault rates for touching data
  write_bytes_test             Test writing to a newly allocated buffer forward and backward
  paging                       Four level paging test
  asm_loop                     Test comparing writing bytes using different ASM loops to see througput
  test                         Run unit tests
```

Contents:
- 8086 Simulator
- File read and write tests to understand pagefault behaviours
- rdtsc based timers
- `zig build page_fault_test -- 32 forward` will run a test and calculate how many pagefaults we achieve when touching new pages in sequence forward and backward
- A fast JSON parser to understand where the performance bottlnecks arise when parsing such large files
    - Store and parse haversine distances as a test
    - Takes about 2.7 seconds to parse a 1GB json file into an in memory format that can be queried for data.
    First generate a 1GB JSON file with haversine distances. This will generate data_100000000_clustered.json in the root folder.
    as well as a binary file with results of distances.
    ```
    >> zig build haversine_data_gen -- clustered 12 10000000

    ```

    Then run the following to parse the json file:
    
    ```
    >>> zig build parser -Doptimize=ReleaseFast -- file .\data_10000000_clustered.json .\data_10000000_clustered_data.bin
    Parsed JSON haversine result: 5030.866415797186
    Cached JSON haversine result: 5030.866415798264
    Average difference: 0
    Number of points with different distances: 0
    Total time: 2758.398563 (CPU freq 2995259440)
            init[1]
                    0.019204 ms (0.00%)     0.019204 ms/hit
            file_read[1]
                    42.238747 ms (1.53%)    42.238747 ms/hit
                    Throughput: 76.29MB (1.76 GB/s)
            json_parse_read_file[13850]
                    208.563067 ms (7.56%)   0.015059 ms/hit
                    Throughput: 1731.25MB (8.11 GB/s)
            json_parse[1]
                    1982.285927 ms (71.86%) 1982.285927 ms/hit
                    ( 2190.848995 ms (79.42%) with children)
                    Throughput: 937.56MB (0.46 GB/s)
            query[1]
                    0.000319 ms (0.00%)     0.000319 ms/hit
            haversine_lookup[1]
                    312.005806 ms (11.31%)  312.005806 ms/hit
            haversine_parse[1]
                    212.906066 ms (7.72%)   212.906066 ms/hit
                    Throughput: 305.18MB (1.40 GB/s)
    Size of JSON file: 937.560 Mb
    Size of JSON storage: 1039.505 Mb
    ```

# 8086 Simulator

For the purpose of understanding assembly. I built a simulator that is capable of 
- Disassembling most 8086 ASM bytecode
- Running 8086 bytecode in a VM and printing the changes in registers and the final state of registers.

This simulator matches the actual 8086 functioning as closely as possible.

NOTE: not all instructions are implemented as this is not meant to be a fully functioning 8086 emulator. But most basic 
functionality has been implemented.

Build the simulator with 

```
zig build sim

Usage:
 sim8086 [options]

      -h, --help                  print usage
      -v, --verbose <?path>       Enable printing of each instruction and change in register states
      -md, --mem_dump <?path>     Dump memory to std out
      -d, --disassemble <path>    file you want to disassemble
      -s, --sim <path>            Takes a binary file and simulates an Intel 8086 running the provided bytecode
                                  stream. Outputs the change in register states as the instructions are processed
                                  and then the final register states.
      -o, --output <?path>        location to store the disassembled result or the output of the simulator
                                  or empty path to store it in the same location with a prefix sim8086
```

example usages:

```
>> zig build sim -- -s .\src\listings\listing_0039_more_movs -v

mov si, bx ;  ip: 0x0000->0x0002
mov dh, al ;  ip: 0x0002->0x0004
mov cl, 12 ; cx: 0x0000->0x000c ip: 0x0004->0x0006
mov ch, 244 ; cx: 0x000c->0xf40c ip: 0x0006->0x0008
mov cx, 12 ; cx: 0xf40c->0x000c ip: 0x0008->0x000b
mov cx, 65524 ; cx: 0x000c->0xfff4 ip: 0x000b->0x000e
mov dx, 3948 ; dx: 0x0000->0x0f6c ip: 0x000e->0x0011
mov dx, 61588 ; dx: 0x0f6c->0xf094 ip: 0x0011->0x0014
mov al, [bx + si] ; ax: 0x0000->0x0089 ip: 0x0014->0x0016
mov bx, [bp + di] ; bx: 0x0000->0xde89 ip: 0x0016->0x0018
mov dx, [bp] ; dx: 0xf094->0xde89 ip: 0x0018->0x001b
mov ah, [bx + si + 4] ;  ip: 0x001b->0x001e
mov al, [bx + si + 4999] ; ax: 0x0089->0x0000 ip: 0x001e->0x0022
mov word [bx + di], cx ;  ip: 0x0022->0x0024
mov byte [bp + si], cl ;  ip: 0x0024->0x0026
mov byte [bp], ch ;  ip: 0x0026->0x0029

Final State:
        cx: 0xfff4 (65524)
        dx: 0xde89 (56969)
        bx: 0xde89 (56969)
        ip: 0x0029 (41)
  flags:
```

You can invoke the disassembly with

```
> zig build sim -- -d .\src\listings\listing_0039_more_movs -v
Bytecode:
        10001001 11011110 10001000 11000110 10110001
        00001100 10110101 11110100 10111001 00001100
        00000000 10111001 11110100 11111111 10111010
        01101100 00001111 10111010 10010100 11110000
        10001010 00000000 10001011 00011011 10001011
        01010110 00000000 10001010 01100000 00000100
        10001010 10000000 10000111 00010011 10001001
        00001001 10001000 00001010 10001000 01101110
        00000000
bits 16

mov si, bx
mov dh, al
mov cl, 12
mov ch, 244
mov cx, 12
mov cx, 65524
mov dx, 3948
mov dx, 61588
mov al, [bx + si]
mov bx, [bp + di]
mov dx, [bp]
mov ah, [bx + si + 4]
mov al, [bx + si + 4999]
mov word [bx + di], cx
mov byte [bp + si], cl
mov byte [bp], ch
```
