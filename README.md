# FPGA PILbox (TinyFPGA BX)

This project is an FPGA-based implementation of a **PILbox** (HP-IL to USB/Serial adapter) designed to run on the [TinyFPGA BX](https://tinyfpga.com/bx/guide.html) development board.

A PILbox allows vintage HP-IL (Hewlett-Packard Interface Loop) hardware, such as the HP-41C and HP-71B calculators, to communicate with modern software like [pyILper](https://github.com/bug400/pyilper) over a standard serial interface.

## Features

- **Native 16MHz Operation**: Designed around the ICE40LP8K's 16MHz clock to accurately sample 1µs and 2µs HP-IL pulses.
- **High-Speed Serial**: Communicates at **230400 baud** for fast data transfer.
- **Hardware Protocol State Machine**: Translates between 11-bit HP-IL frames and the PILbox 2-byte serial format completely in hardware.
- **Intelligent IDY Auto-Forwarding**: Automatically re-transmits HP-IL Identify (IDY) polling frames without sending them over the UART to prevent serial link saturation.
- **pyILper Compatibility**: Fully intercepts and acknowledges `COFF` (0x497), `COFI` (0x495), and `TDIS` (0x494) initialization commands. Supports toggling the auto-forwarding feature via `COFI`.

## Architecture

The project consists of three main modules:
1. **`hpil_link_layer.v`**: The physical layer responsible for interpreting window comparator states into digital signals and driving the direct pulse transformer for transmission.
2. **`uart.v`**: A lightweight RS-232 style UART transmitter and receiver running at 230400 baud.
3. **`pilbox_protocol.v`**: The core state machine that buffers bytes, inspects frame types (CMD, RFC, IDY, DATA), performs auto-forwarding, and handles pyILper commands.

## Pinout

You will need an external USB-to-Serial adapter (like an FT232 or CH340) and an analog HP-IL front-end (using pulse transformers and window comparators).

| TinyFPGA BX Pin | Function | Description |
| --- | --- | --- |
| **Pin 1 (A2)** | `UART RX` | Connect to the **TX** pin of your USB-Serial Adapter |
| **Pin 2 (A1)** | `UART TX` | Connect to the **RX** pin of your USB-Serial Adapter |
| **Pin 3 (B1)** | `HPIL RX_P` | Incoming positive pulse from Window Comparator |
| **Pin 4 (C2)** | `HPIL RX_N` | Incoming negative pulse from Window Comparator |
| **Pin 5 (C1)** | `HPIL TX_P` | Outgoing positive pulse to Direct Drive |
| **Pin 6 (D2)** | `HPIL TX_N` | Outgoing negative pulse to Direct Drive |
| **Pin B3** | `LED` | Onboard LED (flashes on UART RX activity) |

*Note: Ensure your analog front-end levels do not exceed the TinyFPGA BX's 3.3V IO tolerance.*

## Building and Flashing

This project is built using the open-source [Apio](https://github.com/FPGAwars/apio) toolchain.

1. Ensure you have Apio installed (`pip install apio`).
2. Run the build command to synthesize the bitstream:
   ```bash
   apio build
   ```
3. Connect your TinyFPGA BX via USB, put it into bootloader mode (press the reset button), and upload:
   ```bash
   apio upload
   ```

## Usage

Once flashed, connect your USB-to-Serial adapter and your HP-IL hardware. Launch `pyILper` on your PC, point it to the COM port of your serial adapter, set the baud rate to **230400**, and pyILper will automatically initialize the PILbox and start communicating with the loop!

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
