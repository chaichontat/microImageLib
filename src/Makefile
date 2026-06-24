
# ** set environment for CUDA, libtiff and fftw libraries if necessary
# export PATH=$PATH:/usr/local/cuda/bin
# export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/lib:/usr/lib/x86_64-linux-gnu

CUDA_ROOT = /usr/local/cuda

ifeq ($(CUDA_ROOT),)
  $(error Cannot find CUDA_ROOT)
endif

CUDA_TARGET_DIR = $(CUDA_ROOT)/targets/x86_64-linux
CUDA_INC_DIR = $(CUDA_ROOT)/include
CUDA_LIB_FLAG = -L$(CUDA_ROOT)/lib64
CUDA_INC_DIR += -I$(CUDA_TARGET_DIR)/include
CUDA_LIB_FLAG += -L$(CUDA_TARGET_DIR)/lib
CONDA_PREFIX ?= $(shell python3 -c 'import os; print(os.environ.get("CONDA_PREFIX", ""))' 2>/dev/null)
NVIDIA_CUFFT_DIR ?=
ifneq ($(CONDA_PREFIX),)
NVIDIA_CUFFT_DIR ?= $(firstword $(wildcard $(CONDA_PREFIX)/lib/python*/site-packages/nvidia/cufft))
CUDA_LIB_FLAG += -L$(CONDA_PREFIX)/lib
endif
ifneq ($(NVIDIA_CUFFT_DIR),)
CUDA_INC_DIR += -I$(NVIDIA_CUFFT_DIR)/include
CUDA_LIB_FLAG += -L$(NVIDIA_CUFFT_DIR)/lib
endif
NVCC = $(CUDA_ROOT)/bin/nvcc -g -std=c++11 

CUFFT_LIB ?= $(firstword \
  $(wildcard $(CUDA_TARGET_DIR)/lib/libcufft.so) \
  $(wildcard $(CUDA_TARGET_DIR)/lib/libcufft.so.*) \
  $(wildcard $(CONDA_PREFIX)/lib/libcufft.so) \
  $(wildcard $(CONDA_PREFIX)/lib/libcufft.so.*) \
  $(wildcard $(NVIDIA_CUFFT_DIR)/lib/libcufft.so) \
  $(wildcard $(NVIDIA_CUFFT_DIR)/lib/libcufft.so.*))
FFTW3F_LIB ?= $(firstword \
  $(wildcard $(CONDA_PREFIX)/lib/libfftw3f.so) \
  $(wildcard $(CONDA_PREFIX)/lib/libfftw3f.so.*) \
  $(wildcard /usr/lib/x86_64-linux-gnu/libfftw3f.so) \
  $(wildcard /usr/lib/x86_64-linux-gnu/libfftw3f.so.*))
CUFFT_LDLIB = $(if $(CUFFT_LIB),-L$(dir $(CUFFT_LIB)) -l:$(notdir $(CUFFT_LIB)),-lcufft)
FFTW3F_LDLIB = $(if $(FFTW3F_LIB),-L$(dir $(FFTW3F_LIB)) -l:$(notdir $(FFTW3F_LIB)),-lfftw3f)

INC_DIR = ../include
DEP_INC_DIR = ../lib
BIN_DIR = ../bin/linux

CXXFLAGS  = -Wall -std=c++11 -O2  -fPIC
CXXFLAGS += -I$(CUDA_INC_DIR) -I$(INC_DIR) -I$(DEP_INC_DIR) -I$(BIN_DIR)

NVFLAGS = -Xptxas -v,-dlcm=cg 
NVFLAGS += -ftz=true --compiler-options '-fPIC' --compiler-options="-O2" -I$(CUDA_ROOT)/include -I$(CUDA_TARGET_DIR)/include $(if $(NVIDIA_CUFFT_DIR),-I$(NVIDIA_CUFFT_DIR)/include) -I$(INC_DIR) -I$(DEP_INC_DIR)
LDFLAGS = $(CUDA_LIB_FLAG) $(NVFLAGS)

LDLIBS = -ltiff -lcudart $(CUFFT_LDLIB) $(FFTW3F_LDLIB)


%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $^ -o $@ 

%.o: %.c
	$(CC) $(CXXFLAGS) -c $^ -o $@ 

%.o: %.cu
	$(NVCC)  -c $^ $(LDFLAGS) $(LDLIBS)

all: libapi.so

libapi.so: api_reg.o api_decon.o api_powell.o api_subfunc.o apifunc.o
	$(CC) -o $(BIN_DIR)/$@ $^  -shared -Wl,-soname,$@ $(CUDA_LIB_FLAG) $(LDLIBS)

all: checkGPUDevice reg3D deconSingleView deconDualView spimFusion spimFusionBatch

checkGPUDevice: check_gpu.o api_reg.o api_decon.o api_powell.o api_subfunc.o apifunc.o
	$(NVCC) -o $(BIN_DIR)/$@ $^ $(CUDA_LIB_FLAG) $(LDLIBS)

reg3D: reg3D.o api_reg.o api_decon.o api_powell.o api_subfunc.o apifunc.o
	$(NVCC) -o $(BIN_DIR)/$@ $^ $(CUDA_LIB_FLAG) $(LDLIBS)

deconSingleView: decon_sv.o api_reg.o api_decon.o api_powell.o api_subfunc.o apifunc.o
	$(NVCC) -o $(BIN_DIR)/$@ $^ $(CUDA_LIB_FLAG) $(LDLIBS)

deconDualView: decon_dv.o api_reg.o api_decon.o api_powell.o api_subfunc.o apifunc.o
	$(NVCC) -o $(BIN_DIR)/$@ $^ $(CUDA_LIB_FLAG) $(LDLIBS)

spimFusion: spim_fusion.o api_reg.o api_decon.o api_powell.o api_subfunc.o apifunc.o
	$(NVCC) -o $(BIN_DIR)/$@ $^ $(CUDA_LIB_FLAG) $(LDLIBS)

spimFusionBatch: spim_fusion_batch.o api_reg.o api_decon.o api_powell.o api_subfunc.o apifunc.o
	$(NVCC) -o $(BIN_DIR)/$@ $^ $(CUDA_LIB_FLAG) $(LDLIBS)


clean:
	$(RM) *.o *.so

cleanAll:
	$(RM) *.o *.so $(BIN_DIR)/*
