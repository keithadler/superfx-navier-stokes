#!/usr/bin/env python3
"""Tiny Super FX (GSU) assembler.

usage: gsuasm.py in.gsu out.bin out.inc
Syntax: one instruction per line, ';' comments, 'label:', 'NAME = expr', '.org expr',
'.db'/'.dw' data. Registers r0-r15, immediates '#expr', memory '(rN)' or '(expr)'.
Branches and jumps have a delay slot: the instruction after them always executes.
"""
import re, sys

def parse_num(tok, syms):
    tok = tok.strip()
    return eval(re.sub(r'\$([0-9A-Fa-f]+)', lambda m: str(int(m.group(1), 16)), tok), {}, dict(syms))

def reg(tok):
    m = re.fullmatch(r'r(\d+)', tok.strip().lower())
    if not m or not 0 <= int(m.group(1)) <= 15:
        raise ValueError(f'bad register {tok!r}')
    return int(m.group(1))

def split_args(s):
    return [a.strip() for a in re.split(r',(?![^(]*\))', s)] if s.strip() else []

ALT1, ALT2, ALT3 = 0x3D, 0x3E, 0x3F
BRANCHES = {'bra':5,'bge':6,'blt':7,'bne':8,'beq':9,'bpl':10,'bmi':11,'bcc':12,'bcs':13,'bvc':14,'bvs':15}
SIMPLE = {'stop':[0],'nop':[1],'cache':[2],'lsr':[3],'rol':[4],'loop':[0x3C],'plot':[0x4C],
          'rpix':[ALT1,0x4C],'swap':[0x4D],'color':[0x4E],'cmode':[ALT1,0x4E],'not':[0x4F],
          'merge':[0x70],'sbk':[0x90],'sex':[0x95],'asr':[0x96],'div2':[ALT1,0x96],'ror':[0x97],
          'lob':[0x9E],'fmult':[0x9F],'lmult':[ALT1,0x9F],'hib':[0xC0],'getc':[0xDF],
          'ramb':[ALT2,0xDF],'romb':[ALT3,0xDF],'getb':[0xEF],'getbh':[ALT1,0xEF],
          'getbl':[ALT2,0xEF],'getbs':[ALT3,0xEF],'alt1':[ALT1],'alt2':[ALT2],'alt3':[ALT3]}
# op: (base, reg form prefix, imm form prefix)   None = not allowed
ALU = {'add':(0x50,None,ALT2),'adc':(0x50,ALT1,ALT3),'sub':(0x60,None,ALT2),'sbc':(0x60,ALT1,None),
       'cmp':(0x60,ALT3,None),'and':(0x70,None,ALT2),'bic':(0x70,ALT1,ALT3),'mult':(0x80,None,ALT2),
       'umult':(0x80,ALT1,ALT3),'or':(0xC0,None,ALT2),'xor':(0xC0,ALT1,ALT3)}

