# Security

PICT input is hostile input. New parsing and rendering code must use checked
arithmetic, resource limits, bounded opcode readers, and structured operational
errors. Embedded QuickTime images are passed to `jpeglib` only within the
configured embedded-image byte and pixel limits.

Please report security issues privately to the maintainer, at the address
`alire.toml` lists under `maintainers`, before public disclosure.
