// Execute native functions of the analysed program under Ghidra's p-code emulator.
// Usage (headless postScript): EmuCall.java <out_file> <unused> <spec_file>
//
// Spec file, one directive per line ('#' starts a comment):
//   func <addr>                      function every following case calls (__thiscall)
//   case <name>                      start a case; ends at 'end'
//   f32 <addr> <value>               write memory (absolute address)
//   i32 <addr> <value>
//   u8  <addr> <value>
//   thisf <off> <value> / thisi <off> <value> / thisb <off> <value>   write at this+off
//   ptr <off> <addr>                 write a pointer at this+off
//   arg f32 <v> | arg i32 <v> | arg out   stack arguments, first listed = first parameter;
//                                    'out' passes a 16-byte result buffer
//   read out3 | read st0 | read thisf <off>   what to report after the call
//   sintable <addr>                  fill UE3 GSinTable (bss, filled at startup) at addr
//   end
// 'this' lives at 0x10000000, the out buffer at 0x20000000, the stack at 0x30000000.
// @category MirrorsEdge
import ghidra.app.emulator.EmulatorHelper;
import ghidra.app.script.GhidraScript;
import ghidra.pcode.emulate.BreakCallBack;
import ghidra.pcode.memstate.MemoryState;
import ghidra.pcode.pcoderaw.PcodeOpRaw;
import ghidra.program.model.pcode.Varnode;
import ghidra.program.model.address.Address;

import java.io.PrintWriter;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;

public class EmuCall extends GhidraScript {
    // CRT math thunks that dispatch through pointers set at CRT startup; emulated in Java.
    static final long POW = 0x01311720L;   // _CIpow: ST1 = base, ST0 = exponent
    static final long FLOOR = 0x0131172cL; // floor(double) cdecl, result in ST0
    static final long THIS = 0x10000000L, OUT = 0x20000000L, STACK = 0x30000000L, RET = 0x0dead000L;

    @Override
    protected void run() throws Exception {
        String[] a = getScriptArgs();
        List<String> spec = Files.readAllLines(Path.of(a[2]));
        try (PrintWriter out = new PrintWriter(a[0], "UTF-8")) {
            long func = 0;
            List<String> body = null;
            String name = null;
            for (String raw : spec) {
                String line = raw.replaceAll("#.*", "").trim();
                if (line.isEmpty()) continue;
                String[] t = line.split("\\s+");
                if (t[0].equals("func")) func = Long.decode(t[1]);
                else if (t[0].equals("case")) { name = t[1]; body = new ArrayList<>(); }
                else if (t[0].equals("end")) { out.println(name + " " + runCase(func, body)); out.flush(); body = null; }
                else if (body != null) body.add(line);
            }
        }
    }

    private Address ad(long v) { return toAddr(v); }

    private static byte[] f32(float f) { return ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(f).array(); }
    private static byte[] i32(int v) { return ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array(); }
    private static float rf(byte[] b, int o) { return ByteBuffer.wrap(b, o, 4).order(ByteOrder.LITTLE_ENDIAN).getFloat(); }

