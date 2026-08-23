$ErrorActionPreference = 'Stop'
& scripts/prepare_coco3_rom.ps1
& 'C:\AMD\2025.2\Vivado\bin\xvhdl.bat' --2008 rtl/cpu09l_128.vhd
if ($LASTEXITCODE) { throw 'xvhdl failed' }
& 'C:\AMD\2025.2\Vivado\bin\xvlog.bat' rtl/core/coco3_128k_ram.v rtl/core/coco3_system_rom.v rtl/core/coco3_boot_machine.v tb/boot_machine_tb.v
if ($LASTEXITCODE) { throw 'xvlog failed' }
& 'C:\AMD\2025.2\Vivado\bin\xelab.bat' boot_machine_tb -s boot_machine_tb_sim
if ($LASTEXITCODE) { throw 'xelab failed' }
& 'C:\AMD\2025.2\Vivado\bin\xsim.bat' boot_machine_tb_sim -runall
if ($LASTEXITCODE) { throw 'xsim failed' }
