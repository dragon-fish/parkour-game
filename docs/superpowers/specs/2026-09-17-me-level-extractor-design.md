# 镜之边缘通用关卡提取器设计

把《镜之边缘》(2008) 任意章节的一段关卡，从本机正版安装里提取成本项目可玩的关卡：
几何、碰撞、灯光、游戏标注，进去就能跑。教程关迁移到同一条流水线。

产物是他人商业游戏的关卡数据，**只进 `.private` 私仓**；提取器和生成器本身不含
原作数据，放公开仓。

## 背景与已验证的前提

现有教程关导入器（`.private/.../mirrors_edge/import_tools/`）写死了教程关的包名、
出生点类型和过滤锚点，且几何只有碰撞凸包。Stormdrain（第二章「阿杰」）StdP 柱厅的
一次性试探暴露了三件事，本设计以它们为前提：

1. **渲染网格可以可靠解析。** 已解压的 486 个关卡包中 15,363 个 `StaticMesh`、
   抽样的 10 个共享 `.upk` 中 119 个，全部通过自校验（索引不越界、顶点在包围盒内、
   材质分区三角形数之和等于索引缓冲三角形数）。布局见下文「StaticMesh 渲染数据」。
2. **「没有凸包」不等于「没有碰撞」。** 没有凸包的模型分三类：
   - ① 组件/Actor 上 `CollideActors=False`（如光片 `StormDrainLights_01`）：不碰撞。
   - ② 模型上 `UseSimple*Collision=False`（如 `S_StormDrainRing_02`）：用渲染三角面碰撞。
   - ③ 什么都没写、也没有 `BodySetup`：`[ME:INFERRED]` UE3 在无简单碰撞时退回逐三角面，
     与 ② 同样处理。未核实。
   过去给没有凸包的模型补实心包围盒，会把空心结构填死、把光片变成墙。
   另外，有凸包但 `CollideActors=False` 的模型（如 `S_HighRiseConstruction_01`）也不应碰撞，
   现有导入器没遵守。
3. **灯光是 Beast 烘焙。** `bUseBakerColorAndBrightness` 为真时，有效值在 Actor 的
   `BakerBrightness` / `BakerColor`，组件 `Brightness` 常为 0。照搬几乎全黑；
   目测 ×16 能量 + SDFGI 间接光 ×4 效果合适。这是旋钮，没有换算依据。

## 范围

**做：**
- 按「章节 + 分片列表」提取一段关卡，静态导入（不实现原作的流式分段加载）。
- 渲染网格用于显示与逐三角面碰撞；凸包用于简单碰撞。
- 全局模型库：每个模型一个资源文件，所有关卡共用。
- 灯光、环境开关、游戏标注、出生点与检查点。
- 教程关迁移，薄壳保留不动。

**不做：**
- 贴图与 UV（材质分区只用来分色）。以后做烘焙光照时再读光照贴图 UV。
- 原作 Kismet 逻辑（检查点激活、流式加载、脚本事件）。
- `TdFallHeightVolume` 的映射（含义未核实，只进提取报告）。
- `SkyLight`。

## 流水线

```
关卡配置 (.private)
   │
   ▼  提取 (Python, 公开仓)
关卡清单 + 模型数据 (_local 缓存，可再生，不进仓库)
   │
   ▼  生成 (Godot 无界面, 公开仓)
模型库 .res + 关卡几何 .scn + 薄壳 .tscn (.private)
```

### 文件位置

| 内容 | 位置 |
|---|---|
| 提取器 | `docs/mirrors-edge-deep-research/tools/level_extract/`（复用同目录的 `ue3parse` / `mapdump` / `hulls` / `ue3_decompress`） |
| 生成器、通用验证脚本 | `tools/me_level/` |
| 关卡配置 | `.private/scenes/local_debug_levels/mirrors_edge/levels/<id>.json` |
| 模型库 | `.private/scenes/local_debug_levels/mirrors_edge/mesh_library/<mesh>.res` |
| 关卡几何、薄壳 | `.private/scenes/local_debug_levels/mirrors_edge/<id>_geometry.scn`、`<id>.tscn` |
| 解压包、清单、模型数据 | `_local/me-reference/level-extract/` |

