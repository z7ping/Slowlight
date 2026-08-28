package integration

import "fmt"

var registry = map[string]Provider{}

// Register 注册一个集成 Provider。
// 公开预览阶段对飞书服务端实现套一层安全边界：本机模式继续使用独立实现；
// 云端导出在具备幂等 upsert 前明确拒绝，避免重复记录和假成功。
func Register(p Provider) {
	if p.Name() == "feishu" {
		p = newSafeFeishuProvider(p)
	}
	registry[p.Name()] = p
}

// Get 获取指定平台的 Provider
func Get(name string) (Provider, error) {
	p, ok := registry[name]
	if !ok {
		return nil, fmt.Errorf("unsupported integration platform: %s", name)
	}
	return p, nil
}

// List 获取所有已注册的 Provider
func List() []Provider {
	result := make([]Provider, 0, len(registry))
	for _, p := range registry {
		result = append(result, p)
	}
	return result
}
