VERILATOR ?= verilator
PYTHON ?= python3
OCTAVE ?= octave
NODE ?= node
RTL = rtl/mimo_detector.sv
VFLAGS = --binary -j 4 --timing -Wno-fatal

.PHONY: test lint rtl-test stream-test characterize archive-test model-test web-test
test: model-test rtl-test web-test

lint:
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -Wno-fatal --top-module mimo_detector $(RTL)

rtl-test: lint characterize stream-test

# This remains the normal entry point for the original identity-channel test.
characterize:
	mkdir -p build/diagonal
	$(VERILATOR) $(VFLAGS) --Mdir build/diagonal --top-module diagonal_tb $(RTL) tests/diagonal_tb.sv
	./build/diagonal/Vdiagonal_tb

stream-test:
	mkdir -p build/stream
	$(PYTHON) tests/stream_vectors.py build/stream.txt $(if $(wildcard build/matlab-vectors.txt),--matlab build/matlab-vectors.txt)
	$(VERILATOR) $(VFLAGS) --Mdir build/stream --top-module stream_tb $(RTL) tests/stream_tb.sv
	./build/stream/Vstream_tb +vectors=build/stream.txt

model-test:
	mkdir -p build
	$(OCTAVE) --no-gui --quiet --eval "addpath('model'); test_model; generate_vectors('build/matlab-vectors.txt');"

web-test:
	$(NODE) --test tests/search.test.mjs

archive-test:
	mkdir -p build/archive-top build/archive-metric
	$(VERILATOR) $(VFLAGS) --Mdir build/archive-top --top-module diagonal_tb rtl/archive/mimo_detector.sv tests/diagonal_tb.sv
	./build/archive-top/Vdiagonal_tb +archive
	$(VERILATOR) $(VFLAGS) --Mdir build/archive-metric --top-module metric_tb rtl/archive/mimo_detector.sv tests/metric_tb.sv
	./build/archive-metric/Vmetric_tb
