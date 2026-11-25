# C runtime build.
#   make          build build/kvllm
#   make test     build and run the self-test
#   make clean
#
# Builds natively on the board (aarch64 Ubuntu) or on a dev machine.
# -O3 -march=native matters on the A53: it enables NEON auto-vectorization.

CC      ?= gcc
CFLAGS  ?= -O3 -march=native -Wall -Wextra -std=c11
LDLIBS  := -lm

BUILD   := build
SRCS    := src/main.c src/matvec.c net/net.c
OBJS    := $(SRCS:%.c=$(BUILD)/%.o)
TARGET  := $(BUILD)/kvllm

.PHONY: all test clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -Isrc -Inet -c $< -o $@

test: $(TARGET)
	./$(TARGET)

clean:
	rm -rf $(BUILD)
