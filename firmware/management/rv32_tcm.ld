ENTRY(_start)
MEMORY { TCM (rwx) : ORIGIN = 0x00002000, LENGTH = 0x0000e000 }
SECTIONS {
    .text : { KEEP(*(.text.init)) *(.text*) *(.rodata*) } > TCM
    . = ALIGN(4);
    .data : { *(.data*) } > TCM
    .bss (NOLOAD) : { *(.bss*) *(COMMON) } > TCM
    . = ORIGIN(TCM) + LENGTH(TCM);
    _stack_top = .;
}
