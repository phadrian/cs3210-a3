nvcc -arch=sm_32 mm-sm.cu -o mm-sm -lcuda -lcudart
nvcc -arch=sm_32 mm-banks.cu -o mm-banks -lcuda -lcudart
