// List functions whose instructions use ALL of the given memory displacements, and
// decompile them. Finds the native code that touches a given set of property offsets.
// Usage (headless postScript): FindDisp.java <out_file> <unused> <hex_disp> ...
// @category MirrorsEdge
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.scalar.Scalar;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.util.*;

public class FindDisp extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] a = getScriptArgs();
        Set<Long> want = new HashSet<>();
        for (int i = 2; i < a.length; i++) want.add(Long.decode(a[i]));
        DecompInterface ifc = new DecompInterface();
        ifc.openProgram(currentProgram);
        try (PrintWriter out = new PrintWriter(a[0], "UTF-8")) {
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                Set<Long> seen = new HashSet<>();
                for (Instruction ins : currentProgram.getListing().getInstructions(f.getBody(), true)) {
                    for (int op = 0; op < ins.getNumOperands(); op++) {
                        for (Object o : ins.getOpObjects(op)) {
                            if (o instanceof Scalar s && want.contains(s.getUnsignedValue())) seen.add(s.getUnsignedValue());
                        }
                    }
                }
                if (seen.containsAll(want)) {
                    DecompileResults r = ifc.decompileFunction(f, 120, new ConsoleTaskMonitor());
                    out.println("\n// ---- " + f.getName() + " @ " + f.getEntryPoint() + " (" + f.getBody().getNumAddresses() + " bytes)");
                    out.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// decompile failed");
                    out.flush();
                }
            }
        }
        ifc.dispose();
    }
}