def encode(op, args, pc, syms, final):
    """Return list of bytes for one instruction (labels may be unresolved on pass 1)."""
    def val(expr, bits, signed=False):
        try:
            v = parse_num(expr, syms)
        except NameError:
            if final: raise
            return 0
        if signed:
            lo, hi = -(1 << (bits - 1)), (1 << bits) - 1
        else:
            lo, hi = 0, (1 << bits) - 1
        if final and not lo <= v <= hi:
            raise ValueError(f'{op}: value {v} out of {bits}-bit range')
        return v & ((1 << bits) - 1)
    if op in SIMPLE:
        n = int(parse_num(args[0], syms)) if args else 1     # 'asr 6' = six asr's
        return list(SIMPLE[op]) * n
    if op in BRANCHES:
        tgt = val(args[0], 16)
        off = (tgt - (pc + 2)) if final else 0
        if final and not -128 <= off <= 127:
            raise ValueError(f'{op}: branch out of range ({off})')
        return [BRANCHES[op], off & 0xFF]
    if op in ('to', 'with', 'from'):
        base = {'to':0x10,'with':0x20,'from':0xB0}[op]
        return [base + reg(args[0])]
    if op == 'move':      # move rn, rs  ->  with rs ; to rn
        return [0x20 + reg(args[1]), 0x10 + reg(args[0])]
    if op == 'moves':     # moves rn, rs -> with rn ; from rs
        return [0x20 + reg(args[0]), 0xB0 + reg(args[1])]
    if op in ('stw', 'stb', 'ldw', 'ldb'):
        n = reg(args[0].strip('()'))
        if n > 11: raise ValueError(f'{op}: (r{n}) not allowed')
        base = 0x30 if op[0] == 's' else 0x40
        return ([ALT1] if op.endswith('b') else []) + [base + n]
    if op in ALU:
        base, rpre, ipre = ALU[op]
        if args[0].startswith('#'):
            if ipre is None: raise ValueError(f'{op} #imm not available')
            n = val(args[0][1:], 4)
            if op in ('and','bic','or','xor') and n == 0: raise ValueError(f'{op} #0 is not encodable')
            return [ipre, base + n]
        n = reg(args[0])
        if op in ('and','bic','or','xor') and n == 0: raise ValueError(f'{op} r0 is not encodable')
        return ([rpre] if rpre is not None else []) + [base + n]
    if op == 'link':
        n = val(args[0].lstrip('#'), 3)
        if not 1 <= n <= 4: raise ValueError('link #1..#4 only')
        return [0x90 + n]
    if op in ('jmp', 'ljmp'):
        n = reg(args[0])
        if not 8 <= n <= 13: raise ValueError('jmp r8..r13 only')
        return ([ALT1] if op == 'ljmp' else []) + [0x90 + n]
    if op in ('inc', 'dec'):
        n = reg(args[0])
        if n > 14: raise ValueError(f'{op} r0..r14 only')
        return [(0xD0 if op == 'inc' else 0xE0) + n]
    if op == 'ibt':
        return [0xA0 + reg(args[0]), val(args[1].lstrip('#'), 8, signed=True)]
    if op == 'iwt':
        v = val(args[1].lstrip('#'), 16, signed=True)
        return [0xF0 + reg(args[0]), v & 0xFF, v >> 8]
    if op == 'lm':      # lm rn,(addr)
        v = val(args[1].strip('()'), 16)
        return [ALT1, 0xF0 + reg(args[0]), v & 0xFF, v >> 8]
    if op == 'sm':      # sm (addr),rn
        v = val(args[0].strip('()'), 16)
        return [ALT2, 0xF0 + reg(args[1]), v & 0xFF, v >> 8]
    if op == 'lms':     # lms rn,(addr)  addr even, < 512
        v = val(args[1].strip('()'), 9)
        if v & 1: raise ValueError('lms address must be even')
        return [ALT1, 0xA0 + reg(args[0]), v >> 1]
    if op == 'sms':
        v = val(args[0].strip('()'), 9)
        if v & 1: raise ValueError('sms address must be even')
        return [ALT2, 0xA0 + reg(args[1]), v >> 1]
    raise ValueError(f'unknown op {op!r}')

def assemble(text):
    syms = {}
    for final in (False, True):
        out, pc, org = bytearray(), 0, None
        for lineno, raw in enumerate(text.splitlines(), 1):
            line = raw.split(';', 1)[0].strip()
            if not line: continue
            try:
                m = re.match(r'([A-Za-z_]\w*):\s*(.*)', line)
                if m:
                    syms[m.group(1)] = pc
                    line = m.group(2).strip()
                    if not line: continue
                m = re.match(r'([A-Za-z_]\w*)\s*=\s*(.+)', line)
                if m:
                    syms[m.group(1)] = parse_num(m.group(2), syms); continue
                op, _, rest = line.partition(' ')
                op = op.lower(); args = split_args(rest)
                if op == '.org':
                    org = pc = parse_num(rest, syms); continue
                if op in ('.db', '.dw'):
                    for a in args:
                        v = parse_num(a, syms) if final else 0
                        out += bytes([v & 0xFF] + ([v >> 8 & 0xFF] if op == '.dw' else []))
                        pc += 2 if op == '.dw' else 1
                    continue
                code = encode(op, args, pc, syms, final)
                out += bytes(code); pc += len(code)
            except Exception as e:
                raise SystemExit(f'{lineno}: {raw.strip()}\n   {e}')
    return bytes(out), org, syms

if __name__ == '__main__':
    src, binout, incout = sys.argv[1:4]
    code, org, syms = assemble(open(src).read())
    open(binout, 'wb').write(code)
    with open(incout, 'w') as f:
        f.write(f'; generated by gsuasm.py from {src}\n')
        for k, v in syms.items():
            f.write(f'GSU_{k} = ${v:04X}\n')
    print(f'{binout}: {len(code)} bytes at ${org:04X}, {len(syms)} symbols')
