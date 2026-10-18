import '../services/data_service.dart';
import 'ai_provider.dart';
import 'ai_service.dart';
import 'xiaweis_prompt.dart';

class XiaweisService {
  final AiService ai;
  final DataService data;

  XiaweisService({AiService? ai, DataService? data})
      : ai = ai ?? AiService(),
        data = data ?? DataService();

  Future<AiResponse> reply({
    required List<AiMessage> history,
    required String personalContext,
    required bool includeTodayTasks,
  }) async {
    // 用户主动选择后才读取并发送任务给自己配置的模型。
    // 不允许读取失败时无声退化为“没有任务”。
    final tasks = includeTodayTasks ? await data.getTodayTasks() : null;
    return ai.complete(
      XiaweisPrompt.build(
        history: history,
        personalContext: personalContext,
        todayTasks: tasks,
      ),
    );
  }
}
