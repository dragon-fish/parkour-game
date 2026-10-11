// Decompile every class in a set of UE3 script packages to <out>/<Package>/<Class>.uc.
// All packages are loaded first so native operator tokens (declared in Core/Engine) can be
// resolved to their names through one shared natives table.
using UELib;
using UELib.Core;

// --raw keeps operators as __NFUN_<token>__ calls: the pretty printer drops parentheses,
// so operator precedence must be checked against the raw form.
var raw = args[0] == "--raw";
if (raw) args = args.Skip(1).ToArray();
var outDir = args[0];
var paths = args.Skip(1).ToArray();
var pkgs = paths.Select(p =>
{
    var pkg = UnrealLoader.LoadPackage(p, UnrealPackage.GameBuild.BuildName.MirrorsEdge, FileAccess.Read);
    pkg.InitializePackage();
    return pkg;
}).ToList();

var ntl = new NativesTablePackage { NativeTableList = new List<NativeTableItem>(), NativeTokenMap = new Dictionary<ushort, NativeTableItem>() };
foreach (var fn in pkgs.SelectMany(p => p.Objects).OfType<UFunction>())
{
    if (fn.NativeToken <= 0 || ntl.NativeTokenMap.ContainsKey((ushort)fn.NativeToken)) continue;
    var item = new NativeTableItem(fn);
    ntl.NativeTableList.Add(item);
    ntl.NativeTokenMap[(ushort)fn.NativeToken] = item;
}
Console.WriteLine($"natives table: {ntl.NativeTokenMap.Count} tokens");

for (int i = 0; i < paths.Length; i++)
{
    var pkg = UnrealLoader.LoadPackage(paths[i], UnrealPackage.GameBuild.BuildName.MirrorsEdge, FileAccess.Read);
    if (!raw) pkg.NTLPackage = ntl;
    pkg.InitializePackage();
    var dir = Path.Combine(outDir, Path.GetFileNameWithoutExtension(paths[i]));
    Directory.CreateDirectory(dir);
    int ok = 0, fail = 0;
    foreach (var obj in pkg.Objects)
    {
        if (obj is not UClass cls || obj.ExportTable == null) continue;
        string text;
        try { text = cls.Decompile(); ok++; }
        catch (Exception e) { text = "// DECOMPILE FAILED: " + e; fail++; }
        File.WriteAllText(Path.Combine(dir, cls.Name + ".uc"), text);
    }
    Console.WriteLine($"{Path.GetFileName(paths[i])}: {ok} classes ok, {fail} failed -> {dir}");
}
