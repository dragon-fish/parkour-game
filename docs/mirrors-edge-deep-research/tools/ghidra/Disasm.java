// Print the instruction listing of whole functions.
// Usage (headless postScript): Disasm.java <out_file> <unused_depth> <addr> ...
// @category MirrorsEdge
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;

import java.io.PrintWriter;

public class Disasm extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] a = getScriptArgs();
        try (PrintWriter out = new PrintWriter(a[0], "UTF-8")) {
            for (int i = 2; i < a.length; i++) {
                Function f = getFunctionAt(toAddr(a[i].split("~", 2)[0]));
                if (f == null) { out.println("// no function at " + a[i]); continue; }
                out.println("\n// ==== " + f.getName() + " @ " + f.getEntryPoint());
                for (Instruction ins : currentProgram.getListing().getInstructions(f.getBody(), true))
                    out.println(ins.getAddress() + "  " + ins);
            }
        }
    }
}
