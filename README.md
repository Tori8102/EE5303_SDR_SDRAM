*Ho Chi Minh City University of Technology - Vietnam National University, Ho Chi Minh City*

*Semester 261, 2026-2027*
# EE5303 Assignment

## SDR SDRAM Controller

<ul>
<li>Supervising lecturer: Truong Quang Vinh</li>
</ul>

## List of participating students
| Name | ID |
| :---- | :----: |
| Nguyen Viet Hoang | 2670164 |
| Nguyen Kim Ngoc Vy | 2670192 |
| Nguyen Ngoc Tri | 2670815 |
| Do Thanh Minh | 2670170 |

## About
Implement a basic SDR SDRAM controller with input signals compliant with AXI and APB connection standards, and output signals following the SDR SDRAM architecture standard.

Below is the system architecture diagram as well as the UVM architecture.
<img width="2452" height="1093" alt="SDR SDRAM Controller-SDR SDRAM Controller Architecture drawio" src="https://github.com/user-attachments/assets/0d05bf28-2c9b-48ad-99ae-966e358ba8a7" />
<img width="2493" height="1853" alt="SDR SDRAM Controller-UVM Architecture drawio" src="https://github.com/user-attachments/assets/85ed8259-0e0d-433c-9b5d-55f41c48f8b4" />

## File structure

<ul>
  <li>intf</li>
  <ul>
    <li>Interfaces: axi_if, apb_if, and sdr_sdram_if</li>
    <li>sdr_bfm_pkg: A package containing tasks and functions used to control the interfaces for each command and specific functionality. This package is used to write testbenches or verification tests in the UVM environment</li>
  </ul>
  <li>rtl</li>
  <ul>
    <li>sdr_ctrl: The top-level module of the SDR SDRAM controller</li>
    <li>sdr_ctrl_core: The core module inside sdr_ctrl, handling the main tasks of the controller</li>
    <li>sdr_sdram_model: A basic SDRAM (memory) model, used only for checking controller operation, testbench validation, or debugging</li>
  </ul>
  <li>tb: Contains testbenches (files with _tb suffix) used to verify RTL functionality</li>
  <li>uvm: Contains all files that implement the UVM architecture for SDR SDRAM verification purposes</li>
  <li>capture: Stores images of important report contents with timestamps</li>
</ul>

## Steps to add files in Vivado

<ul>
  <li>Create a Vivado project and select a suitable part/board with sufficient resources</li>
  <li>Add rtl files to the Design section</li>
  <li>Add files from the intf and tb folders to the Simulation section</li>
  <li>Create a basic constraint file</li>
  Example: create_clock -period 10.000 -name clk [get_ports clk]
  <li>Run simulation, synthesis, or implementation</li>
</ul>
<img width="539" height="765" alt="Screenshot 2026-10-17 084747" src="https://github.com/user-attachments/assets/92a3b85d-d5b2-4738-b6c5-10134d0c80db" />

