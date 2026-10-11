// Decompile functions and their callees (to a fixed depth) into one text file.
// Usage (headless postScript): DecompileTree.java <out_file> <depth> <addr>[~label] ...
// @category MirrorsEdge
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.util.*;

public class DecompileTree extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] a = getScriptArgs();
        String outPath = a[0];
        int depth = Integer.parseInt(a[1]);
        DecompInterface ifc = new DecompInterface();
        ifc.openProgram(currentProgram);
        Set<Address> seen = new HashSet<>();
        try (PrintWriter out = new PrintWriter(outPath, "UTF-8")) {
            for (int i = 2; i < a.length; i++) {
                String[] parts = a[i].split("~", 2);
                Address addr = toAddr(parts[0]);
                Function f = getFunctionAt(addr);
                if (f == null) f = createFunction(addr, null);
                if (f == null) { out.println("// no function at " + parts[0]); continue; }
                if (parts.length > 1) out.println("\n// ==== ROOT " + parts[1] + " ====");
                walk(ifc, f, depth, 0, seen, out);
            }
        }
        ifc.dispose();
    }

    private void walk(DecompInterface ifc, Function f, int maxDepth, int d, Set<Address> seen, PrintWriter out) {
        if (f.isExternal() || f.isThunk() || !seen.add(f.getEntryPoint())) return;
        DecompileResults r = ifc.decompileFunction(f, 120, new ConsoleTaskMonitor());
        out.println("\n// ---- " + f.getName() + " @ " + f.getEntryPoint() + "  (depth " + d + ", " + f.getBody().getNumAddresses() + " bytes)");
        out.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// decompile failed: " + r.getErrorMessage());
        if (d >= maxDepth) return;
        List<Function> callees = new ArrayList<>(f.getCalledFunctions(monitor));
        callees.sort(Comparator.comparing(Function::getEntryPoint));
        for (Function c : callees) walk(ifc, c, maxDepth, d + 1, seen, out);
    }
}
