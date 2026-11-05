.PHONY: test lint
lint:
	verilator --lint-only -Wno-fatal --top-module mimo_detector rtl/mimo_detector.sv
test: lint
	mkdir -p build
	verilator --binary --timing -Wno-fatal --top-module metric_tb --Mdir build rtl/mimo_detector.sv tests/metric_tb.sv
	./build/Vmetric_tb
.PHONY: characterize
characterize:
	mkdir -p build/top
	verilator --binary -j 4 --timing -Wno-fatal --top-module diagonal_tb --Mdir build/top rtl/mimo_detector.sv tests/diagonal_tb.sv
	./build/top/Vdiagonal_tb $(ARGS)
