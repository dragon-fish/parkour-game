// For each exact UTF-16 string, list the functions that reference it and decompile them.
// Usage (headless postScript): StringRefs.java <out_file> <depth> <text> ...
// @category MirrorsEdge
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class StringRefs extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] a = getScriptArgs();
        int depth = Integer.parseInt(a[1]);
        DecompInterface ifc = new DecompInterface();
        ifc.openProgram(currentProgram);
        Set<Address> seen = new HashSet<>();
        try (PrintWriter out = new PrintWriter(a[0], "UTF-8")) {
            for (int i = 2; i < a.length; i++) {
                byte[] needle = (a[i] + "\0").getBytes(StandardCharsets.UTF_16LE);
                Address hit = currentProgram.getMinAddress();
                out.println("\n// ==== STRING \"" + a[i] + "\" ====");
                while ((hit = find(hit, needle)) != null) {
                    // UTF-16 strings start on an even address and are preceded by a 0 char or another string's end.
                    out.println("// string at " + hit);
                    for (Reference r : getReferencesTo(hit)) {
                        Function f = getFunctionContaining(r.getFromAddress());
                        out.println("//   ref from " + r.getFromAddress() + (f == null ? " (no function)" : " in " + f.getName() + " @ " + f.getEntryPoint()));
                        if (f != null) walk(ifc, f, depth, 0, seen, out);
                    }
                    hit = hit.add(2);
                }
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
