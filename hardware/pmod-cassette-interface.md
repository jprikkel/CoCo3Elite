# PMOD cassette interface

## Status and scope

This document proposes a physical cassette interface for CoCo3 Elite. The
recommended implementation uses the
[Digilent Pmod I2S2 stereo audio input/output module](https://digilent.com/shop/pmod-i2s2-stereo-audio-input-and-output/)
on Wukong PMOD **J11**, plus a separately isolated switch for the cassette
recorder's remote-motor connection.

This is a design proposal, not an approved direct-wiring diagram. Do not
connect a cassette recorder, cassette remote lead, or other analog signal
directly to an FPGA pin.

![Digilent Pmod I2S2](https://cdn11.bigcommerce.com/s-7gavg/images/stencil/500x659/products/614/4977/Pmod_I2S2_-_Oblique_-_600__05682.1670982395.png?c=2)

*Product image and specifications: [Digilent Pmod I2S2](https://digilent.com/shop/pmod-i2s2-stereo-audio-input-and-output/).*

## Why use the Pmod I2S2

The Pmod I2S2 combines the two analog directions needed by a physical CoCo
cassette interface:

- A stereo, 24-bit line-level ADC connected to a 3.5 mm input jack.
- A stereo, 24-bit line-level DAC connected to a 3.5 mm output jack.
- I2S digital interfaces for both converters.
- Input sample rates up to 108 kHz.
- A standard 12-pin PMOD connector that can plug directly into J11.
- 3.3 V operation compatible with the Wukong PMOD supply and FPGA I/O.

The cassette path only needs one input and one output channel. The second
channel may carry a duplicate signal or remain muted. A nominal sample rate of
48 kHz is more than sufficient for the CoCo cassette tones.

The I2S2 is preferred over the Digilent Pmod MIC3. MIC3 contains a microphone
and an ADC, but it has no line-input jack and no audio output. The I2S2 can
support both cassette loading and saving without a custom analog ADC or DAC.

## General audio input and output

The Pmod I2S2 should be treated as a full-duplex audio interface rather than a
cassette-only device. Its stereo ADC and DAC can provide normal CoCo line
audio, cassette data, line-input monitoring, and future management-processor
audio capture through the same hardware.

The recommended initial channel assignment is:

| Channel | Normal operation | Cassette operation |
| --- | --- | --- |
| Output left | Final CoCo audio | Final CoCo audio or mute |
| Output right | Final CoCo audio | Raw six-bit cassette DAC waveform |
| Input left | General line input or monitor | Cassette recorder output |
| Input right | Auxiliary input | Duplicate input or diagnostic capture |

The channel mapping must be configurable because many cassette cables and
recorders are mono and may short the left and right contacts of a stereo jack.
Do not assume that split-channel operation is safe with every cable. Cassette
mode should be able to place the cassette waveform on both output channels and
select either input channel.

Recommended Settings OSD output choices are:

- `CoCo audio`: final CoCo sound on both output channels.
- `Cassette`: raw cassette DAC waveform on both output channels.
- `Split`: final CoCo sound on the left and cassette waveform on the right.
- `Monitor`: line input routed to line output with bounded gain.
- `Mixed`: final CoCo sound mixed with the selected line input.
- `Mute`: digital silence on both channels.

Recommended input choices are:

- `Cassette`: selected input channel feeds the zero-crossing detector.
- `Monitor`: selected input channel is available for monitored audio.
- `Capture`: samples are exposed to a bounded management-processor capture
  buffer.
- `Off`: samples are discarded after maintaining I2S clocking.

The cassette motor state can provide a useful automatic mode:

- With the motor off, output normal CoCo audio.
- With the motor on, enable cassette input detection and route the raw cassette
  DAC waveform to the configured cassette output channel or channels.
- Keep the ADC running continuously so enabling the motor does not require the
  codec or clocking to restart.

Manual mode selection must remain available for recorders without remote
motor control and for audio testing. Automatic routing must not reset an I2S
interface or interrupt a sample frame when the motor state changes.

The I2S2 outputs are line-level. They are suitable for a cassette recorder,
powered speakers, an amplifier, or an audio interface, but they must not drive
a passive speaker directly.

The FPGA and management processor can consume full-resolution input samples,
but an original CoCo program only sees the one-bit cassette zero-crossing
signal. General sampled-audio access from 6809 software would be a separate
extension requiring a memory-mapped FIFO, a cartridge-style audio peripheral,
or a DMA interface. That extension is not required for cassette compatibility.

## Original CoCo behavior

The physical CoCo cassette interface consists of:

- A six-bit DAC used to generate the cassette recording waveform.
- An attenuated cassette output of approximately 1 V peak-to-peak into a
  2-kilohm load.
- An input zero-crossing detector that presents a digital cassette-data bit to
  the PIA.
- A cassette motor-control output driving an isolated mechanical switch.
- ROM software that generates and decodes the 1200 Hz and 2400 Hz cassette
  tones. The cassette format is approximately 1500 baud.

The FPGA should reproduce this hardware boundary and leave modulation,
demodulation, block formatting, checksums, and commands such as `CLOAD`,
`CSAVE`, `CLOADM`, and `CSAVEM` to the existing CoCo ROM software.

Reference documentation:

- [Tandy Color Computer 3 Service Manual](https://colorcomputerarchive.com/coco/Documents/Manuals/Hardware/Color%20Computer%203%20Service%20Manual%20%28Tandy%29.pdf)
- [Tandy Color Computer 1 Service Manual cassette-interface description](https://colorcomputerarchive.com/repo/Documents/Manuals/Hardware/Color%20Computer%201%20Service%20Manual%20%2826-3001%20%26%2026-3002%29%20%28Tandy%29.pdf)

## Existing CoCo3 Elite support

Much of the internal CoCo-side behavior already exists:

- PIA1 Port A bits 7 through 2 hold the six-bit DAC value.
- PIA1 control register A bit 3 captures the cassette motor command.
- The audio path already consumes the DAC value for normal CoCo sound.
- Extended Color BASIC contains the original cassette load/save routines.

The missing integration is:

1. Export the raw six-bit PIA1 DAC value independently of the sound mux.
2. Export the cassette motor state.
3. Receive a conditioned cassette-data bit on PIA1 Port A bit 0. That input
   currently behaves as a fixed high level.
4. Add I2S transmit and receive logic.
5. Convert ADC samples into the digital zero-crossing signal expected by the
   PIA.

No modification to third-party CoCo or CPU RTL should be necessary. The
integration belongs in the CoCo3 Elite wrapper and machine I/O logic.

## Proposed J11 allocation

The Pmod I2S2 uses every J11 signal pin. Its upper row is the line-output DAC
interface and its lower row is the line-input ADC interface.

| J11 pin | FPGA pin | Direction | Pmod I2S2 signal | Purpose |
| ---: | --- | --- | --- | --- |
| 1 | H4 | FPGA to Pmod | D/A MCLK | DAC master clock |
| 2 | F4 | FPGA to Pmod | D/A LRCK | DAC left/right word clock |
| 3 | A4 | FPGA to Pmod | D/A SCLK | DAC serial bit clock |
| 4 | A5 | FPGA to Pmod | D/A SDIN | Cassette output sample data |
| 5 | GND | Power | GND | Digital and analog reference |
| 6 | 3.3 V | Power | VCC | Pmod supply; do not use 5 V |
| 7 | J4 | FPGA to Pmod | A/D MCLK | ADC master clock |
| 8 | G4 | FPGA to Pmod | A/D LRCK | ADC left/right word clock |
| 9 | B4 | FPGA to Pmod | A/D SCLK | ADC serial bit clock |
| 10 | B5 | Pmod to FPGA | A/D SDOUT | Cassette input samples |
| 11 | GND | Power | GND | Digital and analog reference |
| 12 | 3.3 V | Power | VCC | Pmod supply; do not use 5 V |

Configure the I2S2 line-input converter for **slave mode** during initial
bring-up. The FPGA should provide coherent MCLK, LRCK, and SCLK signals to both
converters. A dedicated audio-clock generator should produce a codec-supported
clock family; do not assume that an existing video or UART clock is an exact
audio master clock without checking its frequency and timing constraints.

J11 cannot simultaneously host this module and the proposed physical-floppy
interface. Those peripherals must be treated as mutually exclusive unless a
future expansion board supplies additional connectors.

## Cassette motor control

The I2S2 does not provide the dry-contact switch required by a cassette
recorder's remote-motor lead. Use a separate protected GPIO, with **J10 pin 9
(`D6`)** as the initial candidate because it is currently reserved by the
digital-joystick interface.

The GPIO must drive one of the following through a proper driver stage:

1. A small PhotoMOS relay, preferred for silent isolated operation.
2. A mechanical relay with a transistor or MOSFET coil driver and flyback
   diode.
3. An optically isolated solid-state switch rated for the recorder's remote
   circuit.

The recorder remote leads connect only to the isolated switch contacts. They
must not share an unknown motor-control voltage with the FPGA. PMOD power must
not energize a cassette motor or relay coil directly.

Using J10 pin 9 for motor control requires a breakout or combined joystick and
cassette adapter. Confirm that the physical joystick cable leaves this PMOD
pin unused before enabling the FPGA output.

## FPGA signal path

```text
PIA1 Port A bits 7:2
    -> expand six-bit offset-binary value to signed 24-bit PCM
    -> hold/resample at the I2S audio sample rate
    -> duplicate to left/right channels
    -> Pmod I2S2 line output
    -> cassette recorder input

cassette recorder output
    -> Pmod I2S2 line input
    -> signed 24-bit PCM samples
    -> DC-removal/high-pass stage
    -> zero-crossing detector with hysteresis
    -> synchronized digital cassette bit
    -> PIA1 Port A bit 0

PIA1 CRA motor state
    -> protected PMOD GPIO
    -> relay/PhotoMOS driver
    -> isolated cassette remote contacts
```

### Output conversion

The cassette output must use the raw PIA1 DAC code rather than the final HDMI
audio mix. The cassette recorder needs the waveform generated by BASIC even
when that waveform is not routed to the speaker. Expand the six-bit
offset-binary value around its midpoint, scale it conservatively, and saturate
before creating the 24-bit I2S sample.

Begin with a low output level and raise it only after measuring the I2S2 jack
with an oscilloscope or audio interface. The target is approximately the
original CoCo cassette level, not headphone or speaker power.

### Input conversion

The original computer presents a binary zero-crossing result to the PIA, not
an amplitude sample. Reproduce that behavior digitally:

1. Select one ADC channel.
2. Remove the measured DC midpoint with a slow tracking average or simple
   high-pass filter.
3. Apply positive and negative thresholds around zero.
4. Change the PIA input state only when a threshold is crossed.
5. Hold the prior state while the sample remains inside the hysteresis band.

Hysteresis prevents noise near zero from creating extra transitions. The
threshold should be adjustable through constants first and later through the
Settings OSD if real-recording tests show that user adjustment is useful.

The PIA-facing bit must cross into the CoCo clock domain through a two-stage
synchronizer. Do not clock PIA logic directly from an I2S clock.

## Clocking recommendation

Use one coherent audio clock family for ADC and DAC. A 48 kHz-class sample
rate is recommended, with MCLK, SCLK, and LRCK ratios accepted by both I2S2
codecs. Generate the clock with an FPGA MMCM/PLL output or a verified integer
clock plan and add explicit timing constraints.

The cassette format's highest fundamental tone is only 2400 Hz, so 48 kHz
provides ample samples per cycle. Higher sample rates add processing and
serial-clock activity without improving ROM compatibility.

## Serial diagnostics

Add on-demand cassette fields to the existing serial API. Continuous traces
must remain disabled by default so diagnostics cannot perturb timing.

Recommended snapshot fields:

- `CAS_MOTOR`: current PIA motor-command state.
- `CAS_DAC`: current six-bit cassette output code.
- `CAS_ADC`: latest signed or centered ADC sample.
- `CAS_MIN` and `CAS_MAX`: sample range since the previous snapshot.
- `CAS_ZERO`: current zero-crossing detector output.
- `CAS_EDGES`: transitions counted during a fixed measurement interval.
- `CAS_HZ`: estimated input tone frequency when stable.
- ADC overflow, clipping, missing-clock, and no-signal flags.
- Current input channel, output mode, motor-auto-routing state, and monitor
  gain.

These values should also be available to automated serial tests. Do not stream
raw 48 kHz audio through the ordinary debug log. A future explicit capture
command may transfer a short bounded sample block if waveform analysis is
needed.

## Implementation stages

### Stage 1: digital I2S loopback

1. Add the J11 constraints with safe reset values.
2. Generate the audio clocks and transmit digital silence.
3. Verify LRCK, SCLK, MCLK, and SDIN with simulation and a logic analyzer.
4. Receive ADC samples and report bounded min/max values over serial.
5. Connect line output to line input and verify a generated 1200/2400 Hz test
   waveform without involving the CoCo CPU.

### Stage 2: cassette playback into the CoCo

1. Implement DC removal, hysteresis, and the zero-crossing detector.
2. Feed the result into PIA1 Port A bit 0.
3. Test `CLOAD` and `CLOADM` from a known-good audio recording.
4. Compare detected edge periods against software-generated fixtures.
5. Tune thresholds while keeping fixed, documented defaults.

### Stage 3: cassette recording from the CoCo

1. Route the raw six-bit PIA DAC code into the I2S transmitter.
2. Verify 1200 Hz and 2400 Hz output frequency and amplitude.
3. Record `CSAVE` and `CSAVEM` output with a PC audio interface first.
4. Load the resulting recording in an emulator or known-good CoCo.
5. Test a physical recorder only after the line level is verified.

### Stage 4: isolated motor control

1. Verify the selected GPIO remains inactive during FPGA configuration and
   reset.
2. Test the relay or PhotoMOS using a meter before attaching a recorder.
3. Confirm that BASIC turns the contact on and off at the expected times.
4. Add timeout and reset behavior that always releases the motor contact.

## Verification plan

Automated simulation should cover:

- I2S frame alignment, left/right selection, and 24-bit sample ordering.
- Six-bit DAC expansion, midpoint, saturation, and output hold behavior.
- Positive and negative input crossings with noise inside the hysteresis band.
- PIA1 Port A bit 0 reads for input-high and input-low states.
- Motor control writes and reset-to-off behavior.
- Clock-domain synchronization and reset recovery.

Hardware validation should use:

- I2S loopback before connecting a cassette recorder.
- Known 1200 Hz and 2400 Hz WAV fixtures played from a PC.
- Oscilloscope or audio-interface measurements of line-output amplitude.
- A known-good `CLOAD`/`CSAVE` program with checksum verification.
- Repeated reset and Ctrl-Esc tests confirming that the motor contact releases.

## Resource and schedule estimate

The I2S serializer, receiver, sample registers, high-pass/threshold logic, and
PIA wiring should require little FPGA memory and a modest amount of logic. No
large BRAM or SDRAM allocation is expected.

Estimated engineering effort after the module and cables are available:

- I2S input/output controller and PIA integration: one to two days.
- Digital thresholding, simulation, and serial diagnostics: approximately one
  day.
- Real cassette level adjustment and compatibility testing: one to two days.
- Isolated motor-switch prototype: straightforward hardware work, followed by
  safety and reset testing.

Overall, this is a medium-sized peripheral feature and should be substantially
simpler than SD-card filesystem or floppy-controller development.

## Future extensions

Once the physical path is stable, the same sample interface could support:

- Short serial waveform captures for debugging.
- WAV playback and recording through the management processor.
- `.CAS` file mounting through firmware, using the same PIA-facing data bit.
- High-quality CoCo line audio independent of HDMI.
- Full-duplex line-input monitoring and bounded mixing with CoCo audio.
- A memory-mapped sample FIFO or cartridge-style digital-audio peripheral for
  new 6809 software.
- Cassette input monitoring through HDMI audio when explicitly enabled.
- Adjustable input channel, threshold, output routing, output level, and
  monitor gain in the Settings OSD.

Virtual `.CAS` and WAV support should remain separate from the initial
physical-interface milestone. First validate the real PIA, DAC, zero-crossing,
and motor behavior with the original ROM routines.
