# X post

## Main post (with the video, 277 characters)

OpenAI's proof that Navier–Stokes blows up in finite time, rendered on a
Super Nintendo.

The SNES is drawing this, not playing a video of it: filled 3D polygons on the
Super FX 2, the Star Fox chip.

Open source, runs in your browser:
github.com/keithadler/superfx-navier-stokes

[attach: superfx-navier-stokes.mp4]

## Reply 1 (with the three images, 279 characters)

What you're seeing: a vortex core collapsing in the paper's own similarity
variables. Radius shrinks like √τ, the swirl speeds up, energy stays bounded.
The rings are the oscillatory pulses in the annulus that grow on the shear,
then die to viscosity.

[attach: 1-cart.png, 2-vortex.png, 3-collapse.png]

## Reply 2 (271 characters)

The cart is a GSU-2: 21.4 MHz, 2 MB ROM, 128 KB RAM, the largest the chip can
address.

Per frame it fills ~170 back-face-culled triangles, 6 streamlines, 256
particles and the pulse rings into cart RAM, double buffered, DMA'd to VRAM in
5 VBlank chunks. 12 fps.

## Reply 3 (272 characters)

Written from scratch: the 65816 side, a Super FX assembler in Python, the
polygon renderer, the tables.

Caveat: the exponents and scalings are the paper's. Its profile functions are
numerical, so these are stand-ins matching at the axis and far field.

## Alt text for the images

1-cart.png: A SNES screen titled SUPER FX 2 DEV CART listing hardware read at
runtime: 65816 CPU at 2.68 MHz, GSU-2 at 21.4 MHz, 2048K LoROM in 64 banks,
128K cartridge RAM tested OK, 256x224 NTSC, with a wireframe cube drawn by the
Super FX chip below.

2-vortex.png: A shaded three-dimensional vortex rendered in teal on a dark blue
SNES screen, ringed by magenta, orange and yellow loops. Readout: TAU 0.93941,
core radius 0.969, max speed x1.02.

3-collapse.png: The same vortex much later and much smaller, the coloured rings
drawn in tight around it. Readout: TAU 0.16843, core radius 0.410, max speed
x2.47, energy x0.428.
