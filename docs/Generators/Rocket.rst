Rocket
====================================

`Rocket <https://github.com/freechipsproject/rocket-chip>`__ is a 5-stage in-order scalar core generator that is supported by `SiFive <https://www.sifive.com/>`__.
It supports the open source RV64GC RISC-V instruction set and is written in the Chisel hardware construction language.
It has an MMU that supports page-based virtual memory, a non-blocking data cache, and a front-end with branch prediction.
Branch prediction is configurable and provided by a branch target buffer (BTB), branch history table (BHT), and a return address stack (RAS).
For floating-point,  Rocket  makes  use  of  Berkeley’s  Chisel  implementations  of  floating-point  units.
Rocket also supports the RISC-V machine, supervisor, and user privilege levels.
A number of parameters are exposed, including the optional support of some ISA extensions (M, A, F, D), the number of floating-point pipeline stages, and the cache and TLB sizes.

For more information, please refer to the `GitHub repository <https://github.com/freechipsproject/rocket-chip>`__, `technical report <https://www2.eecs.berkeley.edu/Pubs/TechRpts/2016/EECS-2016-17.html>`__ or to `this Chisel Community Conference video <https://youtu.be/Eko86PGEoDY>`__.
