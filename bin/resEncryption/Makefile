CXX ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra -pedantic
OPENSSL_CFLAGS ?= $(shell pkg-config --cflags openssl 2>/dev/null)
OPENSSL_LIBS ?= $(shell pkg-config --libs openssl 2>/dev/null || echo -lssl -lcrypto)
NPM ?= npm

ifeq ($(OS),Windows_NT)
  EXE := build/crypto.exe
  RUN := ./build/crypto.exe
else
  EXE := build/crypto
  RUN := ./build/crypto
endif

MANIFEST ?= resources.conf
KEY_RS ?= src-tauri/src/utils/crypto/key.rs
KEY_TMP ?= src-tauri/build_key.tmp

.PHONY: all crypto pack tauri-build clean
all: pack tauri-build

crypto: $(EXE)

$(EXE): tools/crypto.cpp
	mkdir -p build
	$(CXX) $(CXXFLAGS) $(OPENSSL_CFLAGS) $< -o $@ $(OPENSSL_LIBS)

pack: crypto
	$(RUN) --manifest="$(MANIFEST)" --key-out="$(KEY_RS)" --key-tmp="$(KEY_TMP)"

tauri-build:
	$(NPM) run tauri build

tauri-dev:
	$(NPM) run tauri dev

clean:
	rm -rf build
	-rm -f "$(KEY_TMP)" "$(KEY_RS)"
