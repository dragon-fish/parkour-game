# 作者开发笔记

面向作者本人的操作备忘。仓库结构、代码规范等见其他文档；这里只记「怎么用」。

## 私有资产：`.private` 子模块 + `local/` 约定

受授权约束不能公开的资产（Beriul 全套、test.vrm、酒狐、UAL full 动画包、
body profiles、本地白盒场景），放在 GitHub **私有**仓
`dragon-fish/parkour-game-private`，作为**子模块**挂在 `.private/`，大文件走
Git LFS。点开头的目录 Godot 不索引，编辑器里也看不见。

### 唯一的约定

> **主仓永远不创建名为 `local` 或 `local_*` 的文件夹。**

这些名字属于私仓（或纯本地的临时文件）。私有资产一律放进这样的目录，
`tools/link_private.py` 把每个目录**软链**到它该在的位置——于是编辑器里
模型仍然在 `assets/models/local/`，所有 `res://` 路径照写不误。

链接**从不入库**：Git 在 Windows 上会把提交过的软链检出成一个写着目标路径
的文本文件，资产就这么无声无息地丢了。所以本地生成、`.gitignore` 忽略掉。
清单只允许目录：Windows 的目录 junction 不需要管理员权限，单文件软链需要。

### 日常

```sh
git submodule update --init          # 第一次 / 换机器
python3 tools/link_private.py --install-hooks   # 一次性：装钩子（顺带建链）
cd .private && git add -A && git commit && git push   # 改了私有资产
```

装过钩子之后，`git pull` / 切分支 / `git submodule update` 会**自动**重建链接：
新目录建上、上游删掉的链接清掉。手动跑 `python3 tools/link_private.py`
效果一样，可重复执行。

⚠️ **Windows 上敲 `python`，不是 `python3`**。后者在 PATH 上解析到微软商店的
`AppInstallerPythonRedirector.exe`——它存在、可执行、但不是 Python。钩子里
因此是先试 `python` 并**实际探测**解释器版本，而不只是看它在不在 PATH；
只看在不在，这半边设置就会变成一个不报错的空操作。

**钩子本身是入库的**（`tools/githooks/`），因为 git 从不同步 `.git/hooks`；
`core.hooksPath` 指过去就等价于 husky 那套做法。唯一不能自动化的是那句
`git config`——git 有意不让 clone 自动执行仓库里的配置（否则 clone 一个仓
就能在你机器上执行代码）。所以换机器记得跑一次 `--install-hooks`。

⚠️ 这些钩子里**必须**保留 `git lfs` 调用：`core.hooksPath` 会整体顶掉
`git lfs install` 装在 `.git/hooks` 里的那四个，少了它 LFS 会静默停止
smudge 和上传。`tools/githooks/_lfs.sh` 就是干这个的。

### 本地有同名真目录时

链接位置上如果已经存在**真的**文件夹（比如你在主仓手滑建了个 `local/`），
脚本不会覆盖也不会跳过，而是把它改名成 `local_<时间戳>` 挪开、建好链接、
并打印一段醒目的警告。挪开的副本仍被 `.gitignore` 忽略，你把想留的东西并进
`.private` 再删掉它即可。

判断「是不是真文件夹」在 Windows 上有个陷阱，脚本里已经处理掉，但值得记下：
**junction 不是 symlink**，`Path.is_symlink()` 和 `os.path.islink()` 对它都
答 `False`（要问 `os.path.isjunction()`）。所以脚本第一版会把自己上次建的
junction 全部误判成真文件夹挪走，每跑一次留下一批 `local_<时间戳>` 孪生目录
——`.gitignore` 忽略它们，Godot 可不忽略，于是资产双份、uid 撞车。删这种
目录只能用 `rmdir`（只摘掉重解析点），`rm -rf` 会跟进去把私仓真身删了。

`.private` 是个普通仓库，IDE 的源代码管理面板能直接管它，父仓的
`git status` 会显示子模块有新提交——不像以前的 overlay 那样完全隐形。

### 新增私有内容

放进任意 `local/` 目录即可。若是新开的一个 `local` 目录，跑一次
`python3 tools/link_private.py` 之前先更新 `.private/links.txt`（一行一个
路径，两边同名）。

### 换新电脑

```sh
git clone git@github.com:dragon-fish/parkour-game.git
cd parkour-game
git submodule update --init          # 需要私仓权限，别人 clone 主仓不受影响
python3 tools/link_private.py
```

⚠️ **切换/同步子模块时关掉 Godot 编辑器**，并且之后先跑一次
`Godot --headless --path . --import` 再开编辑器。原因见下。

### `_local/` 要放一个 `.gdignore`

`.gitignore` 管 git，**管不住 Godot**。`_local/` 里那些纯本机的东西（UAL 压缩
包、ME 参考数据、临时备份）照样会被引擎索引——最坏的情况是里面躺着一份旧资产
的副本，于是同一个 uid 出现两次。放一个空的 `.gdignore` 进去即可。

这个文件**同步不过去**（`_local/` 本身被忽略），所以每台机器各放一次。

## Beriul 相关的注意事项

- 模型、贴图、材质、wrapper（`assets/models/local/beriul/`）全部不入库；
  入库的是通用脚本（spring_chains / headless_variant / bone_rotation_damp
  / bone_scale_tweak / matcap_toon.gdshader）和 `scenes/player/tuning/
  beriul_body.json`（挂载数值）。
- 骨骼重定向的 BoneMap 只能活在 `beriul.fbx.import` 里。**`.import` 现在
  跟着资产进了私仓**（以前被 .gitignore 排除，所以换台机器就等于从零重新
  导入，默认设置里没有 bone_map——这就是 PC 上「导入完打开引擎，绑骨动画全
  没了」的根因）。洗掉了就 `cd .private && git checkout -- <那个 .import>`
  再 `--headless --import`。
- **编辑器开着的时候不要切换子模块或拉取资产**：Godot 会在文件被换掉的瞬间
  重扫并改写 `.import`，而 `.godot/` 是空的那一次全新扫描正是会清空
  `_subresources` 的那一次。顺序永远是：关编辑器 → 同步 → `--headless
  --import` → 再开编辑器 → `git -C .private status` 确认 `.import` 没被改。
- **在编辑器里保存 wrapper 有风险**：Godot 曾在重新序列化 `beriul_body.tscn`
  时丢掉全部 `chain_prefixes`，四组弹簧骨归零、全身次级运动消失且不报错。
  在编辑器里调完数值后，跑一次 `tools/run_tests.sh body_wrapper`：它会
  检查每组弹簧是否还找得到链条。挂了就 `git checkout` 私有仓那份 wrapper
  再手动改回数值（数值是纯文本，直接改文件最省事）。