    private String runCase(long func, List<String> body) throws Exception {
        EmulatorHelper emu = new EmulatorHelper(currentProgram);
        // RSQRTSS is a CALLOTHER the stock emulator leaves unimplemented. Exact 1/sqrt stands in
        // for the hardware estimate; every caller refines it with a Newton step.
        emu.registerCallOtherCallback("rsqrtss", new BreakCallBack() {
            @Override
            public boolean pcodeCallback(PcodeOpRaw op) {
                MemoryState ms = emulate.getMemoryState();
                BigInteger dst = ms.getBigInteger(op.getInput(1), false);
                Varnode srcVn = op.getInput(2);
                BigInteger src = ms.getBigInteger(srcVn, false);
                float x = Float.intBitsToFloat(src.intValue());
                int r = Float.floatToRawIntBits((float) (1.0 / Math.sqrt(x)));
                BigInteger low = BigInteger.valueOf(r & 0xffffffffL);
                BigInteger out = dst.andNot(BigInteger.valueOf(0xffffffffL)).or(low);
                ms.setValue(op.getOutput(), out);
                return true;
            }
        });
        try {
            List<byte[]> args = new ArrayList<>();
            List<String[]> reads = new ArrayList<>();
            for (String line : body) {
                String[] t = line.split("\\s+");
                switch (t[0]) {
                    case "f32": emu.writeMemory(ad(Long.decode(t[1])), f32(Float.parseFloat(t[2]))); break;
                    case "i32": emu.writeMemory(ad(Long.decode(t[1])), i32(Integer.decode(t[2]))); break;
                    case "u8": emu.writeMemory(ad(Long.decode(t[1])), new byte[]{(byte) (int) Integer.decode(t[2])}); break;
                    case "thisf": emu.writeMemory(ad(THIS + Long.decode(t[1])), f32(Float.parseFloat(t[2]))); break;
                    case "thisi": emu.writeMemory(ad(THIS + Long.decode(t[1])), i32(Integer.decode(t[2]))); break;
                    case "thisb": emu.writeMemory(ad(THIS + Long.decode(t[1])), new byte[]{(byte) (int) Integer.decode(t[2])}); break;
                    case "ptr": emu.writeMemory(ad(THIS + Long.decode(t[1])), i32((int) (long) Long.decode(t[2]))); break;
                    case "arg":
                        if (t[1].equals("f32")) args.add(f32(Float.parseFloat(t[2])));
                        else if (t[1].equals("i32")) args.add(i32(Integer.decode(t[2])));
                        else args.add(i32((int) OUT));
                        break;
                    case "sintable": { // UE3 GSinTable: 16384 entries of sin(i * 2pi / 16384), filled at startup
                        ByteBuffer bb = ByteBuffer.allocate(16384 * 4).order(ByteOrder.LITTLE_ENDIAN);
                        for (int i = 0; i < 16384; i++) bb.putFloat((float) Math.sin(i * 2.0 * Math.PI / 16384.0));
                        emu.writeMemory(ad(Long.decode(t[1])), bb.array());
                        break;
                    }
                    case "read": reads.add(t); break;
                    default: throw new IllegalArgumentException("bad directive: " + line);
                }
            }
            long sp = STACK;
            // arguments pushed right to left, then the return address
            for (int i = args.size() - 1; i >= 0; i--) { sp -= 4; emu.writeMemory(ad(sp), args.get(i)); }
            sp -= 4; emu.writeMemory(ad(sp), i32((int) RET));
            emu.writeRegister(emu.getStackPointerRegister(), sp);
            emu.writeRegister("ECX", THIS);
            emu.writeRegister("EBP", STACK + 0x100);
            emu.writeRegister("FS_OFFSET", 0x40000000L);
            emu.writeRegister(emu.getPCRegister(), func);
            emu.setBreakpoint(ad(RET));
            emu.setBreakpoint(ad(POW));
            emu.setBreakpoint(ad(FLOOR));
            boolean ok;
            long pc;
            while (true) {
                ok = emu.run(monitor);
                pc = emu.readRegister(emu.getPCRegister()).longValue();
                if (pc != POW && pc != FLOOR) break;
                long esp = emu.readRegister(emu.getStackPointerRegister()).longValue();
                if (pc == POW) {
                    // returns pow in ST0 with one value popped
                    double y = x87(emu.readRegister("ST0")), x = x87(emu.readRegister("ST1"));
                    for (int k = 0; k < 6; k++) emu.writeRegister("ST" + k, emu.readRegister("ST" + (k + 1)));
                    emu.writeRegister("ST0", toX87(Math.pow(x, y)));
                } else {
                    double arg = ByteBuffer.wrap(emu.readMemory(ad(esp + 4), 8)).order(ByteOrder.LITTLE_ENDIAN).getDouble();
                    for (int k = 7; k > 0; k--) emu.writeRegister("ST" + k, emu.readRegister("ST" + (k - 1)));
                    emu.writeRegister("ST0", toX87(Math.floor(arg)));
                }
                long ret = ByteBuffer.wrap(emu.readMemory(ad(esp), 4)).order(ByteOrder.LITTLE_ENDIAN).getInt() & 0xffffffffL;
                emu.writeRegister(emu.getStackPointerRegister(), esp + 4);
                emu.writeRegister(emu.getPCRegister(), ret);
            }
            StringBuilder sb = new StringBuilder();
            if (!ok || pc != RET) sb.append("STOPPED at 0x").append(Long.toHexString(pc)).append(" ").append(emu.getLastError()).append(" ");
            for (String[] r : reads) {
                switch (r[1]) {
                    case "out3": { byte[] b = emu.readMemory(ad(OUT), 12); sb.append(String.format("out=(%s, %s, %s) ", rf(b, 0), rf(b, 4), rf(b, 8))); break; }
                    case "st0": { BigInteger v = emu.readRegister("ST0"); sb.append("st0=").append(x87(v)).append(" "); break; }
                    case "thisf": { byte[] b = emu.readMemory(ad(THIS + Long.decode(r[2])), 4); sb.append(r[2]).append("=").append(rf(b, 0)).append(" "); break; }
                    default: throw new IllegalArgumentException("bad read: " + String.join(" ", r));
                }
            }
            return sb.toString().trim();
        } finally {
            emu.dispose();
        }
    }

    /** Encode a double as an 80-bit x87 extended value. */
    private static BigInteger toX87(double d) {
        if (d == 0) return BigInteger.ZERO;
        long bits = Double.doubleToRawLongBits(d);
        int sign = (int) (bits >>> 63);
        int exp = (int) ((bits >>> 52) & 0x7ff) - 1023 + 16383;
        long mant = (1L << 63) | ((bits & 0xfffffffffffffL) << 11);
        BigInteger se = BigInteger.valueOf((sign << 15) | exp);
        return se.shiftLeft(64).or(new BigInteger(Long.toUnsignedString(mant)));
    }

    /** Decode an 80-bit x87 extended value. */
    private static double x87(BigInteger v) {
        long mant = v.and(BigInteger.ONE.shiftLeft(64).subtract(BigInteger.ONE)).longValue();
        int se = v.shiftRight(64).intValue() & 0xffff;
        int exp = se & 0x7fff;
        if (exp == 0 && mant == 0) return (se & 0x8000) != 0 ? -0.0 : 0.0;
        double m = (double) (mant >>> 11) / (double) (1L << 52);
        double r = m * Math.pow(2, exp - 16383);
        return (se & 0x8000) != 0 ? -r : r;
    }
}