教程关现有文件名 `me_tutorial.tscn` / `me_tutorial_blockout.scn` 保持不变（薄壳已引用
几何场景），教程关配置显式写出这两个输出路径。

迁移完成后删除 `import_tools/` 中被取代的脚本（含教程关专用的 `extract_bsp.py`、
`extract_collision_details.py`），README 中仍然成立的坑并入提取器文档。

## 关卡配置

JSON，全部是具名字段。可选字段写出默认值。

```jsonc
{
  "id": "sp02_stdp",                 // 必填，决定默认输出文件名
  "chapter": "SP02",                 // 必填，CookedPC/Maps 下的目录
  "sections": [                      // 必填，至少一项
    { "name": "StdP" }
  ],
  "packages": [],                    // 可选，默认 []：按分片推断之外额外加载的包文件名
  "exclude_meshes": [],              // 可选，默认 []：手动排除的模型名
  "anchor_filter": null,             // 可选，默认 null（不过滤）。{ "radius_m": 20 } 时按锚点距离过滤
  "interior": false,                 // 可选：首次创建薄壳时关 Sun、开 SDFGI
  "initial_spawn": null,             // 可选：TdCheckpoint 或 TdTutorialStart 的对象名；null 取范围内第一个
  "outputs": {                       // 可选
    "geometry": null,                //   null → <id>_geometry.scn
    "shell": null                    //   null → <id>.tscn
  }
}
```

**分片推断：** 分片 `StdP` 加载 `<Prefix>_StdP*.me1`（含 `_Art`、`_Bac`、`_Bac2`、`_Lgts`、`_Spt`、
`_LW`），以及文件名里以 `-` 分隔、有一侧恰为该分片的连接段（`Std-StdP_Slc*`、`StdP-StdE_slc*`）。
不加载 `_Aud*`、`*_LOC_*`、`TT_*`。前缀 `<Prefix>` 取章节总包 `*_p.me1` 的名字。
推断出的包清单写进提取报告。

教程关没有分片，配置用 `packages` 列出 `Tutorial_p` / `Tutorial_Art` / `Tutorial_Bac` 等，
`sections` 为空时不做推断；`anchor_filter` 设为 `{ "radius_m": 20 }` 以保持现有结果。

## 提取器

### 输出：关卡清单

```jsonc
{
  "config": { ... },                 // 原样回写，便于追溯
  "packages": ["Stormdrain_StdP.me1", ...],
  "placements": [{
    "name": "StaticMeshActor_172", "package": "...",
    "mesh": "S_StormDrainPillar_01",
    "position": [x, y, z], "basis": [[...], [...], [...]],  // Godot 空间，缩放折进 basis
    "collision": "none" | "simple" | "per_poly"
  }],
  "bsp": [{ "vertices": [[...]], "normal": [...] }],
  "lights": [{
    "name", "class", "tag", "position", "basis",
    "brightness", "color": [r, g, b], "radius_m",
    "outer_cone_deg", "inner_cone_deg"
  }],
  "annotations": [{ "kind", "name", "position", "basis", "hull", ... }],
  "checkpoints": [{ "name", "class", "position", "yaw_deg" }],
  "report": { ... }
}
```

坐标变换沿用 `build_blockout.py` 的 `to_godot` / `godot_basis`（行列式为 -1 的轴映射，
不要改成保手性的映射，会得到镜像关卡）。

### 输出：模型数据

每个被引用的模型一份，键为模型名：

```jsonc
{
  "name": "S_StormDrainRing_02",
  "bounds": { "origin": [...], "extent": [...] },
  "vertices": "<base64 float32 xyz, Godot 空间>",
  "normals": "<base64 float32 xyz>",
  "surfaces": [{ "material": "M_StormDrainRing_01", "collide": true,
                 "indices": "<base64 uint16>" }],
  "hulls": [{ "vertices": [[...]], "triangles": [...] }],
  "simple_collision": true
}
```

**同名模型一致性：** 同一模型名在多个包中出现时，比较顶点数、三角形数、包围盒；
任何一项不同即报错，列出两个来源。

### StaticMesh 渲染数据（包版本 536）

属性区之后依次为（均已在试探中验证）：

