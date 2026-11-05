.PHONY: test lint
lint:
	verilator --lint-only -Wno-fatal --top-module mimo_detector rtl/mimo_detector.sv
test: lint
	mkdir -p build
	verilator --binary --timing -Wno-fatal --top-module metric_tb --Mdir build rtl/mimo_detector.sv tests/metric_tb.sv
	./build/Vmetric_tb
