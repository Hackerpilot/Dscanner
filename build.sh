#dmd *.d std/d/*.d -release -inline -noboundscheck -O -w -wi -m64 -property -ofdscanner -L-lsqlite3 #-inline
#dmd *.d std/d/*.d -g -m64 -w -wi -property -ofdscanner -L-lsqlite3 #-unittest
ldc2 -O2 -release *.d std/d/*.d -of=dscanner  -m64
