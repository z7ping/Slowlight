package handler

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestQuestionMarshalJSONUsesNeutralWording(t *testing.T) {
	tests := []struct {
		name       string
		question   Question
		forbidden  string
		required   string
	}{
		{
			name: "completion rate removes judgment",
			question: Question{
				ID: "completion_rate_weekly", Type: "completion_rate",
				Content: "本周创建了 10 个任务，完成了 3 个（30%），有些低",
			},
			forbidden: "有些低",
			required:  "和你预期的一样吗",
		},
		{
			name: "new habit removes direct advice",
			question: Question{
				ID: "new_habit_1", Type: "new_habit_struggle",
				Content: "「跑步」是 5 天前创建的，只打卡了 1 次，要不要降低难度试试？",
			},
			forbidden: "降低难度",
			required:  "是什么让你没有继续",
		},
		{
			name: "time preference does not label efficiency",
			question: Question{
				ID: "time_preference", Type: "time_preference",
				Content: "过去 30 天，你上午的打卡占 70%，晚上只有 10%，你的高效时段在上午？",
			},
			forbidden: "高效时段",
			required:  "符合你的实际感受吗",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := json.Marshal(tt.question)
			if err != nil {
				t.Fatal(err)
			}
			text := string(data)
			if strings.Contains(text, tt.forbidden) {
				t.Fatalf("unexpected judgment/advice in JSON: %s", text)
			}
			if !strings.Contains(text, tt.required) {
				t.Fatalf("expected question wording in JSON: %s", text)
			}
		})
	}
}
