// For each native UE3 class name: find its registration call, its InternalConstructor and the
// vtable that constructor installs. Prints one line per class:
//   <Class> size=<hex> ctor=<addr> vtable=<addr>
// Registration looks like FUN_010fea20(0, sizeof, ..., L"<Name>", ..., InternalConstructor, ...);
// the constructor's last "*this = &PTR_..." store is the class's own vtable.
// Usage (headless postScript): ClassVTables.java <out_file> <unused> <ClassName> ...
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
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class ClassVTables extends GhidraScript {
    static final String REGISTER = "FUN_010fea20";

    @Override
    protected void run() throws Exception {
        String[] a = getScriptArgs();
        DecompInterface ifc = new DecompInterface();
        ifc.openProgram(currentProgram);
        try (PrintWriter out = new PrintWriter(a[0], "UTF-8")) {
            for (int i = 2; i < a.length; i++) {
                out.println(resolve(ifc, a[i]));
                out.flush();
            }
        }
        ifc.dispose();
    }

    private String decompile(DecompInterface ifc, Function f) {
        DecompileResults r = ifc.decompileFunction(f, 120, new ConsoleTaskMonitor());
        return r.decompileCompleted() ? r.getDecompiledFunction().getC() : "";
    }

    private String resolve(DecompInterface ifc, String name) throws Exception {
        byte[] needle = (name + "\0").getBytes(StandardCharsets.UTF_16LE);
        Address hit = currentProgram.getMinAddress();
        Pattern call = Pattern.compile(REGISTER + "\\(([^;]*)L\"" + Pattern.quote(name) + "\"([^;]*)\\);", Pattern.DOTALL);
        StringBuilder diag = new StringBuilder();
        while ((hit = find(hit, needle)) != null) {
            diag.append(" hit@").append(hit);
            // A suffix of a longer name (TdPawn inside ATdPawn) is rejected by the call
            // pattern, which wants the whole L"<Name>" literal.
            {
                for (Reference r : getReferencesTo(hit)) {
                    Function f = getFunctionContaining(r.getFromAddress());
                    if (f == null) continue;
                    String c = decompile(ifc, f);
                    Matcher m = call.matcher(c);
                    diag.append(" ref:").append(f.getName());
                    if (!m.find()) { int k = c.indexOf(REGISTER); diag.append(k < 0 ? "(no call)" : "(call: " + c.substring(k, Math.min(c.length(), k + 160)).replace('\n', ' ') + ")"); continue; }
                    String[] before = m.group(1).split(",");
                    String size = before.length > 1 ? before[1].trim() : "?";
                    Matcher ctorM = Pattern.compile("(FUN_[0-9a-f]{8})").matcher(m.group(2));
                    if (!ctorM.find()) continue;
                    Function ctor = getFunctionAt(toAddr(ctorM.group(1).substring(4)));
                    String vt = "?";
                    if (ctor != null) {
                        Matcher vm = Pattern.compile("\\*param_1 = &(?:PTR_LAB_|PTR_FUN_|PTR_)([0-9a-f]{8})").matcher(decompile(ifc, ctor));
                        while (vm.find()) vt = vm.group(1);
                    }
                    return name + " size=" + size + " ctor=" + ctorM.group(1).substring(4) + " vtable=" + vt;
                }
            }
            hit = hit.add(2);
        }
        return name + " NOT FOUND" + diag;
    }
}
