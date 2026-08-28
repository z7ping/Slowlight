/// Repository 基类，定义通用 CRUD 操作接口
///
/// ## 适用范围
///
/// 本基类设计用于 **新增** Repository，不会对已有 Repository 进行重构适配。
/// 已有的 Repository（如 [TaskRepository]、[HabitRepository]）因历史原因使用了
/// 不同的签名风格（命名参数而非完整模型对象），与本基类的 `create(T)` / `update(T)`
/// 签名不兼容。如果需要为新领域添加 Repository，推荐继承此基类以保持一致性。
///
/// ## 与 ApiDataSource 的关系
///
/// 本基类与 `ApiDataSource`（位于 `services/data_source.dart`）处于不同抽象层级：
///
/// - **ApiDataSource** 是数据源抽象层，定义了远程（HTTP）和本地（SQLite）
///   两种实现都需要遵守的统一接口。它关注的是"如何访问数据"。
/// - **BaseRepository** 是面向具体领域的仓储基类，每个 Repository 对应一个
///   业务实体。它关注的是"如何组织对某一实体的 CRUD 操作"。
///
/// 典型用法中，Repository 内部会通过 `ApiDataSource` 来完成实际的数据读写，
/// 从而自动适配本地模式和云端模式。
///
/// ## 类型约束
///
/// 泛型参数 `T` 代表仓储所管理的实体类型。`getById`、`delete` 的参数为 `int id`，
/// 因此适用的实体必须具有整数类型的主键。
abstract class BaseRepository<T> {
  /// 获取所有实体
  Future<List<T>> getAll();

  /// 根据 ID 获取单个实体，不存在时返回 null
  Future<T?> getById(int id);

  /// 创建实体并返回创建后的完整实体
  Future<T> create(T item);

  /// 更新实体并返回更新后的完整实体
  Future<T> update(T item);

  /// 根据 ID 删除实体
  Future<void> delete(int id);
}
