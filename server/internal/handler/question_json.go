package handler

import (
	"encoding/json"
	"strings"
)

// MarshalJSON 统一 Question 的用户可见文案边界。
//
// 规则层负责判断“是否值得问”，这里负责保证产品表达遵循：
// 事实 → 问题，不评价用户，也不直接给行为建议。
func (q Question) MarshalJSON() ([]byte, error) {
	normalized := q

	switch normalized.Type {
	case "completion_rate":
		// 旧规则包含“有些低”的价值判断；保留事实数字，改为开放问题。
		if idx := strings.Index(normalized.Content, "（"); idx >= 0 {
			normalized.Content = strings.TrimSpace(normalized.Content[:idx]) + "。和你预期的一样吗？"
		} else {
			normalized.Content = strings.ReplaceAll(normalized.Content, "，有些低", "")
			if !strings.HasSuffix(normalized.Content, "？") {
				normalized.Content += "。和你预期的一样吗？"
			}
		}
	case "new_habit_struggle":
		normalized.Content = strings.ReplaceAll(normalized.Content, "只打卡了", "目前记录了")
		normalized.Content = strings.ReplaceAll(
			normalized.Content,
			"，要不要降低难度试试？",
			"。当时是什么让你没有继续？",
		)
	case "time_preference":
		normalized.Content = strings.ReplaceAll(
			normalized.Content,
			"，你的高效时段在上午？",
			"。这个时间分布符合你的实际感受吗？",
		)
	}

	type plainQuestion Question
	return json.Marshal(plainQuestion(normalized))
}