| 段 | 格式 |
|---|---|
| Bounds | 7 × float32 |
| BodySetup | int32 对象引用（0 = 无） |
| kDOP 节点 | 批量数组：int32 元素大小 (=32)、int32 数量、数据 |
| kDOP 三角形 | 批量数组 (元素 8 字节：3 × uint16 顶点 + uint16 材质) |
| InternalVersion、LOD 数 | 2 × int32 |
| RawTriangles | 批量数据头 4 × int32（flags、count、size、offset），跳过 size 字节 |
| Elements | int32 数量；每项 10 × int32（材质引用、EnableCollision、OldEnableCollision、ShadowCasting、FirstIndex、NumTriangles、MinVertexIndex、MaxVertexIndex、MaterialIndex、碎片数）+ 碎片数 × 8 字节 |
| PositionVertexBuffer | Stride、NumVertices、批量数组 (12 字节 xyz)；位置数为顶点数的 2 倍，后半为阴影体积复制 |
| VertexBuffer | NumTexCoords、Stride、NumVertices、1 × int32、批量数组 |
| ShadowExtrusion | 2 × int32、批量数组 |
| NumVertices | int32（真实顶点数） |
| IndexBuffer | 批量数组 (uint16) |
| Wireframe / Adjacency | 批量数组 |

只读 LOD0。**法线**来自 VertexBuffer 中的打包切线，格式未验证：实现时以单位长度校验，
不通过即停下讨论，不退回自算法线。

kDOP 三角形数与参与碰撞分区的三角形数在 98% 的模型中相等；不等的列入报告。

### 碰撞分类

按以下顺序判定，写进 `placements[].collision`：

1. 组件或 Actor 上 `CollideActors=False`（经原型继承合并后）→ `none`。
2. 模型有简单碰撞形状（`BodySetup` 的凸包或 BoxElems）且简单碰撞开关未关 → `simple`。
   BoxElems 与其 TM 的读取、校验沿用 `extract_collision_details.py` 的做法，并入提取器。
3. 其余 → `per_poly`，只用 `collide=true` 的材质分区三角面。

### 游戏标注

| 原作类 | 清单 kind | 说明 |
|---|---|---|
| `TdZiplineVolume` 等五类线体积 | `zipline` / `swing` / `balance` / `ladder` / `ledgewalk` | 带 spline、start/end、wall、hull |
| `TdBarbedWireVolume` | `barbedwire` | 带 hull |
| `BlockingVolume` | `blocking` | 带 hull 与 exclude_hand / exclude_foot |
| `TdKillVolume` | `kill` | 带 hull |
| `TdCheckpointVolume` | `checkpointvolume` | 教程关 |
| `TdFallHeightVolume` | — | 只计入报告 |

软着陆：碰撞物理材质的 `TdPhysicalMaterialProperty.bEnableSoftLanding=true` 的摆放，在清单里标
`soft_landing`（读取方式沿用 `extract_collision_details.py`，并入提取器）。

### 出生点与检查点

- 教程关：`TdTutorialStart`（出生点）+ `TdCheckpointVolume`（触发外形）。
- 正式章节：章节总包 `*_p.me1` 中的 `TdCheckpoint` 与 `PlayerStart`，位置落在
  「分片范围」内的才要。分片范围 = 推断出的包中**除 `_Bac*` 以外**所有摆放位置的轴对齐包围盒，
  各向外扩 2 m。`_Bac` 是远景，算进去范围会覆盖大半个城市。

### 提取报告

打印并写入清单 `report`，只给人看、不做断言：加载的包、摆放数与三类碰撞各自数量、
灯光按类计数、标注按 kind 计数、未映射的标注类、kDOP 三角形数不符的模型、被
`exclude_meshes` 与 `anchor_filter` 排除的数量。

## 生成器

### 模型库

每个模型一个 `.res`，内含：
- `ArrayMesh`：每个材质分区一个表面，顶点与法线来自清单。
- 碰撞形状：有简单碰撞形状的模型存 `ConvexPolygonShape3D` / `BoxShape3D` 列表；
  有 `collide=true` 分区的模型另存一个 `ConcavePolygonShape3D`。摆放按自己的
  `collision` 类别取其一。
