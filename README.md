# Verilog Keypad Controller

## Overview

This repository contains the Verilog RTL design for a flexible and robust 8x8 matrix keypad controller. The module is designed to detect key presses, perform switch debouncing, and convert the key's physical location into a corresponding 8-bit ASCII value.

The controller is built around a Finite State Machine (FSM) that operates on a configurable, internal clock tick, making its timing operations independent of the main system clock frequency. This ensures consistent performance for debouncing and scanning across various system speeds.

## Collaborators

* **[Raghav Sadh](https://github.com/Raghav1034)** - Author
* **[Krushnai Karkare](https://github.com/KNKarkare)** - Collaborator

## Features

-   [cite_start]**8x8 Matrix Support**: Interfaces directly with a standard 8x8 keypad matrix. [cite: 328]
-   [cite_start]**Configurable Timing**: Debounce time and clock frequency are runtime adjustable through input ports. [cite: 332]
-   [cite_start]**Stable Internal Tick**: A clock divider generates a stable `keypad_tick_en` signal, decoupling the core logic from the system clock frequency. [cite: 330, 384]
-   [cite_start]**4-State FSM**: A simple and robust FSM (SLEEP, SCAN, DEBOUNCE, STORE) governs the controller's operation. [cite: 436]
-   [cite_start]**Debouncing**: Includes a configurable debounce timer to filter out mechanical switch noise. [cite: 329, 440]
-   [cite_start]**FIFO Interface**: Designed to write key position and ASCII data to external FIFOs, with backpressure support (`fifo_full`). [cite: 329, 481]
-   [cite_start]**ASCII Conversion**: An internal lookup function (ROM) converts the detected row and column into a standard ASCII keycode. [cite: 329, 421]

## FSM States

1.  **`STATE_SLEEP`**: The idle state. [cite_start]It drives all row outputs low to listen for any initial key press. [cite: 248, 415, 438]
2.  [cite_start]**`STATE_SCAN`**: After a press is detected, this state scans each row one-by-one to identify the exact key location. [cite: 417, 439]
3.  [cite_start]**`STATE_DEBOUNCE`**: Once a key is found, this state waits for a set duration to confirm it's a valid, continuous press. [cite: 440]
4.  [cite_start]**`STATE_STORE`**: A transient, one-cycle state that asserts the `fifo_write_enable_o` signal to store the data. [cite: 441]

## How to Use

1.  **Instantiate the Module**: Add the `keypad_controller.v` file to your Verilog project.
2.  **Connect System Interfaces**:
    * [cite_start]`system_clk_i`: Connect your main system clock. [cite: 341]
    * [cite_start]`system_rst_n_i`: Connect an active-low system reset. [cite: 342]
3.  **Configure Timing**:
    * [cite_start]`clk_divider_limit_i`: Set this to `(f_system_clk_hz / 1000) - 1` for a 1ms tick. [cite: 346]
    * [cite_start]`debounce_limit_i`: To achieve a 15ms debounce time with a 1ms tick, set this to `14`. [cite: 529]
    * [cite_start]`scan_timeout_limit_i`: For an 8x8 matrix, set this to `7`. [cite: 591]
4.  **Connect Keypad Matrix**:
    * `keypad_columns_i`: Connect the 8 column inputs from your keypad. [cite_start]These should be pulled high externally. [cite: 351, 352]
    * [cite_start]`keypad_rows_o`: Connect the 8 row outputs to your keypad driver. [cite: 353]
5.  **Connect FIFOs**:
    * [cite_start]The controller is designed to interface with two FIFOs: one for position and one for ASCII data. [cite: 480]
    * [cite_start]Use `fifo_write_enable_o` as the write enable for both FIFOs. [cite: 562]
    * [cite_start]Connect `key_position_data_o` (6 bits) and `key_ascii_data_o` (8 bits) to the data inputs of their respective FIFOs. [cite: 356, 357]
    * [cite_start]Connect the `full` signals from your FIFOs to `position_fifo_full_i` and `keycode_fifo_full_i`. [cite: 358]

## Synthesis

[cite_start]The `ascii_lookup` function is implemented as a combinational case statement and will synthesize into a logic block (ROM), not a memory block. [cite: 434]