- 已存在且源数据哈希未变的模型跳过重建（哈希存在资源元数据里）。

表面材质按**材质名**匹配色板分类，匹配不到再按模型名，沿用现有 `MATERIAL_RULES` /
`MATERIAL_PALETTE` 的做法，共享 `StandardMaterial3D`。

### 关卡几何场景

```
<Id>_Geometry (Node3D)
├── Geometry
│   └── <Mesh>_<index> (StaticBody3D 或 Node3D)   # 引用模型库网格与形状
├── BSP
└── Lights (Node3D, 带 energy_scale 导出)
    └── OmniLight3D / SpotLight3D ...
```

- `collision=none` 的摆放是 `Node3D` + `MeshInstance3D`；其余为 `StaticBody3D`。
- 交互物件去碰撞规则保留（梯子、单杠、滑索部件、梯子线经过的水管）。
- `Lights` 挂 `@tool` 脚本：`energy_scale`（默认 16）。每盏灯的原作亮度存在元数据
  `me_brightness`，setter 重算 `light_energy = me_brightness × energy_scale`。
  **调这个值要在薄壳里改实例化节点的属性**，重建几何不会冲掉。
- `PointLight`、`TdAreaLight` → `OmniLight3D`（`TdAreaLight` 底下就是点光组件）；
  `SpotLight`、`SpotLightMovable` → `SpotLight3D`。原作灯沿 Actor +X 照射。阴影默认关。

### 薄壳

继承 `templates/base_level.tscn`，引用关卡几何场景。**仅在文件不存在，或显式传
`--rebuild-interactions` 时生成**；其余时候只重建几何与模型库。

- 交互线 `InterestLine`、`BarbedWire` + `Hazard`（沿用现有 `build_wire_hazard`）、
  空气墙、`DeathVolume`（来自 `kill`）。
- 检查点：
  - 教程关：`Checkpoint` 坐落于最近的 `TdTutorialStart`，触发外形为体积凸包（现有做法）。
  - 正式章节：每个 `TdCheckpoint` 一个 `Checkpoint`，位置朝向取原作，触发外形为默认
    4 m 立方的 `BoxShape3D`，由人在编辑器里调整。
- `SpawnPoint` 取 `initial_spawn` 指定的点，否则取范围内第一个。
- `interior=true`：关 `Sun`，`WorldEnvironment` 开 SDFGI、间接光强度 4。

## 出错处理

提取与生成都是离线工具，一律出错即停并指明包与对象：
- 渲染数据任一自校验失败；法线校验失败。
- 同名模型内容不一致。
- 配置中分片推断不到任何包；`initial_spawn` 指定的对象不存在。
- 摆放引用的模型在所有已加载包中都找不到。

**移除**现有导入器的静默兜底：读不出尺寸丢弃摆放、没有凸包补包围盒、
包围盒比例校验丢弃摆放。

## 验证

表现类数值不写断言（见 `.claude/skills/tuning-dials-not-rules`）。

**通用结构检查**（`tools/me_level/verify_level.gd <config>`）：
- 每个摆放引用的模型库资源存在。
- 各碰撞类别的节点数与清单一致；`none` 的摆放没有 `CollisionShape3D`。
- `InterestLine`、`BarbedWire`（每条带 `Hazard`）、空气墙、`DeathVolume` 数量与清单一致。
- 出生点与生成出来的每个检查点，向下射线能命中地面。

**教程关迁移验收：**
- `verify_tutorial.gd` 通过；删除其中对照原作检查点的检查（薄壳里的检查点是手工重做的）。
- `probe_support.gd` 通过。
- 迁移前后同机位截图，人眼对比。
- 薄壳 `me_tutorial.tscn` 在 git diff 中无改动。

**Stormdrain StdP 验收：** 结构检查通过、截图、人进关卡跑一圈。

公开仓测试套件不依赖私仓数据，本工作不向其中加测试。

## 未核实、需在实现中确认

- 第 ③ 类碰撞是否真的逐三角面（可请人在原作中实地验证一处）。
- 打包法线的格式。
- 正式章节 `TdCheckpoint` 中是否混有计时赛或重开专用的点。
- `SwingPole` 横杆型号在各章节的命名；单杠拼接规则要放宽到全部横杆型号。
